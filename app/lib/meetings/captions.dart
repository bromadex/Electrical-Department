import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/core_providers.dart';

/// One line of a meeting's live captions.
class Caption {
  Caption.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      userId = j['user_id'] as String,
      spokenAt = DateTime.parse(j['spoken_at'] as String).toLocal(),
      body = j['body'] as String;

  final String id;
  final String userId;
  final DateTime spokenAt;
  final String body;
}

/// A meeting's captions, oldest first, kept live over realtime.
final meetingCaptionsProvider = StreamProvider.autoDispose
    .family<List<Caption>, String>((ref, meetingId) {
      return ref
          .watch(supabaseProvider)
          .from('meeting_captions')
          .stream(primaryKey: ['id'])
          .eq('meeting_id', meetingId)
          .order('spoken_at', ascending: true)
          .map((rows) => [for (final r in rows) Caption.fromJson(r)]);
    });

/// Sends what this person says during a meeting, in 15-second pieces, to
/// the meeting-caption edge function, which adds it as a caption with
/// their name. In the browser it listens to the microphone itself; in the
/// Android app it takes the call's own microphone sound (flutter_webrtc,
/// audio input channel), so the call and the captions do not fight over
/// the microphone. Pieces wait and retry when the signal is poor.
class CaptionSender {
  CaptionSender({
    required this.client,
    required this.meetingId,
    required this.micOn,
    required this.onProblem,
  });

  final SupabaseClient client;
  final String meetingId;

  /// Pieces recorded while muted are thrown away.
  final bool Function() micOn;

  /// A message for the person, e.g. captions are not set up.
  final void Function(String message) onProblem;

  static const piece = Duration(seconds: 15);

  bool _running = false;
  Timer? _timer;
  AudioRecorder? _web;
  webrtc.MediaRecorder? _android;
  String? _path;
  DateTime? _started;
  bool _mutedDuringPiece = false;
  final _queue = <({Uint8List bytes, String mime, DateTime at})>[];
  bool _sending = false;

  bool get running => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    if (kIsWeb) {
      _web = AudioRecorder();
      if (!await _web!.hasPermission()) {
        _running = false;
        onProblem('Allow the microphone for live captions.');
        return;
      }
    }
    await _begin();
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    await _finish(send: true);
    await _web?.dispose();
    _web = null;
  }

  Future<void> _begin() async {
    if (!_running) return;
    _started = DateTime.now();
    _mutedDuringPiece = !micOn();
    try {
      if (kIsWeb) {
        await _web!.start(
          const RecordConfig(
            encoder: AudioEncoder.opus,
            bitRate: 16000,
            numChannels: 1,
          ),
          path: '',
        );
      } else {
        _path =
            '${(await getTemporaryDirectory()).path}/caption-'
            '${DateTime.now().millisecondsSinceEpoch}.m4a';
        _android = webrtc.MediaRecorder();
        await _android!.start(
          _path!,
          audioChannel: webrtc.RecorderAudioChannel.INPUT,
        );
      }
    } catch (e) {
      _running = false;
      onProblem('Live captions could not use the microphone ($e).');
      return;
    }
    _timer = Timer(piece, () async {
      await _finish(send: true);
      await _begin();
    });
  }

  /// Ends the current piece and queues it.
  Future<void> _finish({required bool send}) async {
    final started = _started;
    if (started == null) return;
    _started = null;
    if (!micOn()) _mutedDuringPiece = true;
    try {
      Uint8List? bytes;
      String mime;
      if (kIsWeb) {
        final url = await _web?.stop();
        mime = 'audio/webm';
        if (url != null) bytes = await XFile(url).readAsBytes();
      } else {
        await _android?.stop();
        _android = null;
        mime = 'audio/mp4';
        if (_path != null) bytes = await XFile(_path!).readAsBytes();
      }
      // Skip muted pieces and near-empty files (silence compresses small).
      if (send && !_mutedDuringPiece && bytes != null && bytes.length > 2500) {
        _queue.add((bytes: bytes, mime: mime, at: started));
        unawaited(_drain());
      }
    } catch (_) {
      // A lost piece is a few seconds of captions; keep going.
    }
  }

  Future<void> _drain() async {
    if (_sending) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty) {
        final p = _queue.first;
        var tries = 0;
        while (true) {
          try {
            await client.functions.invoke(
              'meeting-caption',
              body: {
                'meeting_id': meetingId,
                'spoken_at': p.at.toUtc().toIso8601String(),
                'mime': p.mime,
                'audio': base64Encode(p.bytes),
              },
            );
            break;
          } on FunctionException catch (e) {
            final d = e.details;
            final msg = d is Map ? '${d['error'] ?? ''}' : '$d';
            if (msg.startsWith('UNAVAILABLE')) {
              _queue.clear();
              _running = false;
              _timer?.cancel();
              onProblem(
                'Live captions are not set up yet. An admin adds the Groq '
                'key in Supabase.',
              );
              return;
            }
            // The meeting ended or this person cannot add captions.
            if (e.status == 400 || e.status == 404) break;
            if (++tries >= 4) break;
            await Future<void>.delayed(Duration(seconds: 2 * tries));
          } catch (_) {
            // No signal: wait and try again, keeping the order.
            if (++tries >= 6) break;
            await Future<void>.delayed(Duration(seconds: 3 * tries));
          }
        }
        _queue.removeAt(0);
      }
    } finally {
      _sending = false;
    }
  }
}
