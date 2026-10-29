import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show DownloadBehavior;
import 'package:uuid/uuid.dart';

import '../services/core_providers.dart';
import '../services/session_controller.dart';

/// A folder in a site's document library (API.md section 12b).
class DocFolder {
  DocFolder.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      siteId = j['site_id'] as String,
      name = j['name'] as String;

  final String id;
  final String siteId;
  final String name;
}

const documentCategories = {
  'sop': 'SOPs',
  'drawing': 'Drawings',
  'manual': 'Manuals',
  'form': 'Forms',
  'other': 'Other',
};

String categoryLabel(String c) => switch (c) {
  'sop' => 'SOP',
  'drawing' => 'Drawing',
  'manual' => 'Manual',
  'form' => 'Form',
  _ => 'Other',
};

class DocVersion {
  DocVersion.fromJson(Map<String, dynamic> j)
    : version = (j['version'] as num).toInt(),
      path = j['path'] as String,
      fileName = j['file_name'] as String,
      mimeType = j['mime_type'] as String?,
      sizeBytes = (j['size_bytes'] as num?)?.toInt(),
      note = j['note'] as String?,
      createdBy = j['created_by'] as String?,
      createdAt = DateTime.parse(j['created_at'] as String).toLocal();

  final int version;
  final String path;
  final String fileName;
  final String? mimeType;
  final int? sizeBytes;
  final String? note;
  final String? createdBy;
  final DateTime createdAt;

  bool get isImage => mimeType?.startsWith('image/') ?? false;
}

/// A document with all its versions and whether I have acknowledged it.
class Doc {
  Doc.fromJson(
    Map<String, dynamic> j,
    Map<String, int> myAcks, [
    Map<String, int> signed = const {},
    this.member = true,
  ]) : id = j['id'] as String,
       siteId = j['site_id'] as String,
       code = j['code'] as String,
       title = j['title'] as String,
       category = j['category'] as String,
       needsAck = j['needs_ack'] as bool,
       folderId = j['folder_id'] as String?,
       createdBy = j['created_by'] as String?,
       currentVersion = (j['current_version'] as num).toInt(),
       updatedAt = DateTime.parse(j['updated_at'] as String).toLocal(),
       versions = [
         for (final v in (j['document_versions'] as List? ?? const []))
           DocVersion.fromJson(v as Map<String, dynamic>),
       ]..sort((a, b) => b.version.compareTo(a.version)),
       myAckVersion = myAcks[j['id']],
       signed = signed[j['id']];

  final String id;
  final String siteId;
  final String code;
  final String title;
  final String category;
  final bool needsAck;
  final String? folderId;
  final String? createdBy;
  final int currentVersion;
  final DateTime updatedAt;
  final List<DocVersion> versions;
  final int? myAckVersion;

  /// The user works at the document's site; other sites are view only.
  final bool member;

  /// People who signed the current version; only supervisors see it.
  final int? signed;

  DocVersion? get current => versions.firstOrNull;

  /// The file name of the current version, for its type badge.
  String get fileName => current?.fileName ?? '';

  /// Needs my acknowledgement of the current version.
  bool get toSign =>
      member &&
      needsAck &&
      currentVersion > 0 &&
      myAckVersion != currentVersion;
}

/// Documents at the current site (online: files need a connection anyway).
final documentsProvider = FutureProvider<List<Doc>>((ref) async {
  final site = ref.watch(currentSiteProvider.select((s) => s?.id));
  final me = ref.watch(authUserIdProvider);
  if (site == null || me == null) return const [];
  final db = ref.watch(supabaseProvider);
  final (rows, acks) = await (
    db
        .from('documents')
        .select('*, document_versions(*)')
        .eq('site_id', site)
        .eq('is_archived', false)
        .order('title'),
    db.from('document_acks').select('document_id, version').eq('user_id', me),
  ).wait;
  final mine = <String, int>{};
  for (final a in acks) {
    final id = a['document_id'] as String;
    final v = (a['version'] as num).toInt();
    if (v > (mine[id] ?? 0)) mine[id] = v;
  }
  // Supervisors see everyone's signatures (RLS); count them on the current
  // version of each document that needs them.
  final signed = <String, int>{};
  if (ref.read(sessionProvider).can('docs.manage', siteId: site)) {
    final current = {
      for (final r in rows)
        if (r['needs_ack'] == true)
          r['id'] as String: (r['current_version'] as num).toInt(),
    };
    if (current.isNotEmpty) {
      final all = await db
          .from('document_acks')
          .select('document_id, version, user_id')
          .inFilter('document_id', current.keys.toList());
      final who = <String, Set<String>>{};
      for (final a in all) {
        final id = a['document_id'] as String;
        if ((a['version'] as num).toInt() == current[id]) {
          (who[id] ??= {}).add(a['user_id'] as String);
        }
      }
      for (final id in current.keys) {
        signed[id] = who[id]?.length ?? 0;
      }
    }
  }
  final member = ref.read(sessionProvider).worksAt(site);
  return [for (final r in rows) Doc.fromJson(r, mine, signed, member)];
});

