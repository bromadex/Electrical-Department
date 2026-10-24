import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../jobcards/job_card_tile.dart';
import '../jobcards/models.dart';
import '../jobcards/repository.dart';
import '../reference/reference_data.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/format.dart';
import '../ui/page.dart';
import '../ui/panels.dart';
import 'assets_screen.dart' show AssetStatusPill;
import 'repository.dart';

class AssetScreen extends ConsumerWidget {
  const AssetScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = ref.watch(assetProvider(id));
    final history = ref.watch(
      jobCardsPageProvider(JobCardFilter(view: JobCardView.all, assetId: id)),
    );
    final canManage = ref.watch(
      sessionProvider.select((s) => s.perms.can('assets.manage')),
    );
    final departments = ref.watch(referenceDataProvider).value;

    return AsyncView(
      value: asset,
      onRetry: () => ref.invalidate(assetProvider(id)),
      data: (a) {
        String? rated(num? v, String unit) => v == null ? null : '$v $unit';
        return AppPage(
          title: a.name,
          subtitle: a.assetNo,
          leading: IconButton(
            tooltip: 'Back',
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/assets'),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          actions: [
            if (canManage)
              OutlinedButton.icon(
                onPressed: () => context.go('/assets/${a.id}/edit'),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      children: [
                        AssetStatusPill(a.status),
                        Pill(
                          label: 'Criticality: ${a.criticality}',
                          dense: true,
                          color: a.criticality == 'high'
                              ? AppColors.critical
                              : a.criticality == 'medium'
                              ? AppColors.warning
                              : AppColors.neutral,
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.md),
                    ResponsiveGrid(
                      minItemWidth: 200,
                      children: [
                        KeyValue('Category', a.categoryName),
                        KeyValue('Site', a.siteName),
                        KeyValue('Work area', a.areaName),
                        KeyValue('Location', a.location),
                        KeyValue('Manufacturer', a.manufacturer),
                        KeyValue('Model', a.model),
                        KeyValue('Serial number', a.serialNo),
                        KeyValue('Electrical rating', a.rating),
                        KeyValue('Voltage', rated(a.voltage, 'V')),
                        KeyValue('Current rating', rated(a.current, 'A')),
                        KeyValue('Power rating', rated(a.power, 'kW')),
                        KeyValue('Installed', fmtDate(a.installedOn)),
                        KeyValue(
                          'Responsible department',
                          departments?.departmentName(a.departmentId),
                        ),
                        KeyValue(
                          'Maintenance frequency',
                          a.maintenanceFrequency,
                        ),
                        KeyValue(
                          'Warranty until',
                          fmtDate(a.warrantyExpiresOn),
                        ),
                        KeyValue('Warranty notes', a.warrantyNotes),
                      ],
                    ),
                    if (a.notes != null) ...[
                      const SizedBox(height: Space.md),
                      KeyValue('Notes', a.notes),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: Space.md),
              Panel(
                title: 'Job card history',
                subtitle: 'Faults, repairs and maintenance recorded against this equipment',
                icon: Icons.history_rounded,
                child: AsyncView(
                  value: history,
                  data: (page) {
                    if (page.rows.isEmpty) {
                      return const Text('No job cards for this equipment yet.');
                    }
                    final recentFaults = page.rows
                        .where(
                          (j) =>
                              j.maintenanceType != 'preventive' &&
                              j.receivedAt.isAfter(
                                DateTime.now().toUtc().subtract(
                                  const Duration(days: 90),
                                ),
                              ),
                        )
                        .length;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (recentFaults >= 3)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.sm),
                            child: Pill(
                              label:
                                  'Repeated failures: $recentFaults job cards in the last 90 days',
                              icon: Icons.repeat_rounded,
                              color: AppColors.critical,
                            ),
                          ),
                        for (final j in page.rows)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.xs),
                            child: JobCardTile(
                              job: j,
                              onTap: () => context.go('/job-cards/${j.number}'),
                            ),
                          ),
                        if (page.total > page.rows.length)
                          Text(
                            'Showing the latest ${page.rows.length} of ${page.total}.',
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
