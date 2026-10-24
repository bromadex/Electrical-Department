import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/push_service.dart';
import '../theme/theme_mode.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';

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
    return Material(
      color: AppColors.info.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 4),
        child: Row(
          children: [
            const Icon(
              Icons.notifications_active_outlined,
              size: 20,
              color: AppColors.info,
            ),
            const SizedBox(width: Space.xs),
            const Expanded(
              child: Text(
                'Get alerts on this device for P1 jobs, assignments and reviews, '
                'even when the app is closed.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.info, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await prefs.setBool(PushPrompt._dismissedKey, true);
                      setState(() {});
                    },
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await ref.read(pushProvider.notifier).enable();
                      } catch (e) {
                        if (context.mounted) showError(context, e);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: const Text('Turn on'),
            ),
          ],
        ),
      ),
    );
  }
}
