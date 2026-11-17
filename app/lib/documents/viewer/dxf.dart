import 'dart:math' as math;
import 'dart:ui';

/// Reads an ASCII DXF drawing (AutoCAD's text exchange format) into simple
/// shapes for the in-app drawing viewer: lines, polylines, circles, arcs,
/// ellipses, text and blocks placed with INSERT (moved, scaled, rotated).
/// Hatches, dimensions' styles and binary DXF are left out.

sealed class DxfShape {
  const DxfShape(this.color);

  /// AutoCAD colour index (1 red … 7 white/black); 256 = by layer.
  final int color;
}

class DxfLine extends DxfShape {
  const DxfLine(this.a, this.b, super.color);
  final Offset a;
  final Offset b;
}

class DxfPolyline extends DxfShape {
  const DxfPolyline(this.points, this.closed, super.color);
  final List<Offset> points;
  final bool closed;
}

class DxfCircle extends DxfShape {
  const DxfCircle(this.centre, this.radius, super.color);
  final Offset centre;
  final double radius;
}

/// An arc from [start] to [end] degrees, counter-clockwise (DXF's way).
class DxfArc extends DxfShape {
  const DxfArc(this.centre, this.radius, this.start, this.end, super.color);
  final Offset centre;
  final double radius;
  final double start;
  final double end;
}

class DxfText extends DxfShape {
  const DxfText(this.at, this.height, this.text, this.rotation, super.color);
  final Offset at;
  final double height;
  final String text;

  /// Degrees, counter-clockwise.
  final double rotation;
}

class DxfDrawing {
  const DxfDrawing(this.shapes, this.layerColors);

  final List<DxfShape> shapes;

  /// Layer name → colour index (for "by layer").
  final Map<String, int> layerColors;

