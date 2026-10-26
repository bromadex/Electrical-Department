import 'dart:io';

import 'package:electrical_department/services/outbox_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every function the app queues is an allowed outbox action', () {
    final queued = <String>{};
    final call = RegExp(r"""(?:enqueue|_queue)\(\s*'(fn_[a-z_]+)'""");
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final m in call.allMatches(f.readAsStringSync())) {
        queued.add(m.group(1)!);
      }
    }
    expect(queued, isNotEmpty);
    expect(
      queued.difference(OutboxService.actions.keys.toSet()),
      isEmpty,
      reason: 'Add these to OutboxService.actions',
    );
  });
}
