import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Sends app errors to Supabase (`fn_report_error`, API.md section 21), so
/// admins see what goes wrong on people's phones without a paid service.
/// Best effort: at most [maxPerSession] reports, each error once per
/// session, nothing sent while signed out, and a failure to send is ignored.
class ErrorReporter {
  ErrorReporter(this._client);

  final SupabaseClient _client;
  static const maxPerSession = 20;

  final _sent = <String>{};

  /// Where the app is, for the report (set from the router).
  static String Function()? currentRoute;

  void report(Object error, StackTrace? stack) {
    if (_client.auth.currentUser == null || _sent.length >= maxPerSession) {
      return;
    }
    final message = error.toString();
    final print = fingerprint(message, stack);
    if (!_sent.add(print)) return;
    String? route;
    try {
      route = currentRoute?.call();
    } catch (_) {}
    unawaited(
      _client
          .rpc(
            'fn_report_error',
            params: {
              'p_fingerprint': print,
              'p_message': message.length > 1000
                  ? message.substring(0, 1000)
                  : message,
              'p_stack': stack?.toString().split('\n').take(40).join('\n'),
              'p_route': route,
              'p_platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
              'p_app_version': Env.appVersion,
            },
          )
          .then((_) {}, onError: (_) {}),
    );
  }
}

/// The same error in the same place gets the same fingerprint: the error's
/// first line with numbers taken out, and the first frame in the app's own
/// code.
String fingerprint(String message, StackTrace? stack) {
  final first = message.split('\n').first.replaceAll(RegExp(r'\d+'), '#');
  final frame =
      stack
          ?.toString()
          .split('\n')
          .firstWhere(
            (l) => l.contains('package:electrical_department/'),
            orElse: () => '',
          )
          .replaceAll(RegExp(r'^#\d+\s+'), '')
          .replaceAll(RegExp(r':\d+(:\d+)?\)?$'), '') ??
      '';
  // FNV-1a, 32 bits: short and stable across runs.
  var h = 0x811c9dc5;
  for (final c in '$first|$frame'.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}
