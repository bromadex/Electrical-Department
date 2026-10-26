import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../services/core_providers.dart';
import '../services/session_controller.dart';

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
  Doc.fromJson(Map<String, dynamic> j, Map<String, int> myAcks)
    : id = j['id'] as String,
      siteId = j['site_id'] as String,
      code = j['code'] as String,
      title = j['title'] as String,
      category = j['category'] as String,
      needsAck = j['needs_ack'] as bool,
      currentVersion = (j['current_version'] as num).toInt(),
      updatedAt = DateTime.parse(j['updated_at'] as String).toLocal(),
      versions = [
        for (final v in (j['document_versions'] as List? ?? const []))
          DocVersion.fromJson(v as Map<String, dynamic>),
      ]..sort((a, b) => b.version.compareTo(a.version)),
      myAckVersion = myAcks[j['id']];

  final String id;
  final String siteId;
  final String code;
  final String title;
  final String category;
  final bool needsAck;
  final int currentVersion;
  final DateTime updatedAt;
  final List<DocVersion> versions;
  final int? myAckVersion;

  DocVersion? get current => versions.firstOrNull;

  /// Needs my acknowledgement of the current version.
  bool get toSign =>
      needsAck && currentVersion > 0 && myAckVersion != currentVersion;
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
  return [for (final r in rows) Doc.fromJson(r, mine)];
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
    await _flushAndReload();
    return id;
  }

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
    'dwg' => 'application/acad',
    _ => 'application/octet-stream',
  };
}
