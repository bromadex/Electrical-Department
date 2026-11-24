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
import '../v2/site_filter.dart';
import '../widgets/app_back_button.dart';
import 'document_detail_screen.dart';
import 'documents_repository.dart';
import 'drop/drop_files.dart';
import 'offline/offline_docs.dart';
import 'viewer/file_viewer.dart' show viewerLabel;

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
    'dwg' => (label: 'DWG', color: const Color(0xFFFF7A6B)),
    'dxf' => (label: 'DXF', color: const Color(0xFFFF7A6B)),
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

enum _Show { all, starred, offline, toSign, recent, mine }

/// How files are ordered (folders always by name).
enum _Sort { name, updated, size, type }

/// SOPs, drawings and manuals at the current site, in folders, as a grid or
/// a list (API.md section 12b).
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  static const _gridKey = 'documents_grid';
  static const _sortKey = 'documents_sort';

  String? _category;
  _Show _show = _Show.all;
  String _query = '';
  final _search = TextEditingController();

  /// The folder being looked at; null is the top of the library.
  String? _folder;
  late bool _grid = _loadGrid();
  late _Sort _sort = _loadSort();

  /// Documents ticked for Move, Share, Star or Archive together.
  final _selected = <String>{};
  bool _selectMode = false;
  bool get _selecting => _selectMode || _selected.isNotEmpty;

  void _clearSelection() => setState(() {
    _selected.clear();
    _selectMode = false;
  });

  /// Files are being dragged over the page (browser).
  bool _dragging = false;
  Object? _drops;

  @override
  void initState() {
    super.initState();
    _drops = listenForDrops(
      onOver: (over) {
        if (mounted && over != _dragging && _canUpload) {
          setState(() => _dragging = over);
        }
      },
      onDrop: (files) {
        if (!mounted || !_canUpload) return;
        setState(() => _dragging = false);
        showFormSheet<void>(
          context,
          UploadSheet(folderId: _folder, dropped: files),
        );
      },
    );
  }

  @override
  void dispose() {
    stopListening(_drops);
    _search.dispose();
    super.dispose();
  }

  _Sort _loadSort() {
    try {
      final v = ref.read(sharedPrefsProvider).getString(_sortKey);
      return _Sort.values.firstWhere(
        (e) => e.name == v,
        orElse: () => _Sort.name,
      );
    } catch (_) {
      return _Sort.name;
    }
  }

  void _setSort(_Sort v) {
    setState(() => _sort = v);
    try {
      ref.read(sharedPrefsProvider).setString(_sortKey, v.name);
    } catch (_) {}
  }

  /// Opens a folder (null: the top), clearing the search and selection.
  void _open(String? folder) {
    setState(() {
      _folder = folder;
      _selected.clear();
      _selectMode = false;
    });
  }

  void _toggle(Doc d) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.remove(d.id)) _selected.add(d.id);
    });
  }

  bool get _canUpload => ref.read(sessionProvider).canAnywhere('docs.manage');

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

  /// Searching, filtering or All my sites lists documents from every folder
  /// (folders belong to one site).
  bool get _filtering =>
      _query.isNotEmpty ||
      _category != null ||
      _show != _Show.all ||
      (ref.read(siteFilterProvider) == null);

  Future<void> _folderSheet({DocFolder? folder}) async {
    // Inside a folder: its site; at the top: the filtered or home site.
    final site = folder?.siteId ?? _siteFor(ref, _folder);
    if (site == null) return;
    await showFormSheet<void>(
      context,
      _FolderForm(siteId: site, folder: folder, parentId: _folder),
    );
  }

  /// Moves a folder (with what is in it) somewhere else.
  Future<void> _moveFolder(DocFolder f) async {
    final folders = ref.read(foldersProvider).value ?? const <DocFolder>[];
    final to = await showFormSheet<({String? id})>(
      context,
      MoveSheet(
        title: 'Move ${f.name}',
        current: f.parentId,
        exclude: folderTree(folders, f.id),
      ),
    );
    if (to == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(documentActionsProvider).moveFolder(f.id, to.id);
      messenger.showSnackBar(SnackBar(content: Text('Moved ${f.name}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(AppError.from(e).message)));
    }
  }

  /// Runs an action on every ticked document.
  Future<void> _bulk(String action, List<Doc> all) async {
    final docs = [
      for (final d in all)
        if (_selected.contains(d.id)) d,
    ];
    if (docs.isEmpty) return;
    final actions = ref.read(documentActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    void say(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));
    final n = '${docs.length} ${docs.length == 1 ? 'file' : 'files'}';
    try {
      switch (action) {
        case 'move':
          final to = await showFormSheet<({String? id})>(
            context,
            MoveSheet(title: 'Move $n', current: _folder),
          );
          if (to == null) return;
          await actions.move([for (final d in docs) d.id], to.id);
          say('Moved $n');
        case 'star':
          final starred = ref.read(starredDocsProvider);
          final on = !docs.every((d) => starred.contains(d.id));
          await actions.star([for (final d in docs) d.id], on);
          say(on ? 'Starred $n' : 'Took the star off $n');
        case 'chat':
          final chat = await showFormSheet<Conversation>(
            context,
            const _ChatPicker(),
          );
          if (chat == null) return;
          await shareInChat(ref, chat.id, docs);
          say('Shared $n in ${chat.title}');
        case 'archive':
          if (!mounted) return;
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Archive $n?'),
              content: const Text(
                'They leave the library and job cards; their files and '
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
          for (final d in docs) {
            await actions.save(
              doc: d,
              siteId: d.siteId,
              title: d.title,
              category: d.category,
              needsAck: d.needsAck,
              archived: true,
              reload: false,
            );
          }
          ref.invalidate(documentsProvider);
          say('Archived $n');
      }
      if (mounted) _clearSelection();
    } catch (e) {
      say(
        AppError.from(e).isRetryable
            ? 'Connect to the internet for that.'
            : AppError.from(e).message,
      );
    }
  }

  /// A document dragged onto a folder moves into it.
  Future<void> _dropInto(Doc d, DocFolder f) async {
    if (d.folderId == f.id) return;
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(documentActionsProvider).move([d.id], f.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Moved ${d.title} to ${f.name}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () =>
                ref.read(documentActionsProvider).move([d.id], d.folderId),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(AppError.from(e).message)));
    }
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
                    'up a level, and its folders are archived with it; '
                    'nothing is deleted.',
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
      final folders = ref.read(foldersProvider).value ?? const <DocFolder>[];
      if (_folder != null && folderTree(folders, f.id).contains(_folder)) {
        _open(f.parentId);
      }
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
    (ref.watch(siteFilterProvider) == null);
    ref.watch(offlineRefreshProvider);
    final folders = ref.watch(foldersProvider).value ?? const <DocFolder>[];
    final session = ref.watch(sessionProvider);
    final me = ref.watch(authUserIdProvider);
    final canManage = session.canAnywhere('docs.manage');
    final toSign = ref.watch(toSignCountProvider);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final folder = folders.where((f) => f.id == _folder).firstOrNull;
    final path = folderPath(folders, _folder);
    final all = docs.value ?? const <Doc>[];

    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: Space.xs),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );

    // Back: out of selecting first, then up a folder, then off the page.
    return PopScope(
      canPop: _folder == null && !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selecting) {
          _clearSelection();
        } else {
          _open(folder?.parentId);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          leading: _selecting
              ? IconButton(
                  tooltip: 'Clear selection',
                  icon: const Icon(CupertinoIcons.xmark),
                  onPressed: _clearSelection,
                )
              : _folder == null
              ? const AppBackButton()
              : IconButton(
                  tooltip: path.length > 1 ? path[path.length - 2].name : 'Up',
                  icon: const Icon(CupertinoIcons.back),
                  onPressed: () => _open(folder?.parentId),
                ),
          title: Text(
            _selecting
                ? '${_selected.length} selected'
                : folder?.name ?? 'Documents',
            overflow: TextOverflow.ellipsis,
          ),
          flexibleSpace: const GlassSurface(
            radius: 0,
            child: SizedBox.expand(),
          ),
          actions: [
            if (!_selecting)
              IconButton(
                tooltip: 'Select files',
                icon: const Icon(CupertinoIcons.checkmark_circle),
                onPressed: () => setState(() => _selectMode = true),
              ),
            PopupMenuButton<_Sort>(
              tooltip: 'Sort',
              icon: const Icon(CupertinoIcons.arrow_up_arrow_down),
              initialValue: _sort,
              onSelected: _setSort,
              itemBuilder: (_) => [
                for (final (v, label) in const [
                  (_Sort.name, 'Name'),
                  (_Sort.updated, 'Last updated'),
                  (_Sort.size, 'Size'),
                  (_Sort.type, 'Type'),
                ])
                  CheckedPopupMenuItem(
                    value: v,
                    checked: _sort == v,
                    child: Text(label),
                  ),
              ],
            ),
            IconButton(
              tooltip: _grid ? 'Show as a list' : 'Show as a grid',
              icon: Icon(
                _grid
                    ? CupertinoIcons.list_bullet
                    : CupertinoIcons.square_grid_2x2,
              ),
              onPressed: () => _setGrid(!_grid),
            ),
            if (canManage && folder != null && !_selecting)
              PopupMenuButton<String>(
                tooltip: 'Folder',
                icon: const Icon(CupertinoIcons.ellipsis_vertical),
                onSelected: (v) {
                  final count = all
                      .where((d) => d.folderId == folder.id)
                      .length;
                  if (v == 'rename') _folderSheet(folder: folder);
                  if (v == 'move') _moveFolder(folder);
                  if (v == 'archive') _archiveFolder(folder, count);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename folder')),
                  PopupMenuItem(value: 'move', child: Text('Move folder')),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text('Archive folder'),
                  ),
                ],
              ),
          ],
        ),
        bottomNavigationBar: _selecting
            ? _SelectionBar(
                count: _selected.length,
                canManage: canManage,
                allStarred: _selected.every(
                  ref.watch(starredDocsProvider).contains,
                ),
                onAction: (a) => _bulk(a, all),
              )
            : null,
        floatingActionButton: canManage && !_selecting
            ? FloatingActionButton.extended(
                onPressed: () => showFormSheet<void>(
                  context,
                  UploadSheet(folderId: _folder),
                ),
                icon: const Icon(CupertinoIcons.cloud_upload),
                label: const Text('Upload'),
              )
            : null,
        body: Stack(
          children: [
            MeshBackground(
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
                            if (path.isNotEmpty) ...[
                              _Breadcrumbs(path: path, onOpen: _open),
                              const SizedBox(height: Space.xs),
                            ],
                            CupertinoSearchTextField(
                              controller: _search,
                              placeholder: folder == null
                                  ? 'Search every folder: name, code or file'
                                  : 'Search in ${folder.name} and its folders',
                              onChanged: (v) => setState(() => _query = v),
                            ),
                            const SizedBox(height: Space.sm),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  if (_folder == null) ...[
                                    const SiteFilterChip(),
                                    const SizedBox(width: Space.xs),
                                  ],
                                  chip(
                                    'All',
                                    _show == _Show.all && _category == null,
                                    () => setState(() {
                                      _show = _Show.all;
                                      _category = null;
                                    }),
                                  ),
                                  chip(
                                    'Starred',
                                    _show == _Show.starred,
                                    () => setState(() => _show = _Show.starred),
                                  ),
                                  if (OfflineDocs.supported)
                                    chip(
                                      'On this phone',
                                      _show == _Show.offline,
                                      () =>
                                          setState(() => _show = _Show.offline),
                                    ),
                                  chip(
                                    toSign > 0
                                        ? 'To sign ($toSign)'
                                        : 'To sign',
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
                                    margin: const EdgeInsets.only(
                                      right: Space.xs,
                                    ),
                                    color: theme.dividerColor,
                                  ),
                                  for (final c in documentCategories.keys)
                                    chip(
                                      categoryLabel(c),
                                      _category == c,
                                      () => setState(
                                        () => _category = _category == c
                                            ? null
                                            : c,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: Space.md),
                            ...docs.when(
                              loading: () => [
                                const Center(
                                  child: CircularProgressIndicator(),
                                ),
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
            if (_dragging)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: const EdgeInsets.all(Space.lg),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(Radii.xl),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(CupertinoIcons.cloud_upload, size: 56),
                        const SizedBox(height: Space.sm),
                        Text(
                          'Drop files to upload them here',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
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
    final starred = ref.watch(starredDocsProvider);
    final kept = ref.watch(offlineDocsProvider);
    final known = {for (final f in folders) f.id};
    // Where to look: this folder only, or (searching or filtering) this
    // folder and every folder under it; at the top, everything.
    final tree = _folder == null ? null : folderTree(folders, _folder!);
    bool here(Doc d) {
      final f = d.folderId != null && known.contains(d.folderId)
          ? d.folderId
          : null;
      if (_filtering) return tree == null || tree.contains(f);
      return f == _folder;
    }

    final shown = [
      for (final d in list)
        if (here(d) &&
            (_category == null || d.category == _category) &&
            switch (_show) {
              _Show.all => true,
              _Show.starred => starred.contains(d.id),
              _Show.offline => kept.containsKey(d.id),
              _Show.toSign => d.toSign,
              _Show.recent => d.updatedAt.isAfter(recent),
              _Show.mine => d.createdBy == me,
            } &&
            (q.isEmpty ||
                d.title.toLowerCase().contains(q) ||
                d.code.toLowerCase().contains(q) ||
                d.fileName.toLowerCase().contains(q)))
          d,
    ];
    int bySort(Doc a, Doc b) => switch (_sort) {
      _Sort.name => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      _Sort.updated => b.updatedAt.compareTo(a.updatedAt),
      _Sort.size => (b.current?.sizeBytes ?? 0).compareTo(
        a.current?.sizeBytes ?? 0,
      ),
      _Sort.type => fileType(
        a.fileName,
      ).label.compareTo(fileType(b.fileName).label),
    };
    shown.sort(
      _show == _Show.recent
          ? (a, b) => b.updatedAt.compareTo(a.updatedAt)
          : bySort,
    );

    final showFolders = !_filtering;
    final subfolders = [
      for (final f in folders)
        if (f.parentId == _folder ||
            (_folder == null &&
                f.parentId != null &&
                !known.contains(f.parentId)))
          f,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final dragOk = canManage && showFolders && !_selecting;
    final out = <Widget>[];
    if (showFolders && (subfolders.isNotEmpty || canManage)) {
      out
        ..add(_SectionLabel('Folders'))
        ..add(
          _ResponsiveGrid(
            minWidth: 240,
            minColumns: 1,
            children: [
              for (final f in subfolders)
                Builder(
                  builder: (context) {
                    final inside = folderTree(folders, f.id);
                    return _FolderTile(
                      folder: f,
                      docs: [
                        for (final d in list)
                          if (inside.contains(d.folderId)) d,
                      ],
                      folders: inside.length - 1,
                      canManage: canManage,
                      onDrop: dragOk ? (d) => _dropInto(d, f) : null,
                      onOpen: () => _open(f.id),
                      onRename: () => _folderSheet(folder: f),
                      onMove: () => _moveFolder(f),
                      onArchive: (n) => _archiveFolder(f, n),
                    );
                  },
                ),
              if (canManage) _NewFolderTile(onTap: () => _folderSheet()),
            ],
          ),
        )
        ..add(const SizedBox(height: Space.md))
        ..add(_SectionLabel('Files'));
    } else if (_filtering && shown.isNotEmpty) {
      out.add(
        _SectionLabel(
          '${shown.length} ${shown.length == 1 ? 'file' : 'files'}'
          '${_folder == null ? '' : ' in this folder and its folders'}',
        ),
      );
    }

    if (shown.isEmpty) {
      // Only folders at this level: no "Files" heading, nothing to explain.
      if (showFolders && subfolders.isNotEmpty) {
        out.removeLast();
        return out;
      }
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: Space.lg),
          child: EmptyState(
            icon: _show == _Show.toSign
                ? CupertinoIcons.checkmark_seal
                : _show == _Show.starred
                ? CupertinoIcons.star
                : CupertinoIcons.doc_text,
            title: _show == _Show.toSign
                ? 'All signed'
                : _show == _Show.starred
                ? 'Nothing starred yet'
                : _show == _Show.offline
                ? 'Nothing kept on this phone'
                : list.isEmpty
                ? 'No documents yet'
                : _folder != null && !_filtering
                ? 'No files here'
                : 'Nothing here',
            message: _show == _Show.toSign
                ? 'You have read every SOP that needs it.'
                : _show == _Show.starred
                ? 'Star the files you use most (⋮ → Star) to find them here.'
                : _show == _Show.offline
                ? 'Keep SOPs and drawings on this phone (⋮ → Keep on this '
                      'phone) to open them on site without signal.'
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

    Widget pick(Doc d, Widget child) => _Selectable(
      selected: _selected.contains(d.id),
      selecting: _selecting,
      onToggle: () => _toggle(d),
      child: child,
    );
    String? where(Doc d) => _filtering && d.folderId != null
        ? folderPath(folders, d.folderId).map((f) => f.name).join(' › ')
        : null;

    if (_grid) {
      out.add(
        _ResponsiveGrid(
          minWidth: 170,
          children: [
            for (final d in shown)
              _DraggableDoc(
                doc: d,
                enabled: dragOk && subfolders.isNotEmpty,
                child: pick(
                  d,
                  _DocCard(
                    doc: d,
                    starred: starred.contains(d.id),
                    actions: DocMenu(doc: d),
                  ),
                ),
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
                    child: _DraggableDoc(
                      doc: d,
                      enabled: dragOk && subfolders.isNotEmpty,
                      child: pick(
                        d,
                        DocTile(
                          doc: d,
                          wide: wide,
                          where: where(d),
                          menu: _selecting ? null : DocMenu(doc: d),
                        ),
                      ),
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
    required this.onMove,
    required this.onArchive,
    this.folders = 0,
    this.onDrop,
  });

  final DocFolder folder;

  /// Documents in it and in its folders.
  final List<Doc> docs;

  /// How many folders are inside it (at any depth).
  final int folders;
  final bool canManage;
  final VoidCallback onMove;

  /// A document dropped on the folder (null: not a drop target).
  final ValueChanged<Doc>? onDrop;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final void Function(int count) onArchive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = docs.fold<int>(0, (n, d) => n + (d.current?.sizeBytes ?? 0));
    final toSign = docs.where((d) => d.toSign).length;
    final drop = onDrop;
    if (drop == null) return _tile(theme, size, toSign, false);
    return DragTarget<Doc>(
      onWillAcceptWithDetails: (d) => d.data.folderId != folder.id,
      onAcceptWithDetails: (d) => drop(d.data),
      builder: (context, over, _) =>
          _tile(theme, size, toSign, over.isNotEmpty),
    );
  }

  Widget _tile(ThemeData theme, int size, int toSign, bool over) {
    final card = SurfaceCard(
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
                    if (folders > 0)
                      '$folders ${folders == 1 ? 'folder' : 'folders'}',
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
                if (v == 'move') onMove();
                if (v == 'archive') onArchive(docs.length);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'move', child: Text('Move')),
                PopupMenuItem(value: 'archive', child: Text('Archive')),
              ],
            )
          else
            const SizedBox(width: Space.sm),
        ],
      ),
    );
    // Lit up while a document is held over it.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: over ? theme.colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: AnimatedScale(
        scale: over ? 1.03 : 1,
        duration: const Duration(milliseconds: 150),
        child: card,
      ),
    );
  }
}

/// A document that can be dragged onto a folder with a mouse. On phones a
/// long press selects it instead (then Move).
class _DraggableDoc extends StatelessWidget {
  const _DraggableDoc({
    required this.doc,
    required this.enabled,
    required this.child,
  });

  final Doc doc;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final theme = Theme.of(context);
    final feedback = Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(Radii.md),
          boxShadow: const [BoxShadow(blurRadius: 16, color: Colors.black38)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FileBadge(fileName: doc.fileName, size: 32),
            const SizedBox(width: Space.sm),
            Flexible(
              child: Text(
                doc.title,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
    final dimmed = Opacity(opacity: 0.4, child: child);
    final touch = switch (theme.platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    // Phones: a long press selects (then Move); dragging is for the mouse.
    return touch
        ? child
        : Draggable<Doc>(
            data: doc,
            feedback: feedback,
            childWhenDragging: dimmed,
            child: child,
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
  const _DocCard({
    required this.doc,
    required this.actions,
    this.starred = false,
  });

  final Doc doc;
  final Widget actions;
  final bool starred;

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
              if (starred)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Icon(
                    CupertinoIcons.star_fill,
                    size: 16,
                    color: Colors.amber,
                  ),
                ),
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
    this.where,
  });

  final Doc doc;

  /// The folder it is in, shown while searching ("Drawings › MCC-3").
  final String? where;
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
                    if ((ref.watch(siteFilterProvider) == null)) ...[
                      const SizedBox(width: Space.xs),
                      Pill(
                        label:
                            ref
                                .watch(sessionProvider)
                                .siteById(doc.siteId)
                                ?.code ??
                            '',
                        dense: true,
                      ),
                    ],
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Text(
                        doc.title,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (ref.watch(offlineDocsProvider).containsKey(doc.id))
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(
                          CupertinoIcons.arrow_down_circle_fill,
                          size: 14,
                          color: BrandColors.success,
                        ),
                      ),
                    if (ref.watch(starredDocsProvider).contains(doc.id))
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(
                          CupertinoIcons.star_fill,
                          size: 14,
                          color: Colors.amber,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (where != null) '📁 $where',
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
          await shareInChat(ref, chat.id, [doc]);
          say('Shared in ${chat.title}');
        case 'move':
          if (!context.mounted) return;
          final to = await showFormSheet<({String? id})>(
            context,
            MoveSheet(title: 'Move ${doc.code}', current: doc.folderId),
          );
          if (to == null) return;
          await actions.move([doc.id], to.id);
          say(to.id == null ? 'Moved to the top of Documents' : 'Moved');
        case 'star':
          final on = !ref.read(starredDocsProvider).contains(doc.id);
          await actions.star([doc.id], on);
          say(on ? 'Starred ${doc.code}' : 'Took the star off ${doc.code}');
        case 'rename':
          if (!context.mounted) return;
          final name = await showDialog<String>(
            context: context,
            builder: (context) => _RenameDialog(title: doc.title),
          );
          if (name == null || name == doc.title) return;
          await actions.save(
            doc: doc,
            siteId: doc.siteId,
            title: name,
            category: doc.category,
            needsAck: doc.needsAck,
          );
          say('Renamed to $name');
        case 'properties':
          if (!context.mounted) return;
          await showFormSheet<void>(context, DocProperties(doc: doc));
        case 'keep':
          await ref.read(offlineDocsProvider.notifier).keep(doc);
          say('${doc.code} is on this phone: it opens without signal');
        case 'unkeep':
          await ref.read(offlineDocsProvider.notifier).remove(doc.id);
          say('Removed ${doc.code} from this phone');
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
    final starred = ref.watch(starredDocsProvider).contains(doc.id);
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
        item(
          'star',
          starred ? CupertinoIcons.star_slash : CupertinoIcons.star,
          starred ? 'Unstar' : 'Star',
        ),
        if (hasFile && OfflineDocs.supported)
          ref.watch(offlineDocsProvider).containsKey(doc.id)
              ? item(
                  'unkeep',
                  CupertinoIcons.checkmark_circle_fill,
                  'Remove from this phone',
                )
              : item(
                  'keep',
                  CupertinoIcons.arrow_down_circle,
                  'Keep on this phone',
                ),
        item('properties', CupertinoIcons.info, 'Properties'),
        if (hasFile && canManage)
          item('link', CupertinoIcons.link, 'Copy a 7-day link'),
        if (canManage) ...[
          const PopupMenuDivider(),
          item('rename', CupertinoIcons.textformat, 'Rename'),
          item('move', CupertinoIcons.folder, 'Move to folder'),
          item('edit', CupertinoIcons.pencil, 'Edit or new version'),
          item('archive', CupertinoIcons.archivebox, 'Archive'),
        ],
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.title});

  final String title;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.title);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final v = _name.text.trim();
    if (v.length >= 3) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 160,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _done(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _done, child: const Text('Rename')),
      ],
    );
  }
}

/// A file's details: type, size, version, folder, who added it, signatures,
/// and the chats it is tagged in.
class DocProperties extends ConsumerWidget {
  const DocProperties({super.key, required this.doc});

  final Doc doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final v = doc.current;
    final people = ref.watch(peopleProvider).value ?? const <String, String>{};
    final folders = ref.watch(foldersProvider).value ?? const <DocFolder>[];
    final where = folderPath(folders, doc.folderId).map((f) => f.name);
    final mentions = ref.watch(documentMentionsProvider(doc.id));
    final dates = MaterialLocalizations.of(context);
    String when(DateTime t) =>
        '${dates.formatMediumDate(t)}, ${TimeOfDay.fromDateTime(t).format(context)}';
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FileBadge(fileName: doc.fileName, size: 48),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(doc.title, style: theme.textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            row('Code', doc.code),
            row(
              'Type',
              '${fileType(doc.fileName).label} · '
                  '${categoryLabel(doc.category)}',
            ),
            if (v != null) row('File', v.fileName),
            if (v?.sizeBytes != null) row('Size', formatBytes(v!.sizeBytes!)),
            row(
              'Version',
              doc.currentVersion == 0
                  ? 'No file yet'
                  : 'v${doc.currentVersion} of ${doc.versions.length}',
            ),
            row(
              'Folder',
              where.isEmpty ? 'Top of Documents' : where.join(' › '),
            ),
            if (people[v?.createdBy ?? doc.createdBy] case final String by)
              row('Added by', by),
            if (v != null) row('Uploaded', when(v.createdAt)),
            row('Updated', when(doc.updatedAt)),
            if (ref.watch(offlineDocsProvider)[doc.id] case final kept?)
              row(
                'On this phone',
                'v${kept.version} · ${formatBytes(kept.size)} · '
                    'saved ${when(kept.savedAt)}',
              ),
            row('Opens in', viewerLabel(doc.fileName)),
            if (doc.needsAck)
              row(
                'Signing',
                doc.signed == null
                    ? 'Everyone reads and signs it'
                    : '${doc.signed} signed this version',
              ),
            const SizedBox(height: Space.md),
            Text('Tagged in', style: theme.textTheme.titleSmall),
            const SizedBox(height: Space.xs),
            mentions.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(
                AppError.from(e).isRetryable
                    ? 'Shows when you are connected.'
                    : AppError.from(e).message,
              ),
              data: (list) => list.isEmpty
                  ? Text(
                      'Not tagged in your chats yet. Type # in a chat to tag it.',
                      style: theme.textTheme.bodySmall,
                    )
                  : Column(
                      children: [
                        for (final m in list.take(10))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(CupertinoIcons.chat_bubble_2),
                            title: Text(m.chat),
                            subtitle: Text('${m.author} · ${when(m.at)}'),
                            onTap: () {
                              Navigator.pop(context);
                              context.push('/chat/${m.conversationId}');
                            },
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

/// Picks a folder to move documents or a folder to: the folder tree, with
/// "Top of Documents". Pops `(id: folder)`, or `(id: null)` for the top.
class MoveSheet extends ConsumerWidget {
  const MoveSheet({
    super.key,
    required this.title,
    this.current,
    this.exclude = const {},
  });

  final String title;

  /// Where it is now (ticked, not offered).
  final String? current;

  /// Folders it cannot go into (a folder and its own subfolders).
  final Set<String> exclude;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final folders = ref.watch(foldersProvider).value ?? const <DocFolder>[];
    final known = {for (final f in folders) f.id};
    final rows = <(DocFolder, int)>[];
    void add(String? parent, int depth) {
      final kids = [
        for (final f in folders)
          if (f.parentId == parent ||
              (parent == null &&
                  f.parentId != null &&
                  !known.contains(f.parentId)))
            f,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      for (final f in kids) {
        if (exclude.contains(f.id)) continue;
        rows.add((f, depth));
        add(f.id, depth + 1);
      }
    }

    add(null, 0);
    Widget tile(String? id, String name, IconData icon, int depth) => ListTile(
      contentPadding: EdgeInsets.only(left: depth * 20.0),
      dense: true,
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: current == id ? const Icon(CupertinoIcons.checkmark_alt) : null,
      onTap: current == id ? null : () => Navigator.pop(context, (id: id)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.sm),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                tile(null, 'Top of Documents', CupertinoIcons.tray, 0),
                for (final (f, depth) in rows)
                  tile(f.id, f.name, CupertinoIcons.folder_fill, depth + 1),
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

/// Sends documents to a chat as one message, each a tag that opens it
/// (nothing is attached; migration 0053).
Future<void> shareInChat(WidgetRef ref, String chatId, List<Doc> docs) {
  final links = <MessageLink>[
    for (final d in docs.take(10))
      (label: '#${_tagName(d)}', link: 'doc:${d.id}'),
  ];
  return ref
      .read(chatActionsProvider)
      .send(
        chatId,
        text: docs.length == 1
            ? links.single.label
            : 'Files: ${links.map((l) => l.label).join(', ')}',
        links: links,
      );
}

String _tagName(Doc d) {
  final t = d.title.trim().isEmpty ? d.code : d.title.trim();
  return t.length > 40 ? '${t.substring(0, 39).trimRight()}…' : t;
}

/// Documents › Drawings › MCC-3: tap a step to go back to it.
class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.path, required this.onOpen});

  final List<DocFolder> path;
  final ValueChanged<String?> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget step(String label, String? id, {bool last = false}) => InkWell(
      onTap: last ? null : () => onOpen(id),
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: last ? null : theme.colorScheme.primary,
            fontWeight: last ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
    final sep = Icon(
      CupertinoIcons.chevron_right,
      size: 12,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Icon(
            CupertinoIcons.folder,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          step('Documents', null),
          for (final (i, f) in path.indexed) ...[
            sep,
            step(f.name, f.id, last: i == path.length - 1),
          ],
        ],
      ),
    );
  }
}

/// A file that can be ticked: a long press starts selecting; while
/// selecting, a tap ticks or unticks it.
class _Selectable extends StatelessWidget {
  const _Selectable({
    required this.selected,
    required this.selecting,
    required this.onToggle,
    required this.child,
  });

  final bool selected;
  final bool selecting;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPress: onToggle,
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: child,
          ),
          if (selecting)
            Positioned.fill(
              child: Semantics(
                checked: selected,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggle,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        selected
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.circle,
                        color: selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The actions for ticked files, along the bottom.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.canManage,
    required this.allStarred,
    required this.onAction,
  });

  final int count;
  final bool canManage;
  final bool allStarred;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final on = count > 0;
    Widget action(String id, IconData icon, String label) => Expanded(
      child: TextButton(
        onPressed: on ? () => onAction(id) : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
    return GlassSurface(
      radius: 0,
      strong: true,
      padding: EdgeInsets.fromLTRB(
        Space.sm,
        Space.xs,
        Space.sm,
        Space.xs + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        children: [
          action('chat', CupertinoIcons.chat_bubble_2, 'Share in chat'),
          action(
            'star',
            allStarred ? CupertinoIcons.star_slash : CupertinoIcons.star,
            allStarred ? 'Unstar' : 'Star',
          ),
          if (canManage) ...[
            action('move', CupertinoIcons.folder, 'Move'),
            action('archive', CupertinoIcons.archivebox, 'Archive'),
          ],
        ],
      ),
    );
  }
}

/// Creates or renames a folder.
class _FolderForm extends ConsumerStatefulWidget {
  const _FolderForm({required this.siteId, this.folder, this.parentId});

  final String siteId;
  final DocFolder? folder;

  /// Where a new folder goes (null: the top).
  final String? parentId;

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
          f.parentId == (widget.folder?.parentId ?? widget.parentId) &&
          f.name.toLowerCase() == name.toLowerCase(),
    );
    if (taken) {
      setState(() => _error = 'There is already a folder called $name here');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(documentActionsProvider)
          .saveFolder(
            folder: widget.folder,
            siteId: widget.siteId,
            name: name,
            parentId: widget.parentId,
          );
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
  const UploadSheet({super.key, this.folderId, this.dropped = const []});

  final String? folderId;

  /// Files dragged onto the page (browser).
  final List<DroppedFile> dropped;

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

  @override
  void initState() {
    super.initState();
    _add([
      for (final f in widget.dropped) (name: f.name, read: () async => f.bytes),
    ]);
  }

  /// Adds files, leaving out any over 25 MB.
  Future<void> _add(
    List<({String name, Future<Uint8List> Function() read})> picked,
  ) async {
    final big = <String>[];
    for (final f in picked) {
      final bytes = await f.read();
      if (bytes.length > _maxBytes) {
        big.add(f.name);
        continue;
      }
      _files.add((name: f.name, bytes: bytes));
      _state.add(_UploadState.waiting);
    }
    if (!mounted) return;
    setState(
      () => _error = big.isEmpty
          ? null
          : '${big.join(', ')} ${big.length == 1 ? 'is' : 'are'} over 25 MB',
    );
  }

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
    await _add([
      for (final f in picked) (name: f.name, read: f.xFile.readAsBytes),
    ]);
  }

  Future<void> _upload() async {
    final site = _siteFor(ref, _folder);
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
            siteId: site,
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
    final site = widget.doc?.siteId ?? _siteFor(ref, null);
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
            siteId: site,
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

/// Where something new goes: [folder]'s site, else the filtered or home
/// site.
String? _siteFor(WidgetRef ref, String? folder) => siteForFolder(
  ref.read(foldersProvider).value ?? const <DocFolder>[],
  folder,
  ref.read(currentSiteProvider)?.id,
);
