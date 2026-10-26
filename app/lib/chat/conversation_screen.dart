import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../jobs/job_editor.dart';
import '../jobs/jobs_repository.dart';
import '../jobs/media.dart';
import '../services/core_providers.dart';
import '../services/push_service.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import 'chat_list_screen.dart';
import 'chat_repository.dart';

const _quickReactions = ['👍', '✅', '❤️', '😂', '🙏', '⚠️'];

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  ChatMessage? _replyTo;
  Timer? _readTimer;

  @override
  void initState() {
    super.initState();
    _markRead();
  }

  @override
  void dispose() {
    _readTimer?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _markRead() {
    _readTimer?.cancel();
    _readTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(ref.read(chatActionsProvider).markRead(widget.id));
    });
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    _text.clear();
    final reply = _replyTo?.id;
    setState(() => _replyTo = null);
    _focus.requestFocus();
    await ref
        .read(chatActionsProvider)
        .send(widget.id, text: text, replyTo: reply);
  }

  Future<void> _sendPhoto() async {
    final photos = await PhotoPicking.pick(context);
    final reply = _replyTo?.id;
    if (photos.isNotEmpty) setState(() => _replyTo = null);
    for (final p in photos) {
      await ref
          .read(chatActionsProvider)
          .send(widget.id, photo: p, replyTo: reply);
    }
  }

  Future<void> _tagRecord() async {
    final hit = await showFormSheet<RecordHit>(context, const _RecordPicker());
    if (hit == null) return;
    final note = _text.text.trim();
    _text.clear();
    await ref
        .read(chatActionsProvider)
        .send(
          widget.id,
          text: note.isEmpty ? '${hit.code} · ${hit.title}' : note,
          recordLink: hit.link,
        );
  }

  void _actions(ChatMessage m, bool mine, String? author) {
    final canJob = ref.read(sessionProvider).can('jobs.create');
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!m.pending)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final e in _quickReactions)
                      IconButton(
                        onPressed: () {
                          Navigator.pop(sheet);
                          HapticFeedback.selectionClick();
                          unawaited(
                            ref.read(chatActionsProvider).react(m.id, e),
                          );
                        },
                        icon: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                  ],
                ),
              ListTile(
                leading: const Icon(CupertinoIcons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(sheet);
                  setState(() => _replyTo = m);
                  _focus.requestFocus();
                },
              ),
              if (m.body != null)
                ListTile(
                  leading: const Icon(CupertinoIcons.doc_on_doc),
                  title: const Text('Copy text'),
                  onTap: () {
                    Navigator.pop(sheet);
                    Clipboard.setData(ClipboardData(text: m.body!));
                  },
                ),
              if (canJob && m.body != null && m.recordLink == null)
                ListTile(
                  leading: const Icon(CupertinoIcons.hammer),
                  title: const Text('Make a job from this'),
                  onTap: () {
                    Navigator.pop(sheet);
                    final body = m.body!;
                    final firstLine = body.split('\n').first;
                    showJobEditor(
                      context,
                      title: firstLine.length > 120
                          ? firstLine.substring(0, 120)
                          : firstLine,
                      description:
                          '$body\n\nFrom chat${author == null ? '' : ' · $author'}',
                    );
                  },
                ),
              if (mine && !m.pending)
                ListTile(
                  leading: const Icon(CupertinoIcons.trash, color: Colors.red),
                  title: const Text(
                    'Unsend',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(sheet);
                    unawaited(
                      ref.read(chatActionsProvider).unsend(widget.id, m.id),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thread = ref.watch(chatThreadProvider(widget.id));
    final chats = ref.watch(conversationsProvider).value ?? const [];
    final chat = chats.where((c) => c.id == widget.id).firstOrNull;
    final people = ref.watch(peopleProvider).value ?? const {};
    final me = ref.watch(authUserIdProvider);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    ref.listen(chatThreadProvider(widget.id), (prev, next) {
      if ((prev?.messages.length ?? 0) < next.messages.length) _markRead();
    });

    final shown = [
      for (final m in thread.messages)
        if (!m.archived) m,
    ];
    final byId = {for (final m in shown) m.id: m};

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          tooltip: 'Chats',
          icon: const Icon(CupertinoIcons.back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/chat'),
        ),
        title: Row(
          children: [
            chat == null || chat.isDirect
                ? AppAvatar(name: chat?.title ?? 'Chat', size: 34)
                : ChatGroupAvatar(chat: chat, size: 34),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat?.title ?? 'Chat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  if (chat != null)
                    Text(
                      chat.isDirect
                          ? 'Direct chat'
                          : '${chat.memberCount} members',
                      style: theme.textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ],
        ),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: Column(
          children: [
            Expanded(
              child: thread.loading && shown.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : thread.error != null && shown.isEmpty
                  ? Padding(
                      padding: EdgeInsets.only(top: top),
                      child: EmptyState(
                        icon: CupertinoIcons.wifi_slash,
                        title: 'Could not load messages',
                        message: AppError.from(thread.error!).isRetryable
                            ? 'Messages load when you are connected.'
                            : AppError.from(thread.error!).message,
                      ),
                    )
                  : shown.isEmpty
                  ? Padding(
                      padding: EdgeInsets.only(top: top),
                      child: const EmptyState(
                        icon: CupertinoIcons.chat_bubble,
                        title: 'No messages yet',
                        message:
                            'Say hello, share a photo, or tag a job with #.',
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: EdgeInsets.fromLTRB(
                        Space.sm + _side(context),
                        Space.sm,
                        Space.sm + _side(context),
                        top + Space.sm,
                      ),
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final m = shown[shown.length - 1 - i];
                        final prev = i == shown.length - 1
                            ? null
                            : shown[shown.length - 2 - i];
                        final mine = m.authorId == me;
                        final author = people[m.authorId];
                        final newDay =
                            prev == null ||
                            !DateUtils.isSameDay(prev.createdAt, m.createdAt);
                        final sameAuthor =
                            !newDay &&
                            prev.authorId == m.authorId &&
                            m.createdAt.difference(prev.createdAt).inMinutes <
                                5;
                        return Column(
                          children: [
                            if (newDay) _DaySeparator(m.createdAt),
                            _Bubble(
                              message: m,
                              mine: mine,
                              author: (chat?.isDirect ?? false) || sameAuthor
                                  ? null
                                  : author ?? 'Someone',
                              reply: m.replyTo == null ? null : byId[m.replyTo],
                              replyAuthor: m.replyTo == null
                                  ? null
                                  : people[byId[m.replyTo]?.authorId],
                              photoUrl: thread.photoUrls[m.attachmentPath],
                              reactions: thread.reactions[m.id] ?? const {},
                              me: me,
                              tight: sameAuthor,
                              onLongPress: () => _actions(m, mine, author),
                              onReact: (e) =>
                                  ref.read(chatActionsProvider).react(m.id, e),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            _Composer(
              controller: _text,
              focus: _focus,
              replyTo: _replyTo,
              replyAuthor: _replyTo == null
                  ? null
                  : _replyTo!.authorId == me
                  ? 'yourself'
                  : people[_replyTo!.authorId],
              onCancelReply: () => setState(() => _replyTo = null),
              onSend: _send,
              onPhoto: _sendPhoto,
              onTag: _tagRecord,
            ),
          ],
        ),
      ),
    );
  }
}

/// Side padding that keeps the thread to a readable width on desktop.
double _side(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return w > 900 ? (w - 900) / 2 : 0;
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator(this.day);

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label = DateUtils.isSameDay(day, now)
        ? 'Today'
        : DateUtils.isSameDay(day, now.subtract(const Duration(days: 1)))
        ? 'Yesterday'
        : '${day.day}/${day.month}/${day.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Center(
        child: GlassSurface(
          radius: 99,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(label, style: Theme.of(context).textTheme.labelSmall),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.author,
    required this.reply,
    required this.replyAuthor,
    required this.photoUrl,
    required this.reactions,
    required this.me,
    required this.tight,
    required this.onLongPress,
    required this.onReact,
  });

  final ChatMessage message;
  final bool mine;
  final String? author;
  final ChatMessage? reply;
  final String? replyAuthor;
  final String? photoUrl;
  final Map<String, List<String>> reactions;
  final String? me;
  final bool tight;
  final VoidCallback onLongPress;
  final void Function(String emoji) onReact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = Glass.of(context);
    final m = message;
    final fg = mine ? Colors.white : theme.colorScheme.onSurface;
    final sub = mine
        ? Colors.white.withValues(alpha: 0.75)
        : theme.colorScheme.onSurfaceVariant;
    final width = MediaQuery.sizeOf(context).width;
    final maxW = (width * 0.78).clamp(220.0, 520.0);
    final time =
        '${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}';
    final path = notificationPath(m.recordLink);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (author != null && !mine)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              author!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: BrandColors.coral,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (reply != null)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            decoration: BoxDecoration(
              color: (mine ? Colors.white : BrandColors.maroon).withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(
                  color: mine ? Colors.white : BrandColors.maroon,
                  width: 3,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  replyAuthor ?? 'Message',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  reply!.kind == 'photo' ? '📷 Photo' : reply!.body ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: sub),
                ),
              ],
            ),
          ),
        if (m.kind == 'photo')
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: GestureDetector(
              onTap: photoUrl == null
                  ? null
                  : () => showPhoto(
                      context,
                      JobPhoto(
                        id: m.id,
                        kind: 'photo',
                        path: m.attachmentPath ?? '',
                        url: photoUrl,
                      ),
                    ),
              child: SizedBox(
                width: maxW - 24,
                height: (maxW - 24) * 0.75,
                child: m.bytes != null
                    ? Image.memory(m.bytes!, fit: BoxFit.cover)
                    : photoUrl != null
                    ? Image.network(photoUrl!, fit: BoxFit.cover)
                    : ColoredBox(
                        color: g.fill,
                        child: const Center(child: Icon(CupertinoIcons.photo)),
                      ),
              ),
            ),
          ),
        if (m.kind == 'record')
          InkWell(
            onTap: path == null ? null : () => context.push(path),
            borderRadius: BorderRadius.circular(Radii.md),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (mine ? Colors.white : BrandColors.info).withValues(
                  alpha: 0.14,
                ),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    switch (m.recordLink?.split(':').first) {
                      'asset' => CupertinoIcons.gear_alt_fill,
                      'tool' => CupertinoIcons.wrench_fill,
                      _ => CupertinoIcons.tag_fill,
                    },
                    size: 18,
                    color: mine ? Colors.white : BrandColors.info,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Open ${m.recordLink?.split(':').first ?? 'record'}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: mine ? Colors.white : BrandColors.info,
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 14,
                    color: mine ? Colors.white : BrandColors.info,
                  ),
                ],
              ),
            ),
          ),
        if (m.body != null)
          Padding(
            padding: EdgeInsets.only(top: m.kind == 'text' ? 0 : 6),
            child: Text(
              m.body!,
              style: theme.textTheme.bodyMedium?.copyWith(color: fg),
            ),
          ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(time, style: theme.textTheme.labelSmall?.copyWith(color: sub)),
            if (mine) ...[
              const SizedBox(width: 4),
              Icon(
                m.pending ? CupertinoIcons.clock : CupertinoIcons.checkmark_alt,
                size: 12,
                color: sub,
              ),
            ],
          ],
        ),
      ],
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(top: tight ? 2 : Space.xs),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: () {
                HapticFeedback.mediumImpact();
                onLongPress();
              },
              onSecondaryTap: onLongPress,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  decoration: BoxDecoration(
                    gradient: mine
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [BrandColors.maroon, BrandColors.coral],
                          )
                        : null,
                    color: mine ? null : g.fillStrong,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(mine ? 18 : 6),
                      bottomRight: Radius.circular(mine ? 6 : 18),
                    ),
                    boxShadow: g.shadow,
                  ),
                  child: Opacity(opacity: m.pending ? 0.75 : 1, child: content),
                ),
              ),
            ),
            if (reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Wrap(
                  spacing: 4,
                  children: [
                    for (final e in reactions.entries)
                      InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: () => onReact(e.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: e.value.contains(me)
                                ? BrandColors.maroon.withValues(alpha: 0.18)
                                : g.fillStrong,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '${e.key} ${e.value.length}',
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.replyTo,
    required this.replyAuthor,
    required this.onCancelReply,
    required this.onSend,
    required this.onPhoto,
    required this.onTag,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ChatMessage? replyTo;
  final String? replyAuthor;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;
  final VoidCallback onPhoto;
  final VoidCallback onTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return GlassSurface(
      radius: 0,
      strong: true,
      padding: EdgeInsets.fromLTRB(Space.xs, Space.xs, Space.xs, bottom + 6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (replyTo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.sm, 0, 0, 4),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.reply,
                        size: 16,
                        color: BrandColors.maroon,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Replying to ${replyAuthor ?? 'message'}: '
                          '${replyTo!.kind == 'photo' ? 'Photo' : replyTo!.body ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: onCancelReply,
                        icon: const Icon(CupertinoIcons.xmark, size: 16),
                      ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Photo',
                    onPressed: onPhoto,
                    icon: const Icon(CupertinoIcons.camera),
                  ),
                  IconButton(
                    tooltip: 'Tag a job, asset or tool',
                    onPressed: onTag,
                    icon: const Icon(CupertinoIcons.number),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focus,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: onSend,
                    icon: const Icon(CupertinoIcons.arrow_up),
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

/// Search jobs, assets and tools to tag in a message.
class _RecordPicker extends ConsumerStatefulWidget {
  const _RecordPicker();

  @override
  ConsumerState<_RecordPicker> createState() => _RecordPickerState();
}

class _RecordPickerState extends ConsumerState<_RecordPicker> {
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hits = ref.watch(recordSearchProvider(_query));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Tag a record', style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.sm),
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(CupertinoIcons.number),
              hintText: 'Job code, asset tag, tool or title',
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 300),
                () => setState(() => _query = v.trim()),
              );
            },
          ),
          const SizedBox(height: Space.xs),
          Flexible(
            child: hits.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(Space.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Text(AppError.from(e).message),
              ),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(Space.lg),
                      child: Text('Nothing found.'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final h in list)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(switch (h.link.split(':').first) {
                              'asset' => CupertinoIcons.gear_alt,
                              'tool' => CupertinoIcons.wrench,
                              _ => CupertinoIcons.hammer,
                            }),
                            title: Text(
                              '${h.code} · ${h.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('${h.status} · ${h.siteCode}'),
                            onTap: () => Navigator.pop(context, h),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: Space.md),
        ],
      ),
    );
  }
}
