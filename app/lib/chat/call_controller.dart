import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;
import 'package:livekit_client/livekit_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../meetings/captions.dart';
import '../meetings/meetings_repository.dart';
import '../services/core_providers.dart';
import '../services/incoming_calls.dart';
import 'chat_repository.dart';

/// For messages from a call while its screen is closed (minimised).
final appMessenger = GlobalKey<ScaffoldMessengerState>();

/// The one call you are in, for the whole app: the call screen and the
/// "return to call" bar both read it, so leaving the screen (back, ⌄)
/// keeps the call going; only hanging up ends it.
final callControllerProvider = Provider<CallController>((ref) {
  final c = CallController(ref);
  ref.onDispose(c.dispose);
  return c;
});

enum CallStage { idle, connecting, inCall }

/// An emoji floating up the call screen.
class FloatingReaction {
  FloatingReaction(this.emoji, this.from, this.x, this.id);

  final String emoji;
  final String? from;

  /// Where across the screen it rises, 0–1.
  final double x;
  final int id;
}

class CallController extends ChangeNotifier {
  CallController(this._ref) : _db = _ref.read(supabaseProvider);

  final Ref _ref;
  final SupabaseClient _db;

  CallStage stage = CallStage.idle;
  Room? room;

  /// The chat whose call this is (also while connecting).
  String? conversationId;
  String? serverTitle;
  String? error;

  /// When someone else first joined (the call timer runs from here, as on
  /// WhatsApp); null while calling or ringing.
  DateTime? since;

  /// The other phone reported that it is ringing (calls.rang_at); until
  /// then the caller sees "Calling…".
  bool rang = false;

  /// You started the call and nobody else has come yet.
  bool waiting = false;

  /// Loudspeaker (true) or earpiece; null in the browser.
  bool? speaker;
  bool captionsOff = false;
  final floating = <FloatingReaction>[];

  /// The screen is being shared from this phone (Android needs a
  /// foreground service while it lasts).
  bool get sharing => room?.localParticipant?.isScreenShareEnabled() ?? false;

  DateTime? _dialedAt;
  bool _checkingRang = false;
  Timer? _clock;
  Timer? _beat;
  String? _callId;
  String? _ongoing;
  String? _ringId;
  StreamSubscription<String>? _hungUp;
  EventsListener<RoomEvent>? _events;
  CaptionSender? _captions;
  bool _disposed = false;

  /// How long a direct call rings before it gives up.
  static const ringFor = Duration(seconds: 45);

  bool get active => stage != CallStage.idle;
  bool inCallFor(String conversation) =>
      stage == CallStage.inCall && conversationId == conversation;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void snack(String text) {
    appMessenger.currentState?.showSnackBar(
      SnackBar(duration: const Duration(seconds: 6), content: Text(text)),
    );
  }

  bool _isDirect(String conversation) =>
      (_ref.read(conversationsProvider).value ?? const [])
          .where((c) => c.id == conversation)
          .firstOrNull
          ?.isDirect ??
      false;

