import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../jobs/jobs_repository.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/theme_mode.dart';

const frequencyLabels = {
  'daily': 'Daily',
  'weekly': 'Weekly',
  'monthly': 'Monthly',
};

class ChecklistItem {
  ChecklistItem({
    this.id,
    required this.label,
    this.kind = 'check',
    this.unit,
    this.min,
    this.max,
    this.photoRequired = false,
  });

  ChecklistItem.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String?,
      label = j['label'] as String,
      kind = (j['kind'] as String?) ?? 'check',
      unit = j['unit'] as String?,
      min = (j['min_value'] as num?)?.toDouble(),
      max = (j['max_value'] as num?)?.toDouble(),
      photoRequired = (j['photo_required'] as bool?) ?? false;

  String? id;
  String label;
  String kind;
  String? unit;
  double? min;
  double? max;
  bool photoRequired;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'kind': kind,
    'unit': unit,
    'min_value': min,
    'max_value': max,
    'photo_required': photoRequired,
  };

  /// The shape fn_save_checklist_template expects.
  Map<String, dynamic> toPayload() => {
    'id': id,
    'label': label.trim(),
    'kind': kind,
    'unit': unit,
    'min': min,
    'max': max,
    'photo_required': photoRequired,
  };

  String? get limits {
    if (kind != 'number' || (min == null && max == null)) return null;
    String f(double? v) => v == null
        ? '…'
        : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());
    return '${f(min)}–${f(max)}${unit == null ? '' : ' $unit'}';
  }
}

class ChecklistTemplate {
  ChecklistTemplate.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      siteId = j['site_id'] as String,
      areaId = j['area_id'] as String?,
      name = j['name'] as String,
      description = j['description'] as String?,
      frequency = j['frequency'] as String,
      assigneeId = j['assignee_id'] as String?,
      items = [
        for (final i in (j['checklist_items'] as List? ?? const []))
          if (i['is_archived'] != true)
            (
              pos: (i['position'] as num?)?.toInt() ?? 0,
              item: ChecklistItem.fromJson(i as Map<String, dynamic>),
            ),
      ].sorted();

  final String id;
  final String siteId;
  final String? areaId;
  final String name;
  final String? description;
  final String frequency;
  final String? assigneeId;
  final List<ChecklistItem> items;
}

extension on List<({int pos, ChecklistItem item})> {
  List<ChecklistItem> sorted() => ([
    ...this,
  ]..sort((a, b) => a.pos.compareTo(b.pos))).map((e) => e.item).toList();
}

/// Templates at the current site. Kept on the device so rounds can be done
/// where there is no signal.
final checklistTemplatesProvider = FutureProvider<List<ChecklistTemplate>>((
  ref,
) async {
  final site = ref.watch(currentSiteProvider.select((s) => s?.id));
  if (site == null) return const [];
  final prefs = ref.watch(sharedPrefsProvider);
  final key = 'checklists:$site';
  List<ChecklistTemplate> parse(List rows) => [
    for (final r in rows) ChecklistTemplate.fromJson(r as Map<String, dynamic>),
  ];
  try {
    final rows = await ref
        .watch(supabaseProvider)
        .from('checklist_templates')
        .select('*, checklist_items(*)')
        .eq('site_id', site)
        .eq('is_archived', false)
        .order('name');
    await prefs.setString(key, jsonEncode(rows));
    return parse(rows);
  } catch (_) {
    final cached = prefs.getString(key);
    if (cached == null) rethrow;
    return parse(jsonDecode(cached) as List);
  }
});

final checklistTemplateProvider = Provider.family<ChecklistTemplate?, String>((
  ref,
  id,
) {
  return ref
      .watch(checklistTemplatesProvider)
      .value
      ?.where((t) => t.id == id)
      .firstOrNull;
});

class ChecklistStatus {
  ChecklistStatus.fromJson(Map<String, dynamic> j)
    : dueBy = DateTime.parse(j['due_by'] as String),
      doneAt = j['done_at'] == null
          ? null
          : DateTime.parse(j['done_at'] as String).toLocal(),
      doneBy = j['done_by'] as String?,
      failed = (j['failed_count'] as num?)?.toInt() ?? 0;

