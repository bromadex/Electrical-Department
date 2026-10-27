import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/local_db.dart';
import '../data/site_data.dart';
import '../v2/jobcards/repository.dart' show openJobCardsByAssetProvider;
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';

/// Common kinds of plant, offered when adding an asset. Free text is fine.
const assetKinds = [
  'Motor',
  'MCC / panel',
  'Distribution board',
  'Transformer',
  'Switchgear',
  'Generator',
  'Pump',
  'Lighting',
  'Cable',
  'Instrument',
];

IconData assetIcon(String? kind) {
  final k = kind?.toLowerCase() ?? '';
  bool has(List<String> words) => words.any(k.contains);
  if (has(['motor', 'pump', 'fan', 'conveyor'])) {
    return Icons.precision_manufacturing_rounded;
  }
  if (has(['transformer', 'generator', 'substation', 'switchgear'])) {
    return CupertinoIcons.bolt_fill;
  }
  if (has(['light', 'flood'])) return CupertinoIcons.lightbulb_fill;
  if (has(['cable', 'termination'])) return CupertinoIcons.link;
  if (has(['instrument', 'meter', 'sensor'])) return CupertinoIcons.gauge;
  if (has(['earth', 'lightning'])) return CupertinoIcons.arrow_down_to_line;
  if (has(['board', 'panel', 'mcc', 'control'])) {
    return CupertinoIcons.square_grid_2x2_fill;
  }
  return Icons.electrical_services_rounded;
}

/// Narrows the equipment side of the Equipment & tools page.
enum AssetFilter { all, inService, outOfService, standby, openJobs }

bool assetMatches(LocalAsset a, String q, Map<String, String> areaNames) =>
    q.isEmpty ||
    a.tag.toLowerCase().contains(q) ||
    a.name.toLowerCase().contains(q) ||
    (a.kind?.toLowerCase().contains(q) ?? false) ||
    (a.serialNo?.toLowerCase().contains(q) ?? false) ||
    (areaNames[a.areaId]?.toLowerCase().contains(q) ?? false);

/// The equipment register at the current site, as cards (two columns on
/// wide screens). The Equipment & tools page supplies search and filter.
class AssetList extends ConsumerWidget {
  const AssetList({super.key, this.query = '', this.filter = AssetFilter.all});

  final String query;
  final AssetFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(siteAssetsProvider).value ?? const [];
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final canEdit = site != null && session.can('jobs.assign', siteId: site.id);
    final areaNames = {for (final a in session.areas) a.id: a.name};
    final openByAsset = site == null
        ? const <String, int>{}
        : ref.watch(openJobCardsByAssetProvider(site.id)).value ??
              const <String, int>{};
    final q = query.trim().toLowerCase();
    final shown = [
      for (final a in assets)
        if (switch (filter) {
              AssetFilter.all => true,
              AssetFilter.inService => a.status == 'in_service',
              AssetFilter.outOfService => a.status == 'out_of_service',
              AssetFilter.standby => a.status == 'standby',
              AssetFilter.openJobs => (openByAsset[a.id] ?? 0) > 0,
            } &&
            assetMatches(a, q, areaNames))
          a,
    ];

    if (shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.xl),
        child: Center(
          child: EmptyState(
            icon: Icons.electrical_services_outlined,
            title: assets.isEmpty ? 'No equipment yet' : 'Nothing here',
            message: assets.isEmpty
                ? (canEdit
                      ? 'Add the motors, panels and transformers you look '
                            'after. Job cards on them build its history.'
                      : 'A supervisor adds the plant you look after here.')
                : 'No equipment matches.',
          ),
        ),
      );
    }
    return CardColumns(
      children: [
        for (final (i, a) in shown.indexed)
          AssetTile(
            asset: a,
            area: areaNames[a.areaId],
            openJobs: openByAsset[a.id] ?? 0,
          ).entrance(context, index: i.clamp(0, 8)),
      ],
    );
  }
}

/// Cards in one column on phones and two side by side on wide screens.
class CardColumns extends StatelessWidget {
  const CardColumns({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final two = box.maxWidth >= 860;
        final w = two ? (box.maxWidth - Space.sm) / 2 : box.maxWidth;
        return Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [for (final c in children) SizedBox(width: w, child: c)],
        );
      },
    );
  }
}

class AssetTile extends StatelessWidget {
  const AssetTile({
    super.key,
    required this.asset,
    this.area,
    this.openJobs = 0,
  });

