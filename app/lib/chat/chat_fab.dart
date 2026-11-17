import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';
import '../services/core_providers.dart';
import '../services/notifications_controller.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import 'chat_repository.dart';

/// Chat lives behind this floating green button, bottom right on every
/// screen (docs/plan-whatsapp-theme.md, Phase A), instead of a tab. The red
/// badge counts chats with unread messages. Long-press (or hover with a
/// mouse) shows the last three chats to jump straight in. Hidden in chat
/// itself, in calls, while typing and before sign-in.
class ChatFabLayer extends ConsumerStatefulWidget {
  const ChatFabLayer({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  /// Screens where the button does not show.
  static bool hiddenOn(String path) =>
      path.startsWith('/chat') ||
      path.startsWith('/calls') ||
      path.startsWith('/starred') ||
      path.startsWith('/guest/') ||
      path == '/login' ||
      path == '/first-password';

  /// The tab screens: on phones the button sits above the tab bar.
  static bool isTab(String path) =>
      path == '/home' || path == '/jobs' || path == '/menu';

  @override
  ConsumerState<ChatFabLayer> createState() => _ChatFabLayerState();
}

class _ChatFabLayerState extends ConsumerState<ChatFabLayer> {
  bool _open = false;

  /// Browsers do not ring: an incoming call shows as WhatsApp Desktop's
  /// dark card at the top right (phones ring full screen instead).
  AppNotification? _incoming;
  Timer? _incomingTimer;
  final _seenCalls = <String>{};

  void _watchCalls() {
    ref.listen(notificationsProvider, (_, next) {
      if (!kIsWeb) return;
      for (final n in next.items) {
        if (n.type != 'call' ||
            n.isRead ||
            _seenCalls.contains(n.id) ||
            DateTime.now().difference(n.createdAt.toLocal()) >
                const Duration(seconds: 45)) {
          continue;
        }
        _seenCalls.add(n.id);
        setState(() => _incoming = n);
        _incomingTimer?.cancel();
        _incomingTimer = Timer(const Duration(seconds: 45), () {
          if (mounted) setState(() => _incoming = null);
        });
        break;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_changed);
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_changed);
    _incomingTimer?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() => _open = false);
  }

  String get _path => topPath(widget.router);

  void _go(String to) {
    setState(() => _open = false);
    widget.router.push(to);
  }

  @override
  Widget build(BuildContext context) {
    _watchCalls();
    final call = _incoming;
    final card = call == null
        ? null
        : Positioned(
            top: MediaQuery.paddingOf(context).top + 16,
            right: 16,
            child: _IncomingCallCard(
              call: call,
              onAccept: () {
                setState(() => _incoming = null);
                final id = (call.link ?? '').replaceFirst('call:', '');
                final video = (call.body ?? '').contains('video');
                widget.router.push(
                  '/chat/$id/call?join=1${video ? '&video=1' : ''}',
                );
              },
              onDecline: () => setState(() => _incoming = null),
            ),
          );
    return card == null
        ? _withFab(context)
        : Stack(children: [_withFab(context), card]);
  }

  Widget _withFab(BuildContext context) {
    final path = _path;
    final signedIn = ref.watch(authUserIdProvider) != null;
    final canChat = ref.watch(sessionProvider).can('chat.use');
    final mq = MediaQuery.of(context);
    final typing = mq.viewInsets.bottom > 0;
    if (!signedIn ||
        !canChat ||
        ChatFabLayer.hiddenOn(path) ||
        path.endsWith('/call') ||
        typing) {
      return widget.child;
    }
    final chats = ref.watch(conversationsProvider).value ?? const [];
    final unreadChats = chats.where((c) => c.unread > 0 && !c.muted).length;
    final recent = chats.take(3).toList();
    // Phones: above the floating tab bar on the tab screens; elsewhere above
    // where a screen's own ➕ button sits, so they never cover each other.
    final phone = mq.size.width < 720;
    final bottom =
        mq.padding.bottom + (phone && ChatFabLayer.isTab(path) ? 104.0 : 88.0);
    final right = mq.padding.right + (phone ? 18.0 : 28.0);

    return Stack(
      children: [
        widget.child,
        if (_open)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = false),
              child: const ColoredBox(color: Color(0x33000000)),
            ),
          ),
        Positioned(
          right: right,
          bottom: bottom,
          child: MouseRegion(
            onEnter: (_) {
              if (recent.isNotEmpty) setState(() => _open = true);
            },
            onExit: (_) => setState(() => _open = false),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_open)
                  for (final c in recent)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _RecentChip(
                        chat: c,
                        onTap: () => _go('/chat/${c.id}'),
                      ),
                    ),
                _Fab(
                  unread: unreadChats,
                  onTap: () => _go('/chat'),
                  onLongPress: recent.isEmpty
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          setState(() => _open = !_open);
                        },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Fab extends StatelessWidget {
  const _Fab({required this.unread, required this.onTap, this.onLongPress});

  final int unread;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: unread > 0 ? 'Chat, $unread unread' : 'Chat',
      child: Badge(
        isLabelVisible: unread > 0,
        backgroundColor: const Color(0xFFE5484D),
        offset: const Offset(-2, 2),
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Material(
          color: ChatColors.green,
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: Colors.black54,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            onLongPress: onLongPress,
            child: const SizedBox.square(
              dimension: 60,
              child: Icon(
                CupertinoIcons.chat_bubble_text_fill,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the last chats, shown above the button.
class _RecentChip extends StatelessWidget {
  const _RecentChip({required this.chat, required this.onTap});

  final Conversation chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? ChatColors.bubbleOtherDark : Colors.white,
      elevation: 4,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppAvatar(name: chat.title, userId: chat.otherUserId, size: 30),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  chat.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: dark ? ChatColors.textDark : ChatColors.text,
                    fontWeight: chat.unread > 0
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
              if (chat.unread > 0) ...[
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 10,
                  backgroundColor: ChatColors.green,
                  child: Text(
                    chat.unread > 99 ? '99+' : '${chat.unread}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// WhatsApp Desktop's incoming call card: photo, name, "Video call",
/// green Accept and red decline.
class _IncomingCallCard extends StatelessWidget {
  const _IncomingCallCard({
    required this.call,
    required this.onAccept,
    required this.onDecline,
  });

  final AppNotification call;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final video = (call.body ?? '').contains('video');
    return Material(
      color: const Color(0xFF1B1B1B),
      elevation: 12,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 300,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppAvatar(name: call.title, size: 64),
              const SizedBox(height: 10),
              Text(
                call.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                video ? 'Video call' : (call.body ?? 'Voice call'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.black,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: onAccept,
                      icon: Icon(
                        video
                            ? CupertinoIcons.video_camera_solid
                            : CupertinoIcons.phone_fill,
                      ),
                      label: const Text('Accept'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    tooltip: 'Decline',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFEA0038),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: onDecline,
                    icon: const Icon(CupertinoIcons.phone_down_fill),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