  final DateTime dueBy;
  final DateTime? doneAt;
  final String? doneBy;
  final int failed;

  bool get done => doneAt != null;
}

/// This period's state of each checklist at the current site (online).
final checklistStatusProvider = FutureProvider<Map<String, ChecklistStatus>>((
  ref,
) async {
  final site = ref.watch(currentSiteProvider.select((s) => s?.id));
  if (site == null) return const {};
  final rows = await ref
      .watch(supabaseProvider)
      .rpc('fn_site_checklists', params: {'p_site': site});
  return {
    for (final r in rows as List)
      r['id'] as String: ChecklistStatus.fromJson(r as Map<String, dynamic>),
  };
});

/// One answer while a round is being done.
class Answer {
  bool? ok;
  String value = '';
  String text = '';
  String comment = '';
  Uint8List? photo;
}

final checklistActionsProvider = Provider((ref) => ChecklistActions(ref));

class ChecklistActions {
  ChecklistActions(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<void> saveTemplate({
    String? id,
    required String siteId,
    String? areaId,
    required String name,
    String? description,
    required String frequency,
    String? assigneeId,
    required List<ChecklistItem> items,
    bool archived = false,
  }) async {
    for (final i in items) {
      i.id ??= _uuid.v4();
    }
    await _ref.read(outboxProvider).enqueue('fn_save_checklist_template', {
      'p_client_ref': id ?? _uuid.v4(),
      'p_site': siteId,
      'p_area': areaId,
      'p_name': name.trim(),
      'p_description': description?.trim(),
      'p_frequency': frequency,
      'p_assignee': assigneeId,
      'p_items': [for (final i in items) i.toPayload()],
      'p_archived': archived,
    }, flushNow: false);
    await _ref.read(outboxProvider).flush();
    _ref.invalidate(checklistTemplatesProvider);
    _ref.invalidate(checklistStatusProvider);
  }

  /// Queues a finished round: photos first, then the answers.
  Future<void> submit(
    ChecklistTemplate t,
    Map<String, Answer> answers, {
    String? notes,
  }) async {
    final runId = _uuid.v4();
    final outbox = _ref.read(outboxProvider);
    final payload = <Map<String, dynamic>>[];
    for (final item in t.items) {
      final a = answers[item.id] ?? Answer();
      String? path;
      if (a.photo != null) {
        final fileId = _uuid.v4();
        path = '${t.siteId}/checklist/$runId/$fileId.jpg';
        await outbox.enqueueUpload(
          id: fileId,
          bucket: 'job-photos',
          path: path,
          bytes: a.photo!,
        );
      }
      payload.add({
        'item_id': item.id,
        'ok': a.ok,
        'value': a.value.trim().replaceAll(',', '.'),
        'text': a.text.trim(),
        'comment': a.comment.trim(),
        'photo_path': path,
      });
    }
    await outbox.enqueue(
      'fn_submit_checklist',
      {
        'p_client_ref': runId,
        'p_template': t.id,
        'p_answers': payload,
        'p_notes': notes?.trim(),
      },
      clientRef: runId,
      flushNow: false,
    );
    unawaited(_afterSubmit());
  }

  Future<void> _afterSubmit() async {
    await _ref.read(outboxProvider).flush();
    _ref.invalidate(checklistStatusProvider);
    // Failed items raised jobs; bring them onto the board.
    await _ref.read(jobsSyncProvider.notifier).refresh();
  }
}

/// Signed links for photos in job-photos (checklists, report updates).
final photoUrlsProvider = FutureProvider.autoDispose
    .family<Map<String, String>, String>((ref, joinedPaths) async {
      final paths = joinedPaths.split('|').where((p) => p.isNotEmpty).toList();
      if (paths.isEmpty) return const {};
      final signed = await ref
          .watch(supabaseProvider)
          .storage
          .from('job-photos')
          .createSignedUrlsResult(paths, 3600);
      return {
        for (final s in signed.whereType<SignedUrlSuccess>())
          s.path: s.signedUrl,
      };
    });
