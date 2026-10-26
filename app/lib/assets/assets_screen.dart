import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/local_db.dart';
import '../jobs/job_editor.dart';
import '../jobs/jobs_repository.dart';
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

IconData assetIcon(String? kind) => switch (kind?.toLowerCase()) {
  'motor' || 'pump' => CupertinoIcons.gear_alt_fill,
  'transformer' || 'generator' => CupertinoIcons.bolt_fill,
  'lighting' => CupertinoIcons.lightbulb_fill,
  'cable' => CupertinoIcons.link,
  'instrument' => CupertinoIcons.gauge,
  _ => CupertinoIcons.square_grid_2x2_fill,
};

/// The asset register at the current site.
class AssetsScreen extends ConsumerStatefulWidget {
  const AssetsScreen({super.key});

  @override
  ConsumerState<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends ConsumerState<AssetsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(siteAssetsProvider).value ?? const [];
    final jobs = ref.watch(siteJobsProvider).value ?? const [];
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final canEdit = site != null && session.can('jobs.assign', siteId: site.id);
    final areaNames = {for (final a in session.areas) a.id: a.name};
    final openByAsset = <String, int>{};
    for (final j in jobs) {
      if (j.assetId != null && !{'done', 'cancelled'}.contains(j.status)) {
        openByAsset[j.assetId!] = (openByAsset[j.assetId!] ?? 0) + 1;
      }
    }
    final q = _query.toLowerCase();
    final shown = [
      for (final a in assets)
        if (q.isEmpty ||
            a.tag.toLowerCase().contains(q) ||
            a.name.toLowerCase().contains(q) ||
            (a.kind?.toLowerCase().contains(q) ?? false))
          a,
    ];
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Equipment · ${site?.code ?? ''}'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => showFormSheet(context, const AssetForm()),
              icon: const Icon(CupertinoIcons.add),
              label: const Text('Add equipment'),
            )
          : null,
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: ref.read(jobsSyncProvider.notifier).refresh,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Space.md,
              top + Space.md,
              Space.md,
              120,
            ),
            children: [
              if (assets.isNotEmpty)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Space.md),
                      child: CupertinoSearchTextField(
                        placeholder: 'Search ${assets.length} assets',
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                  ),
                ),
              if (assets.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xl),
                  child: Center(
                    child: EmptyState(
                      icon: CupertinoIcons.gear_alt,
                      title: 'No equipment yet',
                      message: canEdit
                          ? 'Add the motors, panels and transformers you look '
                                'after. Jobs on them build its history.'
                          : 'A supervisor adds the plant you look after here.',
                    ),
                  ),
                ),
              for (final (i, a) in shown.indexed)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: SurfaceCard(
                        onTap: () => context.push('/assets/${a.id}'),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(Radii.md),
                              ),
                              child: Icon(
                                assetIcon(a.kind),
                                color: theme.colorScheme.primary,
                              ),
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
                                    [?a.kind, ?areaNames[a.areaId]].join(' · '),
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                            if ((openByAsset[a.id] ?? 0) > 0)
                              Pill(
                                label: '${openByAsset[a.id]} open',
                                color: Colors.orange,
                                dense: true,
                              ),
                          ],
                        ),
                      ),
                    ).entrance(context, index: i.clamp(0, 8)),
                  ),
                ),
            ],
          ),
        ),
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
        .read(jobActionsProvider)
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
