import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../ui/time.dart';
import '../data/site_data.dart';
import '../ui/form_sheet.dart';
import '../v2/jobcards/job_card_tile.dart';
import '../v2/jobcards/repository.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import 'assets_screen.dart';
import '../widgets/app_back_button.dart';

/// One asset: its details, planned maintenance and every job on it.
class AssetDetailScreen extends ConsumerWidget {
  const AssetDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = ref.watch(assetProvider(id)).value;
    final jobs = ref.watch(assetJobCardsProvider(id)).value ?? const [];
    final plans = (ref.watch(recurrencesProvider).value ?? const [])
        .where((r) => r['asset_id'] == id)
        .toList();
    final session = ref.watch(sessionProvider);
    final areaNames = {for (final a in session.areas) a.id: a.name};
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final canEdit =
        asset != null && session.can('jobs.assign', siteId: asset.siteId);
    final open = jobs
        .where((j) => !{'closed', 'cancelled'}.contains(j.status.db))
        .length;
    final done = [
      for (final j in jobs)
        if (j.status.db == 'closed' && j.closedAt != null) j,
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(asset?.tag ?? 'Equipment'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Edit asset',
              icon: const Icon(CupertinoIcons.pencil),
              onPressed: () async {
                final kept = await showFormSheet<bool>(
                  context,
                  AssetForm(asset: asset),
                );
                if (kept == false && context.mounted) context.pop();
              },
            ),
        ],
      ),
      floatingActionButton: asset == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/jobs/new?asset=${asset.id}'),
              icon: const Icon(CupertinoIcons.add),
              label: const Text('Job card on this'),
            ),
      body: MeshBackground(
        child: asset == null
            ? const Center(
                child: EmptyState(
                  icon: CupertinoIcons.gear_alt,
                  title: 'Asset not found',
                  message: 'It may have been removed from the register.',
                ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  Space.md,
                  top + Space.md,
                  Space.md,
                  120,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SurfaceCard(
                            padding: const EdgeInsets.all(Space.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      assetIcon(asset.kind),
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: Space.xs),
                                    RecordCode(asset.tag),
                                    if (asset.kind != null) ...[
                                      const SizedBox(width: Space.xs),
                                      Pill(label: asset.kind!, dense: true),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: Space.sm),
                                Text(
                                  asset.name,
                                  style: theme.textTheme.headlineSmall,
                                ),
                                const SizedBox(height: Space.xs),
                                for (final line in [
                                  ?areaNames[asset.areaId],
                                  ?asset.makeModel,
                                  if (asset.serialNo != null)
                                    'Serial ${asset.serialNo}',
                                  ?asset.notes,
                                ])
                                  Text(
                                    line,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                const SizedBox(height: Space.md),
                                Row(
                                  children: [
                                    _Stat(
                                      label: 'Open job cards',
                                      value: '$open',
                                    ),
                                    _Stat(
                                      label: 'Done',
                                      value: '${done.length}',
                                    ),
                                    _Stat(
                                      label: 'Last done',
                                      value: done.isEmpty
                                          ? '—'
                                          : relativeTime(
                                              done
                                                  .map((j) => j.closedAt!)
                                                  .reduce(
                                                    (a, b) =>
                                                        a.isAfter(b) ? a : b,
                                                  ),
                                            ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ).entrance(context),
                          if (plans.isNotEmpty) ...[
                            const SectionHeader('Planned maintenance'),
                            for (final p in plans)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Space.sm,
                                ),
                                child: SurfaceCard(
                                  onTap: () => context.push('/jobs/recurring'),
                                  child: Row(
                                    children: [
                                      Icon(
                                        CupertinoIcons.calendar_badge_plus,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(width: Space.sm),
                                      Expanded(
                                        child: Text(p['title'] as String),
                                      ),
                                      Text(
                                        '${p['every']} · next ${p['next_run']}',
                                        style: theme.textTheme.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                          const SectionHeader('Job history'),
                          if (jobs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: Space.md),
                              child: Center(
                                child: EmptyState(
                                  icon: CupertinoIcons.doc_text,
                                  title: 'No job cards yet',
                                  message:
                                      'Job cards on this equipment show '
                                      'here, newest first.',
                                ),
                              ),
                            ),
                          for (final (i, j) in jobs.indexed)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.sm),
                              child: JobCardTile(
                                job: j,
                                onTap: () => context.push('/jobs/${j.number}'),
                              ),
                            ).entrance(context, index: (i + 1).clamp(0, 8)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.titleLarge),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
