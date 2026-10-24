import 'package:supabase_flutter/supabase_flutter.dart';

/// An error from Supabase, split into the `CODE: human message` form that
/// database functions raise (see API.md section 1).
class AppError implements Exception {
  const AppError(this.code, this.message);

  /// Could not reach Supabase; worth retrying later.
  static const network = 'NETWORK';

  final String code;
  final String message;

  bool get isRetryable => code == network;

  factory AppError.from(Object error) {
    if (error is AppError) return error;
    if (error is PostgrestException) {
      final match = RegExp(r'^([A-Z_]+): (.+)$').firstMatch(error.message);
      if (match != null) return AppError(match.group(1)!, match.group(2)!);
      return AppError('SERVER', error.message);
    }
    if (error is AuthException) return AppError('AUTH', error.message);
    if (error is FunctionException) {
      final details = error.details;
      final text = details is Map
          ? details['error']?.toString()
          : details?.toString();
      final match = RegExp(r'^([A-Z_]+): (.+)$').firstMatch(text ?? '');
      if (match != null) return AppError(match.group(1)!, match.group(2)!);
      return AppError(
        'SERVER',
        text ?? error.reasonPhrase ?? 'The server could not do that.',
      );
    }
    if (error is StorageException) {
      final status = int.tryParse(error.statusCode ?? '');
      if (status == 401 || status == 403) {
        return AppError('NOT_ALLOWED', error.message);
      }
      if (status != null && status >= 400 && status < 500) {
        return AppError('SERVER', error.message);
      }
    }
    return const AppError(network, 'Could not reach the server.');
  }

  @override
  String toString() => '$code: $message';
}
