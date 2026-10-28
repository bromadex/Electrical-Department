import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_error.dart';
import '../ui/form_sheet.dart';
import '../data/site_data.dart';
import '../documents/documents_repository.dart';
import '../documents/documents_screen.dart' show DocTile;
import '../ui/media.dart';
import '../services/core_providers.dart';
import '../services/push_service.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import 'chat_list_screen.dart';
import 'chat_repository.dart';
import 'composer.dart';
import 'voice.dart';
import '../meetings/meeting_screen.dart';
import 'presence.dart';
import '../widgets/app_back_button.dart';

/// Missed calls.
const _missedRed = Color(0xFFD64545);

const _quickReactions = ['👍', '✅', '❤️', '😂', '🙏', '⚠️'];

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({
    super.key,
    required this.id,
    this.embedded = false,
  });

  final String id;

  /// Shown beside the chat list on a wide screen: no back button.
  final bool embedded;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  ChatMessage? _replyTo;
  Timer? _readTimer;

  /// Where you had read up to when the chat opened; the "New messages" line
  /// goes above the first message after it.
  DateTime? _readUpTo;

  @override
  void initState() {
    super.initState();
    final chats = ref.read(conversationsProvider).value ?? const [];
    final chat = chats.where((c) => c.id == widget.id).firstOrNull;
    if (chat != null && chat.unread > 0) _readUpTo = chat.lastReadAt;
    _text.addListener(_typing);
    _markRead();
  }

  void _typing() {
    if (_text.text.trim().isNotEmpty) {
      ref.read(chatPresenceProvider.notifier).typing(widget.id);
    }
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

  Future<void> _send(String text, List<String> mentions) async {
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    _text.clear();
    final reply = _replyTo?.id;
    setState(() => _replyTo = null);
    _focus.requestFocus();
    await ref
        .read(chatActionsProvider)
        .send(widget.id, text: text, replyTo: reply, mentions: mentions);
  }

  Future<void> _sendVoice(ChatAttachment voice) async {
    final reply = _replyTo?.id;
    setState(() => _replyTo = null);
    await ref
        .read(chatActionsProvider)
        .send(widget.id, voice: voice, replyTo: reply);
  }

  Future<void> _sendFile() async {
    final f = await FilePicker.pickFile();
    if (f == null) return;
    final bytes = await f.xFile.readAsBytes();
    if (bytes.length > 25 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('That file is over 25 MB')));
      return;
    }
    final name = f.xFile.name;
    final reply = _replyTo?.id;
    setState(() => _replyTo = null);
    await ref
        .read(chatActionsProvider)
        .send(
          widget.id,
          file: ChatAttachment(
            bytes: bytes,
            name: name,
            type: f.xFile.mimeType ?? _mime(name),
          ),
          text: _text.text.trim().isEmpty ? null : _text.text.trim(),
          replyTo: reply,
        );
    _text.clear();
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

  /// Shares a document from Documents: a message that opens it.
  Future<void> _shareDocument() async {
    final doc = await showFormSheet<Doc>(context, const _DocumentPicker());
    if (doc == null) return;
    final note = _text.text.trim();
    _text.clear();
    final reply = _replyTo?.id;
    setState(() => _replyTo = null);
    await ref
        .read(chatActionsProvider)
        .send(
          widget.id,
          text: note.isEmpty ? '${doc.code} · ${doc.title}' : note,
          recordLink: 'doc:${doc.id}',
          replyTo: reply,
        );
  }

  void _actions(ChatMessage m, bool mine, String? author) {
    final site = ref.read(currentSiteProvider);
    final canJob = ref
        .read(sessionProvider)
        .can('jc.register', siteId: site?.id);
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
                  title: const Text('Make a job card from this'),
                  onTap: () {
                    Navigator.pop(sheet);
                    final body = m.body!;
                    final firstLine = body.split('\n').first;
                    context.push(
                      Uri(
                        path: '/jobs/new',
                        queryParameters: {
                          'title': firstLine.length > 120
                              ? firstLine.substring(0, 120)
                              : firstLine,
                          'description':
                              '$body\n\nFrom chat${author == null ? '' : ' · $author'}',
                        },
                      ).toString(),
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
    final presence = ref.watch(chatPresenceProvider);
    final calls = ref.watch(chatCallsProvider(widget.id)).value ?? const [];
    final callsByMessage = {
      for (final k in calls)
        if (k.messageId != null) k.messageId!: k,
    };
    final live = calls.where((k) => k.live).firstOrNull;
    const bannerHeight = 48.0;
    final top =
        MediaQuery.paddingOf(context).top +
        kToolbarHeight +
        (live != null ? bannerHeight : 0);
    final group = !(chat?.isDirect ?? false);
    final typing = presence.typingIn(widget.id, except: me);
    final online = chat != null && presence.isOnline(chat.otherUserId);
    final status = typing.isNotEmpty
        ? (group
              ? '${typing.map((u) => (people[u] ?? 'Someone').split(' ').first).join(', ')} typing…'
              : 'typing…')
        : chat == null
        ? null
        : chat.isDirect
        ? (online ? 'Online' : 'Direct chat')
        : '${chat.memberCount} members';

    ref.listen(chatThreadProvider(widget.id), (prev, next) {
      if ((prev?.messages.length ?? 0) < next.messages.length) _markRead();
    });

    final shown = [
      for (final m in thread.messages)
        if (!m.archived) m,
    ];
    final byId = {for (final m in shown) m.id: m};
    final readUpTo = _readUpTo;
    final firstNew = readUpTo == null
        ? null
        : shown
              .where(
                (m) =>
                    m.authorId != me &&
                    !m.pending &&
                    m.createdAt.isAfter(readUpTo),
              )
              .firstOrNull
              ?.id;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        titleSpacing: widget.embedded ? Space.md : 0,
        automaticallyImplyLeading: false,
        leading: widget.embedded
            ? null
            : const AppBackButton(fallback: '/chat'),
        title: Row(
          children: [
            chat == null || chat.isDirect
                ? OnlineAvatar(
                    name: chat?.title ?? 'Chat',
                    online: online,
                    size: 36,
                  )
                : ChatGroupAvatar(chat: chat, size: 36),
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
                  if (status != null)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        status,
                        key: ValueKey(status),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: typing.isNotEmpty
                              ? BrandColors.coral
                              : online
                              ? BrandColors.success
                              : null,
                          fontWeight: typing.isNotEmpty || online
                              ? FontWeight.w600
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Voice call',
            icon: const Icon(CupertinoIcons.phone_fill),
            onPressed: () => context.push('/chat/${widget.id}/call?join=1'),
          ),
          IconButton(
            tooltip: 'Video call',
            icon: const Icon(CupertinoIcons.video_camera_solid),
            onPressed: () =>
                context.push('/chat/${widget.id}/call?join=1&video=1'),
          ),
          if (chat != null)
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(CupertinoIcons.ellipsis_vertical),
              onSelected: (v) {
                if (v == 'meeting') {
                  showFormSheet(
                    context,
                    ScheduleMeetingSheet(conversationId: chat.id),
                  );
                }
                if (v == 'pin') {
                  unawaited(
                    ref.read(chatActionsProvider).pin(chat.id, !chat.pinned),
                  );
                }
              },
              itemBuilder: (_) => [
                if (!chat.isDirect &&
                    ref
                        .read(sessionProvider)
                        .can(
                          'meetings.manage',
                          siteId:
                              chat.siteId ?? ref.read(currentSiteProvider)?.id,
                        ))
                  const PopupMenuItem(
                    value: 'meeting',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(CupertinoIcons.calendar_badge_plus),
                      title: Text('Schedule a meeting'),
                    ),
                  ),
                PopupMenuItem(
                  value: 'pin',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      chat.pinned
                          ? CupertinoIcons.pin_slash
                          : CupertinoIcons.pin,
                    ),
                    title: Text(chat.pinned ? 'Unpin chat' : 'Pin to the top'),
                  ),
                ),
              ],
            ),
          const SizedBox(width: Space.xs),
        ],
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
        bottom: live == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(bannerHeight),
                child: _LiveCallBanner(
                  call: live,
                  onJoin: () => context.push('/chat/${widget.id}/call?join=1'),
                ),
              ),
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
                  : LayoutBuilder(
                      builder: (context, box) => ListView.builder(
                        reverse: true,
                        padding: EdgeInsets.fromLTRB(
                          Space.sm + _side(box.maxWidth),
                          Space.sm,
                          Space.sm + _side(box.maxWidth),
                          top + Space.sm,
                        ),
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final m = shown[shown.length - 1 - i];
                          final prev = i == shown.length - 1
                              ? null
                              : shown[shown.length - 2 - i];
                          final next = i == 0 ? null : shown[shown.length - i];
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
                          if (m.kind == 'system') {
                            return Column(
                              children: [
                                if (newDay) _DaySeparator(m.createdAt),
                                if (m.id == firstNew) const _NewMessagesLine(),
                                _SystemRow(
                                  message: m,
                                  call: callsByMessage[m.id],
                                  me: me,
                                ),
                              ],
                            );
                          }
                          // Groups: the avatar sits beside the last message
                          // of each run from one person.
                          final lastOfRun =
                              next == null ||
                              next.authorId != m.authorId ||
                              !DateUtils.isSameDay(
                                next.createdAt,
                                m.createdAt,
                              ) ||
                              next.createdAt
                                      .difference(m.createdAt)
                                      .inMinutes >=
                                  5;
                          final bubble = _Bubble(
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
                            onReply: () {
                              setState(() => _replyTo = m);
                              _focus.requestFocus();
                            },
                          );
                          return Column(
                            children: [
                              if (newDay) _DaySeparator(m.createdAt),
                              if (m.id == firstNew) const _NewMessagesLine(),
                              if (group && !mine)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    SizedBox(
                                      width: 34,
                                      child: lastOfRun
                                          ? AppAvatar(
                                              name: author ?? '?',
                                              size: 28,
                                            )
                                          : null,
                                    ),
                                    Expanded(child: bubble),
                                  ],
                                )
                              else
                                bubble,
                            ],
                          );
                        },
                      ),
                    ),
            ),
            ChatComposer(
              conversationId: widget.id,
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
              onFile: _sendFile,
              onTag: _tagRecord,
              onDocument:
                  ref
                      .watch(sessionProvider)
                      .can(
                        'docs.view',
                        siteId: ref.watch(currentSiteProvider)?.id,
                      )
                  ? _shareDocument
                  : null,
              onVoice: _sendVoice,
            ),
          ],
        ),
      ),
    );
  }
}

