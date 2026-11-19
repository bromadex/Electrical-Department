import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:floating/floating.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;
import 'package:livekit_client/livekit_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

/// Video in calls: Auto, Low (360p, saves data on mine sites) or Audio only
/// (no video sent or received; shared screens still show). Kept on the
/// device.
enum CallQuality {
  auto('Auto'),
  low('Low (saves data)'),
  audio('Audio only');

  const CallQuality(this.label);
  final String label;
}

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

  /// You chair this call (call-admin): mute, remove, lower hands, end.
  bool isChair = false;

  /// Video quality for calls (see [CallQuality]).
  CallQuality quality = CallQuality.auto;

  /// Your signal is poor: the call screen offers audio only, once.
  bool offerAudioOnly = false;
  bool _offeredAudioOnly = false;

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

  /// Bumped by each join and each hang-up: a join that finds it changed
  /// after waiting (for the pass or the call server) was hung up meanwhile
  /// and stops, instead of putting you back in the call.
  int _attempt = 0;

  /// How long a direct call rings before it gives up.
  static const ringFor = Duration(seconds: 45);

  /// A group call or meeting with nobody else in it (no one came, or
  /// everyone left) ends after this, so a forgotten call does not stay open.
  static const aloneFor = Duration(minutes: 5);
  DateTime? _aloneSince;

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
    bool mic = true,
    bool? speaker,
    String? ringId,
  }) async {
    if (conversationId == conversation && active) return;
    if (active) await leave();
    final attempt = ++_attempt;
    bool stale() => attempt != _attempt || _disposed;
    conversationId = conversation;
    _ringId = ringId;
    stage = CallStage.connecting;
    error = null;
    _changed();

    // 0. Answered from the ringing screen: is the call still on? If the
    // caller already hung up, say so instead of starting a new call that
    // would ring them back.
    if (ringId != null) {
      try {
        final live = await _db
            .from('calls')
            .select('id')
            .eq('conversation_id', conversation)
            .isFilter('ended_at', null)
            .limit(1)
            .timeout(const Duration(seconds: 8));
        if (stale()) return;
        if ((live as List).isEmpty) {
          unawaited(IncomingCalls.end(ringId));
          stage = CallStage.idle;
          conversationId = null;
          _changed();
          snack('The call ended before you answered. Call back from the chat.');
          return;
        }
      } catch (_) {
        // No answer from the server: try to join anyway.
        if (stale()) return;
      }
    }

    // 1. The call pass from our server (checks you are in this chat).
    final Map<String, dynamic> data;
    try {
      final res = await _db.functions.invoke(
        'livekit-token',
        body: {'conversation_id': conversation, 'video': video},
      );
      data = Map<String, dynamic>.from(res.data as Map);
      if (stale()) return;
    } on FunctionException catch (e) {
      if (stale()) return;
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
      if (stale()) return;
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
      if (stale()) return;
      return _fail('Could not connect to the call server. ($e)');
    }
    if (stale() || conversationId != conversation) {
      // Hung up while connecting: leave the room and tell the server.
      _endCall();
      await _close(r);
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
      ..on<DataReceivedEvent>((e) {
        if (e.topic != 'chair') return;
        try {
          final a = (jsonDecode(utf8.decode(e.data)) as Map)['a'];
          snack(switch (a) {
            'muted' => 'The chair muted you. Tap the microphone to talk again.',
            'removed' => 'The chair removed you from the call.',
            'ended' => 'The chair ended the call for everyone.',
            _ => 'The chair changed something in the call.',
          });
        } catch (_) {}
        _changed();
      })
      ..on<TrackPublishedEvent>((e) => _applyQuality(e.publication))
      ..on<TrackSubscribedEvent>((e) => _applyQuality(e.publication))
      ..on<ParticipantConnectionQualityUpdatedEvent>((e) {
        if (e.participant is LocalParticipant &&
            e.connectionQuality == ConnectionQuality.poor &&
            quality != CallQuality.audio &&
            !_offeredAudioOnly) {
          _offeredAudioOnly = true;
          offerAudioOnly = true;
        }
        _changed();
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        // A one-to-one call ends for both when either hangs up (as on
        // WhatsApp); a group call goes on while anyone is left.
        if (room == r &&
            since != null &&
            r.remoteParticipants.isEmpty &&
            _isDirect(conversation)) {
          snack('Call ended.');
          unawaited(leave());
        }
      })
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
    if (!kIsWeb) unawaited(setSpeaker(speaker ?? video));
    unawaited(_checkChair(conversation));
    unawaited(_pipOnLeave(true));
    await _loadQuality();
    video = video && quality != CallQuality.audio;

    // 3. Microphone (and camera for a video call). If the browser or phone
    // blocks them you stay in the call, muted.
    try {
      if (mic) await r.localParticipant?.setMicrophoneEnabled(true);
      if (video) {
        await r.localParticipant?.setCameraEnabled(
          true,
          cameraCaptureOptions: _cameraOptions,
        );
      }
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
    if (r.remoteParticipants.isEmpty && !_isDirect(conversationId ?? '')) {
      final alone = _aloneSince ??= DateTime.now();
      if (DateTime.now().difference(alone) > aloneFor) {
        snack(
          since == null
              ? 'Nobody joined for 5 minutes, so the call ended.'
              : 'Everyone else left 5 minutes ago, so the call ended.',
        );
        unawaited(leave());
        return;
      }
    } else {
      _aloneSince = null;
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
    unawaited(_tellLeft(id));
  }

  /// Tells the server you hung up. On a weak line it tries again for a
  /// while: until it hears, the other phone shows the call as still on.
  Future<void> _tellLeft(String id) async {
    for (var wait = 2; wait <= 32; wait *= 2) {
      try {
        await _db
            .rpc('fn_leave_call', params: {'p_call': id})
            .timeout(const Duration(seconds: 10));
        return;
      } catch (_) {
        await Future<void>.delayed(Duration(seconds: wait));
      }
    }
  }

  /// Hangs up (the red button, the notification, or no answer).
  Future<void> leave() async {
    _attempt++;
    if (stage == CallStage.inCall) HapticFeedback.heavyImpact();
    _clock?.cancel();
    _endCall();
    try {
      _stopCaptions();
      await _stopShareService().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Whatever fails here, the call itself still ends below.
    }
    final r = room;
    room = null;
    stage = CallStage.idle;
    since = null;
    waiting = false;
    rang = false;
    floating.clear();
    _aloneSince = null;
    isChair = false;
    offerAudioOnly = false;
    _offeredAudioOnly = false;
    unawaited(_pipOnLeave(false));
    _changed();
    if (r != null) {
      r.removeListener(_changed);
      final events = _events;
      _events = null;
      try {
        await events?.dispose();
      } catch (_) {}
      await _close(r);
    }
  }

  /// Leaves the call server's room and frees it, even on a bad line: a
  /// disconnect that hangs is given up after a few seconds.
  Future<void> _close(Room r) async {
    try {
      await r.disconnect().timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      await r.dispose();
    } catch (_) {}
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
      await local.setCameraEnabled(
        !local.isCameraEnabled(),
        cameraCaptureOptions: _cameraOptions,
      );
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

  /// Rings people into this call (fn_call_invite, migration 0056): chat
  /// members as before, and anyone else you can chat with as a guest of
  /// the call only, so a one-to-one call can become a group call. Returns
  /// how many, or null on failure.
  Future<int?> ring(List<String> userIds) async {
    final id = conversationId;
    if (id == null || userIds.isEmpty) return 0;
    try {
      final n = await _db.rpc(
        'fn_call_invite',
        params: {'p_conversation': id, 'p_users': userIds},
      );
      return (n as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      snack(
        e.message.startsWith('NOT_FOUND')
            ? 'Only people in this chat can add others to the call.'
            : e.message.replaceFirst(RegExp(r'^[A-Z_]+: '), ''),
      );
      return null;
    } catch (_) {
      snack('Could not ring them. Check your signal.');
      return null;
    }
  }

  // ---- Chair controls (call-admin edge function).

  Future<void> _checkChair(String conversation) async {
    try {
      final res = await _db.functions.invoke(
        'call-admin',
        body: {'conversation_id': conversation, 'action': 'check'},
      );
      isChair = (res.data as Map?)?['chair'] == true;
      _changed();
    } catch (_) {
      isChair = false;
    }
  }

  /// mute, mute_all, lower (one or, with no identity, everyone), remove,
  /// end. Returns how many people it changed, or null on failure.
  Future<int?> chair(String action, {String? identity}) async {
    final id = conversationId;
    if (id == null) return null;
    try {
      final res = await _db.functions.invoke(
        'call-admin',
        body: {'conversation_id': id, 'action': action, 'identity': ?identity},
      );
      return ((res.data as Map?)?['changed'] as num?)?.toInt() ?? 0;
    } on FunctionException catch (e) {
      final d = e.details;
      final msg = d is Map ? '${d['error'] ?? ''}' : '$d';
      snack(
        msg.isEmpty
            ? 'That did not work (${e.status}).'
            : msg.replaceFirst(RegExp(r'^[A-Z_]+: '), ''),
      );
    } catch (_) {
      snack('That needs signal. Try again.');
    }
    return null;
  }

  // ---- Video quality and audio only (mine sites with poor signal).

  static const _qualityKey = 'call_video_quality';

  CameraCaptureOptions? get _cameraOptions => quality == CallQuality.low
      ? const CameraCaptureOptions(params: VideoParametersPresets.h360_169)
      : null;

  Future<void> _loadQuality() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_qualityKey);
      quality =
          CallQuality.values.where((q) => q.name == v).firstOrNull ??
          CallQuality.auto;
    } catch (_) {}
  }

  Future<void> setQuality(CallQuality q) async {
    quality = q;
    offerAudioOnly = false;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_qualityKey, q.name);
    } catch (_) {}
    final r = room;
    if (r != null) {
      if (q == CallQuality.audio &&
          (r.localParticipant?.isCameraEnabled() ?? false)) {
        try {
          await r.localParticipant?.setCameraEnabled(false);
        } catch (_) {}
      }
      for (final p in r.remoteParticipants.values) {
        for (final pub in p.videoTrackPublications) {
          await _applyQuality(pub);
        }
      }
    }
    _changed();
  }

  void dismissAudioOnly() {
    offerAudioOnly = false;
    _changed();
  }

  /// Audio only stops receiving cameras (shared screens still come);
  /// Low asks for the smallest video layer.
  Future<void> _applyQuality(TrackPublication pub) async {
    if (pub is! RemoteTrackPublication || pub.kind != TrackType.VIDEO) return;
    try {
      if (pub.source == TrackSource.screenShareVideo) return;
      if (quality == CallQuality.audio) {
        await pub.disable();
      } else {
        await pub.enable();
        await pub.setVideoQuality(
          quality == CallQuality.low ? VideoQuality.LOW : VideoQuality.HIGH,
        );
      }
    } catch (_) {}
  }

  // ---- Picture-in-picture (Android): leaving the app during a call shows
  // a small window with the call.

  bool get _pipSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _pipOnLeave(bool on) async {
    if (!_pipSupported) return;
    try {
      final f = Floating();
      if (on) {
        if (await f.isPipAvailable) {
          await f.enable(const OnLeavePiP(aspectRatio: Rational.vertical()));
        }
      } else {
        await f.cancelOnLeavePiP();
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
