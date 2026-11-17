import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'dxf.dart';
import 'file_viewer.dart';

/// DXF drawings, drawn on a dark sheet as in AutoCAD: pinch or scroll to
/// zoom, drag to pan, double-tap to fit.
class DxfViewer extends FileViewer {
  const DxfViewer();

  @override
  String get name => 'Drawing';

  @override
  Set<String> get extensions => const {'dxf'};

  @override
  Widget build(BuildContext context, Uint8List bytes, String fileName) {
    final DxfDrawing drawing;
    try {
      drawing = readDxf(const Utf8Decoder(allowMalformed: true).convert(bytes));
    } on FormatException catch (e) {
      return Center(child: Text(e.message));
    }
    if (drawing.shapes.isEmpty) {
      return const Center(child: Text('Nothing to draw in this file'));
    }
    return _DrawingView(drawing: drawing);
  }
}

class _DrawingView extends StatefulWidget {
  const _DrawingView({required this.drawing});

  final DxfDrawing drawing;

  @override
  State<_DrawingView> createState() => _DrawingViewState();
}

class _DrawingViewState extends State<_DrawingView> {
  final _zoom = TransformationController();
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(() {
      final s = _zoom.value.getMaxScaleOnAxis();
      if ((s - _scale).abs() > 0.05) setState(() => _scale = s);
    });
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF1E2228),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: () => _zoom.value = Matrix4.identity(),
              child: InteractiveViewer(
                transformationController: _zoom,
                minScale: 0.5,
                maxScale: 200,
                child: SizedBox.expand(
                  child: CustomPaint(
                    painter: _DxfPainter(widget.drawing, _scale),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: Space.sm,
            bottom: Space.sm,
            child: Text(
              'Pinch to zoom · drag to move · double-tap to fit',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}

class _DxfPainter extends CustomPainter {
  _DxfPainter(this.drawing, this.zoom) : bounds = drawing.bounds;

  final DxfDrawing drawing;
  final Rect bounds;

  /// The viewer's zoom, so lines stay thin when zoomed in.
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    if (bounds.isEmpty && bounds.width == 0 && bounds.height == 0) return;
    const pad = 24.0;
    final w = math.max(bounds.width, 1e-6);
    final h = math.max(bounds.height, 1e-6);
    final k = math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
    final ox = (size.width - w * k) / 2;
    final oy = (size.height - h * k) / 2;
    // Drawing units → screen; DXF's y goes up, the screen's goes down.
    Offset map(Offset p) =>
        Offset(ox + (p.dx - bounds.left) * k, oy + (bounds.bottom - p.dy) * k);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / zoom
      ..isAntiAlias = true;
    for (final s in drawing.shapes) {
      paint.color = aciColor(s.color);
      switch (s) {
        case DxfLine(:final a, :final b):
          canvas.drawLine(map(a), map(b), paint);
        case DxfPolyline(:final points, :final closed):
          if (points.length < 2) continue;
          final path = Path()
            ..moveTo(map(points.first).dx, map(points.first).dy);
          for (final p in points.skip(1)) {
            final q = map(p);
            path.lineTo(q.dx, q.dy);
          }
          if (closed) path.close();
          canvas.drawPath(path, paint);
        case DxfCircle(:final centre, :final radius):
          canvas.drawCircle(map(centre), radius * k, paint);
        case DxfArc(:final centre, :final radius, :final start, :final end):
          var sweep = end - start;
          if (sweep <= 0) sweep += 360;
          // Screen angles go clockwise; DXF's go counter-clockwise.
          canvas.drawArc(
            Rect.fromCircle(center: map(centre), radius: radius * k),
            -start * math.pi / 180,
            -sweep * math.pi / 180,
            false,
            paint,
          );
        case DxfText(:final at, :final height, :final text, :final rotation):
          final px = height * k;
          if (px * zoom < 3) continue; // too small to read at this zoom
          final tp = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(color: paint.color, fontSize: px, height: 1),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final p = map(at);
          canvas
            ..save()
            ..translate(p.dx, p.dy)
            ..rotate(-rotation * math.pi / 180);
          tp.paint(canvas, Offset(0, -tp.height));
          canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_DxfPainter old) =>
      old.drawing != drawing || old.zoom != zoom;
}
