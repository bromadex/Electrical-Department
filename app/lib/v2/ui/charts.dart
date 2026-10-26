import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/charts.dart' as kit;
import '../theme/tokens.dart';
import 'format.dart';

class ChartSegment {
  const ChartSegment(this.label, this.value, this.color);

  final String label;
  final num value;
  final Color color;
}

double _niceMax(num v) => v <= 4 ? 4 : ((v / 4).ceil() * 4).toDouble();

TextStyle _small(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall!
        .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.lg),
    child: Center(
      child: Text('No data for this period', style: _small(context)),
    ),
  );
}

/// Colour square, label and value, used under every chart.
class ChartLegendItem extends StatelessWidget {
  const ChartLegendItem({
    super.key,
    required this.color,
    required this.label,
    this.value,
  });

  final Color color;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
        if (value != null) ...[
          const SizedBox(width: 6),
          Text(
            value!,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

/// Donut with the total in the middle and a legend with counts and shares.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.segments,
    this.centerLabel = 'Total',
    this.size = 150,
  });

  final List<ChartSegment> segments;
  final String centerLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = segments.fold<num>(0, (s, e) => s + e.value);
    if (total == 0) return const _NoData();
    final shown = [
      for (final s in segments)
        if (s.value > 0) s,
    ];

    final chart = SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          kit.DonutChart(
            values: [for (final s in shown) s.value],
            colors: [for (final s in shown) s.color],
            size: size,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$total', style: theme.textTheme.titleLarge),
              Text(centerLabel, style: _small(context)),
            ],
          ),
        ],
      ),
    );
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in segments)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: ChartLegendItem(
              color: s.color,
              label: s.label,
              value: '${s.value} (${(s.value * 100 / total).round()}%)',
            ),
          ),
      ],
    );
    return Wrap(
      spacing: Space.lg,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [chart, legend],
    );
  }
}

class TrendPoint {
  const TrendPoint(this.period, this.received, this.closed);

  final DateTime period;
  final int received;
  final int closed;
}

/// Job cards received versus closed per day, week or month.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.points, this.height = 220});

  final List<TrendPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty ||
        points.every((p) => p.received == 0 && p.closed == 0)) {
      return const _NoData();
    }
    final scheme = Theme.of(context).colorScheme;
    final maxY = _niceMax(
      points.fold<int>(
        0,
        (m, p) => math.max(m, math.max(p.received, p.closed)),
      ),
    );

    final labelEvery = math.max(1, (points.length / 6).ceil());
    final small = _small(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Space.md,
          children: const [
            ChartLegendItem(color: AppColors.info, label: 'Received'),
            ChartLegendItem(color: AppColors.success, label: 'Closed'),
          ],
        ),
        const SizedBox(height: Space.sm),
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Y axis: 0 at the bottom, four steps up to the rounded top.
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 4; i >= 0; i--)
                      Text('${(maxY * i / 4).round()}', style: small),
                  ],
                ),
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Semantics(
                        label:
                            'Received ${points.fold<int>(0, (a, p) => a + p.received)}, '
                            'closed ${points.fold<int>(0, (a, p) => a + p.closed)}',
                        child: CustomPaint(
                          painter: _TrendPainter(
                            received: [for (final p in points) p.received],
                            closed: [for (final p in points) p.closed],
                            maxY: maxY,
                            grid: scheme.outlineVariant,
                            dots: points.length <= 31,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 20,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final (i, p) in points.indexed)
                            if (i % labelEvery == 0 || i == points.length - 1)
                              Text(fmtDayMonth(p.period), style: small),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.received,
    required this.closed,
    required this.maxY,
    required this.grid,
    required this.dots,
  });

  final List<int> received;
  final List<int> closed;
  final double maxY;
  final Color grid;
  final bool dots;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    Offset at(int i, int v, int n) => Offset(
      n == 1 ? size.width / 2 : size.width * i / (n - 1),
      size.height - size.height * v / maxY,
    );
    void series(List<int> values, Color color) {
      if (values.isEmpty) return;
      final n = values.length;
      final path = Path()
        ..moveTo(at(0, values[0], n).dx, at(0, values[0], n).dy);
      for (var i = 1; i < n; i++) {
        final p = at(i, values[i], n);
        path.lineTo(p.dx, p.dy);
      }
      final area = Path.from(path)
        ..lineTo(at(n - 1, 0, n).dx, size.height)
        ..lineTo(at(0, 0, n).dx, size.height)
        ..close();
      canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.08));
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round,
      );
      if (dots) {
        for (var i = 0; i < n; i++) {
          canvas.drawCircle(at(i, values[i], n), 3, Paint()..color = color);
        }
      }
    }

    series(received, AppColors.info);
    series(closed, AppColors.success);
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.received != received || old.closed != closed || old.maxY != maxY;
}

class BarItem {
  const BarItem(this.label, this.value, {this.color, this.onTap});

  final String label;
  final num value;
  final Color? color;
  final VoidCallback? onTap;
}

/// Horizontal bars with the label and count beside each bar; long names
/// (equipment, work areas) stay readable at any width.
class BarList extends StatelessWidget {
  const BarList({
    super.key,
    required this.items,
    this.color = AppColors.burgundy,
    this.format,
  });

  final List<BarItem> items;
  final Color color;
  final String Function(num value)? format;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty || items.every((i) => i.value == 0)) {
      return const _NoData();
    }
    final maxV = items.fold<num>(0, (m, i) => math.max(m, i.value));
    return Column(
      children: [
        for (final item in items)
          _BarRow(
            label: item.label,
            valueText: format?.call(item.value) ?? '${item.value}',
            segments: [(item.value / maxV, item.color ?? color)],
            onTap: item.onTap,
          ),
      ],
    );
  }
}

class StackedItem {
  const StackedItem(this.label, this.values);

  final String label;

  /// One value per series, in the order of [StackedBarList.series].
  final List<num> values;
}

/// Horizontal bars split by series (e.g. open / closed per priority).
class StackedBarList extends StatelessWidget {
  const StackedBarList({super.key, required this.series, required this.items});

  final List<(String, Color)> series;
  final List<StackedItem> items;

  @override
  Widget build(BuildContext context) {
    num total(StackedItem i) => i.values.fold<num>(0, (s, v) => s + v);
    if (items.isEmpty || items.every((i) => total(i) == 0)) {
      return const _NoData();
    }
    final maxV = items.fold<num>(0, (m, i) => math.max(m, total(i)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Space.md,
          children: [
            for (final (label, color) in series)
              ChartLegendItem(color: color, label: label),
          ],
        ),
        const SizedBox(height: Space.xs),
        for (final item in items)
          _BarRow(
            label: item.label,
            valueText: item.values.join(' / '),
            segments: [
              for (final (i, v) in item.values.indexed)
                if (i < series.length) (v / maxV, series[i].$2),
            ],
          ),
      ],
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.valueText,
    required this.segments,
    this.onTap,
  });

  final String label;
  final String valueText;
  final List<(num, Color)> segments;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: LayoutBuilder(
          builder: (context, c) {
            final labelWidth = math.min(170.0, c.maxWidth * 0.38);
            return Row(
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, bc) => Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          for (final (share, color) in segments)
                            Container(
                              width: bc.maxWidth * share.toDouble().clamp(0, 1),
                              color: color,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.xs),
                SizedBox(
                  width: 56,
                  child: Text(
                    valueText,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
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
