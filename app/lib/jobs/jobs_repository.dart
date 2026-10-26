import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/app_error.dart';
import '../data/local_db.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import 'job_rules.dart';

LocalJob jobFromRow(Map<String, dynamic> r) {
  DateTime? t(String k) =>
      r[k] == null ? null : DateTime.parse(r[k] as String).toLocal();
  return LocalJob(
    id: r['id'] as String,
    siteId: r['site_id'] as String,
    areaId: r['area_id'] as String?,
    code: r['code'] as String?,
    title: r['title'] as String,
    description: r['description'] as String?,
    priority: r['priority'] as String,
    status: r['status'] as String,
    waitingReason: r['waiting_reason'] as String?,
    dueAt: t('due_at'),
    lat: (r['lat'] as num?)?.toDouble(),
    lng: (r['lng'] as num?)?.toDouble(),
    createdBy: r['created_by'] as String?,
    assigneeId: r['assignee_id'] as String?,
    closedAt: t('closed_at'),
    closeNote: r['close_note'] as String?,
    recurrenceId: r['recurrence_id'] as String?,
    createdAt: t('created_at')!,
    updatedAt: t('updated_at')!,
    pending: false,
    assetId: r['asset_id'] as String?,
    maintenanceType: (r['maintenance_type'] as String?) ?? 'corrective',
    isolationRequired: (r['isolation_required'] as bool?) ?? false,
  );
}

LocalAsset assetFromRow(Map<String, dynamic> r) => LocalAsset(
  id: r['id'] as String,
  siteId: r['site_id'] as String,
  areaId: r['area_id'] as String?,
  tag: r['tag'] as String,
  name: r['name'] as String,
  kind: r['kind'] as String?,
  makeModel: r['make_model'] as String?,
  serialNo: r['serial_no'] as String?,
  notes: r['notes'] as String?,
);

class JobsSyncState {
  const JobsSyncState({this.loading = false, this.error, this.synced = false});

  final bool loading;
  final AppError? error;
  final bool synced;
}

/// Keeps the current site's jobs in drift: loads them, listens on the
/// `jobs:<site_id>` realtime channel, and reloads after queued changes land.
final jobsSyncProvider = NotifierProvider<JobsSyncNotifier, JobsSyncState>(
  JobsSyncNotifier.new,
);

class JobsSyncNotifier extends Notifier<JobsSyncState> {
  LocalDb get _db => ref.read(localDbProvider);
  SupabaseClient get _client => ref.read(supabaseProvider);
  String? _siteId;

