import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/site_data.dart';
import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import 'chat_repository.dart';

/// The call stage is always dark, like a phone's own call screen, so faces
/// and controls stand out in both themes.
const _stageTop = Color(0xFF1C0D12);
const _stageBottom = Color(0xFF0B1022);
const _hangUp = Color(0xFFE5484D);
const _live = Color(0xFF2FBF71);

/// A chat's call (LiveKit). One person fills the stage (whoever is talking,
/// or the one you tap), your own picture floats in the corner, everyone else
/// sits in a strip, and the controls float over the call. Wide screens keep
/// the chat beside the call; phones slide it up. Calls start with sound
/// only unless [video] is set. [join] connects straight away (the caller
/// tapped Call); from a notification the screen asks first.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({
    super.key,
    required this.conversationId,
    this.join = false,
    this.video = false,
  });

  final String conversationId;
  final bool join;
  final bool video;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

enum _Stage { ready, connecting, inCall }

class _CallScreenState extends ConsumerState<CallScreen> {
  Room? _room;
  _Stage _stage = _Stage.ready;
  String? _error;
  String? _title;
  DateTime? _since;
  Timer? _clock;
  String? _pinned;
  bool _front = true;
  bool _chatOpen = true;

  /// Reaction bar open, and the emoji floating up the screen.
  bool _reactOpen = false;
  final _floating = <_Floating>[];
  EventsListener<RoomEvent>? _events;

  /// This call's record on our server, kept alive by [_beat].
  String? _callId;
  Timer? _beat;

  /// You started the call and nobody else has come yet.
  bool _waiting = false;

  /// How long a direct call rings before it gives up.
  static const _ringFor = Duration(seconds: 45);

  /// Kept from the start: leaving runs in dispose, when ref is gone.
  late final SupabaseClient _db;

  @override
  void initState() {
    super.initState();
    _db = ref.read(supabaseProvider);
    if (widget.join) _join(video: widget.video);
  }

