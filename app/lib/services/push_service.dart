import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/firebase_config.dart';
import '../theme/theme_mode.dart';
import 'core_providers.dart';

/// Push notifications on this device (API.md section 8).
enum PushState {
  /// Not set up for this platform or browser.
  unavailable,

  /// Supported, but not switched on here (yet).
  off,

  /// This device gets pushes for the signed-in person.
  on,

  /// The person blocked notifications in the browser or phone settings.
  blocked,
}

/// Starts Firebase once, before the app runs. Never throws: without Firebase
/// the app works as before, only without pushes.
/// Where a notification link opens in the app: `job:<id>` → `/jobs/<id>`,
/// `chat:<id>` → `/chat/<id>`, `tool:<id>` → `/tools/<id>`. Unknown links
/// open nothing.
String? notificationPath(String? link) {
  if (link == null) return null;
  final i = link.indexOf(':');
  if (i <= 0 || i == link.length - 1) return null;
  final id = link.substring(i + 1);
  return switch (link.substring(0, i)) {
    'job' => '/jobs/$id',
    'chat' => '/chat/$id',
    'tool' => '/tools/$id',
    _ => null,
  };
}

class PushSupport {
  static bool ready = false;

  static Future<void> init() async {
    final options = FirebaseConfig.options;
    if (options == null) return;
    try {
      await Firebase.initializeApp(options: options);
      ready = await FirebaseMessaging.instance.isSupported();
    } catch (e) {
      debugPrint('Push notifications are off: $e');
      ready = false;
    }
  }
}

final pushProvider = NotifierProvider<PushNotifier, PushState>(
  PushNotifier.new,
);

class PushNotifier extends Notifier<PushState> {
  /// Set when the person switched alerts off on this device.
  static const _offKey = 'push_off';

  String? _token;
  StreamSubscription<String>? _refresh;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  String get _platform => kIsWeb ? 'web' : 'android';

  @override
  PushState build() {
    final userId = ref.watch(authUserIdProvider);
    ref.onDispose(() => _refresh?.cancel());
    if (!PushSupport.ready) return PushState.unavailable;
    if (userId != null) Future.microtask(_sync);
    return PushState.off;
  }

  /// On start: keeps the token registered when permission was given before.
  Future<void> _sync() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      if (!ref.mounted) return;
      switch (settings.authorizationStatus) {
        case AuthorizationStatus.denied ||
            AuthorizationStatus.deniedPermanently:
          state = PushState.blocked;
        case AuthorizationStatus.authorized || AuthorizationStatus.provisional:
          if (ref.read(sharedPrefsProvider).getBool(_offKey) ?? false) return;
          await _register();
        case AuthorizationStatus.notDetermined:
          break;
      }
    } catch (e) {
      debugPrint('Push sync failed: $e');
    }
  }

  /// Asks for permission (the browser needs a tap first) and registers.
  Future<void> enable() async {
    if (!PushSupport.ready) return;
    await ref.read(sharedPrefsProvider).setBool(_offKey, false);
    final settings = await _messaging.requestPermission();
    if (!ref.mounted) return;
    switch (settings.authorizationStatus) {
      case AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently:
        state = PushState.blocked;
      case AuthorizationStatus.authorized || AuthorizationStatus.provisional:
        await _register();
      case AuthorizationStatus.notDetermined:
        state = PushState.off;
    }
  }

  // push-send addresses devices by FCM registration token (HTTP v1 `token`).
  // firebase_messaging 17 marks the token calls deprecated in favour of
  // installation IDs for direct send; they still work, and keeping tokens
  // keeps the device and the server in step.

  Future<void> disable() async {
    await ref.read(sharedPrefsProvider).setBool(_offKey, true);
    await forgetDevice();
    if (ref.mounted) state = PushState.off;
  }

  Future<void> _register() async {
    // ignore: deprecated_member_use
    final token = await _messaging.getToken(
      vapidKey: kIsWeb ? FirebaseConfig.vapidKey : null,
    );
    if (token == null || !ref.mounted) return;
    await _save(token);
    // ignore: deprecated_member_use
    _refresh ??= _messaging.onTokenRefresh.listen(_save);
    state = PushState.on;
  }

  Future<void> _save(String token) async {
    _token = token;
    final outbox = ref.read(outboxProvider);
    await outbox.enqueue('fn_register_device', {
      'p_token': token,
      'p_platform': _platform,
    });
    unawaited(outbox.flush());
  }

  /// Stops pushes to this device for the signed-in person: when alerts are
  /// switched off, and before signing out (a shared phone must not keep
  /// getting the last person's jobs).
  Future<void> forgetDevice() async {
    final token = _token;
    if (!PushSupport.ready || token == null) return;
    _token = null;
    await _refresh?.cancel();
    _refresh = null;
    try {
      await ref
          .read(supabaseProvider)
          .rpc('fn_unregister_device', params: {'p_token': token});
    } catch (e) {
      debugPrint('Could not unregister this device: $e');
    }
    try {
      // ignore: deprecated_member_use
      await _messaging.deleteToken();
    } catch (_) {}
  }
}
