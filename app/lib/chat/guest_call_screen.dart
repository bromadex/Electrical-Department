import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';

/// Outsiders waiting to join a chat's call (migration 0048), live.
final waitingGuestsProvider = StreamProvider.autoDispose
    .family<List<({String id, String name})>, String>((ref, conversationId) {
      return ref
          .watch(supabaseProvider)
          .from('call_guests')
          .stream(primaryKey: ['id'])
          .eq('conversation_id', conversationId)
          .map(
            (rows) => [
              for (final r in rows)
                if (r['status'] == 'waiting')
                  (id: r['id'] as String, name: r['name'] as String),
            ],
          );
    });

/// Makes a guest link for a chat's call and offers to share it.
Future<void> inviteGuest(
  BuildContext context,
  WidgetRef ref,
  String conversationId,
) async {
  final hours = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (s) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('Invite a guest by link'),
            subtitle: Text(
              'For contractors or clients without an account. They join in '
              'a browser and wait until someone in the call lets them in.',
            ),
          ),
          for (final (h, label) in const [
            (2, '2 hours'),
            (8, '8 hours'),
            (24, '1 day'),
            (72, '3 days'),
          ])
            ListTile(
              leading: const Icon(CupertinoIcons.link),
              title: Text('Link that works for $label'),
              onTap: () => Navigator.pop(s, h),
            ),
        ],
      ),
    ),
  );
  if (hours == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final res =
        await ref
                .read(supabaseProvider)
                .rpc(
                  'fn_create_guest_link',
                  params: {'p_conversation': conversationId, 'p_hours': hours},
                )
            as Map;
    final link = '${Env.webUrl}/guest/${res['token']}';
    await SharePlus.instance.share(
      ShareParams(text: 'Join our call: $link', subject: 'Call link'),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          e is PostgrestException
              ? e.message.replaceFirst(RegExp(r'^[A-Z_]+: '), '')
              : 'Could not make a link. Check your signal.',
        ),
      ),
    );
  }
}

