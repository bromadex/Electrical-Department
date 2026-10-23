import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/motion.dart';

/// Chip showing the current site; opens a sheet to switch site.
class SitePicker extends ConsumerWidget {
  const SitePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sites = ref.watch(sessionProvider.select((s) => s.mySites));
    final current = ref.watch(currentSiteProvider);
    if (current == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final canSwitch = sites.length > 1;
    final narrow = MediaQuery.sizeOf(context).width < 380;

    return Pressable(
      onTap: canSwitch ? () => _open(context, ref) : null,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.medium),
        padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.place_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: 4),
            AnimatedSwitcher(
              duration: Motion.of(context, Motion.medium),
              child: Text(
                narrow ? current.code : current.name,
                key: ValueKey(current.id),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            if (canSwitch)
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final theme = Theme.of(context);
          final session = ref.watch(sessionProvider);
          final current = ref.watch(currentSiteProvider);
          return Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: Space.sm),
                  child: Text('Switch site', style: theme.textTheme.titleLarge),
                ),
                for (final (i, s) in session.mySites.indexed)
                  _SiteRow(
                    code: s.code,
                    name: s.name,
                    areas: session.areasAt(s.id).length,
                    selected: s.id == current?.id,
                    onTap: () {
                      ref.read(pickedSiteIdProvider.notifier).pick(s.id);
                      Navigator.pop(context);
                    },
                  ).entrance(context, index: i),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SiteRow extends StatelessWidget {
  const _SiteRow({
    required this.code,
    required this.name,
    required this.areas,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final String name;
  final int areas;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.1)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.md),
        child: ListTile(
          onTap: onTap,
          leading: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? scheme.primary : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Text(
              code,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
          ),
          title: Text(name, style: theme.textTheme.titleMedium),
          subtitle: Text(areas == 1 ? '1 area' : '$areas areas'),
          trailing: AnimatedScale(
            scale: selected ? 1 : 0,
            duration: Motion.of(context, Motion.medium),
            curve: Motion.spring,
            child: Icon(Icons.check_circle_rounded, color: scheme.primary),
          ),
        ),
      ),
    );
  }
}
