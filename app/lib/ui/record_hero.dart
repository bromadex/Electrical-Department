import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'bits.dart';
import 'motion.dart';
import 'surfaces.dart';

/// One line of facts under a record's name, e.g. where it is.
typedef RecordFact = ({IconData icon, String text, Color? color});

/// The top of a register record (equipment, tool): its icon, code, pills,
/// name, a few facts and up to four numbers. Equipment and tools share it so
/// both pages read the same way.
class RecordHero extends StatelessWidget {
  const RecordHero({
    super.key,
    required this.icon,
    required this.title,
    this.code,
    this.pills = const [],
    this.facts = const [],
    this.stats = const [],
  });

  final IconData icon;
  final String title;
  final String? code;
  final List<Widget> pills;
  final List<RecordFact> facts;

  /// (value, label) pairs.
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: BrandColors.brandGradient,
                  borderRadius: BorderRadius.circular(Radii.lg),
                  boxShadow: [
                    BoxShadow(
                      color: BrandColors.maroon.withValues(alpha: 0.3),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Space.xs,
                      runSpacing: Space.xs,
                      children: [
                        ?(code == null ? null : RecordCode(code!)),
                        ...pills,
                      ],
                    ),
                    const SizedBox(height: Space.xs),
                    Text(title, style: theme.textTheme.headlineSmall),
                  ],
                ),
              ),
            ],
          ),
          if (facts.isNotEmpty) const SizedBox(height: Space.md),
          for (final f in facts)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    f.icon,
                    size: 16,
                    color: f.color ?? scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Text(
                      f.text,
                      style: TextStyle(
                        color: f.color ?? scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            const Divider(height: 1),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                for (final (value, label) in stats)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(label, style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A round button in a record's action row; null [onTap] greys it out.
typedef QuickAction = ({
  IconData icon,
  String label,
  VoidCallback? onTap,
  Color? color,
});

/// The big round actions under a record, like a phone's contact page.
class QuickActions extends StatelessWidget {
  const QuickActions({super.key, required this.actions});

  final List<QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final (i, a) in actions.indexed) ...[
          if (i > 0) const SizedBox(width: Space.sm),
          Expanded(
            child: Opacity(
              opacity: a.onTap == null ? 0.45 : 1,
              child: Pressable(
                onTap: a.onTap == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        a.onTap!();
                      },
                child: SurfaceCard(
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  radius: Radii.lg,
                  child: Column(
                    children: [
                      Icon(
                        a.icon,
                        color: a.color ?? theme.colorScheme.primary,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        a.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Label and value rows; empty values are left out.
class RecordDetails extends StatelessWidget {
  const RecordDetails({super.key, required this.rows});

  final List<(String, String?)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = [
      for (final r in rows)
        if (r.$2 != null && r.$2!.trim().isNotEmpty) r,
    ];
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Column(
        children: [
          for (final (i, (label, value)) in shown.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: Space.md),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(child: SelectableText(value!)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
