import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/core_providers.dart';
import '../../theme/theme_mode.dart';
import '../documents_repository.dart';
import 'file_store.dart';

/// A document kept on this phone: which version, and where.
class OfflineCopy {
  const OfflineCopy({
    required this.docId,
    required this.version,
    required this.fileName,
    required this.file,
    required this.size,
    required this.savedAt,
  });

  OfflineCopy.fromJson(Map<String, dynamic> j)
    : docId = j['id'] as String,
      version = (j['v'] as num).toInt(),
      fileName = j['name'] as String,
      file = j['file'] as String,
      size = (j['size'] as num?)?.toInt() ?? 0,
      savedAt = DateTime.parse(j['at'] as String);

  final String docId;
  final int version;
  final String fileName;

  /// Its name in the app's offline folder.
  final String file;
  final int size;
  final DateTime savedAt;

  Map<String, Object> toJson() => {
    'id': docId,
    'v': version,
    'name': fileName,
    'file': file,
    'size': size,
    'at': savedAt.toIso8601String(),
  };
}

/// Documents kept on this phone ("Keep on this phone"), by document id.
/// They open without signal and are brought up to date when a newer
/// version is uploaded and the phone is online. Browsers keep none.
final offlineDocsProvider =
    NotifierProvider<OfflineDocs, Map<String, OfflineCopy>>(OfflineDocs.new);

class OfflineDocs extends Notifier<Map<String, OfflineCopy>> {
  static const _key = 'offline_documents';
  final _store = FileStore();

  static bool get supported => FileStore.supported;

  @override
  Map<String, OfflineCopy> build() {
    try {
      final raw = ref.read(sharedPrefsProvider).getString(_key);
      if (raw == null) return const {};
      final list = jsonDecode(raw) as List;
      return {
        for (final e in list)
          if (e is Map)
            (e['id'] as String): OfflineCopy.fromJson(
              Map<String, dynamic>.from(e),
            ),
      };
    } catch (_) {
      return const {};
    }
  }

  void _save(Map<String, OfflineCopy> next) {
    state = next;
    try {
      ref
          .read(sharedPrefsProvider)
          .setString(
            _key,
            jsonEncode([for (final c in next.values) c.toJson()]),
          );
    } catch (_) {}
  }

  /// Downloads the current version and keeps it (replacing an older one).
  Future<void> keep(Doc doc) async {
    final v = doc.current;
    if (!supported || v == null) return;
    final bytes = await ref
        .read(supabaseProvider)
        .storage
        .from('documents')
        .download(v.path);
    final safe = v.fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = '${doc.id}-v${v.version}-$safe';
    await _store.write(file, bytes);
    final old = state[doc.id];
    if (old != null && old.file != file) await _store.delete(old.file);
    _save({
      ...state,
      doc.id: OfflineCopy(
        docId: doc.id,
        version: v.version,
        fileName: v.fileName,
        file: file,
        size: bytes.length,
        savedAt: DateTime.now(),
      ),
    });
  }

  Future<void> remove(String docId) async {
    final c = state[docId];
    if (c == null) return;
    await _store.delete(c.file);
    _save({...state}..remove(docId));
  }

  /// The kept bytes of [docId], if this phone has [version] (or, with
  /// [version] null, whatever version it has).
  Future<Uint8List?> read(String docId, {int? version}) async {
    final c = state[docId];
    if (c == null || (version != null && c.version != version)) return null;
    return _store.read(c.file);
  }

  /// A path to the kept file, for "Open with another app".
  Future<String?> pathOf(String docId) async {
    final c = state[docId];
    return c == null ? null : _store.pathOf(c.file);
  }

  /// Brings kept copies up to date with [docs] (newer versions uploaded)
  /// and drops copies of documents that were archived. Returns how many
  /// were downloaded again. Failures (no signal) leave the old copy.
  Future<int> refresh(List<Doc> docs) async {
    if (!supported || state.isEmpty) return 0;
    final byId = {for (final d in docs) d.id: d};
    var n = 0;
    for (final c in [...state.values]) {
      final d = byId[c.docId];
      if (d == null) continue;
      if (d.currentVersion > c.version) {
        try {
          await keep(d);
          n++;
        } catch (_) {
          // Offline or the file is gone: keep the old copy for now.
        }
      }
    }
    return n;
  }

  int get totalBytes => state.values.fold(0, (n, c) => n + c.size);
}

/// The bytes of a version: the kept copy when this phone has it, otherwise
/// downloaded (and, for a kept document with a newer version, kept again).
final documentBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, ({String docId, DocVersion version})>((ref, k) async {
      final offline = ref.read(offlineDocsProvider.notifier);
      final kept = await offline.read(k.docId, version: k.version.version);
      if (kept != null) return kept;
      try {
        final bytes = await ref
            .read(supabaseProvider)
            .storage
            .from('documents')
            .download(k.version.path);
        return bytes;
      } catch (e) {
        // No signal: an older kept version is better than nothing.
        final older = await offline.read(k.docId);
        if (older != null) return older;
        rethrow;
      }
    });

/// Keeps offline copies fresh whenever the document list loads.
final offlineRefreshProvider = Provider<void>((ref) {
  ref.listen(documentsProvider, (_, next) {
    final docs = next.value;
    if (docs != null && OfflineDocs.supported) {
      ref.read(offlineDocsProvider.notifier).refresh(docs);
    }
  });
});
