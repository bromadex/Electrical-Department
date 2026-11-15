import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';

import '../data/site_data.dart';
import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../meetings/captions.dart';
import '../meetings/meetings_repository.dart';
import 'call_controller.dart';
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
    this.ringId,
  });

  final String conversationId;
  final bool join;
  final bool video;

  /// The answered incoming call (Android), whose notification this call
  /// takes over.
  final String? ringId;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  late final CallController _call = ref.read(callControllerProvider);
  String? _pinned;
  bool _chatOpen = true;

  /// Reaction bar open.
  bool _reactOpen = false;

  /// Before joining: camera preview, microphone and speaker choices.
  late bool _preCam = widget.video;
  bool _preMic = true;
  bool _preSpeaker = false;
  LocalVideoTrack? _preview;

  /// Everyone in tiles (grid) instead of one large speaker.
  bool _grid = false;

  /// Your own small picture: which corner, and where it is while dragged.
  Alignment _selfCorner = Alignment.topRight;
  Offset _selfDrag = Offset.zero;

  /// This screen was showing the call; when it ends (hung up here, on the
  /// notification, or no answer) the screen closes.
  bool _wasIn = false;

  @override
  void initState() {
    super.initState();
    _call.addListener(_changed);
    _wasIn = _call.inCallFor(widget.conversationId);
    if (_call.conversationId != widget.conversationId) _call.reset();
    if (widget.join && !_wasIn) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _call.join(
          widget.conversationId,
          video: widget.video,
          ringId: widget.ringId,
        ),
      );
    }
  }

  @override
  void dispose() {
    _call.removeListener(_changed);
    unawaited(_preview?.dispose());
    super.dispose();
  }

  Future<void> _togglePreviewCam() async {
    final on = !_preCam;
    setState(() => _preCam = on);
    if (on) {
      try {
        final t = await LocalVideoTrack.createCameraTrack();
        if (!mounted || !_preCam) {
          await t.dispose();
          return;
        }
        setState(() => _preview = t);
      } catch (_) {
        if (mounted) setState(() => _preCam = false);
      }
    } else {
      final t = _preview;
      setState(() => _preview = null);
      await t?.dispose();
    }
  }

  Future<void> _joinFromPreview() async {
    final t = _preview;
    _preview = null;
    await t?.dispose();
    await _call.join(
      widget.conversationId,
      video: _preCam,
      mic: _preMic,
      speaker: kIsWeb ? null : _preSpeaker,
    );
  }

  void _changed() {
    if (!mounted) return;
    final inNow = _call.inCallFor(widget.conversationId);
    if (_wasIn && !inNow) {
      _wasIn = false;
      if (ModalRoute.of(context)?.isCurrent ?? false) _close();
      return;
    }
    _wasIn = inNow;
    setState(() {});
  }

  void _close() => context.canPop()
      ? context.pop()
      : context.go('/chat/${widget.conversationId}');

  /// Back or ⌄: the call keeps going, with the bar at the top of the app.
  void _minimise() => _close();

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
    final call = _call;
    final chats = ref.watch(conversationsProvider).value ?? const [];
    final chat = chats.where((c) => c.id == widget.conversationId).firstOrNull;
    final mine = call.conversationId == widget.conversationId;
    // The chat's own name (for a direct chat, the other person); the
    // server's title is a fallback before the chat list loads.
    final title = chat?.title ?? (mine ? call.serverTitle : null) ?? 'Call';
    final room = call.inCallFor(widget.conversationId) ? call.room : null;
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    // A meeting on now in this chat: captions run while you are in the call.
    final meeting =
        (ref.watch(chatMeetingsProvider(widget.conversationId)).value ??
                const <Meeting>[])
            .where((m) => m.open)
            .firstOrNull;
    if (room != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) call.syncCaptions(meeting);
      });
    }

    final Widget body;
    if (room == null) {
      body = _Ringing(
        title: title,
        isGroup: !(chat?.isDirect ?? true),
        connecting: mine && call.stage == CallStage.connecting,
        error: mine ? call.error : null,
        otherCall: call.active && !mine,
        preview: _preview,
        cam: _preCam,
        mic: _preMic,
        speaker: kIsWeb ? null : _preSpeaker,
        onCam: _togglePreviewCam,
        onMic: () => setState(() => _preMic = !_preMic),
        onSpeaker: () => setState(() => _preSpeaker = !_preSpeaker),
        onJoin: _joinFromPreview,
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
      final hands = call.hands;
      final stage = Stack(
        fit: StackFit.expand,
        children: [
          if (_grid)
            Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + 84,
                bottom: 140,
                left: Space.sm,
                right: Space.sm,
              ),
              child: _Grid(
                people: everyone,
                perPage: wide ? 9 : 4,
                onPin: (p) => setState(() {
                  _pinned = p.identity;
                  _grid = false;
                }),
              ),
            )
          else if (focus != null)
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
                for (final f in call.floating)
                  _FloatingEmoji(key: ValueKey(f.id), floating: f),
              ],
            ),
          ),
          // Your own picture: drag it to any corner.
          if (!_grid && local != null && focus is! LocalParticipant)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.md, 76, Space.md, 150),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  alignment: _selfCorner,
                  child: Transform.translate(
                    offset: _selfDrag,
                    child: GestureDetector(
                      onTap: () => setState(() => _pinned = local.identity),
                      onPanUpdate: (d) => setState(() => _selfDrag += d.delta),
                      onPanEnd: (d) {
                        final box = context.findRenderObject() as RenderBox?;
                        final size = box?.size ?? MediaQuery.sizeOf(context);
                        final x =
                            (_selfCorner.x + 1) / 2 * size.width + _selfDrag.dx;
                        final y =
                            (_selfCorner.y + 1) / 2 * size.height +
                            _selfDrag.dy;
                        setState(() {
                          _selfCorner = Alignment(
                            x < size.width / 2 ? -1 : 1,
                            y < size.height / 2 ? -1 : 1,
                          );
                          _selfDrag = Offset.zero;
                        });
                      },
                      child: SizedBox(
                        width: wide ? 160 : 104,
                        height: wide ? 120 : 140,
                        child: _Face(participant: local, you: true),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Column(
                children: [
                  _TopBar(
                    title: title,
                    subtitle: everyone.length > 1
                        ? '${everyone.length} in the call'
                        : call.waiting
                        ? (call.rang ? 'Ringing…' : 'Calling…')
                        : 'Waiting for others to join',
                    // The timer starts when someone answers.
                    time: call.elapsed,
                    onBack: _minimise,
                    onMore: () => _more(room),
                  ),
                  if (call.sharing)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.sm),
                      child: _SharingBar(onStop: call.toggleShare),
                    ),
                  if (hands.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.sm),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _HandsPill(hands: hands),
                      ),
                    ),
                  if (call.offerAudioOnly)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.sm),
                      child: _AudioOnlyOffer(
                        onYes: () => call.setQuality(CallQuality.audio),
                        onNo: call.dismissAudioOnly,
                      ),
                    ),
                  const Spacer(),
                  if (!_grid && focus != null && focus is! LocalParticipant)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _NameTag(participant: focus),
                    ),
                  if (!_grid && strip.isNotEmpty) ...[
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
                  if (meeting != null && !call.captionsOff)
                    _CaptionsOverlay(meetingId: meeting.id),
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
                            ])
                              InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => call.react(e),
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
                    canShare: call.canShare && (wide || !kIsWeb),
                    handUp: call.handUp,
                    onHand: call.toggleHand,
                    reactOpen: _reactOpen,
                    captions: meeting == null ? null : !call.captionsOff,
                    onCaptions: () => call.setCaptionsOff(!call.captionsOff),
                    onShare: call.toggleShare,
                    onReact: () => setState(() => _reactOpen = !_reactOpen),
                    chatOpen: wide && _chatOpen,
                    speaker: call.speaker,
                    onSpeaker: () => call.setSpeaker(!(call.speaker ?? false)),
                    onMic: call.toggleMic,
                    onCamera: call.toggleCamera,
                    onFlip: call.flip,
                    onChat: () => wide
                        ? setState(() => _chatOpen = !_chatOpen)
                        : _openChatSheet(everyone),
                    onLeave: call.leave,
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

  /// ⋯: speaker or grid view, video quality, and the chair's controls.
  void _more(Room room) {
    final call = _call;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: Icon(
                _grid
                    ? CupertinoIcons.person_crop_rectangle
                    : CupertinoIcons.square_grid_2x2,
              ),
              title: Text(_grid ? 'Speaker view' : 'Grid view'),
              subtitle: Text(
                _grid
                    ? 'Whoever is talking, large'
                    : 'Everyone in tiles, swipe for more',
              ),
              onTap: () {
                Navigator.pop(sheet);
                setState(() {
                  _grid = !_grid;
                  _pinned = null;
                });
              },
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text('Video quality'),
            ),
            RadioGroup<CallQuality>(
              groupValue: call.quality,
              onChanged: (q) {
                Navigator.pop(sheet);
                if (q != null) call.setQuality(q);
              },
              child: Column(
                children: [
                  for (final q in CallQuality.values)
                    RadioListTile<CallQuality>(
                      value: q,
                      title: Text(q.label),
                      dense: true,
                    ),
                ],
              ),
            ),
            if (call.isChair) ...[
              const Divider(),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text('You chair this call'),
              ),
              ListTile(
                leading: const Icon(CupertinoIcons.mic_slash),
                title: const Text('Mute everyone'),
                subtitle: const Text('They can unmute themselves'),
                onTap: () async {
                  Navigator.pop(sheet);
                  final n = await call.chair('mute_all');
                  if (n != null) {
                    call.snack(
                      n == 0 ? 'Everyone was already muted' : 'Muted $n',
                    );
                  }
                },
              ),
              if (call.hands.isNotEmpty)
                ListTile(
                  leading: const Icon(CupertinoIcons.hand_raised_slash),
                  title: const Text('Lower all hands'),
                  onTap: () {
                    Navigator.pop(sheet);
                    call.chair('lower');
                  },
                ),
              ListTile(
                leading: const Icon(CupertinoIcons.stop_circle, color: _hangUp),
                title: const Text(
                  'End the call for everyone',
                  style: TextStyle(color: _hangUp),
                ),
                onTap: () async {
                  Navigator.pop(sheet);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('End the call for everyone?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(d, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _hangUp,
                          ),
                          onPressed: () => Navigator.pop(d, true),
                          child: const Text('End for everyone'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) await call.chair('end');
                },
              ),
            ],
          ],
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
}

