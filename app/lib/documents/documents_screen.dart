import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:url_launcher/url_launcher.dart';

import '../chat/chat_repository.dart';
import '../data/app_error.dart';
import '../data/site_data.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/theme_mode.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/form_sheet.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'document_detail_screen.dart';
import 'documents_repository.dart';

IconData docIcon(Doc d) {
  final mime = d.current?.mimeType ?? '';
  if (mime.startsWith('image/')) return CupertinoIcons.photo;
  if (d.category == 'drawing') return CupertinoIcons.square_stack_3d_up;
  if (d.category == 'sop') return CupertinoIcons.shield_lefthalf_fill;
  return CupertinoIcons.doc_text_fill;
}

/// The short type label and its usual colour for a file name: PDF red,
/// Word blue, Excel green and so on, as people know them from their PCs.
({String label, Color color}) fileType(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'pdf' => (label: 'PDF', color: const Color(0xFFE5484D)),
    'doc' || 'docx' => (label: 'DOC', color: const Color(0xFF3E7BFA)),
    'xls' || 'xlsx' || 'csv' => (label: 'XLS', color: const Color(0xFF30A46C)),
    'ppt' || 'pptx' => (label: 'PPT', color: const Color(0xFFF59E0B)),
    'dwg' || 'dxf' => (label: 'DWG', color: const Color(0xFFFF7A6B)),
    'png' ||
    'jpg' ||
    'jpeg' ||
    'webp' => (label: 'IMG', color: const Color(0xFFE38FB1)),
    '' => (label: '—', color: const Color(0xFF9AA0A6)),
    _ => (
      label: ext.length > 4 ? 'FILE' : ext.toUpperCase(),
      color: const Color(0xFF9AA0A6),
    ),
  };
}

/// The coloured file-type badge on document tiles.
class FileBadge extends StatelessWidget {
  const FileBadge({super.key, required this.fileName, this.size = 44});