  final LocalAsset asset;
  final String? area;
  final int openJobs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = asset;
    final (statusLabel, statusColor) = switch (a.status) {
      'out_of_service' => ('Out of service', Colors.red),
      'standby' => ('Standby', Colors.blueGrey),
      'decommissioned' => ('Decommissioned', Colors.grey),
      _ => (null, null),
    };
    return SurfaceCard(
      onTap: () => context.push('/assets/${a.id}'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(assetIcon(a.kind), color: theme.colorScheme.primary),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RecordCode(a.tag),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Text(
                        a.name,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [?a.kind, ?area].join(' · '),
                  style: theme.textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (statusLabel != null)
            Padding(
              padding: const EdgeInsets.only(left: Space.xs),
              child: Pill(label: statusLabel, color: statusColor, dense: true),
            ),
          if (openJobs > 0)
            Padding(
              padding: const EdgeInsets.only(left: Space.xs),
              child: Pill(
                label: '$openJobs open',
                color: Colors.orange,
                dense: true,
              ),
            ),
        ],
      ),
    );
  }
}

/// Add or edit an asset (supervisors).
class AssetForm extends ConsumerStatefulWidget {
  const AssetForm({super.key, this.asset});

  final LocalAsset? asset;

  @override
  ConsumerState<AssetForm> createState() => _AssetFormState();
}

class _AssetFormState extends ConsumerState<AssetForm> {
  late final _tag = TextEditingController(text: widget.asset?.tag);
  late final _name = TextEditingController(text: widget.asset?.name);
  late final _kind = TextEditingController(text: widget.asset?.kind);
  late final _makeModel = TextEditingController(text: widget.asset?.makeModel);
  late final _serial = TextEditingController(text: widget.asset?.serialNo);
  late final _notes = TextEditingController(text: widget.asset?.notes);
  late String? _areaId = widget.asset?.areaId;
  String? _error;

  @override
  void dispose() {
    for (final c in [_tag, _name, _kind, _makeModel, _serial, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save({bool archive = false}) async {
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    final tag = _tag.text.trim().toUpperCase();
    if (tag.isEmpty) {
      setState(() => _error = 'Give it a tag, e.g. MCC-03');
      return;
    }
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Name the equipment');
      return;
    }
    final clash = (ref.read(siteAssetsProvider).value ?? const []).any(
      (a) => a.tag == tag && a.id != widget.asset?.id,
    );
    if (clash && !archive) {
      setState(() => _error = 'Something else already has the tag $tag');
      return;
    }
    HapticFeedback.mediumImpact();
    await ref
        .read(siteActionsProvider)
        .saveAsset(
          id: widget.asset?.id,
          siteId: widget.asset?.siteId ?? site.id,
          areaId: _areaId,
          tag: tag,
          name: _name.text,
          kind: _kind.text,
          makeModel: _makeModel.text,
          serialNo: _serial.text,
          notes: _notes.text,
          archived: archive,
        );
    if (!mounted) return;
    Navigator.pop(context, !archive);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final areas = site == null ? <LocalArea>[] : session.areasAt(site.id);
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
      child: Text(t, style: theme.textTheme.labelLarge),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.asset == null
                ? 'Add equipment'
                : 'Edit ${widget.asset!.tag}',
            style: theme.textTheme.headlineSmall,
          ),
          label('Tag and name'),
          Row(
            children: [
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _tag,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'MCC-03'),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Primary crusher motor',
                  ),
                ),
              ),
            ],
          ),
          label('Kind'),
          TextField(
            controller: _kind,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Motor, panel…'),
          ),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in assetKinds)
                ChoiceChip(
                  label: Text(k),
                  selected: _kind.text == k,
                  onSelected: (_) => setState(() => _kind.text = k),
                ),
            ],
          ),
          if (areas.isNotEmpty) ...[
            label('Area'),
            DropdownButtonFormField<String?>(
              initialValue: _areaId,
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('No specific area'),
                ),
                for (final a in areas)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => _areaId = v),
            ),
          ],
          label('Make / model and serial (optional)'),
          TextField(
            controller: _makeModel,
            decoration: const InputDecoration(hintText: 'e.g. WEG W22 75 kW'),
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _serial,
            decoration: const InputDecoration(hintText: 'Serial number'),
          ),
          label('Notes (optional)'),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: Space.lg),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(CupertinoIcons.check_mark),
            label: const Text('Save'),
          ),
          if (widget.asset != null) ...[
            const SizedBox(height: Space.xs),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () => _save(archive: true),
              icon: const Icon(CupertinoIcons.archivebox),
              label: const Text('Remove from register'),
            ),
          ],
        ],
      ),
    );
  }
}
