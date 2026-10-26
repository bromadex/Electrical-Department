import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.dart';
import '../ui/surfaces.dart';
import 'documents_repository.dart';
import 'documents_screen.dart';

/// SOPs and drawings attached to a job card. Hidden when the site has none.
class JobDocumentsPanel extends ConsumerWidget {
  const JobDocumentsPanel({
    super.key,
    required this.jobCardId,
    required this.closed,
    required this.canAttach,
  });

  final String jobCardId;
  final bool closed;
  final bool canAttach;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(documentsProvider).value ?? const [];
    final linkedIds =
        ref.watch(jobDocumentsProvider(jobCardId)).value ?? const [];
    final linked = [
      for (final d in all)
        if (linkedIds.contains(d.id)) d,
    ];
    if (all.isEmpty && linked.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Panel(
      icon: CupertinoIcons.book,
      title: 'Documents',
      actions: [
        if (canAttach && !closed)
          TextButton.icon(
            onPressed: () => _attach(context, ref, all, linkedIds),
            icon: const Icon(CupertinoIcons.paperclip, size: 18),
            label: const Text('Attach'),
          ),
      ],
      child: linked.isEmpty
          ? Text(
              'Attach the SOP or drawing for this work, e.g. the LOTO '
              'procedure.',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (final d in linked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.xs),
                    child: DocTile(
                      doc: d,
                      trailing: canAttach && !closed
                          ? IconButton(
                              tooltip: 'Detach',
                              icon: const Icon(CupertinoIcons.minus_circle),
                              onPressed: () => ref
                                  .read(documentActionsProvider)
                                  .link(jobCardId, d.id, linked: false),
                            )
                          : null,
                    ),
                  ),
              ],
            ),
    );
  }

  void _attach(
    BuildContext context,
    WidgetRef ref,
    List<Doc> all,
    List<String> linkedIds,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
          children: [
            Text(
              'Attach a document',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: Space.md),
            for (final d in all.where((d) => !linkedIds.contains(d.id)))
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: DocTile(
                  doc: d,
                  trailing: const Icon(CupertinoIcons.add_circled),
                  onTap: () {
                    ref.read(documentActionsProvider).link(jobCardId, d.id);
                    Navigator.pop(context);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
