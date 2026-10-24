import 'package:electrical_department/data/app_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('splits CODE: message from database functions', () {
    final e = AppError.from(
      const PostgrestException(message: 'NOT_ALLOWED: You cannot assign jobs'),
    );
    expect(e.code, 'NOT_ALLOWED');
    expect(e.message, 'You cannot assign jobs');
    expect(e.isRetryable, isFalse);
  });

  test('other server errors keep their message', () {
    final e = AppError.from(
      const PostgrestException(message: 'permission denied for table x'),
    );
    expect(e.code, 'SERVER');
    expect(e.isRetryable, isFalse);
  });

  test('edge function errors use the same CODE: message form', () {
    final e = AppError.from(
      const FunctionException(
        status: 403,
        details: {
          'error':
              'NOT_ALLOWED: Only a system administrator can create accounts',
        },
      ),
    );
    expect(e.code, 'NOT_ALLOWED');
    expect(e.message, 'Only a system administrator can create accounts');
  });

  test('unknown errors are treated as network problems', () {
    final e = AppError.from(Exception('socket closed'));
    expect(e.code, AppError.network);
    expect(e.isRetryable, isTrue);
  });
}
