import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/local_db.dart';
import '../data/site_data.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../tools/tools_repository.dart';
import '../tools/tools_screen.dart';
import '../ui/charts.dart' show GlassSegmented;
import '../ui/form_sheet.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import '../v2/jobcards/repository.dart' show openJobCardsByAssetProvider;
import '../widgets/app_back_button.dart';
import 'assets_screen.dart';

enum EquipmentSide { equipment, tools }

/// The side last looked at, so coming back opens it again.
final equipmentSideProvider =
    NotifierProvider<EquipmentSideNotifier, EquipmentSide>(
      EquipmentSideNotifier.new,
    );

class EquipmentSideNotifier extends Notifier<EquipmentSide> {
  @override
  EquipmentSide build() => EquipmentSide.equipment;

  void set(EquipmentSide side) => state = side;
}

/// Equipment & tools: the site's plant register and tools register on one
/// page. One search box, a switch between the two, and four numbers per
/// side that filter the list when tapped. `/assets` and `/tools` open here.
class EquipmentScreen extends ConsumerStatefulWidget {
  const EquipmentScreen({super.key, this.side, this.mine = false});

  /// Opens this side (from a link); otherwise the last one used.
  final EquipmentSide? side;

  /// Opens the tools side showing the tools you hold.
  final bool mine;

