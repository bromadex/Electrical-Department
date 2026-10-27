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
import '../ui/charts.dart' show GlassSegmented;
import '../ui/record_hero.dart';
import '../ui/surfaces.dart';
import 'assets_screen.dart';
import '../widgets/app_back_button.dart';

/// One piece of equipment: the shared record header, quick actions, then
/// Job cards · Maintenance · Details.
class AssetDetailScreen extends ConsumerStatefulWidget {
  const AssetDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

enum _Tab { jobs, maintenance, details }

class _AssetDetailScreenState extends ConsumerState<AssetDetailScreen> {
  _Tab _tab = _Tab.jobs;

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
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
    final canRaise =
        asset != null && session.can('jc.register', siteId: asset.siteId);
    final open = jobs
        .where((j) => !{'closed', 'cancelled'}.contains(j.status.db))
        .length;
    final done = [
      for (final j in jobs)
        if (j.status.db == 'closed' && j.closedAt != null) j,
    ];

    Future<void> edit() async {
      final kept = await showFormSheet<bool>(context, AssetForm(asset: asset));
      if (kept == false && context.mounted) context.pop();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/equipment?side=equipment'),
        title: Text(asset?.tag ?? 'Equipment'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: asset == null
            ? const Center(
                child: EmptyState(
                  icon: Icons.electrical_services_outlined,
                  title: 'Equipment not found',
                  message: 'It may have been removed from the register.',
                ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  Space.md,
                  top + Space.md,
                  Space.md,
                  Space.xl,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          RecordHero(
                            icon: assetIcon(asset.kind),
                            code: asset.tag,
                            title: asset.name,
                            pills: [
                              _statusPill(asset.status),
                              if (asset.kind != null)
                                Pill(label: asset.kind!, dense: true),
                            ],
                            facts: [
                              if (areaNames[asset.areaId] != null)
                                (
                                  icon: CupertinoIcons.location,
                                  text: areaNames[asset.areaId]!,
                                  color: null,
                                ),
                              if (asset.makeModel != null)
                                (
                                  icon: CupertinoIcons.tag,
                                  text: asset.makeModel!,
                                  color: null,
                                ),
                            ],
                            stats: [
                              ('$open', 'Open job cards'),
                              ('${done.length}', 'Done'),
                              (
                                done.isEmpty
                                    ? '—'
                                    : relativeTime(
                                        done
                                            .map((j) => j.closedAt!)
                                            .reduce(
                                              (a, b) => a.isAfter(b) ? a : b,
                                            ),
                                      ),
                                'Last done',
                              ),
                            ],
                          ).entrance(context),
                          const SizedBox(height: Space.sm),
                          QuickActions(
                            actions: [
                              (
                                icon: CupertinoIcons
                                    .exclamationmark_triangle_fill,
                                label: 'Report fault',
                                onTap: canRaise
                                    ? () => context.push(
                                        '/jobs/new?asset=${asset.id}',
                                      )
                                    : null,
                                color: BrandColors.maroon,
                              ),
                              (
                                icon: CupertinoIcons.calendar_badge_plus,
                                label: 'Maintenance',
                                onTap: () => context.push('/jobs/recurring'),
                                color: BrandColors.info,
                              ),
                              (
                                icon: CupertinoIcons.pencil,
                                label: 'Edit',
                                onTap: canEdit ? edit : null,
                                color: null,
                              ),
                            ],
                          ).entrance(context, index: 1),
                          const SizedBox(height: Space.md),
                          GlassSegmented<_Tab>(
                            value: _tab,
                            segments: {
                              _Tab.jobs: 'Job cards · ${jobs.length}',
                              _Tab.maintenance: 'Plans · ${plans.length}',
                              _Tab.details: 'Details',
                            },
                            onChanged: (t) => setState(() => _tab = t),
                          ),
                          const SizedBox(height: Space.md),
                          ...switch (_tab) {
                            _Tab.jobs => [
                              if (jobs.isEmpty)
                                const EmptyState(
                                  icon: CupertinoIcons.doc_text,
                                  title: 'No job cards yet',
                                  message:
                                      'Job cards on this equipment show '
                                      'here, newest first.',
                                ),
                              for (final (i, j) in jobs.indexed)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: Space.sm,
                                  ),
                                  child: JobCardTile(
                                    job: j,
                                    onTap: () =>
                                        context.push('/jobs/${j.number}'),
                                  ),
                                ).entrance(context, index: i.clamp(0, 8)),
                            ],
                            _Tab.maintenance => [
                              if (plans.isEmpty)
                                const EmptyState(
                                  icon: CupertinoIcons.calendar,
                                  title: 'No planned maintenance',
                                  message:
                                      'Plans raise job cards on this '
                                      'equipment on a schedule.',
                                ),
                              for (final p in plans)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: Space.sm,
                                  ),
                                  child: SurfaceCard(
                                    onTap: () =>
                                        context.push('/jobs/recurring'),
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
                            _Tab.details => [
                              RecordDetails(
                                rows: [
                                  ('Tag', asset.tag),
                                  ('Name', asset.name),
                                  ('Kind', asset.kind),
                                  ('Area', areaNames[asset.areaId]),
                                  ('Make and model', asset.makeModel),
                                  ('Serial number', asset.serialNo),
                                  ('Status', _statusLabel(asset.status)),
                                  ('Notes', asset.notes),
                                ],
                              ),
                            ],
                          },
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

String _statusLabel(String s) => switch (s) {
  'out_of_service' => 'Out of service',
  'standby' => 'Standby',
  'decommissioned' => 'Decommissioned',
  _ => 'In service',
};

Widget _statusPill(String s) => Pill(
  label: _statusLabel(s),
  dense: true,
  color: switch (s) {
    'out_of_service' => Colors.red,
    'standby' => Colors.blueGrey,
    'decommissioned' => Colors.grey,
    _ => BrandColors.success,
  },
);
