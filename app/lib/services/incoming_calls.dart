import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../config/env.dart';
import '../config/firebase_config.dart';

/// Ringing calls on Android. A direct call arrives as a high-priority data
/// push (push-send, type `call`); this shows the full-screen incoming call
/// with a ringtone, even when the app is closed or the phone is locked.
/// Answer opens the call (see [IncomingCalls.listen] in main.dart).

/// Runs in the background, also when the app is closed.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessage(RemoteMessage message) async {
  // The caller gave up: stop this phone ringing for that chat.
  if (await IncomingCalls.stopRingingFor(message.data)) return;
  // A chat alert: tell the sender it reached this phone (two grey ticks).
  if (const {'chat', 'mentioned'}.contains(message.data['type'])) {
    await IncomingCalls.reportReceived(
      '${message.data['notification_id'] ?? ''}',
    );
    return;
  }
  if (message.data['kind'] != 'call') return;
  final options = FirebaseConfig.options;
  if (options != null && Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: options);
  }
  await IncomingCalls.ring(message.data);
}

class IncomingCalls {
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Opens the call when an incoming call is answered, also when answering
  /// started the app.
  static StreamSubscription<CallEvent?>? listen(void Function(String) open) {
    if (!supported) return null;
    unawaited(
      FlutterCallkitIncoming.activeCalls().then((calls) {
        for (final c in calls) {
          final path = c.isAccepted == true ? _callPath(c) : null;
          if (path != null) return open(path);
        }
      }, onError: (_) {}),
    );
    return FlutterCallkitIncoming.onEvent.listen((e) {
      if (e is CallEventActionCallAccept) {
        final path = _callPath(e.callKitParams);
        if (path != null) open(path);
      }
    }, onError: (_) {});
  }

  /// Hang up pressed on the "call in progress" notification.
  static Stream<String> get hungUp => supported
      ? FlutterCallkitIncoming.onEvent
            .where((e) => e is CallEventActionCallEnded)
            .map((e) => (e as CallEventActionCallEnded).callKitParams.id)
      : const Stream.empty();

  static String? _callPath(CallKitParams c) {
    final id = c.extra?['conversation_id'];
    if (id == null) return null;
    return '/chat/$id/call?join=1&ring=${Uri.encodeQueryComponent(c.id)}';
  }

  /// A "Missed call" alert (the caller hung up before anyone answered)
  /// stops this phone ringing for that chat. Only rings carry the chat in
  /// their extra; the "call in progress" notification does not, so a live
  /// call is never ended this way. Returns whether it was such an alert.
  static Future<bool> stopRingingFor(Map<String, dynamic> data) async {
    final link = '${data['link'] ?? ''}';
    final title = '${data['title'] ?? ''}';
    if (!link.startsWith('call:') || !title.startsWith('Missed call')) {
      return false;
    }
    if (!supported) return true;
    final chat = link.substring(5);
    try {
      for (final c in await FlutterCallkitIncoming.activeCalls()) {
        if (c.extra?['conversation_id'] == chat) {
          await FlutterCallkitIncoming.endCall(c.id);
        }
      }
    } catch (_) {
      // Nothing ringing, or the ring already timed out.
    }
    return true;
  }

  /// Shows the incoming-call screen for a `call` push.
  static Future<void> ring(Map<String, dynamic> data) async {
    if (!supported) return;
    final link = '${data['link'] ?? ''}';
    if (!link.startsWith('call:')) return;
    final body = '${data['body'] ?? 'Incoming call'}';
    await FlutterCallkitIncoming.showCallkitIncoming(
      CallKitParams(
        id: '${data['notification_id']}',
        nameCaller: '${data['caller'] ?? 'Someone'}',
        appName: 'Bravura Electrical',
        handle: body,
        type: body.contains('video') ? 1 : 0,
        // Rings for 45 seconds, like the caller's "No answer".
        duration: 45000,
        extra: {'conversation_id': link.substring(5)},
        // Our server already sends the missed-call alert.
        missedCallNotification: const NotificationParams(
          showNotification: false,
        ),
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#4E1019',
          actionColor: '#2FBF71',
          textColor: '#ffffff',
          incomingCallNotificationChannelName: 'Incoming calls',
          missedCallNotificationChannelName: 'Missed calls',
          isShowFullLockedScreen: true,
          textAccept: 'Answer',
          textDecline: 'Decline',
        ),
      ),
    );
    unawaited(reportReceived('${data['notification_id'] ?? ''}'));
  }

  /// Tells the server a push reached this phone: a call shows "Ringing…"
  /// to the caller instead of "Calling…", a chat message gets two grey
  /// ticks. Works without a sign-in, from the background: the alert's id
  /// is the proof (push-received). Best effort.
  static Future<void> reportReceived(String notificationId) async {
    if (notificationId.isEmpty || Env.supabaseUrl.isEmpty) return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.postUrl(
        Uri.parse('${Env.supabaseUrl}/functions/v1/push-received'),
      );
      req.headers
        ..contentType = ContentType.json
        ..set('apikey', Env.supabaseAnonKey);
      req.write(jsonEncode({'notification_id': notificationId}));
      await (await req.close().timeout(const Duration(seconds: 10)))
          .drain<void>();
    } catch (_) {
      // No signal: the sender keeps seeing one tick or "Calling…".
    } finally {
      client.close(force: true);
    }
  }

  /// The call screen while in a call: Android's "call in progress"
  /// notification, which keeps the microphone and sound going when the app
  /// is minimised or the screen is off. Returns the id to end it with.
  static Future<String?> startOngoing({
    required String id,
    required String title,
    required bool video,
  }) async {
    if (!supported) return null;
    try {
      await FlutterCallkitIncoming.startCall(
        CallKitParams(
          id: id,
          nameCaller: title,
          appName: 'Bravura Electrical',
          handle: 'Call in progress',
          type: video ? 1 : 0,
          callingNotification: const NotificationParams(
            showNotification: true,
            isShowCallback: true,
            subtitle: 'Call in progress · tap to return',
            callbackText: 'Hang up',
          ),
          android: const AndroidParams(
            isCustomNotification: true,
            isShowLogo: false,
            backgroundColor: '#4E1019',
            actionColor: '#E5484D',
            textColor: '#ffffff',
          ),
        ),
      );
      await FlutterCallkitIncoming.setCallConnected(id);
      return id;
    } catch (e) {
      debugPrint('Could not show the call notification: $e');
      return null;
    }
  }

  /// An answered incoming call is now connected.
  static Future<void> connected(String id) async {
    if (!supported) return;
    try {
      await FlutterCallkitIncoming.setCallConnected(id);
    } catch (_) {}
  }

  static Future<void> end(String id) async {
    if (!supported) return;
    try {
      await FlutterCallkitIncoming.endCall(id);
    } catch (_) {}
  }

  /// Asks once for what ringing needs on Android 13+ and 14+: notifications
  /// and full-screen alerts.
  static Future<void> askPermissions() async {
    if (!supported) return;
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Allow notifications',
        'rationaleMessagePermission':
            'Calls ring and job cards alert you through notifications.',
        'postNotificationMessageRequired':
            'Allow notifications for Bravura Electrical in your phone '
            'settings so calls can ring.',
      });
      if (!await FlutterCallkitIncoming.canUseFullScreenIntent()) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } catch (e) {
      debugPrint('Call permissions: $e');
    }
  }
}
