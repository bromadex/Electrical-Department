import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:electrical_department/data/local_db.dart';
import 'package:electrical_department/services/outbox_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late LocalDb db;
  late List<(String, Map<String, dynamic>)> calls;
  late Object? failWith;
  late OutboxService outbox;

  setUp(() {
    db = LocalDb(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    calls = [];
    failWith = null;
    outbox = OutboxService(db, (fn, params) async {
      if (failWith != null) throw failWith!;
      calls.add((fn, params));
    });
  });

  tearDown(() => db.close());

  Future<List<OutboxEntry>> rows() => db.select(db.outbox).get();

  test('sends the call and removes it', () async {
    await outbox.enqueue('fn_mark_read', {'p_ids': null});
    await outbox.flush();

    expect(calls.single.$1, 'fn_mark_read');
    expect(calls.single.$2, {'p_ids': null});
    expect(await rows(), isEmpty);
  });

  test('keeps the call when offline and retries later', () async {
    failWith = Exception('offline');
    await outbox.enqueue('fn_mark_read', {'p_ids': null});
    await outbox.flush();

    var pending = await rows();
    expect(pending, hasLength(1));
    expect(pending.single.tries, 0, reason: 'no signal never uses up a try');
    expect(pending.single.lastError, contains('NETWORK'));

    failWith = null;
    await outbox.flush(force: true);
    expect(calls, hasLength(1));
    expect(await rows(), isEmpty);
    expect(outbox.waitUntil, isNull, reason: 'sending again resets the wait');
  });

  test('a long time without signal never drops queued work', () async {
    failWith = Exception('offline');
    await outbox.enqueue('fn_mark_read', {'p_ids': null});
    for (var i = 0; i < 3 * OutboxService.maxTries; i++) {
      await outbox.flush(force: true);
    }
    expect((await rows()).single.tries, 0);
    expect(await outbox.watchFailed().first, isEmpty);
    expect(await outbox.watchPending().first, 1);
  });

  test('after a failure for lack of signal, sending waits', () async {
    failWith = Exception('offline');
    await outbox.enqueue('fn_mark_read', {'p_ids': null});
    await outbox.flush();
    final wait = outbox.waitUntil!;
    expect(wait.difference(DateTime.now()).inSeconds, inInclusiveRange(25, 30));

    failWith = null;
    await outbox.flush();
    expect(calls, isEmpty, reason: 'the 30-second timer does not hammer');
    await outbox.flush(force: true);
    expect(calls, hasLength(1), reason: 'Send now goes straight away');
  });

  test('the wait doubles, up to ten minutes', () async {
    failWith = Exception('offline');
    await outbox.enqueue('fn_mark_read', {'p_ids': null});
    Duration left() => outbox.waitUntil!.difference(DateTime.now());
    await outbox.flush(force: true);
    expect(left().inSeconds, inInclusiveRange(25, 30));
    await outbox.flush(force: true);
    expect(left().inSeconds, inInclusiveRange(55, 60));
    for (var i = 0; i < 12; i++) {
      await outbox.flush(force: true);
    }
    expect(left().inMinutes, inInclusiveRange(9, 10));
  });

  test('work given up for lack of signal comes back', () async {
    await outbox.enqueue('fn_mark_read', {'p_ids': null}, flushNow: false);
    await (db.update(db.outbox)).write(
      const OutboxCompanion(
        tries: Value(OutboxService.maxTries),
        lastError: Value('NETWORK: Could not reach the server.'),
      ),
    );
    expect(await outbox.watchFailed().first, hasLength(1));
    expect(await outbox.reviveOfflineFailures(), 1);
    expect(await outbox.watchFailed().first, isEmpty);
    await outbox.flush(force: true);
    expect(calls, hasLength(1));
  });

  test('stops retrying when the server rejects the call', () async {
    failWith = const PostgrestException(
      message: 'NOT_ALLOWED: Your account is not active',
    );
    await outbox.enqueue('fn_register_device', {
      'p_token': 't',
      'p_platform': 'web',
    });
    await outbox.flush();

    final failed = await outbox.watchFailed().first;
    expect(failed.single.lastError, 'NOT_ALLOWED: Your account is not active');
    expect(await outbox.watchPending().first, 0);

    failWith = null;
    await outbox.flush();
    expect(calls, isEmpty);
    expect(
      await outbox.reviveOfflineFailures(),
      0,
      reason: 'a refusal from the server is not brought back',
    );

    await outbox.retry(failed.single.clientRef);
    expect(calls, hasLength(1), reason: 'Try again sends it once more');
  });

  test('rejects actions that are not in API.md', () {
    expect(
      () => outbox.enqueue('drop_everything', {}),
      throwsA(isA<ArgumentError>()),
    );
  });
}
