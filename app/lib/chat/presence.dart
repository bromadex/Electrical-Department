import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/core_providers.dart';

/// Who has the app open right now, and who is typing in which chat. Lives
/// on one realtime channel (presence for online, broadcast for typing);
/// nothing is stored. AppShell watches it so it runs while signed in.
class ChatPresence {
  const ChatPresence({this.online = const {}, this.typing = const {}});

  final Set<String> online;

  /// conversation id → people typing there.
  final Map<String, Set<String>> typing;

  bool isOnline(String? userId) => userId != null && online.contains(userId);

  Set<String> typingIn(String conversationId, {String? except}) => {
    for (final u in typing[conversationId] ?? const <String>{})
      if (u != except) u,
  };
}

final chatPresenceProvider =
    NotifierProvider<ChatPresenceNotifier, ChatPresence>(
      ChatPresenceNotifier.new,
    );

class ChatPresenceNotifier extends Notifier<ChatPresence> {
  RealtimeChannel? _channel;
  final _expiry = <String, Timer>{};
  DateTime _lastSent = DateTime(2000);

  @override
  ChatPresence build() {
    final me = ref.watch(authUserIdProvider);
    if (me == null) return const ChatPresence();
    final client = ref.read(supabaseProvider);
    final channel = client.channel(
      'online',
      opts: RealtimeChannelConfig(key: me),
    );
    _channel = channel;
    channel
        .onPresenceSync((_) {
          if (!ref.mounted) return;
          state = ChatPresence(
            online: {for (final s in channel.presenceState()) s.key},
            typing: state.typing,
          );
        })
        .onBroadcast(event: 'typing', callback: _typing)
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) _show(channel);
        });
    // Phones: leaving the app ends "Online" at once (they keep the
    // connection open a while in the background); coming back starts it
    // again. Browsers stay online while the tab is open, as on WhatsApp Web.
    final life = kIsWeb
        ? null
        : AppLifecycleListener(
            onHide: () => unawaited(channel.untrack()),
            onShow: () => _show(channel),
          );
    ref.onDispose(() {
      life?.dispose();
      for (final t in _expiry.values) {
        t.cancel();
      }
      _expiry.clear();
      _channel = null;
      unawaited(client.removeChannel(channel));
    });
    return const ChatPresence();
  }

  void _show(RealtimeChannel channel) {
    final state = SchedulerBinding.instance.lifecycleState;
    if (!kIsWeb && state != null && state != AppLifecycleState.resumed) {
      return;
    }
    unawaited(channel.track({'at': DateTime.now().toIso8601String()}));
  }

  void _typing(Map<String, dynamic> message) {
    final p = message['payload'] is Map
        ? Map<String, dynamic>.from(message['payload'] as Map)
        : message;
    final chat = p['c'] as String?;
    final user = p['u'] as String?;
    if (chat == null || user == null || !ref.mounted) return;
    _set(chat, user, true);
    final key = '$chat/$user';
    _expiry[key]?.cancel();
    _expiry[key] = Timer(const Duration(seconds: 4), () {
      _expiry.remove(key);
      if (ref.mounted) _set(chat, user, false);
    });
  }

  void _set(String chat, String user, bool on) {
    final now = {...?state.typing[chat]};
    on ? now.add(user) : now.remove(user);
    state = ChatPresence(
      online: state.online,
      typing: {...state.typing, chat: now},
    );
  }

  /// Tells the others you are typing in [conversationId]; at most every
  /// two seconds.
  void typing(String conversationId) {
    final me = ref.read(authUserIdProvider);
    final channel = _channel;
    if (me == null || channel == null) return;
    final now = DateTime.now();
    if (now.difference(_lastSent) < const Duration(seconds: 2)) return;
    _lastSent = now;
    unawaited(
      channel.sendBroadcastMessage(
        event: 'typing',
        payload: {'c': conversationId, 'u': me},
      ),
    );
  }
}