  final String fileName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = fileType(fileName);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(color: t.color.withValues(alpha: 0.45)),
      ),
      child: Text(
        t.label,
        style: TextStyle(
          color: t.color,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.27,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).ceil()} KB';
  if (b < 1024 * 1024 * 1024) {
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

enum _Show { all, toSign, recent, mine }

/// SOPs, drawings and manuals at the current site, in folders, as a grid or
/// a list (API.md section 12b).
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  static const _gridKey = 'documents_grid';

  String? _category;
  _Show _show = _Show.all;
  String _query = '';
  String? _folder;
  late bool _grid = _loadGrid();

  bool _loadGrid() {
    try {
      return ref.read(sharedPrefsProvider).getBool(_gridKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  void _setGrid(bool v) {
    setState(() => _grid = v);
    try {
      ref.read(sharedPrefsProvider).setBool(_gridKey, v);
    } catch (_) {}
  }

  bool get _filtering =>
      _query.isNotEmpty || _category != null || _show != _Show.all;

  Future<void> _folderSheet({DocFolder? folder}) async {
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    await showFormSheet<void>(
      context,
      _FolderForm(siteId: site.id, folder: folder),
    );
  }

  Future<void> _archiveFolder(DocFolder f, int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archive "${f.name}"?'),
        content: Text(
          count == 0
              ? 'The folder is empty.'
              : 'Its $count ${count == 1 ? 'document moves' : 'documents move'} '
                    'out to All documents; nothing is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(documentActionsProvider)
          .saveFolder(
            folder: f,
            siteId: f.siteId,
            name: f.name,
            archived: true,
          );
      if (_folder == f.id) setState(() => _folder = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppError.from(e).message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final docs = ref.watch(documentsProvider);
    final folders = ref.watch(foldersProvider).value ?? const <DocFolder>[];
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final me = ref.watch(authUserIdProvider);
    final canManage =
        site != null && session.can('docs.manage', siteId: site.id);
    final toSign = ref.watch(toSignCountProvider);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final folder = folders.where((f) => f.id == _folder).firstOrNull;

    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: Space.xs),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );

    return PopScope(
      canPop: _folder == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _folder = null);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          leading: _folder == null
              ? const AppBackButton()
              : IconButton(
                  tooltip: 'All documents',
                  icon: const Icon(CupertinoIcons.back),
                  onPressed: () => setState(() => _folder = null),
                ),
          title: Text(
            folder?.name ?? 'Documents · ${site?.code ?? ''}',
            overflow: TextOverflow.ellipsis,
          ),
          flexibleSpace: const GlassSurface(
            radius: 0,
            child: SizedBox.expand(),
          ),
          actions: [
            IconButton(
              tooltip: _grid ? 'Show as a list' : 'Show as a grid',
              icon: Icon(
                _grid
                    ? CupertinoIcons.list_bullet
                    : CupertinoIcons.square_grid_2x2,
              ),
              onPressed: () => _setGrid(!_grid),
            ),
            if (canManage && folder != null)
              PopupMenuButton<String>(
                tooltip: 'Folder',
                icon: const Icon(CupertinoIcons.ellipsis_vertical),
                onSelected: (v) {
                  final count = (docs.value ?? const <Doc>[])
                      .where((d) => d.folderId == folder.id)
                      .length;
                  if (v == 'rename') _folderSheet(folder: folder);
                  if (v == 'archive') _archiveFolder(folder, count);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename folder')),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text('Archive folder'),
                  ),
                ],
              ),
          ],
        ),
        floatingActionButton: canManage
            ? FloatingActionButton.extended(
                onPressed: () => showFormSheet<void>(
                  context,
                  UploadSheet(folderId: _folder),
                ),
                icon: const Icon(CupertinoIcons.cloud_upload),
                label: const Text('Upload'),
              )
            : null,
        body: MeshBackground(
          child: RefreshIndicator(
            edgeOffset: top,
            onRefresh: () async {
              ref.invalidate(foldersProvider);
              ref.invalidate(documentsProvider);
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
                        CupertinoSearchTextField(
                          placeholder: folder == null
                              ? 'Search titles or S- codes'
                              : 'Search in ${folder.name}',
                          onChanged: (v) => setState(() => _query = v),
                        ),
                        const SizedBox(height: Space.sm),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              chip(
                                'All',
                                _show == _Show.all && _category == null,
                                () => setState(() {
                                  _show = _Show.all;
                                  _category = null;
                                }),
                              ),
                              chip(
                                toSign > 0 ? 'To sign ($toSign)' : 'To sign',
                                _show == _Show.toSign,
                                () => setState(() => _show = _Show.toSign),
                              ),
                              chip(
                                'Recent',
                                _show == _Show.recent,
                                () => setState(() => _show = _Show.recent),
                              ),
                              if (canManage)
                                chip(
                                  'Added by me',
                                  _show == _Show.mine,
                                  () => setState(() => _show = _Show.mine),
                                ),
                              Container(
                                width: 1,
                                height: 24,
                                margin: const EdgeInsets.only(right: Space.xs),
                                color: theme.dividerColor,
                              ),
                              for (final c in documentCategories.keys)
                                chip(
                                  categoryLabel(c),
                                  _category == c,
                                  () => setState(
                                    () => _category = _category == c ? null : c,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: Space.md),
                        ...docs.when(
                          loading: () => [
                            const Center(child: CircularProgressIndicator()),
                          ],
                          error: (e, _) => [
                            EmptyState(
                              icon: CupertinoIcons.wifi_slash,
                              title: 'Could not load documents',
                              message: AppError.from(e).isRetryable
                                  ? 'Documents load when you are connected.'
                                  : AppError.from(e).message,
                            ),
                          ],
                          data: (list) =>
                              _body(context, list, folders, canManage, me),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    List<Doc> list,
    List<DocFolder> folders,
    bool canManage,
    String? me,
  ) {
    final theme = Theme.of(context);
    final q = _query.toLowerCase();
    final recent = DateTime.now().subtract(const Duration(days: 30));
    final known = {for (final f in folders) f.id};
    // At the top level, filtering or searching looks in every folder; with
    // nothing chosen it shows the folders and the documents in none.
    final shown = [
      for (final d in list)
        if ((_folder != null
                ? d.folderId == _folder
                : _filtering ||
                      d.folderId == null ||
                      !known.contains(d.folderId)) &&
            (_category == null || d.category == _category) &&
            switch (_show) {
              _Show.all => true,
              _Show.toSign => d.toSign,
              _Show.recent => d.updatedAt.isAfter(recent),
              _Show.mine => d.createdBy == me,
            } &&
            (q.isEmpty ||
                d.title.toLowerCase().contains(q) ||
                d.code.toLowerCase().contains(q)))
          d,
    ];
    if (_show == _Show.recent) {
      shown.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }

    final showFolders = _folder == null && !_filtering;
    final out = <Widget>[];
    if (showFolders && (folders.isNotEmpty || canManage)) {
      out
        ..add(_SectionLabel('Folders'))
        ..add(
          _ResponsiveGrid(
            minWidth: 240,
            minColumns: 1,
            children: [
              for (final f in folders)
                _FolderTile(
                  folder: f,
                  docs: [
                    for (final d in list)
                      if (d.folderId == f.id) d,
                  ],
                  canManage: canManage,
                  onOpen: () => setState(() => _folder = f.id),
                  onRename: () => _folderSheet(folder: f),
                  onArchive: (n) => _archiveFolder(f, n),
                ),
              if (canManage) _NewFolderTile(onTap: () => _folderSheet()),
            ],
          ),
        )
        ..add(const SizedBox(height: Space.md))
        ..add(_SectionLabel(folders.isEmpty ? 'Documents' : 'Not in a folder'));
    }

    if (shown.isEmpty) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: Space.lg),
          child: EmptyState(
            icon: _show == _Show.toSign
                ? CupertinoIcons.checkmark_seal
                : CupertinoIcons.doc_text,
            title: _show == _Show.toSign
                ? 'All signed'
                : list.isEmpty
                ? 'No documents yet'
                : _folder != null && !_filtering
                ? 'This folder is empty'
                : 'Nothing here',
            message: _show == _Show.toSign
                ? 'You have read every SOP that needs it.'
                : list.isEmpty
                ? 'Supervisors upload SOPs, drawings and manuals here.'
                : _folder != null && !_filtering
                ? 'Upload files here, or move documents in from their menu.'
                : 'No documents match.',
          ),
        ),
      );
      return out;
    }

    if (_grid) {
      out.add(
        _ResponsiveGrid(
          minWidth: 170,
          children: [
            for (final d in shown)
              _DocCard(
                doc: d,
                actions: DocMenu(doc: d),
              ),
          ],
        ),
      );
    } else {
      out.add(
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 760;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.md + 44 + Space.sm,
                      0,
                      Space.md + 48,
                      Space.xs,
                    ),
                    child: DefaultTextStyle(
                      style: theme.textTheme.labelSmall!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      child: const Row(
                        children: [
                          Expanded(child: Text('Name')),
                          SizedBox(width: 110, child: Text('Updated')),
                          SizedBox(width: 140, child: Text('Added by')),
                          SizedBox(width: 80, child: Text('Size')),
                          SizedBox(width: 90, child: Text('Signed')),
                        ],
                      ),
                    ),
                  ),
                for (final (i, d) in shown.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: DocTile(
                      doc: d,
                      wide: wide,
                      menu: DocMenu(doc: d),
                    ),
                  ).entrance(context, index: i.clamp(0, 8)),
              ],
            );
          },
        ),
      );
    }
    return out;
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm, left: Space.xs),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Tiles that fill the width, at least [minWidth] each.
class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({
    required this.minWidth,
    required this.children,
    this.minColumns = 2,
  });

  final double minWidth;
  final int minColumns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / minWidth).floor().clamp(minColumns, 6);
        final w = (c.maxWidth - Space.sm * (cols - 1)) / cols;
        return Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final child in children) SizedBox(width: w, child: child),
          ],
        );
      },
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.docs,
    required this.canManage,
    required this.onOpen,
    required this.onRename,
    required this.onArchive,
  });

  final DocFolder folder;
  final List<Doc> docs;
  final bool canManage;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final void Function(int count) onArchive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = docs.fold<int>(0, (n, d) => n + (d.current?.sizeBytes ?? 0));
    final toSign = docs.where((d) => d.toSign).length;
    return SurfaceCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(
        Space.md,
        Space.sm,
        Space.xs,
        Space.sm,
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.folder_fill,
            size: 32,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder.name,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  [
                    '${docs.length} ${docs.length == 1 ? 'file' : 'files'}',
                    if (size > 0) formatBytes(size),
                    if (toSign > 0) '$toSign to sign',
                  ].join(' · '),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          if (canManage)
            PopupMenuButton<String>(
              tooltip: 'Folder',
              icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 18),
              onSelected: (v) {
                if (v == 'rename') onRename();
                if (v == 'archive') onArchive(docs.length);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'archive', child: Text('Archive')),
              ],
            )
          else
            const SizedBox(width: Space.sm),
        ],
      ),
    );
  }
}

