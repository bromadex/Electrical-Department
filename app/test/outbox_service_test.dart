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
    expect(pending.single.tries, greaterThanOrEqualTo(1));
    expect(pending.single.lastError, contains('NETWORK'));

    failWith = null;
    await outbox.flush();
    expect(calls, hasLength(1));
    expect(await rows(), isEmpty);
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
  });

  test('rejects actions that are not in API.md', () {
    expect(
      () => outbox.enqueue('drop_everything', {}),
      throwsA(isA<ArgumentError>()),
    );
  });
}
