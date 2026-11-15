import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as picker;

import 'chat_video.dart';

/// What the camera took: a photo or a video file.
typedef CameraShot = ({XFile file, bool video});

/// Our own camera for the chat (phones): tap the button for a photo, hold
/// it for a video (up to 2 minutes), flash, flip, and the gallery.
/// Returns what was taken, or null.
class ChatCameraScreen extends StatefulWidget {
  const ChatCameraScreen({super.key});

  @override
  State<ChatCameraScreen> createState() => _ChatCameraScreenState();
}

class _ChatCameraScreenState extends State<ChatCameraScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  CameraController? _c;
  int _which = 0;
  FlashMode _flash = FlashMode.off;
  bool _recording = false;
  DateTime? _recStart;
  Timer? _tick;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    unawaited(_c?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      unawaited(c.dispose());
      _c = null;
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_open());
    }
  }

  Future<void> _start() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = 'No camera found.');
        return;
      }
      _which = _cameras
          .indexWhere((c) => c.lensDirection == CameraLensDirection.back)
          .clamp(0, _cameras.length - 1);
      await _open();
    } catch (_) {
      if (mounted) setState(() => _error = 'Allow the camera for this app.');
    }
  }

  Future<void> _open() async {
    final old = _c;
    _c = null;
    if (mounted) setState(() {});
    await old?.dispose();
    final c = CameraController(
      _cameras[_which],
      ResolutionPreset.high,
      enableAudio: true,
    );
    try {
      await c.initialize();
      await c.setFlashMode(_flash);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the camera.');
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() => _c = c);
  }

  Future<void> _photo() async {
    final c = _c;
    if (c == null || _recording || c.value.isTakingPicture) return;
    try {
      final x = await c.takePicture();
      if (mounted) Navigator.pop<CameraShot>(context, (file: x, video: false));
    } catch (_) {}
  }

  Future<void> _startVideo() async {
    final c = _c;
    if (c == null || _recording) return;
    try {
      await c.startVideoRecording();
      setState(() {
        _recording = true;
        _recStart = DateTime.now();
      });
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        setState(() {});
        if (DateTime.now().difference(_recStart!) >= maxVideoLength) {
          unawaited(_stopVideo());
        }
      });
    } catch (_) {}
  }

  Future<void> _stopVideo() async {
    final c = _c;
    if (c == null || !_recording) return;
    _tick?.cancel();
    try {
      final x = await c.stopVideoRecording();
      if (mounted) Navigator.pop<CameraShot>(context, (file: x, video: true));
    } catch (_) {
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _gallery() async {
    final x = await picker.ImagePicker().pickMedia();
    if (x == null || !mounted) return;
    final video =
        x.mimeType?.startsWith('video') ??
        RegExp(
          r'\.(mp4|mov|3gp|webm|mkv)$',
          caseSensitive: false,
        ).hasMatch(x.path);
    Navigator.pop<CameraShot>(context, (file: XFile(x.path), video: video));
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final rec = _recStart == null
        ? Duration.zero
        : DateTime.now().difference(_recStart!);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (c != null && c.value.isInitialized)
            Center(child: CameraPreview(c))
          else
            Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(
                      _error!,
                      style: const TextStyle(color: Colors.white70),
                    ),
            ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      color: Colors.white,
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(CupertinoIcons.xmark),
                    ),
                    const Spacer(),
                    if (_recording)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5484D),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          videoLength(rec.inMilliseconds),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const Spacer(),
                    IconButton(
                      color: Colors.white,
                      tooltip: 'Flash',
                      onPressed: c == null
                          ? null
                          : () async {
                              final next = switch (_flash) {
                                FlashMode.off => FlashMode.auto,
                                FlashMode.auto => FlashMode.always,
                                _ => FlashMode.off,
                              };
                              try {
                                await c.setFlashMode(next);
                                setState(() => _flash = next);
                              } catch (_) {}
                            },
                      icon: Icon(switch (_flash) {
                        FlashMode.off => Icons.flash_off,
                        FlashMode.auto => Icons.flash_auto,
                        _ => Icons.flash_on,
                      }),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  _recording
                      ? 'Let go to stop'
                      : 'Tap for a photo, hold for a video',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        color: Colors.white,
                        iconSize: 30,
                        tooltip: 'Gallery',
                        onPressed: _recording ? null : _gallery,
                        icon: const Icon(CupertinoIcons.photo_on_rectangle),
                      ),
                      GestureDetector(
                        onTap: _photo,
                        onLongPressStart: (_) => _startVideo(),
                        onLongPressEnd: (_) => _stopVideo(),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: _recording ? 92 : 76,
                          height: _recording ? 92 : 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 5),
                            color: _recording
                                ? const Color(0xFFE5484D)
                                : Colors.white24,
                          ),
                        ),
                      ),
                      IconButton(
                        color: Colors.white,
                        iconSize: 30,
                        tooltip: 'Flip camera',
                        onPressed: _recording || _cameras.length < 2
                            ? null
                            : () {
                                _which = (_which + 1) % _cameras.length;
                                unawaited(_open());
                              },
                        icon: const Icon(CupertinoIcons.camera_rotate),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
