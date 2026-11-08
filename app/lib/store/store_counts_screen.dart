import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_error.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import '../v2/site_filter.dart';
import '../widgets/app_back_button.dart';
import 'store_repository.dart';

/// Past stock counts: who counted, when, how many items and how many
/// differed; open one for the items that were corrected.
class StoreCountsScreen extends ConsumerWidget {
  const StoreCountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final counts = ref.watch(stockCountsProvider);
    final session = ref.watch(sessionProvider);
    final all = ref.watch(allSitesProvider);
    final dates = MaterialLocalizations.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/inventory'),
        title: const Text('Past counts'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(stockCountsProvider.future),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Space.md,
              top + Space.md,
              Space.md,
              Space.xl,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: AllSitesChip(),
                      ),
                      const SizedBox(height: Space.sm),
                      ...counts.when(
                        loading: () => [
                          const Center(child: CircularProgressIndicator()),
                        ],
                        error: (e, _) => [
                          EmptyState(
                            icon: CupertinoIcons.wifi_slash,
                            title: 'Could not load counts',
                            message: AppError.from(e).message,
                          ),
                        ],
                        data: (list) => [
                          if (list.isEmpty)
                            const EmptyState(
                              icon: CupertinoIcons.number_square,
                              title: 'No counts yet',
                              message:
                                  'Counts saved from Count stock show '
                                  'here.',
                            ),
                          for (final c in list)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.sm),
                              child: SurfaceCard(
                                padding: EdgeInsets.zero,
                                child: Theme(
                                  data: theme.copyWith(
                                    dividerColor: Colors.transparent,
                                  ),
                                  child: ExpansionTile(
                                    title: Row(
                                      children: [
                                        if (all) ...[
                                          Pill(
                                            label:
                                                session
                                                    .siteById(c.siteId)
                                                    ?.code ??
                                                '',
                                            dense: true,
                                          ),
                                          const SizedBox(width: Space.xs),
                                        ],
                                        Expanded(
                                          child: Text(
                                            '${dates.formatMediumDate(c.at)} · '
                                            '${dates.formatTimeOfDay(TimeOfDay.fromDateTime(c.at))}',
                                            style: theme.textTheme.titleSmall,
                                          ),
                                        ),
                                        Pill(
                                          label: c.differences == 0
                                              ? 'All matched'
                                              : '${c.differences} corrected',
                                          color: c.differences == 0
                                              ? BrandColors.success
                                              : Colors.orange,
                                          dense: true,
                                        ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      [
                                        '${c.items} counted',
                                        if (c.by.isNotEmpty) 'by ${c.by}',
                                        if (c.note != null) c.note!,
                                      ].join(' · '),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    children: [
                                      if (c.differences > 0)
                                        _CountLines(countId: c.id),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
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

class _CountLines extends ConsumerWidget {
  const _CountLines({required this.countId});

  final String countId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lines = ref.watch(stockCountLinesProvider(countId));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
      child: lines.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text(AppError.from(e).message),
        data: (list) => Column(
          children: [
            for (final l in list)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l.code} · ${l.name}',
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${qtyText(l.expected)} → ${qtyText(l.counted)} ${l.unit}',
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(width: Space.sm),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${l.counted > l.expected ? '+' : '−'}'
                        '${qtyText((l.counted - l.expected).abs())}',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