class _NewFolderTile extends StatelessWidget {
  const _NewFolderTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.md,
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.folder_badge_plus,
            size: 28,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: Space.sm),
          Text('New folder', style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

/// A document in the grid view.
class _DocCard extends StatelessWidget {
  const _DocCard({required this.doc, required this.actions});

  final Doc doc;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      onTap: () => context.push('/documents/${doc.id}'),
      padding: const EdgeInsets.fromLTRB(
        Space.md,
        Space.md,
        Space.xs,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FileBadge(fileName: doc.fileName, size: 52),
              const Spacer(),
              actions,
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            doc.title,
            style: theme.textTheme.titleSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            [
              doc.code,
              if (doc.current?.sizeBytes case final int b) formatBytes(b),
            ].join(' · '),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              Pill(label: categoryLabel(doc.category), dense: true),
              if (doc.toSign)
                const Pill(
                  label: 'Sign',
                  color: Colors.orange,
                  icon: CupertinoIcons.signature,
                  dense: true,
                )
              else if (doc.signed != null)
                Pill(
                  label: '${doc.signed} signed',
                  color: BrandColors.success,
                  dense: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class DocTile extends ConsumerWidget {
  const DocTile({
    super.key,
    required this.doc,
    this.trailing,
    this.onTap,
    this.menu,
    this.wide = false,
  });

  final Doc doc;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// The ⋮ quick actions, on the Documents screen.
  final Widget? menu;

  /// Columns for updated, added by, size and signatures (wide screens).
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final people = wide
        ? ref.watch(peopleProvider).value ?? const <String, String>{}
        : const <String, String>{};
    final by = people[doc.current?.createdBy ?? doc.createdBy] ?? '';
    final status = doc.toSign
        ? const Pill(
            label: 'Sign',
            color: Colors.orange,
            icon: CupertinoIcons.signature,
            dense: true,
          )
        : doc.needsAck && doc.currentVersion > 0
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.checkmark_seal_fill,
                color: BrandColors.success,
                size: 20,
              ),
              if (doc.signed != null) ...[
                const SizedBox(width: 4),
                Text('${doc.signed}', style: theme.textTheme.labelMedium),
              ],
            ],
          )
        : null;
    return SurfaceCard(
      onTap: onTap ?? () => context.push('/documents/${doc.id}'),
      padding: menu == null
          ? const EdgeInsets.all(Space.md)
          : const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.xs, Space.sm),
      child: Row(
        children: [
          FileBadge(fileName: doc.fileName),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RecordCode(doc.code),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Text(
                        doc.title,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    categoryLabel(doc.category),
                    if (doc.currentVersion > 0)
                      'v${doc.currentVersion}'
                    else
                      'no file yet',
                    if (!wide) relativeDate(context, doc.updatedAt),
                    if (!wide && doc.signed != null) '${doc.signed} signed',
                  ].join(' · '),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          if (wide) ...[
            SizedBox(
              width: 110,
              child: Text(
                relativeDate(context, doc.updatedAt),
                style: theme.textTheme.labelMedium,
              ),
            ),
            SizedBox(
              width: 140,
              child: Text(
                by,
                style: theme.textTheme.labelMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                doc.current?.sizeBytes == null
                    ? ''
                    : formatBytes(doc.current!.sizeBytes!),
                style: theme.textTheme.labelMedium,
              ),
            ),
            SizedBox(
              width: 90,
              child: Align(alignment: Alignment.centerLeft, child: status),
            ),
          ] else if (trailing != null)
            trailing!
          else
            ?status,
          ?menu,
        ],
      ),
    );
  }
}