/// Folders at the current site, by name (online).
final foldersProvider = FutureProvider<List<DocFolder>>((ref) async {
  final site = ref.watch(currentSiteProvider.select((s) => s?.id));
  if (site == null) return const [];
  final rows = await ref
      .watch(supabaseProvider)
      .from('document_folders')
      .select('id, site_id, name')
      .eq('site_id', site)
      .eq('is_archived', false)
      .order('name');
  return [for (final r in rows) DocFolder.fromJson(r)];
});

final documentProvider = Provider.family<Doc?, String>((ref, id) {
  return ref
      .watch(documentsProvider)
      .value
      ?.where((d) => d.id == id)
      .firstOrNull;
});

/// How many SOPs wait for my acknowledgement at the current site.
final toSignCountProvider = Provider<int>((ref) {
  return ref.watch(documentsProvider).value?.where((d) => d.toSign).length ?? 0;
});

/// Who has and has not acknowledged (supervisors).
final documentAcksProvider = FutureProvider.autoDispose
    .family<List<({String name, DateTime? at})>, String>((ref, id) async {
      final rows = await ref
          .watch(supabaseProvider)
          .rpc('fn_document_acks', params: {'p_document': id});
      return [
        for (final r in rows as List)
          (
            name: (r['full_name'] as String?) ?? '',
            at: r['acked_at'] == null
                ? null
                : DateTime.parse(r['acked_at'] as String).toLocal(),
          ),
      ];
    });

/// Documents linked to a job.
final jobDocumentsProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, jobCardId) async {
      final rows = await ref
          .watch(supabaseProvider)
          .from('job_card_documents')
          .select('document_id')
          .eq('job_card_id', jobCardId);
      return [for (final r in rows) r['document_id'] as String];
    });

/// A signed link to a document file, valid for an hour.
final documentUrlProvider = FutureProvider.autoDispose.family<String, String>((
  ref,
  path,
) {
  return ref
      .watch(supabaseProvider)
      .storage
      .from('documents')
      .createSignedUrl(path, 3600);
});

final documentActionsProvider = Provider((ref) => DocumentActions(ref));