  /// Joins a chat's call. Already in another call: that one ends first.
  Future<void> join(
    String conversation, {
    bool video = false,
    String? ringId,
  }) async {
    if (conversationId == conversation && active) return;
    if (active) await leave();
    conversationId = conversation;
    _ringId = ringId;
    stage = CallStage.connecting;
    error = null;
    _changed();

    // 1. The call pass from our server (checks you are in this chat).
    final Map<String, dynamic> data;
    try {
      final res = await _db.functions.invoke(
        'livekit-token',
        body: {'conversation_id': conversation, 'video': video},
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
    final r = Room(
      roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
    );
    _callId = data['call_id'] as String?;
    try {
      await r.connect(data['url'] as String, data['token'] as String);
    } catch (e) {
      await r.dispose();
      _endCall();
      return _fail('Could not connect to the call server. ($e)');
    }
    if (conversationId != conversation || _disposed) {
      await r.disconnect();
      return;
    }
    r.addListener(_changed);
    _events = r.createListener()
      ..on<DataReceivedEvent>((e) {
        if (e.topic != 'reaction') return;
        try {
          final m = jsonDecode(utf8.decode(e.data)) as Map;
          float('${m['e']}', e.participant?.name);
        } catch (_) {}
      })
      ..on<ParticipantAttributesChanged>((_) => _changed())
      ..on<RoomDisconnectedEvent>((e) {
        if (room == r && e.reason != DisconnectReason.clientInitiated) {
          snack('The call ended.');
          unawaited(leave());
        }
      });
    // You started it, or it is a direct call nobody else is in yet: it is
    // calling the other person.
    waiting =
        (data['new_call'] == true || _isDirect(conversation)) &&
        r.remoteParticipants.isEmpty;
    rang = false;
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
    room = r;
    serverTitle = data['title'] as String?;
    _dialedAt = DateTime.now();
    since = r.remoteParticipants.isEmpty ? null : DateTime.now();
    stage = CallStage.inCall;
    _changed();
    unawaited(_startOngoing(serverTitle, video));
    if (!kIsWeb) unawaited(setSpeaker(video));

    // 3. Microphone (and camera for a video call). If the browser or phone
    // blocks them you stay in the call, muted.
    try {
      await r.localParticipant?.setMicrophoneEnabled(true);
      if (video) await r.localParticipant?.setCameraEnabled(true);
    } catch (_) {
      snack(
        'Your microphone or camera is blocked. Allow it for this app and '
        'tap the button again.',
      );
    }
    _changed();
  }

  void _fail(String message) {
    stage = CallStage.idle;
    error = message;
    _changed();
  }

  void _tick() {
    final r = room;
    if (r == null) return;
    if (r.remoteParticipants.isNotEmpty) {
      waiting = false;
      since ??= DateTime.now();
    }
    if (waiting && !rang) unawaited(_checkRang());
    final at = _dialedAt;
    if (waiting &&
        at != null &&
        DateTime.now().difference(at) > ringFor &&
        _isDirect(conversationId ?? '')) {
      waiting = false;
      snack('No answer. They will see a missed call.');
      unawaited(leave());
      return;
    }
    _changed();
  }

  /// Every other second while calling: is the other phone ringing yet?
  Future<void> _checkRang() async {
    final id = _callId;
    if (id == null || _checkingRang) return;
    if ((DateTime.now().second % 2) != 0) return;
    _checkingRang = true;
    try {
      final row = await _db
          .from('calls')
          .select('rang_at, answered_at')
          .eq('id', id)
          .maybeSingle();
      if (row != null &&
          (row['rang_at'] != null || row['answered_at'] != null)) {
        rang = true;
        _changed();
      }
    } catch (_) {
      // No signal: keep showing "Calling…".
    } finally {
      _checkingRang = false;
    }
  }

  Future<void> _startOngoing(String? title, bool video) async {
    if (!IncomingCalls.supported) return;
    final ring = _ringId;
    if (ring != null) {
      _ongoing = ring;
      await IncomingCalls.connected(ring);
    } else {
      _ongoing = await IncomingCalls.startOngoing(
        id: _callId ?? 'chat-$conversationId',
        title: title ?? 'Call',
        video: video,
      );
    }
    _hungUp ??= IncomingCalls.hungUp.listen((id) {
      if (id == _ongoing && stage == CallStage.inCall) {
        _ongoing = null;
        unawaited(leave());
      }
    });
  }

  /// Tells our server you left; the last one out ends the call.
  void _endCall() {
    _beat?.cancel();
    final ongoing = _ongoing;
    _ongoing = null;
    if (ongoing != null) unawaited(IncomingCalls.end(ongoing));
    final id = _callId;
    _callId = null;
    if (id == null) return;
    unawaited(
      _db
          .rpc('fn_leave_call', params: {'p_call': id})
          .then((_) {}, onError: (_) {}),
    );
  }

  /// Hangs up (the red button, the notification, or no answer).
  Future<void> leave() async {
    if (stage == CallStage.inCall) HapticFeedback.heavyImpact();
    _clock?.cancel();
    _endCall();
    _stopCaptions();
    await _stopShareService();
    final r = room;
    room = null;
    stage = CallStage.idle;
    since = null;
    waiting = false;
    rang = false;
    floating.clear();
    _changed();
    if (r != null) {
      r.removeListener(_changed);
      await _events?.dispose();
      _events = null;
      await r.disconnect();
      await r.dispose();
    }
  }

  /// Clears a failed join so the screen offers Join again.
  void reset() {
    if (stage != CallStage.idle) return;
    error = null;
    conversationId = null;
    _changed();
  }

  Future<void> toggleMic() async {
    final local = room?.localParticipant;
    if (local == null) return;
    try {
      await local.setMicrophoneEnabled(!local.isMicrophoneEnabled());
    } catch (_) {
      snack('Your microphone is blocked. Allow it for this app.');
    }
    _changed();
  }

  Future<void> toggleCamera() async {
    final local = room?.localParticipant;
    if (local == null) return;
    try {
      await local.setCameraEnabled(!local.isCameraEnabled());
    } catch (_) {
      snack('Your camera is blocked. Allow it for this app.');
    }
    _changed();
  }

  bool _front = true;
  Future<void> flip() async {
    final pub = room?.localParticipant?.videoTrackPublications.firstOrNull;
    final track = pub?.track;
    if (track is! LocalVideoTrack) return;
    _front = !_front;
    await track.setCameraPosition(
      _front ? CameraPosition.front : CameraPosition.back,
    );
    _changed();
  }

  Future<void> setSpeaker(bool on) async {
    try {
      await AudioManager.instance.setSpeakerOutputPreferred(on);
      speaker = on;
      _changed();
    } catch (_) {
      snack('Could not switch the speaker.');
    }
  }

  /// Shows an emoji floating up the screen for a few seconds.
  void float(String emoji, String? from) {
    final f = FloatingReaction(
      emoji,
      from,
      0.15 + math.Random().nextDouble() * 0.7,
      DateTime.now().microsecondsSinceEpoch,
    );
    floating.add(f);
    _changed();
    Timer(const Duration(milliseconds: 2600), () {
      floating.remove(f);
      _changed();
    });
  }

  /// Sends a reaction to everyone in the call (nothing is stored).
  Future<void> react(String emoji) async {
    HapticFeedback.selectionClick();
    float(emoji, null);
    try {
      await room?.localParticipant?.publishData(
        utf8.encode(jsonEncode({'e': emoji})),
        reliable: true,
        topic: 'reaction',
      );
    } catch (_) {}
  }

  // ---- Raise hand: a participant attribute, so people who join later see
  // it too. The value is when it went up (for the order).

  static const handKey = 'hand';

  /// When this person raised their hand; null when it is down.
  static DateTime? handOf(Participant p) {
    final v = int.tryParse(p.attributes[handKey] ?? '');
    return v == null || v == 0 ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  bool get handUp {
    final local = room?.localParticipant;
    return local != null && handOf(local) != null;
  }

  Future<void> toggleHand() async {
    final local = room?.localParticipant;
    if (local == null) return;
    HapticFeedback.selectionClick();
    final up = !handUp;
    try {
      await local.setAttributes({
        handKey: up ? '${DateTime.now().millisecondsSinceEpoch}' : '0',
      });
      if (up) unawaited(react('✋'));
    } catch (_) {
      snack('Could not raise your hand. Check your signal.');
    }
    _changed();
  }

  /// Everyone with a hand up, first raised first.
  List<Participant> get hands {
    final r = room;
    if (r == null) return const [];
    final all = <Participant>[
      ...r.remoteParticipants.values,
      ?r.localParticipant,
    ]..retainWhere((p) => handOf(p) != null);
    return all..sort((a, b) => handOf(a)!.compareTo(handOf(b)!));
  }

  // ---- Screen sharing. Browsers ask which screen; Android asks for screen
  // capture, then runs a foreground service (notification) while sharing.

  bool get canShare {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  Future<void> toggleShare() async {
    final local = room?.localParticipant;
    if (local == null) return;
    if (sharing) {
      try {
        await local.setScreenShareEnabled(false);
      } catch (_) {}
      await _stopShareService();
      _changed();
      return;
    }
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    try {
      if (android) {
        if (!await Helper.requestCapturePermission()) return;
        if (!await _startShareService()) {
          snack(
            'Allow the app to keep running in the background to share '
            'your screen.',
          );
          return;
        }
      }
      await local.setScreenShareEnabled(true, captureScreenAudio: android);
    } catch (_) {
      await _stopShareService();
      snack('Could not share your screen.');
    }
    _changed();
  }

  Future<bool> _startShareService() async {
    try {
      var ok = await FlutterBackground.initialize(
        androidConfig: const FlutterBackgroundAndroidConfig(
          notificationTitle: 'Sharing your screen',
          notificationText: 'Everyone in the call can see your screen.',
          notificationImportance: AndroidNotificationImportance.normal,
          notificationIcon: AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
        ),
      );
      if (ok && !FlutterBackground.isBackgroundExecutionEnabled) {
        ok = await FlutterBackground.enableBackgroundExecution();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> _stopShareService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      if (FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.disableBackgroundExecution();
      }
    } catch (_) {}
  }

  // ---- Live captions while a meeting is on in this chat (captions.dart).

  void _stopCaptions() {
    final c = _captions;
    _captions = null;
    if (c != null) unawaited(c.stop());
    unawaited(WakelockPlus.disable().catchError((_) {}));
  }

  void setCaptionsOff(bool off) {
    captionsOff = off;
    _changed();
  }

  /// Starts or stops this person's captions to match the meeting.
  void syncCaptions(Meeting? meeting) {
    final want = meeting != null && !captionsOff && room != null;
    if (want && _captions?.meetingId != meeting.id) {
      _captions?.stop();
      final sender = CaptionSender(
        client: _db,
        meetingId: meeting.id,
        micOn: () => room?.localParticipant?.isMicrophoneEnabled() ?? false,
        onProblem: (msg) {
          snack(msg);
          captionsOff = true;
          _changed();
        },
      );
      _captions = sender;
      unawaited(sender.start());
      // Captions stop if the phone sleeps, so keep the screen on.
      unawaited(WakelockPlus.enable().catchError((_) {}));
    } else if (!want && _captions != null) {
      _stopCaptions();
    }
  }

  /// The call's length so far, e.g. 3:07; null before anyone answered.
  String? get elapsed => since == null ? null : formatCallLength(since!);

  @override
  void dispose() {
    _disposed = true;
    _clock?.cancel();
    _beat?.cancel();
    _hungUp?.cancel();
    unawaited(leave());
    super.dispose();
  }
}

/// 3:07, or 1:02:07 past an hour.
String formatCallLength(DateTime since, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(since);
  final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:$sec'
      : '${d.inMinutes}:$sec';
}
