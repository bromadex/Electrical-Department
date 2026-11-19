import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'push_service.dart';

/// Android notification channels, and the pop-up banner for pushes that
/// arrive while the app is open (Android only shows a push itself when the
/// app is in the background), as on WhatsApp.
///
/// Channels (push-send picks one per alert type):
/// * `messages` — chat messages and @mentions: pops up, with sound.
/// * `urgent` — critical, overdue and (re)assigned job cards, meetings and
///   missed calls: pops up.
/// * `general` — everything else: in the shade, no pop-up.
class MessageBanners {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const _channels = [
    AndroidNotificationChannel(
      'messages',
      'Messages',
      description: 'Chat messages and @mentions',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      'urgent',
      'Urgent alerts',
      description:
          'Critical, overdue and assigned job cards; meetings and '
          'missed calls',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      'general',
      'Other alerts',
      description: 'Reminders, approvals and everything else',
    ),
  ];

  /// The channel for an alert type (the same rule as push-send).
  static String channelFor(String? type) => switch (type) {
    'chat' || 'mentioned' => 'messages',
    'critical' ||
    'overdue' ||
    'assigned' ||
    'reassigned' ||
    'meeting' => 'urgent',
    _ => 'general',
  };

  /// Creates the channels and handles a tapped banner by opening [open]'s
  /// path. Safe to call more than once.
  static Future<void> init(void Function(String path) open) async {
    if (!supported || _ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (r) {
          final path = r.payload;
          if (path != null && path.isNotEmpty) open(path);
        },
      );
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      for (final c in _channels) {
        await android?.createNotificationChannel(c);
      }
      _ready = true;
    } catch (e) {
      debugPrint('Notification channels: $e');
    }
  }

  /// Shows [m] as a banner while the app is open, unless [here] (the page
  /// on screen) is the one it opens: no banner for the chat you are in.
  static Future<void> show(RemoteMessage m, {required String here}) async {
    if (!_ready || m.data['kind'] == 'call') return;
    final title = m.notification?.title ?? '${m.data['title'] ?? ''}';
    final body = m.notification?.body ?? '';
    if (title.isEmpty && body.isEmpty) return;
    final link = '${m.data['link'] ?? ''}';
    final path = notificationPath(link) ?? '';
    if (path.isNotEmpty && (here == path || here.startsWith('$path/'))) return;
    final channel = channelFor('${m.data['type'] ?? ''}');
    final c = _channels.firstWhere((x) => x.id == channel);
    try {
      await _plugin.show(
        // One banner per chat or record: a newer message replaces it.
        id:
            (link.isEmpty ? '${m.data['notification_id']}' : link).hashCode &
            0x7fffffff,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            c.id,
            c.name,
            channelDescription: c.description,
            importance: c.importance,
            priority: c.importance == Importance.high
                ? Priority.high
                : Priority.defaultPriority,
            category: channel == 'messages'
                ? AndroidNotificationCategory.message
                : null,
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
        payload: path,
      );
    } catch (e) {
      debugPrint('Banner: $e');
    }
  }
}