  @override
  JobsSyncState build() {
    final userId = ref.watch(authUserIdProvider);
    final site = ref.watch(currentSiteProvider.select((s) => s?.id));
    _siteId = site;
    if (userId == null || site == null) return const JobsSyncState();

    final channel = _client
        .channel('jobs:$site')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'jobs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'site_id',
            value: site,
          ),
          callback: (p) {
            if (p.newRecord.isEmpty) return;
            unawaited(_upsertFromServer([jobFromRow(p.newRecord)]));
          },
        )
        .subscribe();
    ref.onDispose(() => unawaited(_client.removeChannel(channel)));

    Future.microtask(refresh);
    return const JobsSyncState(loading: true);
  }

  Future<void> refresh() async {
    final site = _siteId;
    if (site == null) return;
    state = JobsSyncState(loading: true, synced: state.synced);
    try {
      final since = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 30))
          .toIso8601String();
      final results = await Future.wait<dynamic>([
        _client
            .from('jobs')
            .select()
            .eq('site_id', site)
            .eq('is_archived', false)
            .or(
              'status.in.(open,taken,in_progress,waiting),closed_at.gte.$since',
            )
            .order('updated_at', ascending: false)
            .limit(500),
        _client.from('profiles').select('id, full_name'),
        _client
            .from('assets')
            .select()
            .eq('site_id', site)
            .eq('is_archived', false)
            .order('tag'),
      ]);
      if (!ref.mounted || _siteId != site) return;

      final jobs = [for (final r in results[0] as List) jobFromRow(r)];
      await _db.transaction(() async {
        // Drop rows the server no longer returns, unless changed locally.
        final keep = jobs.map((j) => j.id).toList();
        await (_db.delete(_db.localJobs)
              ..where((j) => j.siteId.equals(site))
              ..where((j) => j.pending.equals(false))
              ..where((j) => j.id.isNotIn(keep)))
            .go();
        await _upsertFromServer(jobs);
        // The register is small: replace this site's copy outright.
        await (_db.delete(
          _db.localAssets,
        )..where((a) => a.siteId.equals(site))).go();
        await _db.batch((b) {
          b.insertAll(_db.localAssets, [
            for (final r in results[2] as List) assetFromRow(r),
          ]);
        });
        await _db.batch((b) {
          b.insertAllOnConflictUpdate(_db.localPeople, [
            for (final p in results[1] as List)
              LocalPeopleCompanion.insert(
                id: p['id'] as String,
                fullName: (p['full_name'] as String?) ?? '',
              ),
          ]);
        });
      });
      state = const JobsSyncState(synced: true);
    } catch (e) {
      if (!ref.mounted) return;
      state = JobsSyncState(error: AppError.from(e), synced: state.synced);
    }
  }

  /// Server rows win unless this device has unsent changes to that job.
  Future<void> _upsertFromServer(List<LocalJob> jobs) async {
    if (jobs.isEmpty) return;
    final ids = jobs.map((j) => j.id).toList();
    final pending =
        (await (_db.select(_db.localJobs)
                  ..where((j) => j.id.isIn(ids))
                  ..where((j) => j.pending.equals(true)))
                .get())
            .map((j) => j.id)
            .toSet();
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.localJobs, [
        for (final j in jobs)
          if (!pending.contains(j.id)) j,
      ]);
    });
  }

  /// Called once the outbox is empty: local changes are now on the server.
  Future<void> settle() async {
    await (_db.update(_db.localJobs)..where((j) => j.pending.equals(true)))
        .write(const LocalJobsCompanion(pending: Value(false)));
    await refresh();
  }
}

/// Jobs at the current site, from the device cache.
final siteJobsProvider = StreamProvider<List<LocalJob>>((ref) {
  ref.watch(jobsSyncProvider.select((_) => null));
  final site = ref.watch(currentSiteProvider.select((s) => s?.id));
  if (site == null) return Stream.value(const []);
  final db = ref.watch(localDbProvider);
  return (db.select(db.localJobs)..where((j) => j.siteId.equals(site))).watch();
});

final jobProvider = StreamProvider.family<LocalJob?, String>((ref, id) {
  final db = ref.watch(localDbProvider);
  return (db.select(
    db.localJobs,
  )..where((j) => j.id.equals(id))).watchSingleOrNull();
});

/// Everyone's display name by id.
final peopleProvider = StreamProvider<Map<String, String>>((ref) {
  final db = ref.watch(localDbProvider);
  return db
      .select(db.localPeople)
      .watch()
      .map((rows) => {for (final p in rows) p.id: p.fullName});
});

class JobPhoto {
  const JobPhoto({
    required this.id,
    required this.kind,
    required this.path,
    this.url,
    this.bytes,
  });

  final String id;
  final String kind;
  final String path;

  /// Signed URL (60 min) for uploaded photos.
  final String? url;

  /// Local bytes for photos still waiting to upload.
  final Uint8List? bytes;
}

class JobComment {
  const JobComment({
    required this.id,
    required this.authorId,
    required this.body,
    required this.createdAt,
    this.pending = false,
  });

  final String id;
  final String? authorId;
  final String body;
  final DateTime createdAt;
  final bool pending;
}

class JobDetail {
  const JobDetail({this.photos = const [], this.comments = const []});

  final List<JobPhoto> photos;
  final List<JobComment> comments;
}

