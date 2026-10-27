import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/local_db.dart';
import '../data/site_data.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/form_sheet.dart';
import '../ui/surfaces.dart';
import 'issue_form_screen.dart' show ToolPickerSheet, issuable;
import 'issue_forms_repository.dart';
import 'tools_repository.dart';

/// The tools a job card needs: who has each one now, and a button to issue
/// the ones in store on a form for this job. Each tool's page lists the
/// job cards it was used on.
class JobToolsPanel extends ConsumerWidget {
  const JobToolsPanel({
    super.key,
    required this.jobCardId,
    required this.siteId,
    required this.closed,
    required this.canChange,
  });

  final String jobCardId;
  final String siteId;
  final bool closed;
  final bool canChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (!session.can('tools.view', siteId: siteId)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final all = ref.watch(siteToolsProvider).value ?? const <LocalTool>[];
    final ids = ref.watch(jobCardToolsProvider(jobCardId));
    final people = ref.watch(peopleProvider).value ?? const {};
    final me = ref.watch(authUserIdProvider);
    final linked = [
      for (final t in all)
        if (ids.value?.contains(t.id) ?? false) t,
    ];
    final canIssue = session.can('tools.issue', siteId: siteId);
    final canEdit = !closed && (canChange || canIssue) && ids.hasValue;
    final ready = [
      for (final t in linked)
        if (issuable(t) == null) t,
    ];

    return Panel(
      icon: CupertinoIcons.wrench,
      title: 'Tools',
      subtitle: linked.isEmpty ? null : '${linked.length} for this job',
      actions: [
        if (canEdit)
          TextButton.icon(
            onPressed: () async {
              final picked = await showFormSheet<List<LocalTool>>(
                context,
                ToolPickerSheet(
                  tools: all,
                  already: {for (final t in linked) t.id},
                  title: 'Tools for this job',
                  onlyIssuable: false,
                ),
              );
              for (final t in picked ?? const <LocalTool>[]) {
                await ref
                    .read(issueFormActionsProvider)
                    .linkToJobCard(jobCardId, t.id, linked: true);
              }
            },
            icon: const Icon(CupertinoIcons.add, size: 18),
            label: const Text('Add'),
          ),
      ],
      child: ids.isLoading && !ids.hasValue
          ? const LinearProgressIndicator()
          : ids.hasError && !ids.hasValue
          ? Text(
              'Tools load when you are online.',
              style: theme.textTheme.labelMedium,
            )
          : linked.isEmpty
          ? Text(
              'Pick the tools this work needs, e.g. the megger and the '
              'crimper. You then see who has each one, and each tool shows '
              'the jobs it was used on.',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final t in linked)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onTap: () => context.push('/tools/${t.id}'),
                    leading: Icon(
                      toolOut(t)
                          ? CupertinoIcons.person_fill
                          : CupertinoIcons.cube_box,
                      color: toolOut(t)
                          ? BrandColors.info
                          : BrandColors.success,
                    ),
                    title: Text('${t.code ?? 'New'} · ${t.name}'),
                    subtitle: Text(
                      toolOut(t)
                          ? 'With ${t.holderId != null && t.holderId == me ? 'you' : toolHolder(t, people) ?? 'someone'}'
                          : issuable(t) ?? 'In store',
                    ),
                    trailing: canEdit
                        ? IconButton(
                            tooltip: 'Remove from the job',
                            icon: const Icon(CupertinoIcons.minus_circle),
                            onPressed: () => ref
                                .read(issueFormActionsProvider)
                                .linkToJobCard(jobCardId, t.id, linked: false),
                          )
                        : null,
                  ),
                if (canIssue && !closed && ready.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: FilledButton.tonalIcon(
                      onPressed: () => context.push(
                        '/tools/forms/new?job=$jobCardId'
                        '&tools=${ready.map((t) => t.id).join(',')}',
                      ),
                      icon: const Icon(CupertinoIcons.doc_text),
                      label: Text('Issue ${ready.length} in store on a form'),
                    ),
                  ),
              ],
            ),
    );
  }
}
