import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/session_controller.dart';

/// Placeholder for a tab whose feature is not built yet.
class ComingSoon extends ConsumerWidget {
  const ComingSoon({
    super.key,
    required this.icon,
    required this.title,
    required this.phase,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String phase;
  final String description;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final site = ref.watch(currentSiteProvider);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.titleLarge),
              if (site != null)
                Text(site.name, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              Text(description, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Chip(label: Text(phase)),
            ],
          ),
        ),
      ),
    );
  }
}
