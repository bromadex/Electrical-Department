import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/format.dart';
import '../ui/media.dart';
import 'models.dart';
import 'repository.dart';

const _kindLabels = {
  'photo_before': 'Before photos',
  'photo_after': 'After photos',
  'photo': 'Photos',
  'test_sheet': 'Test sheets',
  'document': 'Documents',
  'other': 'Other files',
};

/// Photos and files on a job card, grouped by kind, with upload.
class AttachmentsPanel extends ConsumerStatefulWidget {
  const AttachmentsPanel({
    super.key,
    required this.job,
    required this.files,
    required this.canAdd,
  });

  final JobCard job;
  final List<JobAttachment> files;
  final bool canAdd;

  @override
  ConsumerState<AttachmentsPanel> createState() => _AttachmentsPanelState();
}

class _AttachmentsPanelState extends ConsumerState<AttachmentsPanel> {
  bool _busy = false;

  Future<void> _add(Future<List<PickedFile>> Function() pick) async {
    final picked = await pick();
    if (picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(jobCardActionsProvider)
          .addFiles(
            jobId: widget.job.id,
            siteId: widget.job.siteId,
            files: picked,
          );
      if (mounted) {
        showSnack(
          context,
          picked.length == 1 ? 'File added' : '${picked.length} files added',
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _photoKind() => showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('What do the photos show?'),
      children: [
        for (final k in const ['photo_before', 'photo_after', 'photo'])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, k),
            child: Text(_kindLabels[k]!),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <String, List<JobAttachment>>{};
    for (final f in widget.files) {
      groups.putIfAbsent(f.kind, () => []).add(f);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.canAdd)
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _add(() async {
                        final kind = await _photoKind();
                        if (kind == null || !mounted) {
                          return const <PickedFile>[];
                        }
                        return MediaPicking.photos(this.context, kind: kind);
                      }),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Add photos'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _add(
                        () =>
                            MediaPicking.documents(context, kind: 'test_sheet'),
                      ),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Add test sheet'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _add(() => MediaPicking.documents(context)),
                icon: const Icon(Icons.attach_file_rounded),
                label: const Text('Add document'),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        if (widget.files.isEmpty)
          const EmptyState(
            icon: Icons.photo_library_outlined,
            title: 'No photos or files yet',
            message: 'Before and after photos, test sheets and documents appear here.',
          ),
        for (final kind in _kindLabels.keys)
          if (groups[kind] != null) ...[
            SectionHeader('${_kindLabels[kind]} (${groups[kind]!.length})'),
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                for (final f in groups[kind]!)
                  Tooltip(
                    message:
                        '${f.fileName ?? 'File'} · ${f.uploaderName ?? 'Someone'} · ${fmtDateTime(f.createdAt)}',
                    child: FileThumb(
                      url: f.url,
                      name: f.fileName,
                      isImage: f.isImage,
                      size: 104,
                      onTap: f.url == null
                          ? null
                          : () => f.isImage
                                ? showImage(context, url: f.url)
                                : launchUrl(
                                    Uri.parse(f.url!),
                                    mode: LaunchMode.externalApplication,
                                  ),
                    ),
                  ),
              ],
            ),
          ],
        if (widget.files.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(
              'Links to files last an hour; reopen the job card for fresh ones.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

const _commentKinds = {
  'comment': ('Comment', Icons.chat_bubble_outline_rounded, AppColors.neutral),
  'finding': ('Finding', Icons.search_rounded, AppColors.info),
  'instruction': (
    'Engineering instruction',
    Icons.rule_rounded,
    AppColors.navy600,
  ),
  'handover': ('Handover note', Icons.swap_horiz_rounded, AppColors.warning),
  'assistance': (
    'Assistance request',
    Icons.support_agent_rounded,
    AppColors.critical,
  ),
};

/// Append-only feed: nobody edits or removes another person's findings.
class CommentsPanel extends ConsumerStatefulWidget {
  const CommentsPanel({
    super.key,
    required this.job,
    required this.comments,
    required this.canComment,
  });

  final JobCard job;
  final List<JobComment> comments;
  final bool canComment;

  @override
  ConsumerState<CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends ConsumerState<CommentsPanel> {
  final _body = TextEditingController();
  String _kind = 'comment';
  bool _requesterVisible = false;
  final Set<String> _mentions = {};
  bool _busy = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_body.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(jobCardActionsProvider)
          .comment(
            widget.job.id,
            _body.text,
            kind: _kind,
            visibility: _requesterVisible ? 'requester' : 'internal',
            mentions: _mentions.toList(),
          );
      _body.clear();
      setState(() {
        _mentions.clear();
        _kind = 'comment';
        _requesterVisible = false;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = widget.canComment
        ? ref.watch(sitePeopleProvider(widget.job.siteId)).value ?? const []
        : const <Person>[];
    final names = {for (final p in people) p.id: p.name};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.comments.isEmpty)
          const EmptyState(
            icon: Icons.forum_outlined,
            title: 'No comments yet',
            message: 'Findings, instructions, handover notes and questions appear here.',
          ),
        for (final c in widget.comments) _CommentTile(comment: c),
        if (widget.canComment) ...[
          const Divider(height: Space.lg),
          TextField(
            controller: _body,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Add to the job card',
              hintText: 'Write a comment, finding or instruction',
            ),
          ),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: _kind,
                onChanged: (v) => setState(() => _kind = v ?? 'comment'),
                items: [
                  for (final e in _commentKinds.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value.$1)),
                ],
              ),
              if (widget.job.requestId != null)
                FilterChip(
                  label: const Text('Visible to the requester'),
                  selected: _requesterVisible,
                  onSelected: (v) => setState(() => _requesterVisible = v),
                ),
              MenuAnchor(
                builder: (context, controller, _) => ActionChip(
                  avatar: const Icon(Icons.alternate_email_rounded, size: 18),
                  label: Text(
                    _mentions.isEmpty
                        ? 'Mention someone'
                        : _mentions.map((m) => names[m] ?? '?').join(', '),
                  ),
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                ),
                menuChildren: [
                  for (final p in people)
                    CheckboxMenuButton(
                      value: _mentions.contains(p.id),
                      onChanged: (v) => setState(
                        () => v == true
                            ? _mentions.add(p.id)
                            : _mentions.remove(p.id),
                      ),
                      child: Text(p.name),
                    ),
                ],
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Post'),
              ),
            ],
          ),
          Text(
            'Posts cannot be edited or deleted afterwards.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final JobComment comment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = _commentKinds[comment.kind] ?? _commentKinds['comment']!;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(name: comment.authorName, size: 32),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(comment.authorName, style: theme.textTheme.titleSmall),
                    if (comment.kind != 'comment')
                      Pill(
                        label: kind.$1,
                        icon: kind.$2,
                        color: kind.$3,
                        dense: true,
                      ),
                    if (comment.visibility == 'requester')
                      const Pill(
                        label: 'Visible to requester',
                        icon: Icons.visibility_outlined,
                        color: AppColors.info,
                        dense: true,
                      ),
                    Text(
                      fmtDateTime(comment.createdAt),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                CopyableText(comment.body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Every event on the job card, oldest first, with who and when.
class TimelinePanel extends ConsumerWidget {
  const TimelinePanel({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AsyncView(
      value: ref.watch(jobCardTimelineProvider(jobId)),
      onRetry: () => ref.invalidate(jobCardTimelineProvider(jobId)),
      data: (entries) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, e) in entries.indexed)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 28,
                    child: Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: _color(e.kind).withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _icon(e.kind),
                            size: 13,
                            color: _color(e.kind),
                          ),
                        ),
                        if (i < entries.length - 1)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${e.actor} · ${fmtDateTime(e.at)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (e.detail != null && e.detail!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(e.detail!),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static IconData _icon(String kind) => switch (kind) {
    'status' => Icons.flag_outlined,
    'assignment' => Icons.person_outline_rounded,
    'comment' => Icons.chat_bubble_outline_rounded,
    'attachment' => Icons.attach_file_rounded,
    _ => Icons.edit_outlined,
  };

  static Color _color(String kind) => switch (kind) {
    'status' => AppColors.info,
    'assignment' => AppColors.navy600,
    'comment' => AppColors.neutral,
    'attachment' => AppColors.success,
    _ => AppColors.warning,
  };
}
