import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../jobs/jobs_repository.dart';
import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../tools/tools_repository.dart';
import '../tools/tools_screen.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/page.dart';
import '../ui/surfaces.dart';

/// Store tab: the tools register now; stock and materials in phase 4.
class StoreScreen extends ConsumerWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = ref.watch(siteToolsProvider).value ?? const [];
    final people = ref.watch(peopleProvider).value ?? const {};
    final me = ref.watch(authUserIdProvider);
    final theme = Theme.of(context);
    final mine = tools.where((t) => t.holderId == me).toList();
    final out = tools.where((t) => t.holderId != null).length;
    final overdue = tools.where(toolOverdue).length;
    final calibrate = tools.where(calibrationDue).length;

    Widget stat(String label, int value, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: theme.textTheme.headlineMedium?.copyWith(color: color),
          ),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );

    return PageScroll(
      maxWidth: 720,
      onRefresh: ref.read(toolsSyncProvider.notifier).refresh,
      children: [
        PanelCard(
          icon: CupertinoIcons.wrench_fill,
          title: 'Tools',
          trailing: TextButton(
            onPressed: () => context.push('/tools'),
            child: const Text('Open register'),
          ),
          child: Row(
            children: [
              stat('In register', tools.length),
              stat('Out now', out),
              stat('Overdue', overdue, color: overdue > 0 ? Colors.red : null),
              stat(
                'Calibrate',
                calibrate,
                color: calibrate > 0 ? Colors.orange : null,
              ),
            ],
          ),
        ).entrance(context),
        const SectionHeader('My tools'),
        if (mine.isEmpty)
          Text(
            'You are not holding any tools.',
            style: theme.textTheme.bodySmall,
          )
        else
          for (final (i, t) in mine.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: ToolTile(
                tool: t,
                holderName: people[t.holderId],
                isMine: true,
              ),
            ).entrance(context, index: i + 1),
        const SectionHeader('Coming next'),
        SurfaceCard(
          child: Row(
            children: [
              Icon(CupertinoIcons.cube_box, color: theme.colorScheme.primary),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'Stock on hand, issues to jobs, receipts, counts, '
                  'material requests and BOQ arrive in phase 4.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
