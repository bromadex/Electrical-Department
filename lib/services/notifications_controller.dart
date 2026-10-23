import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_error.dart';
import 'outbox_service.dart';

class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.createdAt,
    this.body,
    this.link,
    this.readAt,
  });

  factory AppNotification.fromRow(Map<String, dynamic> r) => AppNotification(
    id: r['id'] as String,
    type: r['type'] as String,
    title: r['title'] as String,
    body: r['body'] as String?,
    link: r['link'] as String?,
    readAt: r['read_at'] == null
        ? null
        : DateTime.parse(r['read_at'] as String),
    createdAt: DateTime.parse(r['created_at'] as String),
  );

  final String id;
  final String type;
  final String title;
  final String? body;
  final String? link;
  final DateTime createdAt;
  DateTime? readAt;

  bool get isRead => readAt != null;
}

/// The signed-in user's notifications, kept live over the
/// `notifications:<user_id>` realtime channel.
class NotificationsController extends ChangeNotifier {
  NotificationsController(this._client, this._outbox);

  static const pageSize = 50;

  final SupabaseClient _client;
  final OutboxService _outbox;
  RealtimeChannel? _channel;

  List<AppNotification> items = [];
  AppError? error;

  int get unread => items.where((n) => !n.isRead).length;

  Future<void> start(String userId) async {
    await stop();
    _channel = _client
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final n = AppNotification.fromRow(payload.newRecord);
            if (items.any((i) => i.id == n.id)) return;
            items = [n, ...items];
            notifyListeners();
          },
        )
        .subscribe();
    await refresh();
  }

  Future<void> refresh() async {
    try {
      final rows = await _client
          .from('notifications')
          .select()
          .eq('is_archived', false)
          .order('created_at', ascending: false)
          .limit(pageSize);
      items = [for (final r in rows) AppNotification.fromRow(r)];
      error = null;
    } catch (e) {
      error = AppError.from(e);
    }
    notifyListeners();
  }

  /// Marks [ids] read, or everything when null. Works offline.
  Future<void> markRead([List<String>? ids]) async {
    final now = DateTime.now();
    for (final n in items) {
      if (!n.isRead && (ids == null || ids.contains(n.id))) n.readAt = now;
    }
    notifyListeners();
    await _outbox.enqueue('fn_mark_read', {'p_ids': ids});
  }

  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) await _client.removeChannel(channel);
    items = [];
    error = null;
    notifyListeners();
  }
}
