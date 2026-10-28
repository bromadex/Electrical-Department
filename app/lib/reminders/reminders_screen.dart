import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../services/push_service.dart' show notificationPath;
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'remind_me_sheet.dart';
import 'reminders_repository.dart';

/// Your reminders: what is coming up (cancel with the ×) and what went off.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = MaterialLocalizations.of(context);
    final list = ref.watch(myRemindersProvider);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    Widget tile(Reminder r) {
      final when =
          '${l.formatMediumDate(r.remindAt)}, '
          '${l.formatTimeOfDay(TimeOfDay.fromDateTime(r.remindAt))}';
      final path = notificationPath(r.link);
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: SurfaceCard(
          padding: const EdgeInsets.all(Space.sm),
          onTap: path == null ? null : () => context.push(path),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (r.done ? Colors.grey : BrandColors.coral).withValues(
                    alpha: 0.18,
                  ),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Icon(
                  r.done ? CupertinoIcons.checkmark_alt : CupertinoIcons.alarm,
                  color: r.done
                      ? theme.colorScheme.onSurfaceVariant
                      : BrandColors.coral,
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.note, style: theme.textTheme.titleSmall),
                    Text(
                      [
                        when,
                        if (r.pending) 'waiting to send',
                        if (path != null) 'opens the record',
                      ].join(' · '),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              if (!r.done)
                IconButton(
                  tooltip: 'Cancel reminder',
                  icon: const Icon(CupertinoIcons.xmark),
                  onPressed: () => ref.read(reminderActionsProvider).cancel(r),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/menu'),
        title: const Text('Reminders'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showRemindMe(context),
        icon: const Icon(CupertinoIcons.add),
        label: const Text('New reminder'),
      ),
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () async => ref.invalidate(myRemindersProvider),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Space.md,
              top + Space.md,
              Space.md,
              120,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: list.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => EmptyState(
                      icon: CupertinoIcons.wifi_slash,
                      title: 'Reminders load when you are online',
                      message: AppError.from(e).isRetryable
                          ? 'New reminders you set now still go off.'
                          : AppError.from(e).message,
                    ),
                    data: (all) {
                      final upcoming = all.where((r) => !r.done).toList();
                      final past = all.where((r) => r.done).take(20).toList();
                      if (all.isEmpty) {
                        return const EmptyState(
                          icon: CupertinoIcons.alarm,
                          title: 'No reminders',
                          message:
                              'Set one here, or with "Remind me" on a job '
                              'card or a tool. It comes as a notification.',
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (upcoming.isNotEmpty) ...[
                            SectionHeader('Coming up · ${upcoming.length}'),
                            for (final r in upcoming) tile(r),
                          ],
                          if (past.isNotEmpty) ...[
                            const SectionHeader('Went off'),
                            for (final r in past) tile(r),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