/// The ⋮ quick actions on a document: open, download, share in a chat or
/// by a 7-day link, and for supervisors move, edit and archive.
class DocMenu extends ConsumerWidget {
  const DocMenu({super.key, required this.doc});

  final Doc doc;

  Future<void> _run(BuildContext context, WidgetRef ref, String action) async {
    final actions = ref.read(documentActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final v = doc.current;
    void say(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));
    try {
      switch (action) {
        case 'open':
          if (v != null) await openDocument(context, ref, v);
        case 'download':
          if (v == null) return;
          await launchUrl(
            Uri.parse(await actions.downloadLink(v)),
            mode: LaunchMode.externalApplication,
          );
        case 'link':
          if (v == null) return;
          final url = await actions.shareLink(v);
          await Clipboard.setData(ClipboardData(text: url));
          say(
            'Link copied. Anyone with it can open ${doc.code} for 7 days, '
            'without the app.',
          );
        case 'chat':
          if (!context.mounted) return;
          final chat = await showFormSheet<Conversation>(
            context,
            const _ChatPicker(),
          );
          if (chat == null) return;
          await ref
              .read(chatActionsProvider)
              .send(
                chat.id,
                text: '${doc.code} · ${doc.title}',
                recordLink: 'doc:${doc.id}',
              );
          say('Shared in ${chat.title}');
        case 'move':
          if (!context.mounted) return;
          final to = await showFormSheet<({String? id})>(
            context,
            _MoveSheet(doc: doc),
          );
          if (to == null) return;
          await actions.move([doc.id], to.id);
          say(to.id == null ? 'Moved out of the folder' : 'Moved');
        case 'edit':
          if (!context.mounted) return;
          await showFormSheet<bool>(context, DocumentForm(doc: doc));
        case 'archive':
          if (!context.mounted) return;
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Archive ${doc.code}?'),
              content: const Text(
                'It leaves the library and job cards; its files and '
                'signatures are kept.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Archive'),
                ),
              ],
            ),
          );
          if (ok != true) return;
          await actions.save(
            doc: doc,
            siteId: doc.siteId,
            title: doc.title,
            category: doc.category,
            needsAck: doc.needsAck,
            archived: true,
          );
          say('${doc.code} archived');
      }
    } catch (e) {
      say(
        AppError.from(e).isRetryable
            ? 'Connect to the internet for that.'
            : AppError.from(e).message,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref
        .watch(sessionProvider)
        .can('docs.manage', siteId: doc.siteId);
    final hasFile = doc.current != null;
    PopupMenuItem<String> item(String value, IconData icon, String label) =>
        PopupMenuItem(
          value: value,
          child: Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: Space.sm),
              Text(label),
            ],
          ),
        );
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 18),
      onSelected: (a) => _run(context, ref, a),
      itemBuilder: (_) => [
        if (hasFile) ...[
          item('open', CupertinoIcons.eye, 'Open'),
          item('download', CupertinoIcons.arrow_down_to_line, 'Download'),
        ],
        item('chat', CupertinoIcons.chat_bubble_2, 'Share in a chat'),
        if (hasFile && canManage)
          item('link', CupertinoIcons.link, 'Copy a 7-day link'),
        if (canManage) ...[
          const PopupMenuDivider(),
          item('move', CupertinoIcons.folder, 'Move to folder'),
          item('edit', CupertinoIcons.pencil, 'Edit or new version'),
          item('archive', CupertinoIcons.archivebox, 'Archive'),
        ],
      ],
    );
  }
}

