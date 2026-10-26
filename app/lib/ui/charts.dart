import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'surfaces.dart';

/// Vertical bar chart with gridlines; bars grow in, the highlighted bar is
/// filled with the accent colour and shows its value in a bubble.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.values,
    required this.labels,
    this.highlight,
    this.height = 220,
  });

  final List<int> values;
  final List<String> labels;
  final int? highlight;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = Glass.of(context);
    final maxV = values.fold<int>(0, math.max);
    final top = _niceTop(maxV);
    return TweenAnimationBuilder<double>(
      key: ValueKey(Object.hashAll(values)),
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, const Duration(milliseconds: 900)),
      curve: Motion.decelerate,
      builder: (context, t, _) => SizedBox(
        width: double.infinity,
        height: height,
        child: CustomPaint(
          painter: _BarPainter(
            values: values,
            labels: labels,
            top: top,
            t: t,
            highlight: highlight,
            bar: g.dark
                ? Colors.white.withValues(alpha: 0.78)
                : BrandColors.maroon.withValues(alpha: 0.22),
            accent: g.dark ? BrandColors.coral : BrandColors.maroon,
            grid: g.hairline,
            text:
                theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ) ??
                const TextStyle(),
            bubble: g.dark ? const Color(0xFF3A1218) : Colors.white,
            bubbleText: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  static int _niceTop(int v) {
    if (v <= 4) return 4;
    final step = math.pow(10, (math.log(v) / math.ln10).floor()).toInt();
    return ((v / step).ceil() * step).clamp(4, 1 << 30);
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.values,
    required this.labels,
    required this.top,
    required this.t,
    required this.highlight,
    required this.bar,
    required this.accent,
    required this.grid,
    required this.text,
    required this.bubble,
    required this.bubbleText,
  });

  final List<int> values;
  final List<String> labels;
  final int top;
  final double t;
  final int? highlight;
  final Color bar, accent, grid, bubble, bubbleText;
  final TextStyle text;

  TextPainter _tp(String s, TextStyle style) => TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0, bottom = 24.0, topPad = 28.0;
    final h = size.height - bottom - topPad;
    final w = size.width - left;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y = topPad + h - h * i / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), gridPaint);
      final tp = _tp('${(top * i / 4).round()}', text);
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    if (values.isEmpty) return;
    final slot = w / values.length;
    final bw = math.min(14.0, slot * 0.5);
    for (var i = 0; i < values.length; i++) {
      final x = left + slot * i + (slot - bw) / 2;
      final bh = math.max(values[i] == 0 ? 0.0 : 4.0, h * values[i] / top * t);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, topPad + h - bh, bw, bh),
        Radius.circular(bw / 2),
      );
      final hi = i == highlight;
      canvas.drawRRect(rect, Paint()..color = hi ? accent : bar);

      final n = values.length;
      final showLabel = n <= 10 || i == n - 1 || (i % 3 == 0 && i < n - 2);
      if (showLabel && i < labels.length) {
        final tp = _tp(labels[i], text);
        tp.paint(
          canvas,
          Offset(x + bw / 2 - tp.width / 2, size.height - tp.height),
        );
      }
      if (hi && t > 0.9) {
        final tp = _tp(
          '${values[i]}',
          text.copyWith(color: bubbleText, fontWeight: FontWeight.w700),
        );
        final bubbleRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + bw / 2, topPad + h - bh - 18),
            width: tp.width + 16,
            height: tp.height + 8,
          ),
          const Radius.circular(8),
        );
        canvas.drawRRect(bubbleRect, Paint()..color = bubble);
        tp.paint(
          canvas,
          bubbleRect.center - Offset(tp.width / 2, tp.height / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.t != t || old.values != values || old.highlight != highlight;
}

/// Ring chart with rounded gaps between segments; sweeps in.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.values,
    required this.colors,
    this.size = 120,
    this.center,
  });

  final List<num> values;
  final List<Color> colors;
  final double size;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return TweenAnimationBuilder<double>(
      key: ValueKey(Object.hashAll(values)),
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, const Duration(milliseconds: 1100)),
      curve: Motion.emphasized,
      builder: (context, t, _) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _DonutPainter(values, colors, t, g.fillInset),
          child: Center(child: center),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values, this.colors, this.t, this.track);

  final List<num> values;
  final List<Color> colors;
  final double t;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.16;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    final total = values.fold<num>(0, (a, b) => a + b);
    if (total <= 0) return;
    const gap = 0.16;
    var start = -math.pi / 2;
    final sweepAll = math.pi * 2 * t;
    for (var i = 0; i < values.length; i++) {
      final sweep = sweepAll * values[i] / total;
      if (sweep > gap) {
        canvas.drawArc(
          rect,
          start + gap / 2,
          sweep - gap,
          false,
          Paint()
            ..color = colors[i % colors.length]
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = stroke,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.t != t || old.values != values;
}

/// Legend row: dot, label, value on the right, with a hairline under it.
class LegendRow extends StatelessWidget {
  const LegendRow({
    super.key,
    required this.color,
    required this.label,
    required this.value,
    this.last = false,
  });

  final Color color;
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: Glass.of(context).hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// iOS-style sliding segmented control on glass.
class GlassSegmented<T extends Object> extends StatelessWidget {
  const GlassSegmented({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> segments;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final theme = Theme.of(context);
    return CupertinoSlidingSegmentedControl<T>(
      groupValue: value,
      backgroundColor: g.fillInset,
      thumbColor: g.dark ? Colors.white.withValues(alpha: 0.14) : Colors.white,
      padding: const EdgeInsets.all(4),
      onValueChanged: (v) {
        if (v == null) return;
        HapticFeedback.selectionClick();
        onChanged(v);
      },
      children: {
        for (final e in segments.entries)
          e.key: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              e.value,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
      },
    );
  }
}

/// Small rounded chip with a trend arrow, e.g. "12% ↑".
class TrendChip extends StatelessWidget {
  const TrendChip(this.label, {super.key, this.up = true});

  final String label;
  final bool up;

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final color = up ? BrandColors.success : BrandColors.coral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: g.fillInset,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 2),
          Icon(
            up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 13,
            color: color,
          ),
        ],
      ),
    );
  }
}
