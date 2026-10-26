import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Holds the strokes drawn on a [SignaturePad] and turns them into a PNG.
class SignatureController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  Size _size = Size.zero;

  bool get isEmpty => _strokes.every((s) => s.length < 2);

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  void _start(Offset p) {
    _strokes.add([p]);
    notifyListeners();
  }

  void _extend(Offset p) {
    if (_strokes.isEmpty) return;
    _strokes.last.add(p);
    notifyListeners();
  }

  /// Black ink on white, at twice the on-screen size.
  Future<Uint8List?> toPng() async {
    if (isEmpty || _size.isEmpty) return null;
    const scale = 2.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    canvas.drawRect(Offset.zero & _size, Paint()..color = Colors.white);
    _paint(canvas, _strokes, Colors.black);
    final image = await recorder.endRecording().toImage(
      (_size.width * scale).round(),
      (_size.height * scale).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }
}

void _paint(Canvas canvas, List<List<Offset>> strokes, Color color) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = 2.6
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  for (final s in strokes) {
    if (s.length < 2) continue;
    final path = Path()..moveTo(s.first.dx, s.first.dy);
    for (final p in s.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }
}

/// A box to sign in with a finger or mouse.
class SignaturePad extends StatelessWidget {
  const SignaturePad({super.key, required this.controller, this.height = 180});

  final SignatureController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md),
        child: LayoutBuilder(
          builder: (context, c) {
            controller._size = Size(c.maxWidth, height);
            return Stack(
              children: [
                Positioned(
                  left: Space.md,
                  right: Space.md,
                  bottom: Space.lg,
                  child: Container(height: 1, color: Colors.black26),
                ),
                const Positioned(
                  left: Space.md,
                  bottom: Space.lg + 4,
                  child: Text(
                    '✕',
                    style: TextStyle(color: Colors.black38, fontSize: 16),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => controller._start(d.localPosition),
                  onPanUpdate: (d) => controller._extend(d.localPosition),
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => CustomPaint(
                      size: Size(c.maxWidth, height),
                      painter: _StrokesPainter(controller._strokes),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    tooltip: 'Clear',
                    color: Colors.black54,
                    icon: const Icon(CupertinoIcons.clear_circled),
                    onPressed: controller.clear,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) => _paint(canvas, strokes, Colors.black);

  @override
  bool shouldRepaint(_StrokesPainter old) => true;
}
