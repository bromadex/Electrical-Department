import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/time.dart';

/// Faults and time out of service for one piece of equipment (issue #33),
/// from fn_equipment_history.
class EquipmentHistory {
  const EquipmentHistory({
    required this.assetId,
    required this.tag,
    required this.name,
    required this.faults,
    required this.faults30,
    required this.lastFaultAt,
    required this.downHours,
    required this.downNow,
  });

  factory EquipmentHistory.fromJson(Map<String, dynamic> j) => EquipmentHistory(
    assetId: j['asset_id'] as String,
    tag: j['tag'] as String? ?? '',
    name: j['name'] as String? ?? '',
    faults: (j['faults'] as num?)?.toInt() ?? 0,
    faults30: (j['faults_30'] as num?)?.toInt() ?? 0,
    lastFaultAt: DateTime.tryParse(j['last_fault_at'] as String? ?? ''),
    downHours: (j['down_hours'] as num?)?.toDouble() ?? 0,
    downNow: j['down_now'] as bool? ?? false,
  );

  final String assetId;
  final String tag;
  final String name;
  final int faults;
  final int faults30;
  final DateTime? lastFaultAt;
  final double downHours;
  final bool downNow;

  /// Several faults in 30 days: worth looking at the cause, not just the
  /// symptom.
  bool get repeats => faults30 >= repeatFaultThreshold;
}

/// Faults in 30 days that make equipment a repeat fault.
const repeatFaultThreshold = 3;

/// "36 h", "2.5 days".
String downtimeText(double hours) {
  if (hours <= 0) return '0 h';
  if (hours < 48) {
    return '${hours == hours.roundToDouble() ? hours.toInt() : hours.toStringAsFixed(1)} h';
  }
  final days = hours / 24;
  return '${days.toStringAsFixed(days < 10 ? 1 : 0)} days';
}

/// Equipment history for a site (null: every site) over [days] days, most
/// repeated faults first.
final equipmentHistoryProvider = FutureProvider.autoDispose
    .family<List<EquipmentHistory>, ({String? site, int days})>((
      ref,
      args,
    ) async {
      final rows = await ref
          .watch(supabaseProvider)
          .rpc(
            'fn_equipment_history',
            params: {'p_site': args.site, 'p_days': args.days},
          );
      return [
        for (final r in rows as List)
          EquipmentHistory.fromJson(Map<String, dynamic>.from(r as Map)),
      ];
    });

/// One asset's numbers for its page.
final assetHistoryProvider = FutureProvider.autoDispose
    .family<EquipmentHistory?, ({String assetId, String siteId})>((
      ref,
      args,
    ) async {
      final all = await ref.watch(
        equipmentHistoryProvider((site: args.siteId, days: 90)).future,
      );
      return all.where((h) => h.assetId == args.assetId).firstOrNull;
    });

/// The line on an asset's page: faults in 30 and 90 days, time out of
/// service in 90 days, and a warning when the faults repeat.
class AssetHistoryStrip extends ConsumerWidget {
  const AssetHistoryStrip({
    super.key,
    required this.assetId,
    required this.siteId,
  });

  final String assetId;
  final String siteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final h = ref
        .watch(assetHistoryProvider((assetId: assetId, siteId: siteId)))
        .value;
    if (h == null) return const SizedBox.shrink();
    return Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (h.repeats)
          const Pill(
            label: 'Repeat faults',
            icon: CupertinoIcons.repeat,
            color: Colors.orange,
          ),
        if (h.downNow)
          const Pill(
            label: 'Out of service now',
            icon: CupertinoIcons.exclamationmark_octagon,
            color: Color(0xFFC8423B),
          ),
        Text(
          [
            '${h.faults30} ${h.faults30 == 1 ? 'fault' : 'faults'} in 30 days',
            '${h.faults} in 90 days',
            'down ${downtimeText(h.downHours)} in 90 days',
            if (h.lastFaultAt != null)
              'last fault ${relativeTime(h.lastFaultAt!)}',
          ].join(' · '),
          style: theme.textTheme.labelMedium,
        ),
      ],
    );
  }
}

/// Equipment with repeat faults, for Job statistics.
class RepeatFaultsList extends ConsumerWidget {
  const RepeatFaultsList({super.key, required this.site, required this.days});

  final String? site;
  final int days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final list = ref.watch(equipmentHistoryProvider((site: site, days: days)));
    return list.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(Space.md),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('Could not load: $e'),
      data: (all) {
        final shown = [
          for (final h in all)
            if (h.faults > 0 || h.downHours > 0) h,
        ].take(8).toList();
        if (shown.isEmpty) {
          return Text(
            'No equipment faults in this period.',
            style: theme.textTheme.bodySmall,
          );
        }
        return Column(
          children: [
            for (final h in shown)
              InkWell(
                borderRadius: BorderRadius.circular(Radii.sm),
                onTap: () => context.push('/assets/${h.assetId}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${h.tag} · ${h.name}',
                              style: theme.textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              [
                                '${h.faults30} in 30 days',
                                'down ${downtimeText(h.downHours)}',
                                if (h.downNow) 'out of service now',
                              ].join(' · '),
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      if (h.repeats)
                        const Padding(
                          padding: EdgeInsets.only(right: Space.xs),
                          child: Icon(
                            CupertinoIcons.repeat,
                            size: 16,
                            color: Colors.orange,
                          ),
                        ),
                      Text(
                        '${h.faults}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