/// Side padding that keeps the thread to a readable width on desktop.
double _side(double w) => w > 900 ? (w - 900) / 2 : 0;

/// "Call in progress · 2 in the call · Join" under the chat's header.
class _LiveCallBanner extends StatelessWidget {
  const _LiveCallBanner({required this.call, required this.onJoin});

  final CallInfo call;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BrandColors.success,
      child: InkWell(
        onTap: onJoin,
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Row(
              children: [
                Icon(
                  call.video
                      ? CupertinoIcons.video_camera_solid
                      : CupertinoIcons.phone_fill,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'Call in progress · ${call.inCall} in the call',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: BrandColors.success,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onJoin,
                  child: const Text('Join'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A line from the app itself. Calls show what happened: Join while it is
/// going, a missed call, or how long it lasted, with Call back.
class _SystemRow extends StatelessWidget {
  const _SystemRow({required this.message, this.call, this.me});

  final ChatMessage message;
  final CallInfo? call;
  final String? me;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = message;
    final k = call;
    final isCall = m.recordLink?.startsWith('call:') ?? false;
    if (m.recordLink?.startsWith('meeting:') ?? false) {
      return _MeetingRow(message: m);
    }
    final chatId = isCall ? m.recordLink!.substring(5) : null;
    String hm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final time = hm(m.createdAt);

    final String text;
    final Color color;
    IconData icon = k?.video ?? false
        ? CupertinoIcons.video_camera_solid
        : CupertinoIcons.phone_fill;
    String? action;
    if (k == null) {
      text = '${m.body ?? ''} · $time';
      color = BrandColors.success;
    } else if (k.live) {
      text = '${m.body ?? 'Call'} · $time';
      color = BrandColors.success;
      action = 'Join';
    } else if (k.missed) {
      final mine = k.startedBy == me;
      text = mine
          ? 'No answer · $time'
          : '${m.body?.replaceFirst('started', 'Missed') ?? 'Missed call'} · $time';
      color = _missedRed;
      icon = mine ? CupertinoIcons.phone_fill : CupertinoIcons.phone_down_fill;
      action = 'Call back';
    } else {
      final len = k.length;
      text =
          '${k.video ? 'Video call' : 'Call'}'
          '${len == null ? '' : ' · ${_callLength(len)}'} · $time';
      color = BrandColors.info;
      action = 'Call back';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Center(
        child: GlassSurface(
          radius: 99,
          padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCall)
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 15, color: Colors.white),
                ),
              const SizedBox(width: Space.xs),
              Flexible(
                child: Text(
                  text,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: k?.missed ?? false ? _missedRed : null,
                    fontWeight: k?.missed ?? false ? FontWeight.w600 : null,
                  ),
                ),
              ),
              if (chatId != null && action != null) ...[
                const SizedBox(width: Space.sm),
                action == 'Join'
                    ? FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: BrandColors.success,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        onPressed: () =>
                            context.push('/chat/$chatId/call?join=1'),
                        child: const Text('Join'),
                      )
                    : TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => context.push(
                          '/chat/$chatId/call?join=1'
                          '${k?.video ?? false ? '&video=1' : ''}',
                        ),
                        icon: const Icon(CupertinoIcons.phone, size: 16),
                        label: Text(action),
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A meeting's card in the chat: scheduled, recording, minutes, cancelled.
class _MeetingRow extends StatelessWidget {
  const _MeetingRow({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = message;
    final body = m.body ?? 'Meeting';
    final (icon, color) = body.startsWith('Minutes')
        ? (CupertinoIcons.doc_text_fill, BrandColors.success)
        : body.startsWith('Recording')
        ? (CupertinoIcons.circle_fill, Colors.red)
        : body.contains('cancelled')
        ? (CupertinoIcons.calendar_badge_minus, Colors.grey)
        : (CupertinoIcons.calendar, BrandColors.info);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SurfaceCard(
            padding: const EdgeInsets.all(Space.sm),
            onTap: () =>
                context.push('/meetings/${m.recordLink!.substring(8)}'),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: Space.sm),
                Expanded(child: Text(body, style: theme.textTheme.titleSmall)),
                const Icon(CupertinoIcons.chevron_right, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _callLength(Duration d) {
  if (d.inMinutes < 1) return '${d.inSeconds} sec';
  if (d.inHours < 1) return '${d.inMinutes} min';
  return '${d.inHours} h ${d.inMinutes % 60} min';
}

/// Drag a message to the right to reply to it, like WhatsApp.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.child, required this.onReply});

  final Widget child;
  final VoidCallback onReply;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  double _dx = 0;
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) {
        final next = (_dx + d.delta.dx).clamp(0.0, 72.0);
        if (!_armed && next >= 56) HapticFeedback.selectionClick();
        setState(() {
          _dx = next;
          _armed = next >= 56;
        });
      },
      onHorizontalDragEnd: (_) {
        if (_armed) widget.onReply();
        setState(() {
          _dx = 0;
          _armed = false;
        });
      },
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Opacity(
            opacity: (_dx / 56).clamp(0.0, 1.0),
            child: const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(CupertinoIcons.reply, color: BrandColors.maroon),
            ),
          ),
          AnimatedContainer(
            duration: Duration(milliseconds: _dx == 0 ? 180 : 0),
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// Where the unread messages start.
class _NewMessagesLine extends StatelessWidget {
  const _NewMessagesLine();

  @override
  Widget build(BuildContext context) {
    const color = BrandColors.coral;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: [
          Expanded(child: Divider(color: color.withValues(alpha: 0.6))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm),
            child: Text(
              'New messages',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Divider(color: color.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
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
    required this.onReply,
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
  final VoidCallback onReply;

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
                  switch (reply!.kind) {
                    'photo' => '📷 Photo',
                    'voice' => '🎤 Voice note',
                    'file' => '📎 ${reply!.attachmentName ?? 'File'}',
                    _ => reply!.body ?? '',
                  },
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
        if (m.kind == 'voice')
          VoiceNotePlayer(
            id: m.id,
            url: photoUrl,
            bytes: m.bytes,
            durationMs: m.durationMs ?? 0,
            mine: mine,
          ),
        if (m.kind == 'file')
          InkWell(
            borderRadius: BorderRadius.circular(Radii.md),
            onTap: photoUrl == null
                ? null
                : () => launchUrl(
                    Uri.parse(photoUrl!),
                    mode: LaunchMode.externalApplication,
                  ),
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
                    CupertinoIcons.doc_fill,
                    size: 28,
                    color: mine ? Colors.white : BrandColors.info,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.attachmentName ?? 'File',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: fg,
                          ),
                        ),
                        Text(
                          [
                            if (m.attachmentSize != null)
                              _fileSize(m.attachmentSize!),
                            if (m.pending)
                              'uploading'
                            else if (photoUrl != null)
                              'tap to open',
                          ].join(' · '),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: sub,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                      'asset' => Icons.electrical_services_rounded,
                      'tool' => CupertinoIcons.wrench_fill,
                      'doc' => CupertinoIcons.book_fill,
                      _ => CupertinoIcons.tag_fill,
                    },
                    size: 18,
                    color: mine ? Colors.white : BrandColors.info,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    switch (m.recordLink?.split(':').first) {
                      'jobcard' || 'job' => 'Open job card',
                      'asset' => 'Open equipment',
                      'tool' => 'Open tool',
                      'doc' => 'Open document',
                      _ => 'Open',
                    },
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
            _SwipeToReply(
              onReply: onReply,
              child: GestureDetector(
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
                    child: Opacity(
                      opacity: m.pending ? 0.75 : 1,
                      child: content,
                    ),
                  ),
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

String _fileSize(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).ceil()} KB'
    : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

String _mime(String name) => switch (name.split('.').last.toLowerCase()) {
  'pdf' => 'application/pdf',
  'png' => 'image/png',
  'jpg' || 'jpeg' => 'image/jpeg',
  'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'docx' =>
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'csv' => 'text/csv',
  'txt' => 'text/plain',
  _ => 'application/octet-stream',
};

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
                              'asset' => Icons.electrical_services_outlined,
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

/// Picks a document from the site's Documents, with search.
class _DocumentPicker extends ConsumerStatefulWidget {
  const _DocumentPicker();

  @override
  ConsumerState<_DocumentPicker> createState() => _DocumentPickerState();
}

class _DocumentPickerState extends ConsumerState<_DocumentPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _search.text.trim().toLowerCase();
    final docs = ref.watch(documentsProvider);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.sm,
          Space.lg,
          Space.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Share a document', style: theme.textTheme.headlineSmall),
            const SizedBox(height: Space.sm),
            CupertinoSearchTextField(
              controller: _search,
              placeholder: 'Search title or S- code',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.sm),
            Expanded(
              child: docs.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    AppError.from(e).isRetryable
                        ? 'Documents load when you are online.'
                        : AppError.from(e).message,
                  ),
                ),
                data: (all) {
                  final shown = [
                    for (final d in all)
                      if (q.isEmpty ||
                          d.title.toLowerCase().contains(q) ||
                          d.code.toLowerCase().contains(q) ||
                          d.category.toLowerCase().contains(q))
                        d,
                  ];
                  if (shown.isEmpty) {
                    return const Center(
                      child: EmptyState(
                        icon: CupertinoIcons.book,
                        title: 'No documents',
                        message:
                            'SOPs and drawings added in Documents show here.',
                      ),
                    );
                  }
                  return ListView(
                    children: [
                      for (final d in shown)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.xs),
                          child: DocTile(
                            doc: d,
                            trailing: const Icon(CupertinoIcons.paperplane),
                            onTap: () => Navigator.pop(context, d),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