/// "Ana (guest) wants to join · Let in / Turn away", for people in the call.
class WaitingGuestsBar extends ConsumerWidget {
  const WaitingGuestsBar({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting =
        ref.watch(waitingGuestsProvider(conversationId)).value ?? const [];
    if (waiting.isEmpty) return const SizedBox.shrink();
    Future<void> decide(String id, bool admit) async {
      try {
        await ref
            .read(supabaseProvider)
            .rpc('fn_decide_guest', params: {'p_guest': id, 'p_admit': admit});
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Only whoever runs the call can let guests in.'),
            ),
          );
        }
      }
    }

    return Column(
      children: [
        for (final g in waiting)
          Container(
            margin: const EdgeInsets.only(top: Space.xs),
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.person_crop_circle_badge_exclam,
                  color: Color(0xFFFFC145),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${g.name} (guest) wants to join',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                TextButton(
                  onPressed: () => decide(g.id, false),
                  child: const Text(
                    'Turn away',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: () => decide(g.id, true),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF2FBF71),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Let in'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

enum _GuestStage { name, waiting, inCall, denied, ended }

/// The page an outsider opens from a guest link (browser, no account):
/// their name, then the waiting room, then a simple call with microphone,
/// camera and leave.
class GuestCallScreen extends ConsumerStatefulWidget {
  const GuestCallScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<GuestCallScreen> createState() => _GuestCallScreenState();
}

class _GuestCallScreenState extends ConsumerState<GuestCallScreen> {
  final _name = TextEditingController();
  _GuestStage _stage = _GuestStage.name;
  String? _error;
  String _title = 'Call';
  String? _guestId;
  String? _secret;
  Timer? _poll;
  Room? _room;
  bool _busy = false;

  @override
  void dispose() {
    _poll?.cancel();
    _name.dispose();
    final r = _room;
    if (r != null) unawaited(r.disconnect().then((_) => r.dispose()));
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final res = await ref
        .read(supabaseProvider)
        .functions
        .invoke('guest-join', body: body);
    return Map<String, dynamic>.from(res.data as Map);
  }

  String _msg(Object e) {
    if (e is FunctionException) {
      final d = e.details;
      final m = d is Map ? '${d['error'] ?? ''}' : '$d';
      if (m.isNotEmpty) return m.replaceFirst(RegExp(r'^[A-Z_]+: '), '');
    }
    return 'Could not reach the server. Check your connection.';
  }

  Future<void> _ask() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give your name so they know who you are.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _call({'token': widget.token, 'name': name});
      _guestId = r['guest_id'] as String;
      _secret = r['secret'] as String;
      setState(() {
        _title = r['title'] as String? ?? 'Call';
        _stage = _GuestStage.waiting;
      });
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    } catch (e) {
      setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _checking = false;
  Future<void> _check() async {
    if (_checking || _guestId == null) return;
    _checking = true;
    try {
      final r = await _call({'guest_id': _guestId, 'secret': _secret});
      final status = r['status'] as String?;
      if (status == 'admitted') {
        _poll?.cancel();
        await _join(r['url'] as String, r['token'] as String);
      } else if (status == 'denied' || status == 'ended') {
        _poll?.cancel();
        if (mounted) {
          setState(
            () => _stage = status == 'denied'
                ? _GuestStage.denied
                : _GuestStage.ended,
          );
        }
      }
    } catch (_) {
      // Keep waiting through a dropped connection.
    } finally {
      _checking = false;
    }
  }

  Future<void> _join(String url, String token) async {
    final room = Room(
      roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
    );
    try {
      await room.connect(url, token);
    } catch (e) {
      await room.dispose();
      if (mounted) setState(() => _error = 'Could not connect to the call.');
      return;
    }
    room.addListener(_changed);
    room.createListener().on<RoomDisconnectedEvent>((_) {
      if (mounted) setState(() => _stage = _GuestStage.ended);
    });
    setState(() {
      _room = room;
      _stage = _GuestStage.inCall;
    });
    try {
      await room.localParticipant?.setMicrophoneEnabled(true);
    } catch (_) {}
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _leave() async {
    final r = _room;
    _room = null;
    await r?.disconnect();
    if (mounted) setState(() => _stage = _GuestStage.ended);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A2A24), Color(0xFF0B141A)],
          ),
        ),
        child: SafeArea(
          child: switch (_stage) {
            _GuestStage.inCall => _inCall(),
            _ => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: _before(),
                ),
              ),
            ),
          },
        ),
      ),
    );
  }

  Widget _before() {
    const white = TextStyle(color: Colors.white);
    final Widget body = switch (_stage) {
      _GuestStage.name => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Join the call',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Bravura Electrical invited you. Give your name; someone in the '
            'call will let you in.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _name,
            autofocus: true,
            style: white,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _ask(),
            decoration: const InputDecoration(
              labelText: 'Your name and company',
              labelStyle: TextStyle(color: Colors.white70),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFFFB4B6)),
              ),
            ),
          const SizedBox(height: Space.md),
          FilledButton(
            onPressed: _busy ? null : _ask,
            child: Text(_busy ? 'Asking…' : 'Ask to join'),
          ),
        ],
      ),
      _GuestStage.waiting => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: Space.md),
          Text(
            'Waiting to be let in to $_title…',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 6),
          const Text(
            'Keep this page open. Your microphone will be on when you join.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
      _GuestStage.denied => const Text(
        'You were not let in to this call.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: 18),
      ),
      _ => const Text(
        'The call has ended for you. You can close this page.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: 18),
      ),
    };
    return body;
  }

  Widget _inCall() {
    final room = _room!;
    final local = room.localParticipant;
    final people = <Participant>[...room.remoteParticipants.values, ?local];
    final mic = local?.isMicrophoneEnabled() ?? false;
    final cam = local?.isCameraEnabled() ?? false;
    final cols = people.length <= 1
        ? 1
        : people.length <= 4
        ? 2
        : 3;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Text(
            '$_title · ${people.length} in the call',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: GridView.count(
            crossAxisCount: cols,
            padding: const EdgeInsets.all(Space.sm),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 4 / 3,
            children: [for (final p in people) _GuestTile(participant: p)],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                tooltip: mic ? 'Mute' : 'Unmute',
                onPressed: () async {
                  await local?.setMicrophoneEnabled(!mic);
                  _changed();
                },
                icon: Icon(
                  mic ? CupertinoIcons.mic_fill : CupertinoIcons.mic_slash_fill,
                ),
              ),
              const SizedBox(width: Space.md),
              IconButton.filledTonal(
                tooltip: cam ? 'Camera off' : 'Camera on',
                onPressed: () async {
                  try {
                    await local?.setCameraEnabled(!cam);
                  } catch (_) {}
                  _changed();
                },
                icon: Icon(
                  cam
                      ? CupertinoIcons.video_camera_solid
                      : CupertinoIcons.video_camera,
                ),
              ),
              const SizedBox(width: Space.md),
              IconButton.filled(
                tooltip: 'Leave',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFE5484D),
                ),
                onPressed: _leave,
                icon: const Icon(CupertinoIcons.phone_down_fill),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GuestTile extends StatelessWidget {
  const _GuestTile({required this.participant});

  final Participant participant;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: participant,
      builder: (context, _) {
        final p = participant;
        VideoTrack? video;
        for (final pub in p.videoTrackPublications) {
          final t = pub.track;
          if (t is VideoTrack && !pub.muted) {
            video = t;
            if (pub.source == TrackSource.screenShareVideo) break;
          }
        }
        final name = p is LocalParticipant
            ? 'You'
            : (p.name.isEmpty ? 'Someone' : p.name);
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (video != null)
                VideoTrackRenderer(video, fit: VideoViewFit.contain)
              else
                ColoredBox(
                  color: BrandColors.maroon.withValues(alpha: 0.5),
                  child: Center(child: AppAvatar(name: name, size: 64)),
                ),
              Positioned(
                left: 8,
                bottom: 6,
                child: Text(
                  name,
                  style: TextStyle(
                    color: p.isSpeaking
                        ? const Color(0xFF2FBF71)
                        : Colors.white,
                    fontWeight: FontWeight.w600,
                    shadows: const [Shadow(blurRadius: 6)],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
