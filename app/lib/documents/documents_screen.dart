import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import 'documents_repository.dart';

IconData docIcon(Doc d) {
  final mime = d.current?.mimeType ?? '';
  if (mime.startsWith('image/')) return CupertinoIcons.photo;
  if (d.category == 'drawing') return CupertinoIcons.square_stack_3d_up;
  if (d.category == 'sop') return CupertinoIcons.shield_lefthalf_fill;
  return CupertinoIcons.doc_text_fill;
}

/// SOPs, drawings and manuals at the current site.
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  String? _category;
  bool _toSign = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(documentsProvider);
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final canManage =
        site != null && session.can('docs.manage', siteId: site.id);
    final toSign = ref.watch(toSignCountProvider);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: Space.xs),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Documents · ${site?.code ?? ''}'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => const DocumentForm(),
              ),
              icon: const Icon(CupertinoIcons.cloud_upload),
              label: const Text('Add document'),
            )
          : null,
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () async => ref.invalidate(documentsProvider),
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
                      CupertinoSearchTextField(
                        placeholder: 'Search titles or S- codes',
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      const SizedBox(height: Space.sm),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            chip(
                              'All',
                              _category == null && !_toSign,
                              () => setState(() {
                                _category = null;
                                _toSign = false;
                              }),
                            ),
                            chip(
                              toSign > 0 ? 'To sign ($toSign)' : 'To sign',
                              _toSign,
                              () => setState(() {
                                _toSign = true;
                                _category = null;
                              }),
                            ),
                            for (final c in documentCategories.entries)
                              chip(
                                c.value,
                                _category == c.key,
                                () => setState(() {
                                  _category = c.key;
                                  _toSign = false;
                                }),
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
                        data: (list) {
                          final q = _query.toLowerCase();
                          final shown = [
                            for (final d in list)
                              if ((!_toSign || d.toSign) &&
                                  (_category == null ||
                                      d.category == _category) &&
                                  (q.isEmpty ||
                                      d.title.toLowerCase().contains(q) ||
                                      d.code.toLowerCase().contains(q)))
                                d,
                          ];
                          if (shown.isEmpty) {
                            return [
                              Padding(
                                padding: const EdgeInsets.only(top: Space.xl),
                                child: EmptyState(
                                  icon: _toSign
                                      ? CupertinoIcons.checkmark_seal
                                      : CupertinoIcons.doc_text,
                                  title: _toSign
                                      ? 'All signed'
                                      : list.isEmpty
                                      ? 'No documents yet'
                                      : 'Nothing here',
                                  message: _toSign
                                      ? 'You have read every SOP that needs it.'
                                      : list.isEmpty
                                      ? 'Supervisors upload SOPs, drawings and '
                                            'manuals here.'
                                      : 'No documents match.',
                                ),
                              ),
                            ];
                          }
                          return [
                            for (final (i, d) in shown.indexed)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Space.sm,
                                ),
                                child: DocTile(doc: d),
                              ).entrance(context, index: i.clamp(0, 8)),
                          ];
                        },
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

class DocTile extends StatelessWidget {
  const DocTile({super.key, required this.doc, this.trailing, this.onTap});

  final Doc doc;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SurfaceCard(
      onTap: onTap ?? () => context.push('/documents/${doc.id}'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(docIcon(doc), color: scheme.primary),
          ),
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
                    relativeDate(context, doc.updatedAt),
                  ].join(' · '),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (doc.toSign)
            const Pill(
              label: 'Sign',
              color: Colors.orange,
              icon: CupertinoIcons.signature,
              dense: true,
            )
          else if (doc.needsAck && doc.currentVersion > 0)
            const Icon(
              CupertinoIcons.checkmark_seal_fill,
              color: BrandColors.success,
              size: 20,
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