  /// The drawing's extent, for fitting it on screen.
  Rect get bounds {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    void add(Offset p, [double r = 0]) {
      minX = math.min(minX, p.dx - r);
      minY = math.min(minY, p.dy - r);
      maxX = math.max(maxX, p.dx + r);
      maxY = math.max(maxY, p.dy + r);
    }

    for (final s in shapes) {
      switch (s) {
        case DxfLine(:final a, :final b):
          add(a);
          add(b);
        case DxfPolyline(:final points):
          points.forEach(add);
        case DxfCircle(:final centre, :final radius):
          add(centre, radius);
        case DxfArc(:final centre, :final radius):
          add(centre, radius);
        case DxfText(:final at, :final height, :final text):
          add(at);
          add(at + Offset(height * 0.6 * text.length, height));
      }
    }
    if (minX == double.infinity) return Rect.zero;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

/// One entity's group codes, in order (codes repeat, e.g. polyline points).
class _Entity {
  _Entity(this.type);
  final String type;
  final codes = <(int, String)>[];

  String? s(int code) {
    for (final (c, v) in codes) {
      if (c == code) return v;
    }
    return null;
  }

  double d(int code, [double or = 0]) =>
      double.tryParse(s(code)?.trim() ?? '') ?? or;

  int i(int code, [int or = 0]) => int.tryParse(s(code)?.trim() ?? '') ?? or;

  List<double> all(int code) => [
    for (final (c, v) in codes)
      if (c == code) double.tryParse(v.trim()) ?? 0,
  ];
}

/// Throws [FormatException] for a binary DXF or something else.
DxfDrawing readDxf(String text) {
  if (text.startsWith('AutoCAD Binary DXF')) {
    throw const FormatException('Binary DXF files cannot be shown yet');
  }
  final lines = text.split(RegExp(r'\r?\n'));
  if (lines.length < 4) throw const FormatException('That is not a DXF file');

  // Pairs of group code and value, grouped by section and entity.
  final sections = <String, List<_Entity>>{};
  String? section;
  _Entity? current;
  var expectSectionName = false;
  for (var k = 0; k + 1 < lines.length; k += 2) {
    final code = int.tryParse(lines[k].trim());
    final value = lines[k + 1];
    if (code == null) {
      throw const FormatException('That is not a DXF file');
    }
    if (code == 0) {
      final v = value.trim();
      if (v == 'SECTION') {
        expectSectionName = true;
        current = null;
        continue;
      }
      if (v == 'ENDSEC') {
        section = null;
        current = null;
        continue;
      }
      if (v == 'EOF') break;
      if (section != null) {
        current = _Entity(v);
        sections.putIfAbsent(section, () => []).add(current);
      }
      continue;
    }
    if (expectSectionName && code == 2) {
      section = value.trim();
      expectSectionName = false;
      continue;
    }
    current?.codes.add((code, value));
  }

  // Layer colours.
  final layers = <String, int>{};
  for (final e in sections['TABLES'] ?? const <_Entity>[]) {
    if (e.type == 'LAYER') {
      final name = e.s(2)?.trim();
      if (name != null) layers[name] = e.i(62, 7).abs();
    }
  }

  // Blocks: name → its entities (between BLOCK and ENDBLK), and base point.
  final blocks = <String, (Offset, List<_Entity>)>{};
  {
    String? name;
    Offset base = Offset.zero;
    var list = <_Entity>[];
    for (final e in sections['BLOCKS'] ?? const <_Entity>[]) {
      if (e.type == 'BLOCK') {
        name = e.s(2)?.trim();
        base = Offset(e.d(10), e.d(20));
        list = [];
      } else if (e.type == 'ENDBLK') {
        if (name != null) blocks[name] = (base, list);
        name = null;
      } else if (name != null) {
        list.add(e);
      }
    }
  }

  final shapes = <DxfShape>[];
  int colorOf(_Entity e, int inherited) {
    final c = e.i(62, 256);
    if (c == 0) return inherited; // by block
    if (c == 256) return layers[e.s(8)?.trim()] ?? 7;
    return c.abs();
  }

  void add(
    List<_Entity> entities,
    Offset Function(Offset) at,
    double scale,
    double turn,
    int inherited,
    int depth,
  ) {
    // POLYLINE followed by VERTEX… SEQEND.
    List<Offset>? poly;
    var polyClosed = false;
    var polyColor = 7;
    for (final e in entities) {
      final color = colorOf(e, inherited);
      switch (e.type) {
        case 'LINE':
          shapes.add(
            DxfLine(
              at(Offset(e.d(10), e.d(20))),
              at(Offset(e.d(11), e.d(21))),
              color,
            ),
          );
        case 'LWPOLYLINE':
          final xs = e.all(10);
          final ys = e.all(20);
          shapes.add(
            DxfPolyline(
              [
                for (var k = 0; k < math.min(xs.length, ys.length); k++)
                  at(Offset(xs[k], ys[k])),
              ],
              e.i(70) & 1 == 1,
              color,
            ),
          );
        case 'POLYLINE':
          poly = [];
          polyClosed = e.i(70) & 1 == 1;
          polyColor = color;
        case 'VERTEX':
          poly?.add(at(Offset(e.d(10), e.d(20))));
        case 'SEQEND':
          if (poly != null && poly.length > 1) {
            shapes.add(DxfPolyline(poly, polyClosed, polyColor));
          }
          poly = null;
        case 'CIRCLE':
          shapes.add(
            DxfCircle(at(Offset(e.d(10), e.d(20))), e.d(40) * scale, color),
          );
        case 'ARC':
          shapes.add(
            DxfArc(
              at(Offset(e.d(10), e.d(20))),
              e.d(40) * scale,
              e.d(50) + turn,
              e.d(51) + turn,
              color,
            ),
          );
        case 'ELLIPSE':
          // Drawn as a polyline round its major and minor axes.
          final c = Offset(e.d(10), e.d(20));
          final major = Offset(e.d(11), e.d(21));
          final ratio = e.d(40, 1);
          final from = e.d(41);
          var to = e.d(42, 2 * math.pi);
          if (to <= from) to += 2 * math.pi;
          final minor = Offset(-major.dy, major.dx) * ratio;
          shapes.add(
            DxfPolyline(
              [
                for (var k = 0; k <= 48; k++)
                  at(
                    c +
                        major * math.cos(from + (to - from) * k / 48) +
                        minor * math.sin(from + (to - from) * k / 48),
                  ),
              ],
              false,
              color,
            ),
          );
        case 'TEXT' || 'MTEXT' || 'ATTRIB':
          final raw = e.s(1) ?? '';
          final text = raw
              .replaceAll(RegExp(r'\\P'), ' ')
              .replaceAll(RegExp(r'\\[A-Za-z][^;]*;'), '')
              .replaceAll(RegExp(r'[{}]'), '')
              .trim();
          if (text.isEmpty) continue;
          shapes.add(
            DxfText(
              at(Offset(e.d(10), e.d(20))),
              e.d(40, 2.5) * scale,
              text,
              e.d(50) + turn,
              color,
            ),
          );
        case 'INSERT':
          if (depth >= 4) continue;
          final block = blocks[e.s(2)?.trim()];
          if (block == null) continue;
          final (base, list) = block;
          final ins = Offset(e.d(10), e.d(20));
          final sx = e.d(41, 1);
          final sy = e.d(42, sx);
          final rot = e.d(50) * math.pi / 180;
          Offset place(Offset p) {
            final q = p - base;
            final scaled = Offset(q.dx * sx, q.dy * sy);
            final turned = Offset(
              scaled.dx * math.cos(rot) - scaled.dy * math.sin(rot),
              scaled.dx * math.sin(rot) + scaled.dy * math.cos(rot),
            );
            return at(ins + turned);
          }

          add(list, place, scale * sx.abs(), turn + e.d(50), color, depth + 1);
      }
    }
  }

  add(sections['ENTITIES'] ?? const <_Entity>[], (p) => p, 1, 0, 7, 0);
  return DxfDrawing(shapes, layers);
}

/// AutoCAD colour index → colour; 7 is white on the dark sheet.
Color aciColor(int i) => switch (i) {
  1 => const Color(0xFFFF4040),
  2 => const Color(0xFFFFFF40),
  3 => const Color(0xFF40FF40),
  4 => const Color(0xFF40FFFF),
  5 => const Color(0xFF4080FF),
  6 => const Color(0xFFFF40FF),
  8 => const Color(0xFF808080),
  9 => const Color(0xFFC0C0C0),
  _ => const Color(0xFFF2F2F2),
};
