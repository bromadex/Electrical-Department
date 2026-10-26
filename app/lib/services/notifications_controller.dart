import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_error.dart';
import 'core_providers.dart';

class AppNotification {
  const AppNotification({
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
  final DateTime? readAt;

  bool get isRead => readAt != null;

  AppNotification markedRead(DateTime at) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    link: link,
    createdAt: createdAt,
    readAt: at,
  );
}

class NotificationsState {
  const NotificationsState({this.items = const [], this.error});

  final List<AppNotification> items;
  final AppError? error;

  int get unread => items.where((n) => !n.isRead).length;
}

/// The signed-in user's notifications, kept live over the
/// `notifications:<user_id>` realtime channel.
final notificationsProvider =
    NotifierProvider<NotificationsNotifier, NotificationsState>(
      NotificationsNotifier.new,
    );

class NotificationsNotifier extends Notifier<NotificationsState> {
  static const pageSize = 50;

  @override
  NotificationsState build() {
    final userId = ref.watch(authUserIdProvider);
    if (userId == null) return const NotificationsState();

    final client = ref.read(supabaseProvider);
    final channel = client
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
            if (n.type == 'chat' || state.items.any((i) => i.id == n.id)) {
              return;
            }
            state = NotificationsState(items: [n, ...state.items]);
          },
        )
        .subscribe();
    ref.onDispose(() => unawaited(client.removeChannel(channel)));

    Future.microtask(refresh);
    return const NotificationsState();
  }

  Future<void> refresh() async {
    try {
      final rows = await ref
          .read(supabaseProvider)
          .from('notifications')
          .select()
          .eq('is_archived', false)
          // Chat messages show as unread counts on the Chat tab instead.
          .neq('type', 'chat')
          .order('created_at', ascending: false)
          .limit(pageSize);
      if (!ref.mounted) return;
      state = NotificationsState(
        items: [for (final r in rows) AppNotification.fromRow(r)],
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = NotificationsState(items: state.items, error: AppError.from(e));
    }
  }

  /// Marks [ids] read, or everything when null. Works offline.
  Future<void> markRead([List<String>? ids]) async {
    final now = DateTime.now();
    state = NotificationsState(
      items: [
        for (final n in state.items)
          !n.isRead && (ids == null || ids.contains(n.id))
              ? n.markedRead(now)
              : n,
      ],
      error: state.error,
    );
    await ref.read(outboxProvider).enqueue('fn_mark_read', {'p_ids': ids});
  }
}
