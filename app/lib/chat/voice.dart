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

  /// Time spent paused, and when the current pause began.
  Duration _pausedFor = Duration.zero;
  DateTime? _pausedAt;
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
    _pausedFor = Duration.zero;
    _pausedAt = null;
    return true;
  }

  bool get paused => _pausedAt != null;

  Future<void> pause() async {
    if (_started == null || paused) return;
    await _rec.pause();
    _pausedAt = DateTime.now();
  }

  Future<void> resume() async {
    final at = _pausedAt;
    if (at == null) return;
    await _rec.resume();
    _pausedFor += DateTime.now().difference(at);
    _pausedAt = null;
  }

  /// Recorded length so far, not counting pauses.
  Duration get elapsed => _started == null
      ? Duration.zero
      : (_pausedAt ?? DateTime.now()).difference(_started!) - _pausedFor;

  /// The microphone level, 0 (quiet) to 1 (loud), a few times a second,
  /// for the live waveform.
  Stream<double> levels() => _rec
      .onAmplitudeChanged(const Duration(milliseconds: 120))
      .map((a) => ((a.current + 50) / 50).clamp(0.05, 1.0).toDouble());

  /// Stops and returns the note, or null when it was too short.
  Future<ChatAttachment?> stop() async {
    final ms = elapsed.inMilliseconds;
    final where = await _rec.stop();
    _started = null;
    _pausedAt = null;
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
    _pausedAt = null;
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

  /// Playback speed: 1×, 1.5×, 2×.
  double _speed = 1;

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
      await p.setPlaybackRate(_speed);
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _nextSpeed() async {
    final next = switch (_speed) {
      1.0 => 1.5,
      1.5 => 2.0,
      _ => 1.0,
    };
    setState(() => _speed = next);
    try {
      await _player?.setPlaybackRate(next);
    } catch (_) {}
  }

  /// Tapping or dragging along the waveform jumps there.
  Future<void> _seekTo(double fraction) async {
    final to = Duration(
      milliseconds: (widget.durationMs * fraction.clamp(0.0, 1.0)).round(),
    );
    setState(() => _at = to);
    final p = _player;
    if (p == null) {
      await _toggle();
      await _player?.seek(to);
      return;
    }
    try {
      await p.seek(to);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // On WhatsApp-style bubbles: dark text on the light green, light text
    // on the dark green.
    final fg = Theme.of(context).brightness == Brightness.dark
        ? ChatColors.textDark
        : ChatColors.text;
    final dim = fg.withValues(alpha: 0.35);
    final total = widget.durationMs <= 0 ? 1 : widget.durationMs;
    final done = (_at.inMilliseconds / total).clamp(0.0, 1.0);
    final ready = widget.url != null || widget.bytes != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: ChatColors.green,
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
        LayoutBuilder(
          builder: (context, _) {
            const width = 28 * 5.0;
            void at(double dx) => ready ? _seekTo(dx / width) : null;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => at(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => at(d.localPosition.dx),
              child: SizedBox(
                width: width,
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
            );
          },
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
        if (_playing || _speed != 1)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: _nextSpeed,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${_speed == _speed.roundToDouble() ? _speed.toInt() : _speed}×',
                  style: TextStyle(
                    color: fg,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The live waveform while recording: the last few seconds of microphone
/// level as bars.
class LiveWaveform extends StatelessWidget {
  const LiveWaveform({super.key, required this.levels, this.color});

  final List<double> levels;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: 28,
      child: LayoutBuilder(
        builder: (context, box) {
          final count = (box.maxWidth / 5).floor().clamp(1, 80);
          final shown = levels.length > count
              ? levels.sublist(levels.length - count)
              : levels;
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (final l in shown)
                Container(
                  width: 3,
                  height: 4 + 24 * l,
                  margin: const EdgeInsets.only(left: 2),
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