/// "You are sharing your screen · Stop", while this phone shares.
class _SharingBar extends StatelessWidget {
  const _SharingBar({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return _Frost(
      radius: 99,
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.rectangle_on_rectangle_angled,
            color: _live,
            size: 18,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'You are sharing your screen',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onStop,
            style: TextButton.styleFrom(
              backgroundColor: _hangUp,
              foregroundColor: Colors.white,
            ),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}

/// Raised hands, first raised first.
class _HandsPill extends StatelessWidget {
  const _HandsPill({required this.hands});

  final List<Participant> hands;

  @override
  Widget build(BuildContext context) {
    String name(Participant p) => p is LocalParticipant
        ? 'You'
        : (p.name.isNotEmpty ? p.name.split(' ').first : 'Someone');
    return _Frost(
      radius: 99,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        '✋ ${hands.map(name).join(', ')}',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
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
    required this.onBack,
    required this.cam,
    required this.mic,
    required this.speaker,
    required this.onCam,
    required this.onMic,
    required this.onSpeaker,
    this.preview,
    this.otherCall = false,
  });

  /// The camera as others will see it, while the camera is on.
  final LocalVideoTrack? preview;
  final bool cam;
  final bool mic;

  /// Loudspeaker (true) or earpiece; null in the browser.
  final bool? speaker;
  final VoidCallback onCam;
  final VoidCallback onMic;
  final VoidCallback onSpeaker;

  final String title;
  final bool isGroup;
  final bool connecting;
  final String? error;

  /// You are in a call in another chat; joining this one ends it.
  final bool otherCall;
  final VoidCallback onJoin;
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
                child: widget.preview != null
                    ? ClipOval(
                        child: SizedBox.square(
                          dimension: 150,
                          child: VideoTrackRenderer(
                            widget.preview!,
                            fit: VideoViewFit.cover,
                            mirrorMode: VideoViewMirrorMode.mirror,
                          ),
                        ),
                      )
                    : Container(
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
          if (widget.otherCall)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                'Joining ends your other call.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
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
                if (!widget.connecting) ...[
                  _GlassButton(
                    icon: widget.mic
                        ? CupertinoIcons.mic_fill
                        : CupertinoIcons.mic_slash_fill,
                    tooltip: widget.mic ? 'Join muted' : 'Join with microphone',
                    off: !widget.mic,
                    onTap: widget.onMic,
                  ),
                  const SizedBox(width: Space.sm),
                  _GlassButton(
                    icon: widget.cam
                        ? CupertinoIcons.video_camera_solid
                        : CupertinoIcons.video_camera,
                    tooltip: widget.cam ? 'Camera off' : 'Camera on',
                    off: widget.cam,
                    onTap: widget.onCam,
                  ),
                  if (widget.speaker != null) ...[
                    const SizedBox(width: Space.sm),
                    _GlassButton(
                      icon: widget.speaker!
                          ? CupertinoIcons.speaker_3_fill
                          : CupertinoIcons.ear,
                      tooltip: widget.speaker! ? 'Loudspeaker' : 'Earpiece',
                      off: widget.speaker!,
                      onTap: widget.onSpeaker,
                    ),
                  ],
                  const SizedBox(width: Space.lg),
                ],
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

        final hand = CallController.handOf(p) != null;
        final picture = video != null
            ? showScreen
                  // A shared screen: pinch to zoom and drag to look around
                  // (drawings, PLC screens, photos).
                  ? InteractiveViewer(
                      maxScale: 5,
                      child: VideoTrackRenderer(
                        video,
                        fit: VideoViewFit.contain,
                      ),
                    )
                  : VideoTrackRenderer(video, fit: VideoViewFit.cover)
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
                      if (p.connectionQuality == ConnectionQuality.poor ||
                          p.connectionQuality == ConnectionQuality.lost)
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: Icon(
                            CupertinoIcons.wifi_exclamationmark,
                            size: 12,
                            color: p.connectionQuality == ConnectionQuality.lost
                                ? _hangUp
                                : const Color(0xFFFFC145),
                            semanticLabel: 'Poor signal',
                          ),
                        ),
                      if (hand)
                        const Padding(
                          padding: EdgeInsets.only(right: 3),
                          child: Text('✋', style: TextStyle(fontSize: 12)),
                        ),
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
    this.onMore,
  });

  final VoidCallback? onMore;
  final String title;
  final String subtitle;

  /// Call length; null (hidden) while calling or ringing.
  final String? time;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GlassButton(
          icon: CupertinoIcons.chevron_down,
          onTap: onBack,
          size: 44,
          tooltip: 'Minimise (the call keeps going)',
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
        if (time != null)
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
                  time!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        if (onMore != null) ...[
          const SizedBox(width: Space.xs),
          _GlassButton(
            icon: CupertinoIcons.ellipsis,
            onTap: onMore!,
            size: 44,
            tooltip: 'More',
          ),
        ],
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
    required this.handUp,
    required this.onHand,
    required this.reactOpen,
    required this.onShare,
    required this.onReact,
    required this.captions,
    required this.onCaptions,
    required this.chatOpen,
    required this.speaker,
    required this.onSpeaker,
    required this.onMic,
    required this.onCamera,
    required this.onFlip,
    required this.onChat,
    required this.onLeave,
  });