/// Picks the chat to share a document in.
class _ChatPicker extends ConsumerWidget {
  const _ChatPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final chats = ref.watch(conversationsProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Share in a chat', style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.sm),
          Flexible(
            child: chats.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(AppError.from(e).message),
              data: (list) => ListView(
                shrinkWrap: true,
                children: [
                  for (final c in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: AppAvatar(name: c.title),
                      title: Text(c.title),
                      subtitle: c.isDirect
                          ? null
                          : Text('${c.memberCount} people'),
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks the folder to move a document to.
class _MoveSheet extends ConsumerWidget {
  const _MoveSheet({required this.doc});

  final Doc doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final folders = ref.watch(foldersProvider).value ?? const <DocFolder>[];
    Widget tile(String? id, String name, IconData icon) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(name),
      trailing: doc.folderId == id
          ? const Icon(CupertinoIcons.checkmark_alt)
          : null,
      onTap: doc.folderId == id ? null : () => Navigator.pop(context, (id: id)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Move ${doc.code}', style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.sm),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                tile(null, 'Not in a folder', CupertinoIcons.tray),
                for (final f in folders)
                  tile(f.id, f.name, CupertinoIcons.folder_fill),
              ],
            ),
          ),
          if (folders.isEmpty)
            Text(
              'Make a folder first with New folder on Documents.',
              style: theme.textTheme.labelMedium,
            ),
        ],
      ),
    );
  }
}

