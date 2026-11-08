import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:electrical_department/data/app_error.dart';
import 'package:electrical_department/data/local_db.dart';
import 'package:electrical_department/screens/outbox_screen.dart';
import 'package:electrical_department/services/error_reporter.dart';
import 'package:electrical_department/services/outbox_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('error fingerprints', () {
    final stack = StackTrace.fromString(
      '#0      Object.noSuchMethod (dart:core-patch/object_patch.dart:38:5)\n'
      '#1      _StoreScreenState.build (package:electrical_department/store/store_screen.dart:120:14)\n'
      '#2      StatefulElement.build (package:flutter/src/widgets/framework.dart:5583:27)',
    );

    test('the same error in the same place gets the same fingerprint', () {
      expect(
        fingerprint('RangeError (index): Invalid value: 3', stack),
        fingerprint('RangeError (index): Invalid value: 7', stack),
        reason: 'numbers in the message do not split a group',
      );
    });

    test('a different error or place gets another', () {
      final other = StackTrace.fromString(
        '#0      _ToolsScreenState.build (package:electrical_department/tools/tools_screen.dart:88:3)',
      );
      expect(
        fingerprint('RangeError', stack),
        isNot(fingerprint('RangeError', other)),
      );
      expect(
        fingerprint('RangeError', stack),
        isNot(fingerprint('StateError', stack)),
      );
      expect(fingerprint('x', null), hasLength(8));
    });
  });

  group('the phone', () {
    late LocalDb db;
    setUp(
      () => db = LocalDb(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      ),
    );
    tearDown(() => db.close());

    test('files waiting for signal are capped at 300 MB', () async {
      final outbox = OutboxService(db, (_, _) async {});
      final big = Uint8List(200 * 1024 * 1024);
      await outbox.enqueueUpload(id: 'a', bucket: 'b', path: 'p/a', bytes: big);
      await expectLater(
        outbox.enqueueUpload(id: 'b', bucket: 'b', path: 'p/b', bytes: big),
        throwsA(isA<AppError>()),
      );
      await outbox.discardUpload('a');
      await outbox.enqueueUpload(id: 'b', bucket: 'b', path: 'p/b', bytes: big);
    });

    test('cached lists not refreshed for 60 days are dropped', () async {
      await db.saveJson('fresh', '[]');
      await db
          .into(db.cachedJson)
          .insert(
            CachedJsonData(
              key: 'stale',
              json: '[]',
              savedAt: DateTime.now().subtract(const Duration(days: 61)),
            ),
          );
      expect(await db.pruneJson(), 1);
      expect(await db.readJson('fresh'), '[]');
      expect(await db.readJson('stale'), isNull);
    });
  });

  test('queued actions have readable names', () {
    expect(actionLabel('fn_create_mr'), 'Material request');
    expect(actionLabel('fn_mark_conversation_read'), 'Mark conversation read');
  });
}