  final LocalParticipant? local;
  final bool canFlip;

  /// Screen sharing: Android phones and computers (browser).
  final bool canShare;
  final bool handUp;
  final VoidCallback onHand;
  final bool reactOpen;
  final VoidCallback onShare;
  final VoidCallback onReact;

  /// null: no meeting on; otherwise whether your captions are on.
  final bool? captions;
  final VoidCallback onCaptions;
  final bool chatOpen;

  /// null in the browser; otherwise whether the loudspeaker is on.
  final bool? speaker;
  final VoidCallback onSpeaker;
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
            if (speaker != null) ...[
              _GlassButton(
                icon: speaker!
                    ? CupertinoIcons.speaker_3_fill
                    : CupertinoIcons.speaker_1_fill,
                tooltip: speaker! ? 'Speaker on' : 'Speaker off',
                off: speaker!,
                onTap: onSpeaker,
              ),
              const SizedBox(width: 10),
            ],
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
            if (captions != null) ...[
              _GlassButton(
                icon: CupertinoIcons.captions_bubble_fill,
                tooltip: captions! ? 'Captions on' : 'Captions off',
                off: !captions!,
                onTap: onCaptions,
              ),
              const SizedBox(width: 10),
            ],
            _GlassButton(
              icon: CupertinoIcons.hand_raised_fill,
              tooltip: handUp ? 'Lower your hand' : 'Raise your hand',
              off: handUp,
              onTap: onHand,
            ),
            const SizedBox(width: 10),
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

