import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_error.dart';
import '../data/local_db.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/form_sheet.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';

/// Settings → Sites and areas (admin.sites): add, rename or archive sites
/// and the areas inside them. Online only (API.md, migration 0021).
class SitesScreen extends ConsumerWidget {
  const SitesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final sites = [...session.sites]
      ..sort((a, b) {
        if (a.isArchived != b.isArchived) return a.isArchived ? 1 : -1;
        return a.name.compareTo(b.name);
      });
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/settings'),
        title: const Text('Sites and areas'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showFormSheet(context, const _SiteForm()),
        icon: const Icon(CupertinoIcons.add),
        label: const Text('Add site'),
      ),
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: ref.read(sessionProvider.notifier).refresh,
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
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Areas are the places inside a site that job cards, '
                        'equipment and checklists point to.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: Space.md),
                      for (final (i, s) in sites.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: _SiteCard(
                            site: s,
                            areas:
                                [
                                  for (final a in session.areas)
                                    if (a.siteId == s.id) a,
                                ]..sort((a, b) {
                                  if (a.isArchived != b.isArchived) {
                                    return a.isArchived ? 1 : -1;
                                  }
                                  return a.name.compareTo(b.name);
                                }),
                          ),
                        ).entrance(context, index: i.clamp(0, 8)),
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

class _SiteCard extends StatelessWidget {
  const _SiteCard({required this.site, required this.areas});

  final LocalSite site;
  final List<LocalArea> areas;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = areas.where((a) => !a.isArchived).length;
    return Opacity(
      opacity: site.isArchived ? 0.6 : 1,
      child: SurfaceCard(
        padding: EdgeInsets.zero,
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            shape: const Border(),
            leading: Pill(label: site.code),
            title: Text(site.name, style: theme.textTheme.titleSmall),
            subtitle: Text(
              site.isArchived
                  ? 'Archived'
                  : '$live ${live == 1 ? 'area' : 'areas'}',
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              Space.md,
              0,
              Space.md,
              Space.md,
            ),
            children: [
              for (final a in areas)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    a.isArchived
                        ? CupertinoIcons.archivebox
                        : CupertinoIcons.location,
                    size: 18,
                  ),
                  title: Text(
                    a.name,
                    style: a.isArchived
                        ? const TextStyle(
                            decoration: TextDecoration.lineThrough,
                          )
                        : null,
                  ),
                  trailing: const Icon(CupertinoIcons.pencil, size: 16),
                  onTap: () => showFormSheet(
                    context,
                    _AreaForm(siteId: site.id, area: a),
                  ),
                ),
              const SizedBox(height: Space.xs),
              Row(
                children: [
                  if (!site.isArchived)
                    TextButton.icon(
                      onPressed: () =>
                          showFormSheet(context, _AreaForm(siteId: site.id)),
                      icon: const Icon(CupertinoIcons.add, size: 18),
                      label: const Text('Add area'),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () =>
                        showFormSheet(context, _SiteForm(site: site)),
                    icon: const Icon(CupertinoIcons.pencil, size: 18),
                    label: const Text('Edit site'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared shape of the two forms: fields, an error, a save button.
abstract class _FormState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> {
  bool busy = false;
  String? error;

  Future<void> run(Future<void> Function() save) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await save();
      await ref.read(sessionProvider.notifier).refresh();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = AppError.from(e).message;
        });
      }
    }
  }

  Widget frame(String title, List<Widget> fields, VoidCallback onSave) {
    final theme = Theme.of(context);
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
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.md),
          ...fields,
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed: busy ? null : onSave,
            child: Text(busy ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class _SiteForm extends ConsumerStatefulWidget {
  const _SiteForm({this.site});

  final LocalSite? site;

  @override
  ConsumerState<_SiteForm> createState() => _SiteFormState();
}

class _SiteFormState extends _FormState<_SiteForm> {
  late final _code = TextEditingController(text: widget.site?.code);
  late final _name = TextEditingController(text: widget.site?.name);
  late bool _archived = widget.site?.isArchived ?? false;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return frame(
      widget.site == null ? 'Add a site' : 'Edit ${widget.site!.code}',
      [
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          maxLength: 5,
          decoration: const InputDecoration(
            labelText: 'Code',
            helperText: '2 to 5 letters, shown on job card numbers',
          ),
        ),
        const SizedBox(height: Space.sm),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        if (widget.site != null)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Archived'),
            subtitle: const Text('Hidden from pickers; records are kept'),
            value: _archived,
            onChanged: (v) => setState(() => _archived = v),
          ),
      ],
      () => run(
        () => ref
            .read(supabaseProvider)
            .rpc(
              'fn_save_site',
              params: {
                'p_id': widget.site?.id,
                'p_code': _code.text,
                'p_name': _name.text,
                'p_archived': _archived,
              },
            ),
      ),
    );
  }
}

class _AreaForm extends ConsumerStatefulWidget {
  const _AreaForm({required this.siteId, this.area});

  final String siteId;
  final LocalArea? area;

  @override
  ConsumerState<_AreaForm> createState() => _AreaFormState();
}

class _AreaFormState extends _FormState<_AreaForm> {
  late final _name = TextEditingController(text: widget.area?.name);
  late bool _archived = widget.area?.isArchived ?? false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return frame(
      widget.area == null ? 'Add an area' : 'Edit area',
      [
        TextField(
          controller: _name,
          autofocus: widget.area == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g. Plant – Crusher',
          ),
        ),
        if (widget.area != null)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Archived'),
            subtitle: const Text('Hidden from pickers; records are kept'),
            value: _archived,
            onChanged: (v) => setState(() => _archived = v),
          ),
      ],
      () => run(
        () => ref
            .read(supabaseProvider)
            .rpc(
              'fn_save_area',
              params: {
                'p_id': widget.area?.id,
                'p_site': widget.siteId,
                'p_name': _name.text,
                'p_archived': _archived,
              },
            ),
      ),
    );
  }
}
