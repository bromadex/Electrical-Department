import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../theme/tokens.dart';
import 'chat_repository.dart';

/// Records a voice note: AAC (.m4a) on phones, Opus (.webm) in Chrome.
class VoiceRecorder {
  final _rec = AudioRecorder();
  DateTime? _started;
  String _type = 'audio/mp4';
  String _ext = 'm4a';

  /// Asks for the microphone; false when it is blocked.
  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    var encoder = AudioEncoder.aacLc;
    if (!await _rec.isEncoderSupported(encoder)) {
      encoder = AudioEncoder.opus;
      _type = 'audio/webm';
      _ext = 'webm';
    }
    final path = kIsWeb
        ? ''
        : '${(await getTemporaryDirectory()).path}/voice-'
              '${DateTime.now().millisecondsSinceEpoch}.$_ext';
    await _rec.start(
      RecordConfig(encoder: encoder, bitRate: 32000, numChannels: 1),
      path: path,
    );
    _started = DateTime.now();
    return true;
  }

  Duration get elapsed =>
      _started == null ? Duration.zero : DateTime.now().difference(_started!);

  /// Stops and returns the note, or null when it was too short.
  Future<ChatAttachment?> stop() async {
    final ms = elapsed.inMilliseconds;
    final where = await _rec.stop();
    _started = null;
    if (where == null || ms < 700) return null;
    final bytes = await XFile(where).readAsBytes();
    return ChatAttachment(
      bytes: bytes,
      name: 'voice.$_ext',
      type: _type,
      durationMs: ms,
    );
  }

  Future<void> cancel() async {
    _started = null;
    await _rec.cancel();
  }

  Future<void> dispose() => _rec.dispose();
}

String voiceLength(int ms) {
  final s = (ms / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// A voice note in a chat bubble: play/pause, a waveform that fills as it
/// plays, and the length.
class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({
    super.key,
    required this.id,
    required this.url,
    required this.durationMs,
    required this.mine,
    this.bytes,
  });

  final String id;
  final String? url;
  final int durationMs;
  final bool mine;

  /// Still uploading: play from memory.
  final Uint8List? bytes;

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  AudioPlayer? _player;
  final _subs = <StreamSubscription<Object?>>[];
  bool _playing = false;
  Duration _at = Duration.zero;

  // Bar heights from the message id, so each note looks its own.
  late final List<double> _bars = () {
    final r = math.Random(widget.id.hashCode);
    return [for (var i = 0; i < 28; i++) 0.25 + r.nextDouble() * 0.75];
  }();

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    var p = _player;
    if (p == null) {
      p = _player = AudioPlayer();
      _subs
        ..add(p.onPositionChanged.listen((d) => setState(() => _at = d)))
        ..add(
          p.onPlayerComplete.listen(
            (_) => setState(() {
              _playing = false;
              _at = Duration.zero;
            }),
          ),
        );
    }
    if (_playing) {
      await p.pause();
      setState(() => _playing = false);
      return;
    }
    final source = widget.url != null
        ? UrlSource(widget.url!)
        : widget.bytes != null
        ? BytesSource(widget.bytes!)
        : null;
    if (source == null) return;
    setState(() => _playing = true);
    try {
      if (_at == Duration.zero) {
        await p.play(source);
      } else {
        await p.resume();
      }
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.mine
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    final dim = fg.withValues(alpha: 0.35);
    final total = widget.durationMs <= 0 ? 1 : widget.durationMs;
    final done = (_at.inMilliseconds / total).clamp(0.0, 1.0);
    final ready = widget.url != null || widget.bytes != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: widget.mine
              ? Colors.white.withValues(alpha: 0.2)
              : BrandColors.maroon,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: ready ? _toggle : null,
            child: SizedBox.square(
              dimension: 38,
              child: Icon(
                _playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 30,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final (i, h) in _bars.indexed)
                Container(
                  width: 3,
                  height: 30 * h,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    color: i / _bars.length < done ? fg : dim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          voiceLength(
            _playing || _at > Duration.zero
                ? _at.inMilliseconds
                : widget.durationMs,
          ),
          style: TextStyle(
            color: fg.withValues(alpha: 0.8),
            fontSize: 12,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
