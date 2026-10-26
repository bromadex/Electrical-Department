import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/push_service.dart';
import '../theme/theme_mode.dart';
import '../theme/tokens.dart';
import '../ui/surfaces.dart';

/// Offers push alerts on this device until they are on or dismissed. The
/// browser asks for permission only after this tap, never on page load.
class PushPrompt extends ConsumerStatefulWidget {
  const PushPrompt({super.key});

  static const _dismissedKey = 'push_prompt_dismissed';

  @override
  ConsumerState<PushPrompt> createState() => _PushPromptState();
}

class _PushPromptState extends ConsumerState<PushPrompt> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pushProvider);
    final prefs = ref.watch(sharedPrefsProvider);
    if (state != PushState.off ||
        (prefs.getBool(PushPrompt._dismissedKey) ?? false)) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 560;
    Future<void> dismiss() async {
      await prefs.setBool(PushPrompt._dismissedKey, true);
      setState(() {});
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: SurfaceCard(
        padding: EdgeInsets.all(narrow ? Space.sm : Space.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(CupertinoIcons.bell_fill, color: scheme.primary),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Turn on alerts',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    narrow
                        ? 'Urgent jobs, even when closed'
                        : 'Get urgent jobs and assignments on this device, '
                              'even when the app is closed.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            if (!narrow)
              TextButton(
                onPressed: _busy ? null : dismiss,
                child: const Text('Not now'),
              ),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await ref.read(pushProvider.notifier).enable();
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: const Text('Turn on'),
            ),
            if (narrow)
              IconButton(
                tooltip: 'Not now',
                visualDensity: VisualDensity.compact,
                onPressed: _busy ? null : dismiss,
                icon: const Icon(CupertinoIcons.xmark, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}