/// Creates or renames a folder.
class _FolderForm extends ConsumerStatefulWidget {
  const _FolderForm({required this.siteId, this.folder});

  final String siteId;
  final DocFolder? folder;

  @override
  ConsumerState<_FolderForm> createState() => _FolderFormState();
}

class _FolderFormState extends ConsumerState<_FolderForm> {
  late final _name = TextEditingController(text: widget.folder?.name);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Give the folder a name');
      return;
    }
    final taken = (ref.read(foldersProvider).value ?? const <DocFolder>[]).any(
      (f) =>
          f.id != widget.folder?.id &&
          f.name.toLowerCase() == name.toLowerCase(),
    );
    if (taken) {
      setState(() => _error = 'There is already a folder called $name');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(documentActionsProvider)
          .saveFolder(folder: widget.folder, siteId: widget.siteId, name: name);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = AppError.from(e).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        Space.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.folder == null ? 'New folder' : 'Rename folder',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Substation 3 drawings',
            ),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: Space.md),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(widget.folder == null ? 'Create' : 'Save'),
          ),
        ],
      ),
    );
  }
}

enum _UploadState { waiting, uploading, done, failed }

/// Uploads several files at once, each its own document, with the folder,
/// type and signing chosen once for all of them.
class UploadSheet extends ConsumerStatefulWidget {
  const UploadSheet({super.key, this.folderId});

  final String? folderId;

