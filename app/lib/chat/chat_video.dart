import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import 'chat_repository.dart';

/// Video messages are at most this long.
const maxVideoLength = Duration(minutes: 2);

/// Picks or records a video (up to 2 minutes) and makes it ready to send:
/// on phones compressed to 720p. Null when cancelled or too long.
Future<ChatAttachment?> pickChatVideo(
  BuildContext context, {
  bool record = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final x = await ImagePicker().pickVideo(
    source: record ? ImageSource.camera : ImageSource.gallery,
    maxDuration: maxVideoLength,
  );
  if (x == null) return null;
  return prepareChatVideo(x, messenger: messenger);
}

/// Compresses a recorded or picked video for sending (phones; browsers
/// send it as it is).
Future<ChatAttachment?> prepareChatVideo(
  XFile x, {
  ScaffoldMessengerState? messenger,
}) async {
  try {
    if (kIsWeb) {
      final bytes = await x.readAsBytes();
      if (bytes.length > 50 * 1024 * 1024) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('That video is too big (50 MB most).')),
        );
        return null;
      }
      return ChatAttachment(bytes: bytes, name: x.name, type: 'video/mp4');
    }
    messenger?.showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('Making the video smaller…'),
      ),
    );
    final info = await VideoCompress.compressVideo(
      x.path,
      quality: VideoQuality.Res1280x720Quality,
      includeAudio: true,
    );
    final ms = info?.duration?.round();
    if (ms != null && ms > maxVideoLength.inMilliseconds + 2000) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Videos can be up to 2 minutes long.')),
      );
      return null;
    }
    final file = info?.file;
    final bytes = file != null
        ? await file.readAsBytes()
        : await x.readAsBytes();
    return ChatAttachment(
      bytes: bytes,
      name: 'video.mp4',
      type: 'video/mp4',
      durationMs: ms,
    );
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Could not prepare that video.')),
    );
    return null;
  }
}

String videoLength(int? ms) {
  if (ms == null || ms <= 0) return '';
  final s = (ms / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// A video in the chat: a dark frame with a play button and its length.
class VideoBubble extends StatelessWidget {
  const VideoBubble({
    super.key,
    required this.message,
    required this.url,
    required this.onTap,
  });

  final ChatMessage message;
  final String? url;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final length = videoLength(message.durationMs);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 240,
          height: 160,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1C0D12), Color(0xFF0B1022)],
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: message.pending
                      ? const Padding(
                          padding: EdgeInsets.all(15),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          CupertinoIcons.play_fill,
                          color: Colors.white,
                          size: 26,
                        ),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 6,
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.video_camera_solid,
                      color: Colors.white,
                      size: 14,
                    ),
                    if (length.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        length,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen player: play, pause, seek.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.url, this.caption});

  final String url;
  final String? caption;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(
    Uri.parse(widget.url),
  );
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _c
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _ready = true);
          unawaited(_c.play());
        })
        .catchError((_) {
          if (mounted) setState(() => _failed = true);
        });
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    unawaited(_c.dispose());
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String _t(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Video'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _failed
                    ? const Text(
                        'Could not play this video.',
                        style: TextStyle(color: Colors.white70),
                      )
                    : !_ready
                    ? const CircularProgressIndicator()
                    : GestureDetector(
                        onTap: () => v.isPlaying ? _c.pause() : _c.play(),
                        child: AspectRatio(
                          aspectRatio: v.aspectRatio,
                          child: VideoPlayer(_c),
                        ),
                      ),
              ),
            ),
            if ((widget.caption ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  widget.caption!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            if (_ready)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      color: Colors.white,
                      onPressed: () => v.isPlaying ? _c.pause() : _c.play(),
                      icon: Icon(
                        v.isPlaying
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                      ),
                    ),
                    Text(
                      _t(v.position),
                      style: const TextStyle(color: Colors.white),
                    ),
                    Expanded(
                      child: Slider(
                        value: v.position.inMilliseconds
                            .clamp(0, v.duration.inMilliseconds)
                            .toDouble(),
                        max: v.duration.inMilliseconds.toDouble().clamp(
                          1,
                          double.infinity,
                        ),
                        onChanged: (x) =>
                            _c.seekTo(Duration(milliseconds: x.round())),
                      ),
                    ),
                    Text(
                      _t(v.duration),
                      style: const TextStyle(color: Colors.white),
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
