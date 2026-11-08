import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:electrical_department/data/app_error.dart';
import 'package:electrical_department/data/local_db.dart';
import 'package:electrical_department/services/outbox_service.dart';
import 'package:electrical_department/store/store_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Issues #28 and #29: unsent work is never lost silently, and a change
/// never reaches the server pointing at a file that was refused.
void main() {
  late LocalDb db;
  late List<String> calls;
  late List<String> uploaded;
  late Set<String> refuse;
  late OutboxService outbox;

  setUp(() {
    db = LocalDb(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    calls = [];
    uploaded = [];
    refuse = {};
    outbox = OutboxService(db, (fn, params) async => calls.add(fn), (
      bucket,
      path,
      bytes,
      type,
    ) async {
      if (refuse.contains(path)) {
        throw const AppError('INVALID', 'The file is too big');
      }
      uploaded.add(path);
    });
  });

  tearDown(() => db.close());

  Future<void> photo(String path) => outbox.enqueueUpload(
    id: path,
    bucket: 'job-card-files',
    path: path,
    bytes: Uint8List.fromList([1, 2, 3]),
  );

  test('a change waits while the file it names was refused', () async {
    refuse.add('jc/1/a.jpg');
    await photo('jc/1/a.jpg');
    await outbox.enqueue('fn_add_job_attachment', {
      'p_path': 'jc/1/a.jpg',
    }, flushNow: false);
    await outbox.enqueue('fn_mark_read', {'p_ids': null}, flushNow: false);
    await outbox.flush(force: true);

    expect(calls, isEmpty, reason: 'nothing overtakes the held change');
    final held = await db.select(db.outbox).get();
    expect(held, hasLength(2));
    expect(held.first.tries, 0, reason: 'held, not failed');
    expect(held.first.lastError, contains('a.jpg'));

    // The file is tried again and goes: the change follows.
    refuse.clear();
    final u = await db.select(db.pendingUploads).getSingle();
    await outbox.retryUpload(u.id);
    expect(uploaded, ['jc/1/a.jpg']);
    expect(calls, ['fn_add_job_attachment', 'fn_mark_read']);
  });

  test('changes that do not name a refused file still go', () async {
    refuse.add('jc/1/a.jpg');
    await photo('jc/1/a.jpg');
    await outbox.enqueue('fn_mark_read', {'p_ids': null}, flushNow: false);
    await outbox.flush(force: true);
    expect(calls, ['fn_mark_read']);
  });

  test('discarding a refused file discards the changes that name it', () async {
    refuse.add('jc/1/a.jpg');
    await photo('jc/1/a.jpg');
    await outbox.enqueue('fn_add_job_attachment', {
      'p_path': 'jc/1/a.jpg',
    }, flushNow: false);
    await outbox.enqueue('fn_mark_read', {'p_ids': null}, flushNow: false);
    await outbox.flush(force: true);

    final u = await db.select(db.pendingUploads).getSingle();
    expect(await outbox.discardUpload(u.id), 1);
    await outbox.flush(force: true);
    expect(calls, ['fn_mark_read']);
  });

  test('unsent work counts waiting and refused changes and files', () async {
    refuse.add('jc/1/a.jpg');
    await photo('jc/1/a.jpg');
    await outbox.enqueue('fn_mark_read', {'p_ids': null}, flushNow: false);
    expect(await outbox.unsentCount(), 2);
    await outbox.discardAll();
    expect(await outbox.unsentCount(), 0);
  });

  test('clearing the cache keeps unsent work unless told not to', () async {
    await photo('jc/1/a.jpg');
    await outbox.enqueue('fn_mark_read', {'p_ids': null}, flushNow: false);
    await db.saveJson('jobs', '[]');

    await db.clearAll();
    expect(await db.readJson('jobs'), isNull);
    expect(await outbox.unsentCount(), 2);

    await db.clearAll(keepUnsent: false);
    expect(await outbox.unsentCount(), 0);
  });

  test('heldBy finds the refused path a payload names', () {
    expect(
      OutboxService.heldBy('{"p_path":"a/b.jpg"}', ['a/b.jpg']),
      'a/b.jpg',
    );
    expect(OutboxService.heldBy('{"p_path":"a/c.jpg"}', ['a/b.jpg']), isNull);
  });

  test('a count in progress survives being saved and read back', () {
    final at = DateTime(2026, 11, 8, 9, 30);
    final draft = CountDraft(
      counted: {'i1': 12.5, 'i2': 0},
      countedAt: {'i1': at},
      note: 'Monthly',
    );
    final back = CountDraft.decode(draft.encode());
    expect(back.counted, {'i1': 12.5, 'i2': 0});
    expect(back.countedAt, {'i1': at});
    expect(back.note, 'Monthly');
    expect(CountDraft.decode('not json').isEmpty, isTrue);
    expect(CountDraft.decode(null).isEmpty, isTrue);
  });
}
