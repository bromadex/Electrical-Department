import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_error.dart';
import '../jobs/jobs_repository.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import 'documents_repository.dart';
import 'documents_screen.dart';

/// Opens a document file: images inside the app, anything else (PDF,
/// drawings) in the phone's or browser's own viewer.
Future<void> openDocument(
  BuildContext context,
  WidgetRef ref,
  DocVersion v,
) async {
  try {
    final url = await ref.read(documentUrlProvider(v.path).future);
    if (!context.mounted) return;
    if (v.isImage) {
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.all(Space.md),
          child: InteractiveViewer(child: Image.network(url)),
        ),
      );
    } else {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppError.from(e).isRetryable
              ? 'Connect to open documents.'
              : AppError.from(e).message,
        ),
      ),
    );
  }
}

class DocumentDetailScreen extends ConsumerWidget {
  const DocumentDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider);
    final doc = ref.watch(documentProvider(id));
    final session = ref.watch(sessionProvider);
    final people = ref.watch(peopleProvider).value ?? const {};
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final canManage =
        doc != null && session.can('docs.manage', siteId: doc.siteId);
    final dates = MaterialLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(doc?.code ?? 'Document'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
        actions: [
          if (canManage)
            IconButton(
              tooltip: 'Edit or upload a new version',
              icon: const Icon(CupertinoIcons.pencil),
              onPressed: () async {
                final kept = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => DocumentForm(doc: doc),
                );
                if (kept == false && context.mounted) context.pop();
              },
            ),
        ],
      ),
      body: MeshBackground(
        child: doc == null
            ? Center(
                child: docs.isLoading
                    ? const CircularProgressIndicator()
                    : const EmptyState(
                        icon: CupertinoIcons.doc_text,
                        title: 'Document not found',
                        message: 'It may have been archived.',
                      ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  Space.md,
                  top + Space.md,
                  Space.md,
                  Space.xl,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SurfaceCard(
                            padding: const EdgeInsets.all(Space.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: Space.xs,
                                  runSpacing: Space.xs,
                                  children: [
                                    RecordCode(doc.code),
                                    Pill(label: categoryLabel(doc.category)),
                                    if (doc.currentVersion > 0)
                                      Pill(
                                        label: 'Version ${doc.currentVersion}',
                                      ),
                                  ],
                                ),
                                const SizedBox(height: Space.sm),
                                Row(
                                  children: [
                                    Icon(docIcon(doc), color: scheme.primary),
                                    const SizedBox(width: Space.xs),
                                    Expanded(
                                      child: Text(
                                        doc.title,
                                        style: theme.textTheme.headlineSmall,
                                      ),
                                    ),
                                  ],
                                ),
                                if (doc.current != null) ...[
                                  const SizedBox(height: Space.xs),
                                  Text(
                                    '${doc.current!.fileName} · ${dates.formatMediumDate(doc.current!.createdAt)}',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: Space.md),
                                  FilledButton.icon(
                                    onPressed: () => openDocument(
                                      context,
                                      ref,
                                      doc.current!,
                                    ),
                                    icon: const Icon(CupertinoIcons.book_fill),
                                    label: const Text('Open'),
                                  ),
                                ],
                              ],
                            ),
                          ).entrance(context),
                          if (doc.needsAck && doc.currentVersion > 0) ...[
                            const SizedBox(height: Space.md),
                            _AckCard(doc: doc),
                          ],
                          if (canManage && doc.needsAck) ...[
                            const SectionHeader('Who has signed'),
                            _WhoSigned(id: doc.id),
                          ],
                          if (doc.versions.length > 1) ...[
                            const SectionHeader('Versions'),
                            SurfaceCard(
                              padding: const EdgeInsets.symmetric(
                                vertical: Space.xs,
                              ),
                              child: Column(
                                children: [
                                  for (final v in doc.versions)
                                    ListTile(
                                      leading: CircleAvatar(
                                        radius: 16,
                                        child: Text('${v.version}'),
                                      ),
                                      title: Text(v.note ?? v.fileName),
                                      subtitle: Text(
                                        '${people[v.createdBy] ?? 'Someone'} · ${dates.formatMediumDate(v.createdAt)}',
                                      ),
                                      trailing: const Icon(
                                        CupertinoIcons.arrow_up_right_square,
                                      ),
                                      onTap: () =>
                                          openDocument(context, ref, v),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AckCard extends ConsumerStatefulWidget {
  const _AckCard({required this.doc});

  final Doc doc;

  @override
  ConsumerState<_AckCard> createState() => _AckCardState();
}

class _AckCardState extends ConsumerState<_AckCard> {
  bool _read = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    if (!doc.toSign) {
      return SurfaceCard(
        color: BrandColors.success.withValues(alpha: 0.12),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.checkmark_seal_fill,
              color: BrandColors.success,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                'You signed version ${doc.currentVersion} as read and understood.',
              ),
            ),
          ],
        ),
      );
    }
    return SurfaceCard(
      color: Colors.orange.withValues(alpha: 0.12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.signature, color: Colors.orange),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  doc.myAckVersion == null
                      ? 'Read this SOP, then sign that you understood it.'
                      : 'This SOP changed since you signed. Read version '
                            '${doc.currentVersion} and sign again.',
                ),
              ),
            ],
          ),
          CheckboxListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _read,
            onChanged: (v) => setState(() => _read = v ?? false),
            title: const Text('I have read and understood this document'),
          ),
          FilledButton.icon(
            onPressed: !_read || _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    HapticFeedback.mediumImpact();
                    await ref.read(documentActionsProvider).acknowledge(doc);
                    if (mounted) setState(() => _busy = false);
                  },
            icon: const Icon(CupertinoIcons.checkmark_seal),
            label: const Text('Sign'),
          ),
        ],
      ),
    );
  }
}

class _WhoSigned extends ConsumerWidget {
  const _WhoSigned({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref
        .watch(documentAcksProvider(id))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) =>
              Text(AppError.from(e).message, style: theme.textTheme.bodySmall),
          data: (rows) {
            final signed = rows.where((r) => r.at != null).length;
            return SurfaceCard(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    title: Text('$signed of ${rows.length} signed'),
                    trailing: SizedBox(
                      width: 100,
                      child: LinearProgressIndicator(
                        value: rows.isEmpty ? 0 : signed / rows.length,
                      ),
                    ),
                  ),
                  for (final r in rows)
                    ListTile(
                      dense: true,
                      leading: AppAvatar(name: r.name, size: 30),
                      title: Text(r.name.isEmpty ? 'Unnamed' : r.name),
                      trailing: r.at == null
                          ? const Pill(
                              label: 'Not yet',
                              color: Colors.orange,
                              dense: true,
                            )
                          : Text(
                              MaterialLocalizations.of(context)
                                  .formatShortMonthDay(r.at!),
                              style: theme.textTheme.labelSmall,
                            ),
                    ),
                ],
              ),
            );
          },
        );
  }
}
