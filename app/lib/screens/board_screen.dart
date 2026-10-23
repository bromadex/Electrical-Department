import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';

/// Jobs board placeholder: the status columns the real board will use,
/// shown faded, with the phase it arrives in.
class BoardScreen extends StatelessWidget {
  const BoardScreen({super.key});

  static const _columns = [
    ('Open', Icons.radio_button_unchecked_rounded, BrandColors.info, 3),
    ('Taken', Icons.pan_tool_alt_outlined, BrandColors.coral, 2),
    ('In progress', Icons.bolt_rounded, BrandColors.warning, 2),
    ('Waiting', Icons.hourglass_bottom_rounded, Colors.blueGrey, 1),
    ('Done', Icons.check_circle_outline_rounded, BrandColors.success, 2),
  ];

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context);
    final phone = MediaQuery.sizeOf(context).width < 720;

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ShaderMask(
              shaderCallback: (r) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.85),
                  Colors.black.withValues(alpha: 0.15),
                ],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(
                  Space.md,
                  inset.top + Space.sm,
                  Space.md,
                  inset.bottom,
                ),
                itemCount: _columns.length,
                separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
                itemBuilder: (context, i) => SizedBox(
                  width: phone ? 260 : 280,
                  child: _GhostColumn(
                    title: _columns[i].$1,
                    icon: _columns[i].$2,
                    color: _columns[i].$3,
                    cards: _columns[i].$4,
                  ).entrance(context, index: i, dy: 24),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: inset + const EdgeInsets.all(Space.lg),
          child: Center(
            child: GlassSurface(
              padding: const EdgeInsets.all(Space.xl),
              child: EmptyState(
                icon: Icons.dashboard_rounded,
                title: 'Jobs board',
                message:
                    'Post a job with photos, take it, track it and close it '
                    'with before-and-after pictures. Live for the whole team.',
                badge: 'Phase 1 · weeks 2–3',
                action: Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xs,
                  alignment: WrapAlignment.center,
                  children: const [
                    Pill(
                      label: "I'll take it",
                      icon: Icons.pan_tool_alt_outlined,
                    ),
                    Pill(label: 'Urgent', icon: Icons.priority_high_rounded),
                    Pill(label: 'GPS', icon: Icons.my_location_rounded),
                    Pill(label: 'Realtime', icon: Icons.bolt_rounded),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GhostColumn extends StatelessWidget {
  const _GhostColumn({
    required this.title,
    required this.icon,
    required this.color,
    required this.cards,
  });

  final String title;
  final IconData icon;
  final Color color;
  final int cards;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: Space.xs),
              Text(title, style: theme.textTheme.titleSmall),
              const Spacer(),
              Pill(label: '$cards', color: color, dense: true),
            ],
          ),
          const SizedBox(height: Space.sm),
          for (var i = 0; i < cards; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: Container(
                padding: const EdgeInsets.all(Space.sm),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Skeleton(width: 46, height: 16, radius: 5),
                        const Spacer(),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.xs),
                    Skeleton(width: 150.0 + (i * 23) % 60),
                    const SizedBox(height: 6),
                    const Skeleton(width: 90, height: 10),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
