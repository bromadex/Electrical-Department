import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/session_controller.dart';

/// Switches the site the screens work in. Hidden when the user has access
/// to one site or none.
class SitePicker extends ConsumerWidget {
  const SitePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sites = ref.watch(sessionProvider.select((s) => s.mySites));
    final current = ref.watch(currentSiteProvider);
    if (current == null) return const SizedBox.shrink();
    if (sites.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Center(child: Text(current.name)),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Change site',
      initialValue: current.id,
      onSelected: ref.read(pickedSiteIdProvider.notifier).pick,
      itemBuilder: (_) => [
        for (final s in sites)
          PopupMenuItem(
            value: s.id,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 14,
                child: Text(s.code, style: const TextStyle(fontSize: 10)),
              ),
              title: Text(s.name),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on_outlined, size: 20),
            const SizedBox(width: 4),
            Text(current.name),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