/// Photos and comments of one job: uploaded ones from Supabase (live), plus
/// ones still queued on this device.
final jobDetailProvider = StreamProvider.autoDispose.family<JobDetail, String>((
  ref,
  id,
) {
  final client = ref.watch(supabaseProvider);
  final outbox = ref.watch(outboxProvider);
  final controller = StreamController<JobDetail>();
  var server = const JobDetail();
  var queuedComments = <JobComment>[];
  var queuedPhotos = <JobPhoto>[];

  void emit() {
    final ids = server.comments.map((c) => c.id).toSet();
    final photoPaths = server.photos.map((p) => p.path).toSet();
    controller.add(
      JobDetail(
        photos: [
          ...server.photos,
          for (final p in queuedPhotos)
            if (!photoPaths.contains(p.path)) p,
        ],
        comments: [
          ...server.comments,
          for (final c in queuedComments)
            if (!ids.contains(c.id)) c,
        ]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      ),
    );
  }

  Future<void> load() async {
    try {
      final results = await Future.wait<dynamic>([
        client
            .from('job_photos')
            .select()
            .eq('job_id', id)
            .eq('is_archived', false)
            .order('created_at'),
        client
            .from('job_comments')
            .select()
            .eq('job_id', id)
            .eq('is_archived', false)
            .order('created_at'),
      ]);
      final photoRows = results[0] as List;
      final paths = [for (final p in photoRows) p['path'] as String];
      final signed = paths.isEmpty
          ? <SignedUrlResult>[]
          : await client.storage
                .from('job-photos')
                .createSignedUrlsResult(paths, 3600);
      final urls = {
        for (final s in signed.whereType<SignedUrlSuccess>())
          s.path: s.signedUrl,
      };
      server = JobDetail(
        photos: [
          for (final p in photoRows)
            JobPhoto(
              id: p['id'] as String,
              kind: p['kind'] as String,
              path: p['path'] as String,
              url: urls[p['path']],
            ),
        ],
        comments: [
          for (final c in results[1] as List)
            JobComment(
              id: c['id'] as String,
              authorId: c['author_id'] as String?,
              body: c['body'] as String,
              createdAt: DateTime.parse(c['created_at'] as String).toLocal(),
            ),
        ],
      );
      emit();
    } catch (e) {
      // Offline: show what is queued locally.
      emit();
    }
  }

  final channel = client
      .channel('job:$id')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'job_comments',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'job_id',
          value: id,
        ),
        callback: (_) => load(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'job_photos',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'job_id',
          value: id,
        ),
        callback: (_) => load(),
      )
      .subscribe();

  final subs = <StreamSubscription<dynamic>>[
    outbox.watchActions('fn_comment_job').listen((entries) {
      queuedComments = [
        for (final e in entries)
          if (decodePayload(e.payload)['p_job'] == id)
            JobComment(
              id: e.clientRef,
              authorId: ref.read(authUserIdProvider),
              body: decodePayload(e.payload)['p_body'] as String,
              createdAt: e.createdAt,
              pending: true,
            ),
      ];
      emit();
    }),
    outbox.watchUploads('').listen((uploads) {
      queuedPhotos = [
        for (final u in uploads)
          if (u.path.contains('/job/$id/'))
            JobPhoto(
              id: u.id,
              kind: u.path.split('/').last.startsWith('after')
                  ? 'after'
                  : 'before',
              path: u.path,
              bytes: u.bytes,
            ),
      ];
      emit();
      // A finished upload disappears here; reload to pick up the server copy.
      unawaited(load());
    }),
  ];

  unawaited(load());
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
    unawaited(client.removeChannel(channel));
    controller.close();
  });
  return controller.stream;
});

final jobHistoryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, id) async {
      // Reload whenever the job itself changes.
      ref.watch(jobProvider(id).select((j) => j.value?.updatedAt));
      final rows = await ref
          .watch(supabaseProvider)
          .rpc('fn_job_history', params: {'p_job': id});
      return [for (final r in rows as List) Map<String, dynamic>.from(r)];
    });