  @override
  ConsumerState<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends ConsumerState<EquipmentScreen> {
  final _search = TextEditingController();
  AssetFilter _assetFilter = AssetFilter.all;
  late ToolFilter _toolFilter = widget.mine ? ToolFilter.mine : ToolFilter.all;

  @override
  void initState() {
    super.initState();
    final side = widget.mine ? EquipmentSide.tools : widget.side;
    if (side != null) {
      Future.microtask(
        () => ref.read(equipmentSideProvider.notifier).set(side),
      );
    }
  }

  @override
  void didUpdateWidget(EquipmentScreen old) {
    super.didUpdateWidget(old);
    // A new link to the same page (e.g. /tools after /equipment).
    final side = widget.mine ? EquipmentSide.tools : widget.side;
    if (side != null && (side != old.side || widget.mine != old.mine)) {
      if (widget.mine) _toolFilter = ToolFilter.mine;
      Future.microtask(
        () => ref.read(equipmentSideProvider.notifier).set(side),
      );
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _add(BuildContext context, bool canAsset, bool canTool) {
    if (canAsset && !canTool) {
      showFormSheet(context, const AssetForm());
      return;
    }
    if (canTool && !canAsset) {
      showFormSheet(context, const ToolForm());
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.electrical_services_outlined),
              title: const Text('Equipment'),
              subtitle: const Text('A motor, panel, transformer…'),
              onTap: () {
                Navigator.pop(sheet);
                showFormSheet(context, const AssetForm());
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.wrench),
              title: const Text('Tool'),
              subtitle: const Text('A megger, multimeter, drill…'),
              onTap: () {
                Navigator.pop(sheet);
                showFormSheet(context, const ToolForm());
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final canAsset =
        site != null && session.can('jobs.assign', siteId: site.id);
    final canTool = site != null && session.can('tools.issue', siteId: site.id);
    final seesTools =
        site != null && session.can('tools.view', siteId: site.id);
    final side = seesTools
        ? ref.watch(equipmentSideProvider)
        : EquipmentSide.equipment;
    final onTools = side == EquipmentSide.tools;

    final assets = ref.watch(siteAssetsProvider).value ?? const [];
    final tools = seesTools
        ? ref.watch(siteToolsProvider).value ?? const <LocalTool>[]
        : const <LocalTool>[];
    final openByAsset = site == null
        ? const <String, int>{}
        : ref.watch(openJobCardsByAssetProvider(site.id)).value ??
              const <String, int>{};
    final people = ref.watch(peopleProvider).value ?? const {};
    final areaNames = {for (final a in session.areas) a.id: a.name};
    final q = _search.text.trim().toLowerCase();

    // Matches on the side you are not looking at, to jump across.
    final otherMatches = q.isEmpty || !seesTools
        ? 0
        : onTools
        ? assets.where((a) => assetMatches(a, q, areaNames)).length
        : tools.where((t) => toolMatches(t, q, people)).length;

    final stats = onTools
        ? [
            _StatData(
              'In store',
              tools.where((t) => t.holderId == null).length,
              CupertinoIcons.cube_box,
              BrandColors.success,
              ToolFilter.store,
            ),
            _StatData(
              'Out',
              tools.where((t) => t.holderId != null).length,
              CupertinoIcons.person_crop_circle,
              BrandColors.info,
              ToolFilter.out,
            ),
            _StatData(
              'Overdue back',
              tools.where(toolOverdue).length,
              CupertinoIcons.clock,
              Colors.red,
              ToolFilter.overdue,
            ),
            _StatData(
              'Calibration due',
              tools.where(calibrationDue).length,
              CupertinoIcons.gauge,
              BrandColors.warning,
              ToolFilter.calibration,
            ),
          ]
        : [
            _StatData(
              'In service',
              assets.where((a) => a.status == 'in_service').length,
              CupertinoIcons.checkmark_seal,
              BrandColors.success,
              AssetFilter.inService,
            ),
            _StatData(
              'Out of service',
              assets.where((a) => a.status == 'out_of_service').length,
              CupertinoIcons.xmark_octagon,
              Colors.red,
              AssetFilter.outOfService,
            ),
            _StatData(
              'Open job cards',
              assets.where((a) => (openByAsset[a.id] ?? 0) > 0).length,
              CupertinoIcons.hammer,
              BrandColors.warning,
              AssetFilter.openJobs,
            ),
            _StatData(
              'Standby',
              assets.where((a) => a.status == 'standby').length,
              CupertinoIcons.pause_circle,
              Colors.blueGrey,
              AssetFilter.standby,
            ),
          ];
    final Object current = onTools ? _toolFilter : _assetFilter;
    void pick(Object f) => setState(() {
      if (f is ToolFilter) {
        _toolFilter = _toolFilter == f ? ToolFilter.all : f;
      } else if (f is AssetFilter) {
        _assetFilter = _assetFilter == f ? AssetFilter.all : f;
      }
    });
    final filtered = onTools
        ? _toolFilter != ToolFilter.all
        : _assetFilter != AssetFilter.all;

    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/menu'),
        title: Text(seesTools ? 'Equipment & tools' : 'Equipment'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
        actions: [
          if (onTools && canTool && tools.isNotEmpty)
            TextButton.icon(
              onPressed: () => context.push('/tools/count'),
              icon: const Icon(CupertinoIcons.checkmark_square),
              label: const Text('Count'),
            ),
          const SizedBox(width: Space.xs),
        ],
      ),
      floatingActionButton: canAsset || canTool
          ? FloatingActionButton.extended(
              onPressed: () => _add(context, canAsset, canTool),
              icon: const Icon(CupertinoIcons.add),
              label: const Text('Add'),
            )
          : null,
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () async {
            ref.invalidate(openJobCardsByAssetProvider);
            await Future.wait([
              ref.read(siteDataProvider.notifier).refresh(),
              if (seesTools) ref.read(toolsSyncProvider.notifier).refresh(),
            ]);
          },
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
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (site != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: Text(
                            site.name,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (seesTools) ...[
                        GlassSegmented<EquipmentSide>(
                          value: side,
                          segments: {
                            EquipmentSide.equipment:
                                'Equipment · ${assets.length}',
                            EquipmentSide.tools: 'Tools · ${tools.length}',
                          },
                          onChanged: ref
                              .read(equipmentSideProvider.notifier)
                              .set,
                        ),
                        const SizedBox(height: Space.sm),
                      ],
                      CupertinoSearchTextField(
                        controller: _search,
                        placeholder: onTools
                            ? 'Search tools, codes or who has them'
                            : 'Search tags, names, kinds or areas',
                        onChanged: (_) => setState(() {}),
                      ),
                      if (otherMatches > 0)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: Space.xs),
                            child: ActionChip(
                              avatar: Icon(
                                onTools
                                    ? Icons.electrical_services_outlined
                                    : CupertinoIcons.wrench,
                                size: 16,
                              ),
                              label: Text(
                                '$otherMatches '
                                '${otherMatches == 1 ? 'match' : 'matches'} in '
                                '${onTools ? 'Equipment' : 'Tools'} →',
                              ),
                              onPressed: () => ref
                                  .read(equipmentSideProvider.notifier)
                                  .set(
                                    onTools
                                        ? EquipmentSide.equipment
                                        : EquipmentSide.tools,
                                  ),
                            ),
                          ),
                        ),
                      const SizedBox(height: Space.md),
                      _Stats(
                        stats: stats,
                        current: current,
                        onTap: pick,
                      ).entrance(context),
                      const SizedBox(height: Space.sm),
                      Row(
                        children: [
                          if (onTools)
                            FilterChip(
                              label: const Text('With me'),
                              avatar: const Icon(
                                CupertinoIcons.person_fill,
                                size: 16,
                              ),
                              selected: _toolFilter == ToolFilter.mine,
                              onSelected: (_) => pick(ToolFilter.mine),
                            ),
                          const Spacer(),
                          if (filtered)
                            TextButton(
                              onPressed: () => setState(() {
                                _toolFilter = ToolFilter.all;
                                _assetFilter = AssetFilter.all;
                              }),
                              child: const Text('Show all'),
                            ),
                        ],
                      ),
                      const SizedBox(height: Space.xs),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: onTools
                            ? ToolList(
                                key: const ValueKey('tools'),
                                query: _search.text,
                                filter: _toolFilter,
                              )
                            : AssetList(
                                key: const ValueKey('assets'),
                                query: _search.text,
                                filter: _assetFilter,
                              ),
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

class _StatData {
  const _StatData(this.label, this.value, this.icon, this.color, this.filter);

  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final Object filter;
}

/// Four numbers; tapping one filters the list (tap again to clear).
class _Stats extends StatelessWidget {
  const _Stats({
    required this.stats,
    required this.current,
    required this.onTap,
  });

  final List<_StatData> stats;
  final Object current;
  final ValueChanged<Object> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 640 ? 4 : 2;
        final w = (box.maxWidth - Space.sm * (cols - 1)) / cols;
        return Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final s in stats)
              SizedBox(
                width: w,
                child: Pressable(
                  onTap: () => onTap(s.filter),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      border: Border.all(
                        color: current == s.filter
                            ? s.color
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: SurfaceCard(
                      padding: const EdgeInsets.all(Space.sm),
                      radius: Radii.lg,
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: s.color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(Radii.sm),
                            ),
                            child: Icon(s.icon, color: s.color, size: 20),
                          ),
                          const SizedBox(width: Space.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${s.value}',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color:
                                        s.value > 0 && (s.color == Colors.red)
                                        ? Colors.red
                                        : null,
                                  ),
                                ),
                                Text(
                                  s.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