  @override
  ConsumerState<UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends ConsumerState<UploadSheet> {
  static const _maxBytes = 25 * 1024 * 1024;

  final _files = <({String name, Uint8List bytes})>[];
  final _state = <_UploadState>[];
  late String? _folder = widget.folderId;
  String _category = 'sop';
  bool _needsAck = true;
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'png',
        'jpg',
        'jpeg',
        'webp',
        'docx',
        'doc',
        'xlsx',
        'xls',
        'csv',
        'pptx',
        'ppt',
        'dwg',
        'dxf',
      ],
    );
    if (picked.isEmpty) return;
    final big = <String>[];
    for (final f in picked) {
      final bytes = await f.xFile.readAsBytes();
      if (bytes.length > _maxBytes) {
        big.add(f.name);
        continue;
      }
      _files.add((name: f.name, bytes: bytes));
      _state.add(_UploadState.waiting);
    }
    setState(
      () => _error = big.isEmpty
          ? null
          : '${big.join(', ')} ${big.length == 1 ? 'is' : 'are'} over 25 MB',
    );
  }

  Future<void> _upload() async {
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    if (_files.isEmpty) {
      setState(() => _error = 'Choose the files to upload');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();
    try {
      await ref
          .read(documentActionsProvider)
          .uploadMany(
            siteId: site.id,
            files: List.of(_files),
            category: _category,
            needsAck: _needsAck,
            folderId: _folder,
            onStart: (i) {
              if (mounted) setState(() => _state[i] = _UploadState.uploading);
            },
            onDone: (i) {
              if (mounted) setState(() => _state[i] = _UploadState.done);
            },
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        for (var i = 0; i < _state.length; i++) {
          if (_state[i] == _UploadState.uploading) {
            _state[i] = _UploadState.failed;
          }
        }
        _error = AppError.from(e).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folders = ref.watch(foldersProvider).value ?? const <DocFolder>[];
    final total = _files.fold<int>(0, (n, f) => n + f.bytes.length);
    final done = _state.where((s) => s == _UploadState.done).length;
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
      child: Text(t, style: theme.textTheme.labelLarge),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Upload documents', style: theme.textTheme.headlineSmall),
          Text(
            'Each file becomes its own document, titled from its name; '
            'you can rename it after.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.md),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(CupertinoIcons.paperclip),
            label: Text(_files.isEmpty ? 'Choose files' : 'Add more files'),
          ),
          if (_files.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Text(
              '${_files.length} ${_files.length == 1 ? 'file' : 'files'} · '
              '${formatBytes(total)}'
              '${_busy ? ' · $done of ${_files.length} done' : ''}',
              style: theme.textTheme.labelMedium,
            ),
            if (_busy) ...[
              const SizedBox(height: Space.xs),
              LinearProgressIndicator(value: done / _files.length),
            ],
            for (final (i, f) in _files.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: FileBadge(fileName: f.name, size: 36),
                title: Text(f.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${formatBytes(f.bytes.length)} · ${switch (_state[i]) {
                    _UploadState.waiting => 'waiting',
                    _UploadState.uploading => 'uploading…',
                    _UploadState.done => 'done',
                    _UploadState.failed => 'not sent',
                  }}',
                ),
                trailing: switch (_state[i]) {
                  _UploadState.uploading => const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  _UploadState.done => const Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: BrandColors.success,
                  ),
                  _UploadState.failed => Icon(
                    CupertinoIcons.exclamationmark_circle,
                    color: theme.colorScheme.error,
                  ),
                  _UploadState.waiting =>
                    _busy
                        ? null
                        : IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(CupertinoIcons.xmark, size: 18),
                            onPressed: () => setState(() {
                              _files.removeAt(i);
                              _state.removeAt(i);
                            }),
                          ),
                },
              ),
          ],
          if (folders.isNotEmpty) ...[
            label('Folder'),
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                ChoiceChip(
                  label: const Text('None'),
                  selected: _folder == null,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _folder = null),
                ),
                for (final f in folders)
                  ChoiceChip(
                    avatar: const Icon(CupertinoIcons.folder, size: 16),
                    label: Text(f.name),
                    selected: _folder == f.id,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _folder = f.id),
                  ),
              ],
            ),
          ],
          label('Type'),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final c in documentCategories.keys)
                ChoiceChip(
                  label: Text(categoryLabel(c)),
                  selected: _category == c,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() {
                          _category = c;
                          _needsAck = c == 'sop';
                        }),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Everyone must read and sign'),
            subtitle: const Text('A new version asks them again'),
            value: _needsAck,
            onChanged: _busy ? null : (v) => setState(() => _needsAck = v),
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
            onPressed: _busy || _files.isEmpty ? null : _upload,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(CupertinoIcons.cloud_upload),
            label: Text(
              _files.length > 1 ? 'Upload ${_files.length} files' : 'Upload',
            ),
          ),
        ],
      ),
    );
  }
}