class DocumentActions {
  DocumentActions(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  /// Creates or edits a document; with [file], uploads it as a new version.
  Future<String> save({
    Doc? doc,
    required String siteId,
    required String title,
    required String category,
    required bool needsAck,
    bool archived = false,
    ({String name, Uint8List bytes})? file,
    String? note,
    String? folderId,
    bool reload = true,
  }) async {
    final id = doc?.id ?? _uuid.v4();
    final outbox = _ref.read(outboxProvider);
    await outbox.enqueue('fn_save_document', {
      'p_client_ref': id,
      'p_site': siteId,
      'p_title': title.trim(),
      'p_category': category,
      'p_needs_ack': needsAck,
      'p_archived': archived,
    }, flushNow: false);
    if (file != null) {
      final versionId = _uuid.v4();
      final safe = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '$siteId/doc/$id/$versionId-$safe';
      final mime = mimeFor(file.name);
      await outbox.enqueueUpload(
        id: versionId,
        bucket: 'documents',
        path: path,
        bytes: file.bytes,
        contentType: mime,
      );
      await outbox.enqueue(
        'fn_add_document_version',
        {
          'p_client_ref': versionId,
          'p_document': id,
          'p_path': path,
          'p_file_name': file.name,
          'p_mime_type': mime,
          'p_size_bytes': file.bytes.length,
          'p_note': note?.trim(),
        },
        clientRef: versionId,
        flushNow: false,
      );
    }
    if (doc == null && folderId != null) {
      await outbox.enqueue('fn_move_documents', {
        'p_documents': [id],
        'p_folder': folderId,
      }, flushNow: false);
    }
    if (reload) await _flushAndReload();
    return id;
  }

  /// Uploads several files as new documents, one after another, telling
  /// [onProgress] which file is done. Titles come from the file names.
  Future<void> uploadMany({
    required String siteId,
    required List<({String name, Uint8List bytes})> files,
    required String category,
    required bool needsAck,
    String? folderId,
    void Function(int index)? onStart,
    void Function(int index)? onDone,
  }) async {
    for (final (i, f) in files.indexed) {
      onStart?.call(i);
      await save(
        siteId: siteId,
        title: titleFromFileName(f.name),
        category: category,
        needsAck: needsAck,
        file: f,
        folderId: folderId,
        reload: false,
      );
      // Send each file as it is queued, so the progress is real online.
      await _ref.read(outboxProvider).flush();
      onDone?.call(i);
    }
    _ref.invalidate(documentsProvider);
  }

  /// Creates, renames or archives a folder; returns its id.
  Future<String> saveFolder({
    DocFolder? folder,
    required String siteId,
    required String name,
    bool archived = false,
  }) async {
    final id = folder?.id ?? _uuid.v4();
    await _ref.read(outboxProvider).enqueue('fn_save_folder', {
      'p_client_ref': id,
      'p_site': siteId,
      'p_name': name.trim(),
      'p_archived': archived,
    }, flushNow: false);
    await _ref.read(outboxProvider).flush();
    _ref.invalidate(foldersProvider);
    _ref.invalidate(documentsProvider);
    return id;
  }

  /// Moves documents into [folderId], or out of folders with null.
  Future<void> move(List<String> documentIds, String? folderId) async {
    await _ref.read(outboxProvider).enqueue('fn_move_documents', {
      'p_documents': documentIds,
      'p_folder': folderId,
    }, flushNow: false);
    await _flushAndReload();
  }

  /// A link to the current file that works for 7 days without signing in,
  /// for someone outside the app (a contractor or the client).
  Future<String> shareLink(DocVersion v) => _ref
      .read(supabaseProvider)
      .storage
      .from('documents')
      .createSignedUrl(v.path, 7 * 24 * 3600);

  /// A link that downloads the file instead of opening it.
  Future<String> downloadLink(DocVersion v) => _ref
      .read(supabaseProvider)
      .storage
      .from('documents')
      .createSignedUrl(
        v.path,
        600,
        download: DownloadBehavior.named(v.fileName),
      );

  Future<void> acknowledge(Doc doc) async {
    await _ref.read(outboxProvider).enqueue('fn_acknowledge_document', {
      'p_document': doc.id,
      'p_version': doc.currentVersion,
    }, flushNow: false);
    await _flushAndReload();
  }

  /// Attaches (or detaches) a document on a job card; queued offline.
  Future<void> link(
    String jobCardId,
    String documentId, {
    bool linked = true,
  }) async {
    await _ref.read(outboxProvider).enqueue('fn_link_job_card_document', {
      'p_job_card': jobCardId,
      'p_document': documentId,
      'p_linked': linked,
    }, flushNow: false);
    await _ref.read(outboxProvider).flush();
    _ref.invalidate(jobDocumentsProvider(jobCardId));
  }

  Future<void> _flushAndReload() async {
    await _ref.read(outboxProvider).flush();
    _ref.invalidate(documentsProvider);
  }
}

String titleFromFileName(String name) => name
    .replaceAll(RegExp(r'\.[^.]+$'), '')
    .replaceAll(RegExp(r'[_]+'), ' ')
    .trim();

String mimeFor(String name) {
  final ext = name.split('.').last.toLowerCase();
  return switch (ext) {
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'dwg' => 'application/acad',
    'dxf' => 'image/vnd.dxf',
    'csv' => 'text/csv',
    'txt' => 'text/plain',
    'zip' => 'application/zip',
    _ => 'application/octet-stream',
  };
}
