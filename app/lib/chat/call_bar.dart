import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'call_controller.dart';
import 'chat_repository.dart';

/// The green "Tap to return to call · 3:12 · 🎤" bar above every screen
/// while a call is minimised (as on WhatsApp). Hidden on the call screen.
class CallBar extends ConsumerStatefulWidget {
  const CallBar({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<CallBar> createState() => _CallBarState();
}

class _CallBarState extends ConsumerState<CallBar> {
  late final CallController _call = ref.read(callControllerProvider);

  @override
  void initState() {
    super.initState();
    _call.addListener(_changed);
    widget.router.routerDelegate.addListener(_changed);
  }

  @override
  void dispose() {
    _call.removeListener(_changed);
    widget.router.routerDelegate.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String get _path {
    try {
      return widget.router.routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _call.conversationId;
    final show =
        _call.stage == CallStage.inCall &&
        id != null &&
        !_path.endsWith('/call');
    if (!show) return widget.child;
    final chats = ref.watch(conversationsProvider).value ?? const [];
    final title =
        chats.where((c) => c.id == id).firstOrNull?.title ??
        _call.serverTitle ??
        'Call';
    final mic = _call.room?.localParticipant?.isMicrophoneEnabled() ?? false;
    final status =
        _call.elapsed ??
        (_call.waiting ? (_call.rang ? 'Ringing…' : 'Calling…') : 'Waiting');
    final top = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        Material(
          color: const Color(0xFF1F9D5A),
          child: InkWell(
            onTap: () => unawaited(widget.router.push('/chat/$id/call')),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, top + 6, 8, 6),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.phone_fill,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap to return to call · $title · $status',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: mic ? 'Mute' : 'Unmute',
                    visualDensity: VisualDensity.compact,
                    onPressed: _call.toggleMic,
                    icon: Icon(
                      mic
                          ? CupertinoIcons.mic_fill
                          : CupertinoIcons.mic_slash_fill,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hang up',
                    visualDensity: VisualDensity.compact,
                    onPressed: _call.leave,
                    icon: const Icon(
                      CupertinoIcons.phone_down_fill,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // The screen below starts under the bar.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
