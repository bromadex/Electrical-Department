import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../reference/reference_data.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/data_table.dart';
import '../ui/page.dart';
import 'models.dart';
import 'repository.dart';

class AssetStatusPill extends StatelessWidget {
  const AssetStatusPill(this.status, {super.key});

  final AssetStatus status;

  @override
  Widget build(BuildContext context) => Pill(
    label: status.label,
    dense: true,
    color: switch (status) {
      AssetStatus.inService => AppColors.success,
      AssetStatus.standby => AppColors.info,
      AssetStatus.outOfService => AppColors.critical,
      AssetStatus.decommissioned => AppColors.neutral,
    },
    icon: switch (status) {
      AssetStatus.inService => Icons.check_circle_outline_rounded,
      AssetStatus.standby => Icons.pause_circle_outline_rounded,
      AssetStatus.outOfService => Icons.power_off_outlined,
      AssetStatus.decommissioned => Icons.block_rounded,
    },
  );
}

class AssetsScreen extends ConsumerStatefulWidget {
  const AssetsScreen({super.key});

  @override
  ConsumerState<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends ConsumerState<AssetsScreen> {
  AssetFilter _filter = const AssetFilter();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final site = ref.watch(siteFilterProvider);
    final filter = _filter.forSite(site);
    final page = ref.watch(assetsPageProvider(filter));
    final session = ref.watch(sessionProvider);
    final categories =
        ref.watch(referenceDataProvider).value?.activeAssetCategories ??
        const <Category>[];
    final canManage = session.perms.can('assets.manage');

    return AppPage(
      title: 'Asset Register',
      subtitle: 'Electrical equipment by site',
      actions: [
        if (canManage)
          FilledButton.icon(
            onPressed: () => context.go('/assets/new'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add equipment'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Asset ID, name, serial, location…',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), () {
                      if (mounted) {
                        setState(
                          () => _filter = _filter.copyWith(
                            search: v.trim(),
                            page: 0,
                          ),
                        );
                      }
                    });
                  },
                ),
              ),
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String?>(
                  initialValue: _filter.categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Category',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All categories'),
                    ),
                    for (final c in categories)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(
                    () => _filter = _filter.copyWith(
                      categoryId: v,
                      clearCategory: v == null,
                      page: 0,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String?>(
                  initialValue: _filter.status,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Status',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Any status'),
                    ),
                    for (final s in AssetStatus.values)
                      DropdownMenuItem(value: s.db, child: Text(s.label)),
                  ],
                  onChanged: (v) => setState(
                    () => _filter = _filter.copyWith(
                      status: v,
                      clearStatus: v == null,
                      page: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Card(
            clipBehavior: Clip.antiAlias,
            child: switch (page) {
              AsyncError(:final error) when !page.hasValue => ErrorPanel(
                error: error,
                onRetry: () => ref.invalidate(assetsPageProvider(filter)),
              ),
              _ => PagedTable<Asset>(
                loading: page.isLoading,
                rows: page.value?.rows ?? const [],
                total: page.value?.total ?? 0,
                page: _filter.page,
                pageSize: AssetFilter.pageSize,
                onPage: (p) =>
                    setState(() => _filter = _filter.copyWith(page: p)),
                onTap: (a) => context.go('/assets/${a.id}'),
                emptyMessage: 'No equipment matches. Add equipment to the register to pick it on job cards.',
                cardBuilder: (a) => Card(
                  child: ListTile(
                    onTap: () => context.go('/assets/${a.id}'),
                    title: Text(a.name),
                    subtitle: Text(
                      [
                        a.assetNo,
                        a.categoryName,
                        a.areaName ?? a.location,
                      ].whereType<String>().join(' · '),
                    ),
                    trailing: AssetStatusPill(a.status),
                  ),
                ),
                columns: [
                  TableCol('Asset ID', (a) => RecordCode(a.assetNo)),
                  TableCol(
                    'Name',
                    (a) => SizedBox(
                      width: 200,
                      child: Text(
                        a.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  TableCol('Category', (a) => Text(a.categoryName ?? '—')),
                  TableCol('Site', (a) => Text(a.siteCode ?? '—')),
                  TableCol(
                    'Area / location',
                    (a) => Text(a.areaName ?? a.location ?? '—'),
                  ),
                  TableCol('Status', (a) => AssetStatusPill(a.status)),
                  TableCol(
                    'Criticality',
                    (a) => Text(
                      a.criticality[0].toUpperCase() +
                          a.criticality.substring(1),
                    ),
                  ),
                  TableCol(
                    'Make / model',
                    (a) => Text(
                      [
                            a.manufacturer,
                            a.model,
                          ].whereType<String>().join(' ').trim().isEmpty
                          ? '—'
                          : [
                              a.manufacturer,
                              a.model,
                            ].whereType<String>().join(' '),
                    ),
                  ),
                  TableCol('Rating', (a) => Text(a.rating ?? '—')),
                ],
              ),
            },
          ),
        ],
      ),
    );
  }
}
