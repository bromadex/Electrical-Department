import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'chat_repository.dart';

/// A chat's call (LiveKit). Calls start with sound only, which suits weak
/// signal at the sites; anyone can turn their camera on. [join] connects
/// straight away (the caller tapped Call); from a notification the screen
/// first asks.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({
    super.key,
    required this.conversationId,
    this.join = false,
  });

  final String conversationId;
  final bool join;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

enum _Stage { ready, connecting, inCall, ended }

class _CallScreenState extends ConsumerState<CallScreen> {
  Room? _room;
  _Stage _stage = _Stage.ready;
  String? _error;
  String? _title;
  DateTime? _since;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    if (widget.join) _join();
  }

  @override
  void dispose() {
    _clock?.cancel();
    final room = _room;
    if (room != null) {
      room.removeListener(_changed);
      unawaited(room.disconnect().then((_) => room.dispose()));
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _join() async {
    setState(() {
      _stage = _Stage.connecting;
      _error = null;
    });
    try {
      final res = await ref
          .read(supabaseProvider)
          .functions
          .invoke(
            'livekit-token',
            body: {'conversation_id': widget.conversationId},
          );
      final data = Map<String, dynamic>.from(res.data as Map);
      final room = Room(
        roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
      );
      room.addListener(_changed);
      await room.connect(data['url'] as String, data['token'] as String);
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (!mounted) {
        await room.disconnect();
        return;
      }
      _clock = Timer.periodic(const Duration(seconds: 1), (_) => _changed());
      setState(() {
        _room = room;
        _title = data['title'] as String?;
        _since = DateTime.now();
        _stage = _Stage.inCall;
      });
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = details is Map ? '${details['error'] ?? ''}' : '';
      setState(() {
        _stage = _Stage.ready;
        _error = msg.contains('UNAVAILABLE')
            ? 'Calls are not set up yet.'
            : msg.isNotEmpty
            ? msg.replaceFirst(RegExp(r'^[A-Z_]+: '), '')
            : 'Could not start the call.';
      });
    } catch (e) {
      setState(() {
        _stage = _Stage.ready;
        _error = 'Could not connect. Check your signal and try again.';
      });
    }
  }

  Future<void> _leave() async {
    HapticFeedback.mediumImpact();
    _clock?.cancel();
    await _room?.disconnect();
    if (!mounted) return;
    setState(() => _stage = _Stage.ended);
    context.canPop()
        ? context.pop()
        : context.go('/chat/${widget.conversationId}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chats = ref.watch(conversationsProvider).value ?? const [];
    final chat = chats.where((c) => c.id == widget.conversationId).firstOrNull;
    final title = _title ?? chat?.title ?? 'Call';
    final room = _room;
    final local = room?.localParticipant;
    final people = <Participant>[?local, ...?room?.remoteParticipants.values];

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: AppBackButton(fallback: '/chat/${widget.conversationId}'),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            Text(switch (_stage) {
              _Stage.inCall => '${people.length} in the call · ${_elapsed()}',
              _Stage.connecting => 'Connecting…',
              _ => 'Call',
            }, style: theme.textTheme.labelSmall),
          ],
        ),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: SafeArea(
          child: switch (_stage) {
            _Stage.inCall when room != null => Column(
              children: [
                Expanded(child: _Grid(people: people)),
                _Controls(local: local, onLeave: _leave, onChanged: _changed),
              ],
            ),
            _ => Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: BrandColors.brandGradient,
                      ),
                      child: const Icon(
                        CupertinoIcons.phone_fill,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    Text(title, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: Space.xs),
                    Text(
                      'Starts with sound only. Turn your camera on in the '
                      'call if you need to show something.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Space.md),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                    const SizedBox(height: Space.lg),
                    FilledButton.icon(
                      onPressed: _stage == _Stage.connecting ? null : _join,
                      style: FilledButton.styleFrom(
                        backgroundColor: BrandColors.success,
                        minimumSize: const Size(200, 52),
                      ),
                      icon: _stage == _Stage.connecting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(CupertinoIcons.phone_fill),
                      label: Text(
                        _stage == _Stage.connecting ? 'Joining…' : 'Join call',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          },
        ),
      ),
    );
  }

  String _elapsed() {
    final s = _since;
    if (s == null) return '0:00';
    final d = DateTime.now().difference(s);
    final m = d.inMinutes;
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:${(m % 60).toString().padLeft(2, '0')}:$sec'
        : '$m:$sec';
  }
}

/// Everyone in the call: one column on small phones, more as space allows.
class _Grid extends StatelessWidget {
  const _Grid({required this.people});

  final List<Participant> people;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = people.length <= 1
            ? 1
            : c.maxWidth >= 900
            ? 3
            : 2;
        const gap = Space.sm;
        final w = (c.maxWidth - Space.md * 2 - gap * (cols - 1)) / cols;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(Space.md),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final p in people)
                SizedBox(
                  width: w,
                  height: people.length <= 2 ? w * 0.9 : w,
                  child: _Tile(participant: p),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.participant});

  final Participant participant;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: participant,
      builder: (context, _) {
        final p = participant;
        final theme = Theme.of(context);
        final name = p is LocalParticipant
            ? 'You'
            : (p.name.isNotEmpty ? p.name : 'Someone');
        VideoTrack? video;
        for (final pub in p.videoTrackPublications) {
          final t = pub.track;
          if (t is VideoTrack && !pub.muted) video = t;
        }
        final speaking = p.isSpeaking;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.xl),
            border: Border.all(
              color: speaking ? BrandColors.success : Colors.transparent,
              width: 3,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.xl - 3),
            child: GlassSurface(
              radius: Radii.xl - 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (video != null)
                    VideoTrackRenderer(video, fit: VideoViewFit.cover)
                  else
                    Center(
                      child: AppAvatar(
                        name: p is LocalParticipant
                            ? (p.name.isNotEmpty ? p.name : 'Me')
                            : name,
                        size: 72,
                      ),
                    ),
                  Positioned(
                    left: Space.sm,
                    right: Space.sm,
                    bottom: Space.sm,
                    child: Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!p.isMicrophoneEnabled()) ...[
                                  const Icon(
                                    CupertinoIcons.mic_slash_fill,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.local,
    required this.onLeave,
    required this.onChanged,
  });

  final LocalParticipant? local;
  final VoidCallback onLeave;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final mic = local?.isMicrophoneEnabled() ?? false;
    final cam = local?.isCameraEnabled() ?? false;
    Widget round({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      Color? color,
      bool on = true,
    }) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color ?? (on ? Colors.white : Colors.white24),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: SizedBox.square(
              dimension: 60,
              child: Icon(
                icon,
                color: color != null || !on ? Colors.white : BrandColors.maroon,
                size: 26,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
      child: GlassSurface(
        radius: 36,
        strong: true,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.sm,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            round(
              icon: mic
                  ? CupertinoIcons.mic_fill
                  : CupertinoIcons.mic_slash_fill,
              label: mic ? 'Mute' : 'Unmute',
              on: mic,
              onTap: () async {
                await local?.setMicrophoneEnabled(!mic);
                onChanged();
              },
            ),
            round(
              icon: cam
                  ? CupertinoIcons.video_camera_solid
                  : CupertinoIcons.video_camera,
              label: cam ? 'Camera off' : 'Camera',
              on: cam,
              onTap: () async {
                await local?.setCameraEnabled(!cam);
                onChanged();
              },
            ),
            round(
              icon: CupertinoIcons.phone_down_fill,
              label: 'Leave',
              color: const Color(0xFFE5484D),
              onTap: onLeave,
            ),
          ],
        ),
      ),
    );
  }
}