class Assignee {
  const Assignee(this.id, this.name, this.openJobs);

  final String id;
  final String name;
  final int openJobs;
}

final assigneesProvider = FutureProvider.autoDispose
    .family<List<Assignee>, String>((ref, siteId) async {
      final rows = await ref
          .watch(supabaseProvider)
          .rpc('fn_job_assignees', params: {'p_site': siteId});
      return [
        for (final r in rows as List)
          Assignee(
            r['id'] as String,
            (r['full_name'] as String?) ?? '',
            (r['open_jobs'] as num?)?.toInt() ?? 0,
          ),
      ];
    });

Map<String, dynamic> decodePayload(String s) =>
    Map<String, dynamic>.from(jsonDecode(s) as Map);

/// Everything a user can do to jobs. Each call updates the device cache at
/// once (so it works offline) and queues the matching function.
final jobActionsProvider = Provider<JobActions>(JobActions.new);

class JobActions {
  JobActions(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  LocalDb get _db => _ref.read(localDbProvider);

  Future<void> _queue(
    String action,
    Map<String, dynamic> payload, {
    String? clientRef,
  }) async {
    final outbox = _ref.read(outboxProvider);
    await outbox.enqueue(
      action,
      payload,
      clientRef: clientRef,
      flushNow: false,
    );
    unawaited(_flushAndSettle());
  }

  Future<void> _flushAndSettle() async {
    final outbox = _ref.read(outboxProvider);
    await outbox.flush();
    if (await outbox.isEmpty) {
      await _ref.read(jobsSyncProvider.notifier).settle();
    }
  }

  Future<void> _patch(String id, LocalJobsCompanion change) {
    return (_db.update(_db.localJobs)..where((j) => j.id.equals(id))).write(
      change.copyWith(
        pending: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  String? get _me => _ref.read(authUserIdProvider);

  /// Queues photo uploads + their `fn_add_job_photo` calls.
  Future<void> _photos(
    LocalJob job,
    String kind,
    List<Uint8List> photos,
  ) async {
    final outbox = _ref.read(outboxProvider);
    for (final bytes in photos) {
      final id = _uuid.v4();
      final path = '${job.siteId}/job/${job.id}/$kind-$id.jpg';
      await outbox.enqueueUpload(
        id: id,
        bucket: 'job-photos',
        path: path,
        bytes: bytes,
      );
      await outbox.enqueue(
        'fn_add_job_photo',
        {'p_client_ref': id, 'p_job': job.id, 'p_kind': kind, 'p_path': path},
        clientRef: id,
        flushNow: false,
      );
    }
  }

  Future<String> create({
    required String siteId,
    String? areaId,
    required String title,
    String? description,
    required JobPriority priority,
    DateTime? dueAt,
    double? lat,
    double? lng,
    List<Uint8List> photos = const [],
    String? assigneeId,
    String? assetId,
    bool preventive = false,
    bool isolationRequired = false,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final job = LocalJob(
      id: id,
      siteId: siteId,
      areaId: areaId,
      title: title.trim(),
      description: description?.trim().isEmpty ?? true
          ? null
          : description!.trim(),
      priority: priority.name,
      status: 'open',
      dueAt: dueAt,
      lat: lat,
      lng: lng,
      createdBy: _me,
      createdAt: now,
      updatedAt: now,
      pending: true,
      assetId: assetId,
      maintenanceType: preventive ? 'preventive' : 'corrective',
      isolationRequired: isolationRequired,
    );
    await _db.into(_db.localJobs).insert(job);
    await _ref
        .read(outboxProvider)
        .enqueue(
          'fn_create_job',
          {
            'p_client_ref': id,
            'p_site': siteId,
            'p_area': areaId,
            'p_title': job.title,
            'p_description': job.description,
            'p_priority': priority.name,
            'p_due_at': dueAt?.toUtc().toIso8601String(),
            'p_lat': lat,
            'p_lng': lng,
            'p_asset': assetId,
            'p_maintenance_type': job.maintenanceType,
            'p_isolation_required': isolationRequired,
          },
          clientRef: id,
          flushNow: false,
        );
    await _photos(job, 'before', photos);
    if (assigneeId != null) {
      await _patch(
        id,
        LocalJobsCompanion(
          assigneeId: Value(assigneeId),
          status: const Value('taken'),
        ),
      );
      await _ref.read(outboxProvider).enqueue('fn_assign_job', {
        'p_job': id,
        'p_user': assigneeId,
      }, flushNow: false);
    }
    unawaited(_flushAndSettle());
    return id;
  }

  Future<void> edit(
    LocalJob job, {
    required String title,
    String? description,
    String? areaId,
    required JobPriority priority,
    DateTime? dueAt,
    String? assetId,
    bool preventive = false,
    bool isolationRequired = false,
  }) async {
    await _patch(
      job.id,
      LocalJobsCompanion(
        title: Value(title.trim()),
        description: Value(
          description?.trim().isEmpty ?? true ? null : description!.trim(),
        ),
        areaId: Value(areaId),
        priority: Value(priority.name),
        dueAt: Value(dueAt),
        assetId: Value(assetId),
        maintenanceType: Value(preventive ? 'preventive' : 'corrective'),
        isolationRequired: Value(isolationRequired),
      ),
    );
    await _queue('fn_edit_job', {
      'p_job': job.id,
      'p_title': title.trim(),
      'p_description': description,
      'p_area': areaId,
      'p_priority': priority.name,
      'p_due_at': dueAt?.toUtc().toIso8601String(),
      'p_asset': assetId,
      'p_maintenance_type': preventive ? 'preventive' : 'corrective',
      'p_isolation_required': isolationRequired,
    });
  }

  Future<void> take(LocalJob job) async {
    await _patch(
      job.id,
      LocalJobsCompanion(status: const Value('taken'), assigneeId: Value(_me)),
    );
    await _queue('fn_take_job', {'p_job': job.id});
  }

  Future<void> assign(LocalJob job, String? userId) async {
    await _patch(
      job.id,
      LocalJobsCompanion(
        assigneeId: Value(userId),
        status: Value(
          userId == null
              ? 'open'
              : (job.status == 'open' ? 'taken' : job.status),
        ),
      ),
    );
    await _queue('fn_assign_job', {'p_job': job.id, 'p_user': userId});
  }

  Future<void> setStatus(
    LocalJob job,
    JobStatus status, {
    String? reason,
  }) async {
    await _patch(
      job.id,
      LocalJobsCompanion(
        status: Value(status.db),
        waitingReason: Value(status == JobStatus.waiting ? reason : null),
        assigneeId: status == JobStatus.open
            ? const Value(null)
            : const Value.absent(),
        closedAt: status == JobStatus.cancelled
            ? Value(DateTime.now())
            : const Value.absent(),
      ),
    );
    await _queue('fn_set_job_status', {
      'p_job': job.id,
      'p_status': status.db,
      'p_reason': reason,
    });
  }

  Future<void> addPhotos(
    LocalJob job,
    String kind,
    List<Uint8List> photos,
  ) async {
    await _photos(job, kind, photos);
    unawaited(_flushAndSettle());
  }

  Future<void> close(
    LocalJob job, {
    required String note,
    required List<Uint8List> afterPhotos,
  }) async {
    await _photos(job, 'after', afterPhotos);
    await _patch(
      job.id,
      LocalJobsCompanion(
        status: const Value('done'),
        closeNote: Value(note.trim()),
        closedAt: Value(DateTime.now()),
        assigneeId: Value(job.assigneeId ?? _me),
      ),
    );
    await _queue('fn_close_job', {'p_job': job.id, 'p_note': note.trim()});
  }

  Future<void> comment(LocalJob job, String body) async {
    final id = _uuid.v4();
    await _queue('fn_comment_job', {
      'p_client_ref': id,
      'p_job': job.id,
      'p_body': body.trim(),
    }, clientRef: id);
  }

  /// Adds or edits an asset (supervisors). Saved on the device first, so the
  /// register works offline; the next sync replaces it with the server's.
  Future<String> saveAsset({
    String? id,
    required String siteId,
    String? areaId,
    required String tag,
    required String name,
    String? kind,
    String? makeModel,
    String? serialNo,
    String? notes,
    bool archived = false,
  }) async {
    final ref = id ?? _uuid.v4();
    String? clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    if (archived) {
      await (_db.delete(_db.localAssets)..where((a) => a.id.equals(ref))).go();
    } else {
      await _db
          .into(_db.localAssets)
          .insertOnConflictUpdate(
            LocalAsset(
              id: ref,
              siteId: siteId,
              areaId: areaId,
              tag: tag.trim().toUpperCase(),
              name: name.trim(),
              kind: clean(kind),
              makeModel: clean(makeModel),
              serialNo: clean(serialNo),
              notes: clean(notes),
            ),
          );
    }
    await _queue('fn_save_asset', {
      'p_client_ref': ref,
      'p_site': siteId,
      'p_area': areaId,
      'p_tag': tag.trim(),
      'p_name': name.trim(),
      'p_kind': clean(kind),
      'p_make_model': clean(makeModel),
      'p_serial_no': clean(serialNo),
      'p_notes': clean(notes),
      'p_archived': archived,
    });
    return ref;
  }

  Future<void> saveRecurrence({
    String? id,
    required String siteId,
    String? areaId,
    required String title,
    String? description,
    required JobPriority priority,
    required String every,
    required DateTime nextRun,
    required int dueDays,
    String? assigneeId,
    bool archived = false,
    String? assetId,
    bool isolationRequired = false,
  }) async {
    final ref = id ?? _uuid.v4();
    final d = nextRun;
    await _queue('fn_save_recurrence', {
      'p_client_ref': ref,
      'p_site': siteId,
      'p_area': areaId,
      'p_title': title.trim(),
      'p_description': description,
      'p_priority': priority.name,
      'p_every': every,
      'p_next_run':
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      'p_due_days': dueDays,
      'p_assignee': assigneeId,
      'p_archived': archived,
      'p_asset': assetId,
      'p_isolation_required': isolationRequired,
    });
  }
}

/// Recurring job templates at the current site (online).
final recurrencesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final site = ref.watch(currentSiteProvider.select((s) => s?.id));
      if (site == null) return const [];
      final rows = await ref
          .watch(supabaseProvider)
          .from('job_recurrences')
          .select()
          .eq('site_id', site)
          .eq('is_archived', false)
          .order('next_run');
      return [for (final r in rows) Map<String, dynamic>.from(r)];
    });

/// The asset register at the current site, from the device cache.
final siteAssetsProvider = StreamProvider<List<LocalAsset>>((ref) {
  final site = ref.watch(currentSiteProvider.select((s) => s?.id));
  if (site == null) return Stream.value(const []);
  final db = ref.watch(localDbProvider);
  return (db.select(db.localAssets)
        ..where((a) => a.siteId.equals(site))
        ..orderBy([(a) => OrderingTerm(expression: a.tag)]))
      .watch();
});

final assetProvider = StreamProvider.family<LocalAsset?, String>((ref, id) {
  final db = ref.watch(localDbProvider);
  return (db.select(
    db.localAssets,
  )..where((a) => a.id.equals(id))).watchSingleOrNull();
});

/// Every cached job on one asset, newest first.
final assetJobsProvider = StreamProvider.family<List<LocalJob>, String>((
  ref,
  assetId,
) {
  final db = ref.watch(localDbProvider);
  return (db.select(db.localJobs)
        ..where((j) => j.assetId.equals(assetId))
        ..orderBy([
          (j) => OrderingTerm(expression: j.createdAt, mode: OrderingMode.desc),
        ]))
      .watch();
});