String relativeDate(BuildContext context, DateTime d) =>
    MaterialLocalizations.of(context).formatShortMonthDay(d);

/// Add a document, or edit one and optionally upload a new version.
class DocumentForm extends ConsumerStatefulWidget {
  const DocumentForm({super.key, this.doc});

  final Doc? doc;

  @override
  ConsumerState<DocumentForm> createState() => _DocumentFormState();
}

class _DocumentFormState extends ConsumerState<DocumentForm> {
  late final _title = TextEditingController(text: widget.doc?.title);
  final _note = TextEditingController();
  late String _category = widget.doc?.category ?? 'sop';
  late bool _needsAck = widget.doc?.needsAck ?? true;
  ({String name, Uint8List bytes})? _file;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'png',
        'jpg',
        'jpeg',
        'docx',
        'doc',
        'xlsx',
        'xls',
        'dwg',
      ],
    );
    if (f == null) return;
    final bytes = await f.xFile.readAsBytes();
    if (bytes.length > 25 * 1024 * 1024) {
      setState(() => _error = 'That file is over 25 MB');
      return;
    }
    setState(() {
      _file = (name: f.name, bytes: bytes);
      _error = null;
      if (_title.text.trim().isEmpty) {
        _title.text = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      }
    });
  }

  Future<void> _save({bool archive = false}) async {
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    if (_title.text.trim().length < 3) {
      setState(() => _error = 'Give the document a title');
      return;
    }
    if (widget.doc == null && _file == null) {
      setState(() => _error = 'Choose the file to upload');
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      await ref
          .read(documentActionsProvider)
          .save(
            doc: widget.doc,
            siteId: widget.doc?.siteId ?? site.id,
            title: _title.text,
            category: _category,
            needsAck: _needsAck,
            archived: archive,
            file: _file,
            note: _note.text,
          );
      if (mounted) Navigator.pop(context, !archive);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = AppError.from(e).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
      child: Text(t, style: theme.textTheme.labelLarge),
    );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        Space.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.doc == null ? 'Add document' : 'Edit ${widget.doc!.code}',
            style: theme.textTheme.headlineSmall,
          ),
          label(widget.doc == null ? 'File' : 'New version (optional)'),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(CupertinoIcons.paperclip),
            label: Text(
              _file == null
                  ? 'Choose PDF, drawing or image'
                  : '${_file!.name} · ${(_file!.bytes.length / 1024).ceil()} KB',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.doc != null && _file != null) ...[
            const SizedBox(height: Space.sm),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                hintText: 'What changed? (optional)',
              ),
            ),
          ],
          label('Title'),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Isolation and LOTO procedure',
            ),
          ),
          label('Category'),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final c in documentCategories.keys)
                ChoiceChip(
                  label: Text(categoryLabel(c)),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Everyone must read and sign'),
            subtitle: const Text('A new version asks them again'),
            value: _needsAck,
            onChanged: (v) => setState(() => _needsAck = v),
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
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(CupertinoIcons.cloud_upload),
            label: Text(widget.doc == null ? 'Upload' : 'Save'),
          ),
          if (widget.doc != null) ...[
            const SizedBox(height: Space.xs),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: _busy ? null : () => _save(archive: true),
              icon: const Icon(CupertinoIcons.archivebox),
              label: const Text('Archive document'),
            ),
          ],
        ],
      ),
    );
  }
}