  @override
  void dispose() {
    _clock?.cancel();
    _endCall();
    final room = _room;
    if (room != null) {
      room.removeListener(_changed);
      unawaited(_events?.dispose());
      unawaited(room.disconnect().then((_) => room.dispose()));
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Tells our server you left; the last one out ends the call.
  void _endCall() {
    _beat?.cancel();
    final id = _callId;
    _callId = null;
    if (id == null) return;
    unawaited(
      _db
          .rpc('fn_leave_call', params: {'p_call': id})
          .then((_) {}, onError: (_) {}),
    );
  }

  void _tick() {
    final room = _room;
    if (room == null) return;
    if (room.remoteParticipants.isNotEmpty) _waiting = false;
    final since = _since;
    if (_waiting &&
        since != null &&
        DateTime.now().difference(since) > _ringFor) {
      final chats = ref.read(conversationsProvider).value ?? const [];
      final direct = chats
          .where((c) => c.id == widget.conversationId)
          .firstOrNull
          ?.isDirect;
      if (direct ?? false) {
        _waiting = false;
        _snack('No answer. They will see a missed call.');
        unawaited(_leave());
        return;
      }
    }
    _changed();
  }

  Future<void> _join({bool video = false}) async {
    setState(() {
      _stage = _Stage.connecting;
      _error = null;
    });

    // 1. The call pass from our server (checks you are in this chat).
    final Map<String, dynamic> data;
    try {
      final res = await ref
          .read(supabaseProvider)
          .functions
          .invoke(
            'livekit-token',
            body: {'conversation_id': widget.conversationId, 'video': video},
          );
      data = Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = details is Map ? '${details['error'] ?? ''}' : '$details';
      return _fail(
        msg.contains('UNAVAILABLE')
            ? 'Calls are not set up yet.'
            : msg.isNotEmpty
            ? msg.replaceFirst(RegExp(r'^[A-Z_]+: '), '')
            : 'Could not get a pass for this call (${e.status}).',
      );
    } catch (e) {
      return _fail('Could not reach the server. Check your signal. ($e)');
    }

    // 2. The call server (LiveKit).
    final room = Room(
      roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
    );
    _callId = data['call_id'] as String?;
    try {
      await room.connect(data['url'] as String, data['token'] as String);
    } catch (e) {
      await room.dispose();
      _endCall();
      return _fail('Could not connect to the call server. ($e)');
    }
    if (!mounted) {
      await room.disconnect();
      return;
    }
    room.addListener(_changed);
    _events = room.createListener()
      ..on<DataReceivedEvent>((e) {
        if (e.topic != 'reaction') return;
        try {
          final m = jsonDecode(utf8.decode(e.data)) as Map;
          _float('${m['e']}', e.participant?.name);
        } catch (_) {}
      });
    _waiting = data['new_call'] == true;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _beat = Timer.periodic(const Duration(seconds: 30), (_) {
      final id = _callId;
      if (id == null) return;
      unawaited(
        _db
            .rpc('fn_call_heartbeat', params: {'p_call': id})
            .then((_) {}, onError: (_) {}),
      );
    });
    HapticFeedback.mediumImpact();
    setState(() {
      _room = room;
      _title = data['title'] as String?;
      _since = DateTime.now();
      _stage = _Stage.inCall;
    });

    // 3. Microphone (and camera for a video call). If the browser or phone
    // blocks them you stay in the call, muted.
    try {
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (video) await room.localParticipant?.setCameraEnabled(true);
    } catch (_) {
      _snack(
        'Your microphone or camera is blocked. Allow it for this app and '
        'tap the button again.',
      );
    }
    _changed();
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.ready;
      _error = message;
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(duration: const Duration(seconds: 6), content: Text(text)),
    );
  }

  void _close() => context.canPop()
      ? context.pop()
      : context.go('/chat/${widget.conversationId}');

  Future<void> _leave() async {
    HapticFeedback.heavyImpact();
    _clock?.cancel();
    _endCall();
    await _room?.disconnect();
    if (mounted) _close();
  }

  Future<void> _toggleMic() async {
    final local = _room?.localParticipant;
    if (local == null) return;
    try {
      await local.setMicrophoneEnabled(!local.isMicrophoneEnabled());
    } catch (_) {
      _snack('Your microphone is blocked. Allow it for this app.');
    }
    _changed();
  }

  Future<void> _toggleCamera() async {
    final local = _room?.localParticipant;
    if (local == null) return;
    try {
      await local.setCameraEnabled(!local.isCameraEnabled());
    } catch (_) {
      _snack('Your camera is blocked. Allow it for this app.');
    }
    _changed();
  }

  Future<void> _flip() async {
    final pub = _room?.localParticipant?.videoTrackPublications.firstOrNull;
    final track = pub?.track;
    if (track is! LocalVideoTrack) return;
    _front = !_front;
    await track.setCameraPosition(
      _front ? CameraPosition.front : CameraPosition.back,
    );
    _changed();
  }

  /// Shows an emoji floating up the screen for a few seconds.
  void _float(String emoji, String? from) {
    if (!mounted) return;
    final f = _Floating(
      emoji,
      from,
      0.15 + math.Random().nextDouble() * 0.7,
      DateTime.now().microsecondsSinceEpoch,
    );
    setState(() => _floating.add(f));
    Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _floating.remove(f));
    });
  }

  /// Sends a reaction to everyone in the call (nothing is stored).
  Future<void> _react(String emoji) async {
    HapticFeedback.selectionClick();
    _float(emoji, null);
    try {
      await _room?.localParticipant?.publishData(
        utf8.encode(jsonEncode({'e': emoji})),
        reliable: true,
        topic: 'reaction',
      );
    } catch (_) {}
  }

  Future<void> _toggleShare() async {
    final local = _room?.localParticipant;
    if (local == null) return;
    try {
      await local.setScreenShareEnabled(!local.isScreenShareEnabled());
    } catch (_) {
      _snack('Could not share your screen.');
    }
    _changed();
  }

  /// Who fills the stage: the pinned person, else someone sharing their
  /// screen, else whoever is talking, else the first other person, else you.
  Participant? _focus(Room room) {
    final others = room.remoteParticipants.values.toList();
    final sharing = others.where((p) => p.isScreenShareEnabled()).firstOrNull;
    if (_pinned != null) {
      final p = <Participant>[
        ...others,
        ?room.localParticipant,
      ].where((p) => p.identity == _pinned).firstOrNull;
      if (p != null) return p;
    }
    if (sharing != null) return sharing;
    final speaking = room.activeSpeakers
        .whereType<RemoteParticipant>()
        .firstOrNull;
    return speaking ?? others.firstOrNull ?? room.localParticipant;
  }

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(conversationsProvider).value ?? const [];
    final chat = chats.where((c) => c.id == widget.conversationId).firstOrNull;
    // The chat's own name (for a direct chat, the other person); the
    // server's title is a fallback before the chat list loads.
    final title = chat?.title ?? _title ?? 'Call';
    final room = _room;
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final Widget body;
    if (_stage != _Stage.inCall || room == null) {
      body = _Ringing(
        title: title,
        isGroup: !(chat?.isDirect ?? true),
        connecting: _stage == _Stage.connecting,
        error: _error,
        onJoin: () => _join(),
        onJoinVideo: () => _join(video: true),
        onBack: _close,
      );
    } else {
      final local = room.localParticipant;
      final focus = _focus(room);
      final everyone = <Participant>[...room.remoteParticipants.values, ?local];
      final strip = [
        for (final p in room.remoteParticipants.values)
          if (p != focus) p,
      ];
      final stage = Stack(
        fit: StackFit.expand,
        children: [
          if (focus != null)
            _Face(
              participant: focus,
              large: true,
              you: focus is LocalParticipant,
            ),
          // Shade top and bottom so the overlays read on any picture.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x99000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0xB3000000),
                  ],
                  stops: [0, 0.22, 0.6, 1],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Stack(
              children: [
                for (final f in _floating)
                  _FloatingEmoji(key: ValueKey(f.id), floating: f),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Column(
                children: [
                  _TopBar(
                    title: title,
                    subtitle: everyone.length == 1
                        ? (_waiting ? 'Ringing…' : 'Waiting for others to join')
                        : '${everyone.length} in the call',
                    time: _elapsed(),
                    onBack: _leave,
                  ),
                  const SizedBox(height: Space.sm),
                  Align(
                    alignment: Alignment.topRight,
                    child: focus is LocalParticipant || local == null
                        ? const SizedBox.shrink()
                        : GestureDetector(
                            onTap: () =>
                                setState(() => _pinned = local.identity),
                            child: SizedBox(
                              width: wide ? 160 : 104,
                              height: wide ? 120 : 140,
                              child: _Face(participant: local, you: true),
                            ),
                          ),
                  ),
                  const Spacer(),
                  if (focus != null && focus is! LocalParticipant)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _NameTag(participant: focus),
                    ),
                  if (strip.isNotEmpty) ...[
                    const SizedBox(height: Space.sm),
                    SizedBox(
                      height: 92,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: strip.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: Space.xs),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () =>
                              setState(() => _pinned = strip[i].identity),
                          child: SizedBox(
                            width: 72,
                            child: _Face(participant: strip[i]),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.md),
                  if (_reactOpen)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: _Frost(
                        radius: 99,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final e in const [
                              '👍',
                              '👏',
                              '😂',
                              '❤️',
                              '🔥',
                              '✋',
                            ])
                              InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => _react(e),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Text(
                                    e,
                                    style: const TextStyle(fontSize: 26),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  _Dock(
                    local: local,
                    canFlip: !kIsWeb && (local?.isCameraEnabled() ?? false),
                    canShare: kIsWeb && wide,
                    reactOpen: _reactOpen,
                    onShare: _toggleShare,
                    onReact: () => setState(() => _reactOpen = !_reactOpen),
                    chatOpen: wide && _chatOpen,
                    onMic: _toggleMic,
                    onCamera: _toggleCamera,
                    onFlip: _flip,
                    onChat: () => wide
                        ? setState(() => _chatOpen = !_chatOpen)
                        : _openChatSheet(everyone),
                    onLeave: _leave,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      body = wide && _chatOpen
          ? Row(
              children: [
                Expanded(child: stage),
                SizedBox(
                  width: 380,
                  child: _CallSide(
                    conversationId: widget.conversationId,
                    people: everyone,
                  ),
                ),
              ],
            )
          : stage;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _stageBottom,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_stageTop, _stageBottom],
            ),
          ),
          child: body,
        ),
      ),
    );
  }

  void _openChatSheet(List<Participant> people) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, _) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: _CallSide(
            conversationId: widget.conversationId,
            people: people,
            sheet: true,
          ),
        ),
      ),
    );
  }

  String _elapsed() {
    final s = _since;
    if (s == null) return '0:00';
    final d = DateTime.now().difference(s);
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:$sec'
        : '${d.inMinutes}:$sec';
  }
}