  /// Pick chat members who are not in the call and ring them.
  Future<void> _addPeople(CallController call) async {
    final members = await ref.read(
      chatMembersProvider(widget.conversationId).future,
    );
    if (!mounted) return;
    final names = ref.read(peopleProvider).value ?? const {};
    final inCall = {for (final p in widget.people) p.identity};
    final me = ref.read(authUserIdProvider);
    final out = [
      for (final m in members)
        if (!inCall.contains(m) && m != me) m,
    ];
    if (out.isEmpty) {
      call.snack('Everyone in this chat is already in the call.');
      return;
    }
    final picked = <String>{};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (s) => StatefulBuilder(
        builder: (s, set) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(s).height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Ring people to join'),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final id in out)
                        CheckboxListTile(
                          value: picked.contains(id),
                          onChanged: (v) => set(
                            () =>
                                v == true ? picked.add(id) : picked.remove(id),
                          ),
                          secondary: AppAvatar(
                            name: names[id] ?? '?',
                            size: 34,
                          ),
                          title: Text(names[id] ?? 'Someone'),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(s, true),
                    icon: const Icon(CupertinoIcons.phone_fill),
                    label: const Text('Ring'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || picked.isEmpty) return;
    final n = await call.ring(picked.toList());
    if (n != null) {
      call.snack(n == 1 ? 'Ringing 1 person' : 'Ringing $n people');
    }
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
    final call = ref.read(callControllerProvider);
    final hands = call.hands;
    final people = [
      ...hands,
      for (final p in widget.people)
        if (!hands.contains(p)) p,
    ];
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
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            child: Icon(CupertinoIcons.person_add),
                          ),
                          title: const Text('Add people'),
                          subtitle: const Text(
                            'Ring others in this chat to join',
                          ),
                          onTap: () => _addPeople(call),
                        ),
                        for (final p in people)
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
                              subtitle: CallController.handOf(p) == null
                                  ? null
                                  : const Text('✋ Hand raised'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    p.isMicrophoneEnabled()
                                        ? (p.isSpeaking
                                              ? CupertinoIcons.waveform
                                              : CupertinoIcons.mic)
                                        : CupertinoIcons.mic_slash,
                                    color: p.isSpeaking ? _live : null,
                                  ),
                                  if (call.isChair && p is RemoteParticipant)
                                    PopupMenuButton<String>(
                                      tooltip: 'Chair',
                                      onSelected: (a) =>
                                          call.chair(a, identity: p.identity),
                                      itemBuilder: (_) => [
                                        if (p.isMicrophoneEnabled())
                                          const PopupMenuItem(
                                            value: 'mute',
                                            child: Text('Mute'),
                                          ),
                                        if (CallController.handOf(p) != null)
                                          const PopupMenuItem(
                                            value: 'lower',
                                            child: Text('Lower hand'),
                                          ),
                                        const PopupMenuItem(
                                          value: 'remove',
                                          child: Text('Remove from call'),
                                        ),
                                      ],
                                    ),
                                ],
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

/// One reaction drifting up and fading out.
class _FloatingEmoji extends StatelessWidget {
  const _FloatingEmoji({super.key, required this.floating});

