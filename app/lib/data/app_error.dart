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
    return const AppError(network, 'Could not reach the server.');
  }

  @override
  String toString() => '$code: $message';
}