/// Before joining: the chat's picture with soft pulsing rings, and the two
/// ways in.
class _Ringing extends StatefulWidget {
  const _Ringing({
    required this.title,
    required this.isGroup,
    required this.connecting,
    required this.error,
    required this.onJoin,
    required this.onJoinVideo,
    required this.onBack,
  });

  final String title;
  final bool isGroup;
  final bool connecting;
  final String? error;
  final VoidCallback onJoin;
  final VoidCallback onJoinVideo;
  final VoidCallback onBack;

  @override
  State<_Ringing> createState() => _RingingState();
}

class _RingingState extends State<_Ringing>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: _GlassButton(
                icon: CupertinoIcons.chevron_left,
                onTap: widget.onBack,
                size: 44,
                tooltip: 'Back',
              ),
            ),
          ),
          const Spacer(),
          SizedBox.square(
            dimension: 240,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) => CustomPaint(
                painter: _RingsPainter(_pulse.value),
                child: child,
              ),
              child: Center(
                child: Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: BrandColors.brandGradient,
                    boxShadow: [
                      BoxShadow(
                        color: BrandColors.maroon.withValues(alpha: 0.6),
                        blurRadius: 40,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: widget.isGroup
                      ? const Icon(
                          CupertinoIcons.person_3_fill,
                          color: Colors.white,
                          size: 56,
                        )
                      : Text(
                          AppAvatar.initials(widget.title),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Text(
              widget.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            widget.connecting
                ? 'Connecting…'
                : widget.isGroup
                ? 'Group call'
                : 'Call',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.md,
                Space.lg,
                0,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.xs,
                ),
                decoration: BoxDecoration(
                  color: _hangUp.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: SelectableText(
                  widget.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFFFB4B6)),
                ),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xl),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _BigAction(
                  icon: CupertinoIcons.video_camera_solid,
                  label: 'With video',
                  color: Colors.white.withValues(alpha: 0.16),
                  onTap: widget.connecting ? null : widget.onJoinVideo,
                ),
                const SizedBox(width: Space.xl),
                _BigAction(
                  icon: CupertinoIcons.phone_fill,
                  label: widget.connecting ? 'Joining…' : 'Join',
                  color: _live,
                  busy: widget.connecting,
                  onTap: widget.connecting ? null : widget.onJoin,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      canvas.drawCircle(
        c,
        64 + p * 56,
        Paint()
          ..color = BrandColors.blush.withValues(alpha: (1 - p) * 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t;
}

class _BigAction extends StatelessWidget {
  const _BigAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 76,
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(26),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// One person: their video, or their initials on a soft glow that pulses
/// while they talk. [large] is the stage; otherwise a rounded thumbnail.
class _Face extends StatelessWidget {
  const _Face({
    required this.participant,
    this.large = false,
    this.you = false,
  });

  final Participant participant;
  final bool large;
  final bool you;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: participant,
      builder: (context, _) {
        final p = participant;
        VideoTrack? video;
        VideoTrack? screen;
        for (final pub in p.videoTrackPublications) {
          final t = pub.track;
          if (t is! VideoTrack || pub.muted) continue;
          if (pub.source == TrackSource.screenShareVideo) {
            screen = t;
          } else {
            video = t;
          }
        }
        // On the stage a shared screen wins, shown whole.
        final showScreen = large && screen != null;
        if (showScreen) video = screen;
        final name = p.name.isNotEmpty ? p.name : (you ? 'You' : 'Someone');
        final speaking = p.isSpeaking;
        final muted = !p.isMicrophoneEnabled();

        final picture = video != null
            ? VideoTrackRenderer(
                video,
                fit: showScreen ? VideoViewFit.contain : VideoViewFit.cover,
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      BrandColors.maroon.withValues(alpha: large ? 0.55 : 0.8),
                      BrandColors.info.withValues(alpha: large ? 0.35 : 0.6),
                    ],
                  ),
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: EdgeInsets.all(speaking ? (large ? 10 : 4) : 0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: speaking
                          ? _live.withValues(alpha: 0.35)
                          : Colors.transparent,
                    ),
                    child: AppAvatar(name: name, size: large ? 140 : 40),
                  ),
                ),
              );

        if (large) return picture;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: speaking ? _live : Colors.white.withValues(alpha: 0.35),
              width: speaking ? 2.5 : 1,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 16),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Stack(
              fit: StackFit.expand,
              children: [
                picture,
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 6,
                  child: Row(
                    children: [
                      if (muted)
                        const Padding(
                          padding: EdgeInsets.only(right: 3),
                          child: Icon(
                            CupertinoIcons.mic_slash_fill,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          you ? 'You' : name.split(' ').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            shadows: [Shadow(blurRadius: 6)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The name of whoever fills the stage, in a frosted pill.
class _NameTag extends StatelessWidget {
  const _NameTag({required this.participant});

  final Participant participant;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: participant,
      builder: (context, _) {
        final p = participant;
        return _Frost(
          radius: 99,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                p.isMicrophoneEnabled()
                    ? (p.isSpeaking
                          ? CupertinoIcons.waveform
                          : CupertinoIcons.mic_fill)
                    : CupertinoIcons.mic_slash_fill,
                size: 14,
                color: p.isSpeaking ? _live : Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                p.name.isNotEmpty ? p.name : 'Someone',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final String time;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GlassButton(
          icon: CupertinoIcons.chevron_down,
          onTap: onBack,
          size: 44,
          tooltip: 'Leave call',
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        _Frost(
          radius: 99,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: _hangUp,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                time,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The floating controls: microphone, camera, the red hang-up in the
/// middle, flip and chat.
class _Dock extends StatelessWidget {
  const _Dock({
    required this.local,
    required this.canFlip,
    required this.canShare,
    required this.reactOpen,
    required this.onShare,
    required this.onReact,
    required this.chatOpen,
    required this.onMic,
    required this.onCamera,
    required this.onFlip,
    required this.onChat,
    required this.onLeave,
  });

  final LocalParticipant? local;
  final bool canFlip;

  /// Screen sharing: computers (browser) only.
  final bool canShare;
  final bool reactOpen;
  final VoidCallback onShare;
  final VoidCallback onReact;
  final bool chatOpen;
  final VoidCallback onMic;
  final VoidCallback onCamera;
  final VoidCallback onFlip;
  final VoidCallback onChat;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final mic = local?.isMicrophoneEnabled() ?? false;
    final cam = local?.isCameraEnabled() ?? false;
    return Center(
      child: _Frost(
        radius: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GlassButton(
              icon: mic
                  ? CupertinoIcons.mic_fill
                  : CupertinoIcons.mic_slash_fill,
              tooltip: mic ? 'Mute' : 'Unmute',
              off: !mic,
              onTap: onMic,
            ),
            const SizedBox(width: 10),
            _GlassButton(
              icon: cam
                  ? CupertinoIcons.video_camera_solid
                  : CupertinoIcons.video_camera,
              tooltip: cam ? 'Camera off' : 'Camera on',
              off: !cam,
              onTap: onCamera,
            ),
            const SizedBox(width: 14),
            Tooltip(
              message: 'Leave call',
              child: Material(
                color: _hangUp,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onLeave,
                  child: const SizedBox.square(
                    dimension: 64,
                    child: Icon(
                      CupertinoIcons.phone_down_fill,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            if (canFlip) ...[
              _GlassButton(
                icon: CupertinoIcons.camera_rotate,
                tooltip: 'Flip camera',
                onTap: onFlip,
              ),
              const SizedBox(width: 10),
            ],
            if (canShare) ...[
              _GlassButton(
                icon: CupertinoIcons.rectangle_on_rectangle_angled,
                tooltip: (local?.isScreenShareEnabled() ?? false)
                    ? 'Stop sharing'
                    : 'Share your screen',
                off: local?.isScreenShareEnabled() ?? false,
                onTap: onShare,
              ),
              const SizedBox(width: 10),
            ],
            _GlassButton(
              icon: CupertinoIcons.smiley,
              tooltip: 'React',
              off: reactOpen,
              onTap: onReact,
            ),
            const SizedBox(width: 10),
            _GlassButton(
              icon: chatOpen
                  ? CupertinoIcons.chat_bubble_2_fill
                  : CupertinoIcons.chat_bubble_2,
              tooltip: 'Chat',
              onTap: onChat,
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.onTap,
    this.off = false,
    this.size = 52,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// A switched-off control turns solid white, like iOS.
  final bool off;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: off ? Colors.white : Colors.white.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox.square(
          dimension: size,
          child: Icon(
            icon,
            color: off ? _stageTop : Colors.white,
            size: size * 0.44,
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// Frosted dark glass for anything that floats over the call.
class _Frost extends StatelessWidget {
  const _Frost({required this.child, required this.radius, this.padding});

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The chat and the people in the call: beside the call on wide screens,
/// in a sheet on phones.
class _CallSide extends ConsumerStatefulWidget {
  const _CallSide({
    required this.conversationId,
    required this.people,
    this.sheet = false,
  });

  final String conversationId;
  final List<Participant> people;
  final bool sheet;

  @override
  ConsumerState<_CallSide> createState() => _CallSideState();
}

class _CallSideState extends ConsumerState<_CallSide> {
  final _text = TextEditingController();
  bool _people = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    await ref.read(chatActionsProvider).send(widget.conversationId, text: t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thread = ref.watch(chatThreadProvider(widget.conversationId));
    final me = ref.watch(authUserIdProvider);
    final names = ref.watch(peopleProvider).value ?? const {};
    final messages = [
      for (final m in thread.messages)
        if (!m.archived) m,
    ];

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        left: false,
        child: Column(
          children: [
            if (widget.sheet)
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(Space.md),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<bool>(
                  groupValue: _people,
                  onValueChanged: (v) => setState(() => _people = v ?? false),
                  children: {
                    false: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Messages'),
                    ),
                    true: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('People · ${widget.people.length}'),
                    ),
                  },
                ),
              ),
            ),
            Expanded(
              child: _people
                  ? ListView(
                      padding: const EdgeInsets.symmetric(horizontal: Space.md),
                      children: [
                        for (final p in widget.people)
                          ListenableBuilder(
                            listenable: p,
                            builder: (context, _) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: AppAvatar(
                                name: p.name.isNotEmpty ? p.name : '?',
                                size: 38,
                              ),
                              title: Text(
                                p is LocalParticipant
                                    ? 'You'
                                    : (p.name.isNotEmpty ? p.name : 'Someone'),
                              ),
                              trailing: Icon(
                                p.isMicrophoneEnabled()
                                    ? (p.isSpeaking
                                          ? CupertinoIcons.waveform
                                          : CupertinoIcons.mic)
                                    : CupertinoIcons.mic_slash,
                                color: p.isSpeaking ? _live : null,
                              ),
                            ),
                          ),
                      ],
                    )
                  : messages.isEmpty
                  ? Center(
                      child: Text(
                        'Messages you send here go to the chat.',
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: Space.md),
                      itemCount: messages.length,
                      itemBuilder: (context, i) {
                        final m = messages[messages.length - 1 - i];
                        final mine = m.authorId == me;
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            constraints: const BoxConstraints(maxWidth: 280),
                            decoration: BoxDecoration(
                              gradient: mine
                                  ? const LinearGradient(
                                      colors: [
                                        BrandColors.maroon,
                                        BrandColors.coral,
                                      ],
                                    )
                                  : null,
                              color: mine
                                  ? null
                                  : theme.colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!mine)
                                  Text(
                                    names[m.authorId] ?? 'Someone',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: BrandColors.coral,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                if (m.kind == 'photo')
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      width: 220,
                                      height: 165,
                                      child: m.bytes != null
                                          ? Image.memory(
                                              m.bytes!,
                                              fit: BoxFit.cover,
                                            )
                                          : thread.photoUrls[m
                                                    .attachmentPath] !=
                                                null
                                          ? Image.network(
                                              thread.photoUrls[m
                                                  .attachmentPath]!,
                                              fit: BoxFit.cover,
                                            )
                                          : const Center(
                                              child: Icon(CupertinoIcons.photo),
                                            ),
                                    ),
                                  ),
                                if (m.kind == 'voice' || m.kind == 'file')
                                  Text(
                                    m.kind == 'voice'
                                        ? '🎤 Voice note'
                                        : '📎 ${m.attachmentName ?? 'File'}',
                                    style: TextStyle(
                                      color: mine ? Colors.white : null,
                                    ),
                                  ),
                                if (m.body != null)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      top: m.kind == 'photo' ? 6 : 0,
                                    ),
                                    child: Text(
                                      m.body!,
                                      style: TextStyle(
                                        color: mine ? Colors.white : null,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (!_people)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  Space.md,
                  Space.xs,
                  Space.md,
                  Space.md + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Message the chat',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    IconButton.filled(
                      tooltip: 'Send',
                      onPressed: _send,
                      icon: const Icon(CupertinoIcons.arrow_up),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Floating {
  _Floating(this.emoji, this.from, this.x, this.id);

  final String emoji;
  final String? from;

  /// Where across the screen it rises, 0–1.
  final double x;
  final int id;
}

/// One reaction drifting up and fading out.
class _FloatingEmoji extends StatelessWidget {
  const _FloatingEmoji({super.key, required this.floating});

  final _Floating floating;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 2500),
      curve: Curves.easeOut,
      builder: (context, t, child) => Positioned(
        left: size.width * floating.x - 24,
        bottom: 120 + t * size.height * 0.55,
        child: Opacity(
          opacity: t < 0.7 ? 1 : (1 - t) / 0.3,
          child: Transform.scale(scale: 0.8 + t * 0.6, child: child),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(floating.emoji, style: const TextStyle(fontSize: 40)),
          if (floating.from != null)
            Text(
              floating.from!.split(' ').first,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 6)],
              ),
            ),
        ],
      ),
    );
  }
}