  final FloatingReaction floating;

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

/// The last two things said, with names, while a meeting is on.
class _CaptionsOverlay extends ConsumerWidget {
  const _CaptionsOverlay({required this.meetingId});

  final String meetingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(meetingCaptionsProvider(meetingId)).value ?? const [];
    final names = ref.watch(peopleProvider).value ?? const {};
    final recent = [
      for (final c in all)
        if (DateTime.now().difference(c.spokenAt) < const Duration(seconds: 75))
          c,
    ];
    final shown = recent.length > 2
        ? recent.sublist(recent.length - 2)
        : recent;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: _Frost(
        radius: Radii.lg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: SizedBox(
          width: double.infinity,
          child: shown.isEmpty
              ? Row(
                  children: [
                    const Icon(
                      CupertinoIcons.captions_bubble,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Live captions are on. They appear here as people talk.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final c in shown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    '${(names[c.userId] ?? 'Someone').split(' ').first}: ',
                                style: const TextStyle(
                                  color: BrandColors.blush,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(text: c.body),
                            ],
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.3,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Everyone in tiles, a page at a time (2×2 on phones, 3×3 on wide
/// screens); swipe for the next page. Tap someone to see them large.
class _Grid extends StatelessWidget {
  const _Grid({
    required this.people,
    required this.perPage,
    required this.onPin,
  });

  final List<Participant> people;
  final int perPage;
  final void Function(Participant) onPin;

  @override
  Widget build(BuildContext context) {
    final pages = (people.length / perPage).ceil().clamp(1, 99);
    final cols = perPage == 4 ? 2 : 3;
    return PageView.builder(
      itemCount: pages,
      itemBuilder: (context, page) {
        final shown = people.skip(page * perPage).take(perPage).toList();
        final c = shown.length == 1 ? 1 : cols;
        return LayoutBuilder(
          builder: (context, box) {
            final rows = (shown.length / c).ceil().clamp(1, 9);
            final w = (box.maxWidth - (c - 1) * 8) / c;
            final h = (box.maxHeight - (rows - 1) * 8) / rows;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              children: [
                for (final p in shown)
                  GestureDetector(
                    onTap: () => onPin(p),
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: _Face(participant: p, you: p is LocalParticipant),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Your signal is poor: switch to audio only?
class _AudioOnlyOffer extends StatelessWidget {
  const _AudioOnlyOffer({required this.onYes, required this.onNo});

  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    return _Frost(
      radius: Radii.lg,
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.wifi_exclamationmark,
            color: Color(0xFFFFC145),
            size: 18,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Your signal is poor. Switch to audio only?',
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: onNo,
            child: const Text('No', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: onYes,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _stageTop,
            ),
            child: const Text('Audio only'),
          ),
        ],
      ),
    );
  }
}
