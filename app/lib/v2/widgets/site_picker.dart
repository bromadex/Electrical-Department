import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/session_controller.dart';
import '../site_filter.dart';
import '../theme/tokens.dart';

/// Current site, with a menu to switch site or show all the user's sites.
class SitePicker extends ConsumerWidget {
  const SitePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sites = ref.watch(sessionProvider.select((s) => s.mySites));
    final current = ref.watch(currentSiteProvider);
    final all = ref.watch(allSitesProvider);
    if (current == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final label = all && sites.length > 1 ? 'All sites' : current.name;

    final chip = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.place_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (sites.length > 1) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
    if (sites.length < 2) return chip;

    return PopupMenuButton<String>(
      tooltip: 'Switch site',
      position: PopupMenuPosition.under,
      onSelected: (id) {
        if (id == '*') {
          ref.read(allSitesProvider.notifier).set(true);
        } else {
          ref.read(allSitesProvider.notifier).set(false);
          ref.read(pickedSiteIdProvider.notifier).pick(id);
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: '*',
          checked: all,
          child: const Text('All my sites'),
        ),
        const PopupMenuDivider(),
        for (final s in sites)
          CheckedPopupMenuItem(
            value: s.id,
            checked: !all && s.id == current.id,
            child: Text('${s.name} (${s.code})'),
          ),
      ],
      child: chip,
    );
  }
}
