import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../data/site_data.dart';
import '../services/core_providers.dart';
import '../ui/form_sheet.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/page.dart';
import '../ui/surfaces.dart';
import 'chat_repository.dart';
import 'conversation_screen.dart';
import 'presence.dart';

/// The chat open beside the list on wide screens.
final selectedChatProvider = NotifierProvider<SelectedChat, String?>(
  SelectedChat.new,
);

class SelectedChat extends Notifier<String?> {
  @override
  String? build() => null;

  void open(String? id) => state = id;
}

/// Chat tab. Phones: the list, and a chat opens on top. Wide screens: the
/// list on the left and the open chat on the right, so switching is one
/// click.
/// Wide enough for the list and the open chat side by side.
bool chatTwoPanes(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 1000;

/// Opens a chat: beside the list on wide screens, on top on phones.
void openChat(BuildContext context, WidgetRef ref, String id) {
  if (chatTwoPanes(context)) {
    ref.read(selectedChatProvider.notifier).open(id);
  } else {
    context.push('/chat/$id');
  }
}

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Builder(
      builder: (context) {
        if (!chatTwoPanes(context)) {
          return _ChatList(onOpen: (id) => openChat(context, ref, id));
        }
        final selected = ref.watch(selectedChatProvider);
        final g = Glass.of(context);
        return Row(
          children: [
            SizedBox(
              width: 380,
              child: _ChatList(
                selected: selected,
                onOpen: ref.read(selectedChatProvider.notifier).open,
              ),
            ),
            VerticalDivider(width: 1, color: g.border),
            Expanded(
              child: selected == null
                  ? const Center(
                      child: EmptyState(
                        icon: CupertinoIcons.chat_bubble_2,
                        title: 'Pick a chat',
                        message: 'Your messages open here.',
                      ),
                    )
                  : ConversationScreen(
                      key: ValueKey(selected),
                      id: selected,
                      embedded: true,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ChatList extends ConsumerStatefulWidget {
  const _ChatList({required this.onOpen, this.selected});

  final void Function(String id) onOpen;
  final String? selected;

  @override
  ConsumerState<_ChatList> createState() => _ChatListState();
}

class _ChatListState extends ConsumerState<_ChatList> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chats = ref.watch(conversationsProvider);
    final session = ref.watch(sessionProvider);
    final canChat = session.can('chat.use');
    final q = _search.text.trim().toLowerCase();

    List<Widget> tiles(List<Conversation> list, int from) => [
      for (final (i, c) in list.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.xs),
          child: _ChatTile(
            chat: c,
            selected: c.id == widget.selected,
            onOpen: () => widget.onOpen(c.id),
          ),
        ).entrance(context, index: (from + i).clamp(0, 8)),
    ];

    Widget label(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, Space.sm, 0, Space.xs),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return PageScroll(
      maxWidth: 720,
      onRefresh: ref.read(conversationsProvider.notifier).refresh,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(CupertinoIcons.search),
                  hintText: 'Search chats',
                  isDense: true,
                  suffixIcon: q.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(CupertinoIcons.xmark_circle_fill),
                        ),
                ),
              ),
            ),
            if (canChat) ...[
              const SizedBox(width: Space.xs),
              IconButton.filledTonal(
                tooltip: 'New chat',
                onPressed: () => showFormSheet(context, const _NewChatSheet()),
                icon: const Icon(CupertinoIcons.square_pencil),
              ),
            ],
          ],
        ),
        if (canChat && q.isEmpty) _OnlineNow(onOpen: widget.onOpen),
        const SizedBox(height: Space.xs),
        ...chats.when(
          loading: () => [
            for (var i = 0; i < 4; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: Space.sm),
                child: Skeleton(height: 72),
              ),
          ],
          error: (e, _) => [
            EmptyState(
              icon: CupertinoIcons.wifi_slash,
              title: 'Could not load chats',
              message: AppError.from(e).isRetryable
                  ? 'Chats load when you are connected.'
                  : AppError.from(e).message,
            ),
          ],
          data: (all) {
            final list = [
              for (final c in all)
                if (q.isEmpty ||
                    c.title.toLowerCase().contains(q) ||
                    (c.preview?.toLowerCase().contains(q) ?? false))
                  c,
            ];
            if (all.isEmpty) {
              return [
                EmptyState(
                  icon: CupertinoIcons.chat_bubble_2,
                  title: 'No chats yet',
                  message: canChat
                      ? 'Your site groups appear here. Start a chat with '
                            'anyone in the department.'
                      : 'Chat is for the electrical team.',
                ),
              ];
            }
            if (list.isEmpty) {
              return [
                EmptyState(
                  icon: CupertinoIcons.search,
                  title: 'No chats match',
                  message: 'Nothing called "${_search.text.trim()}".',
                ),
              ];
            }
            final pinned = [
              for (final c in list)
                if (c.pinned) c,
            ];
            final rest = [
              for (final c in list)
                if (!c.pinned) c,
            ];
            return [
              if (pinned.isNotEmpty) ...[
                label('Pinned'),
                ...tiles(pinned, 0),
                label('All chats'),
              ],
              ...tiles(rest, pinned.length),
            ];
          },
        ),
      ],
    );
  }
}

/// A row of people who have the app open now; tap one to chat.
class _OnlineNow extends ConsumerWidget {
  const _OnlineNow({required this.onOpen});

  final void Function(String id) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final me = ref.watch(authUserIdProvider);
    final online = ref.watch(chatPresenceProvider.select((p) => p.online));
    final people = ref.watch(chatPeopleProvider).value ?? const [];
    final here = [
      for (final p in people)
        if (p.id != me && online.contains(p.id)) p,
    ];
    if (here.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ONLINE NOW · ${here.length}',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.xs),
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: here.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
              itemBuilder: (context, i) {
                final p = here[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(Radii.md),
                  onTap: () async {
                    try {
                      final id = await ref
                          .read(chatActionsProvider)
                          .openDirect(p.id);
                      onOpen(id);
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(AppError.from(e).message)),
                      );
                    }
                  },
                  child: SizedBox(
                    width: 60,
                    child: Column(
                      children: [
                        OnlineAvatar(name: p.name, online: true, size: 50),
                        const SizedBox(height: 4),
                        Text(
                          p.name.split(' ').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A person's avatar with a green dot while they have the app open.
class OnlineAvatar extends StatelessWidget {
  const OnlineAvatar({
    super.key,
    required this.name,
    required this.online,
    this.size = 48,
  });

  final String name;
  final bool online;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dot = (size * 0.28).clamp(10.0, 16.0);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AppAvatar(name: name, size: size),
          if (online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: BrandColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String chatTime(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final hm =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (day == today) return hm;
  if (today.difference(day).inDays == 1) return 'Yesterday';
  if (today.difference(day).inDays < 7) {
    return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][t.weekday -
        1];
  }
  return '${t.day}/${t.month}';
}

/// Round icon for a group: a bolt for the department, people otherwise.
class ChatGroupAvatar extends StatelessWidget {
  const ChatGroupAvatar({super.key, required this.chat, this.size = 48});

  final Conversation chat;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: chat.isDefault
            ? BrandColors.brandGradient
            : const LinearGradient(
                colors: [BrandColors.coral, BrandColors.info],
              ),
      ),
      child: Icon(
        chat.siteId == null && chat.isDefault
            ? CupertinoIcons.bolt_fill
            : CupertinoIcons.person_3_fill,
        color: Colors.white,
        size: size * 0.46,
      ),
    );
  }
}

class _ChatTile extends ConsumerWidget {
  const _ChatTile({
    required this.chat,
    required this.selected,
    required this.onOpen,
  });

  final Conversation chat;
  final bool selected;
  final VoidCallback onOpen;

  void _menu(BuildContext context, WidgetRef ref) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                chat.pinned ? CupertinoIcons.pin_slash : CupertinoIcons.pin,
              ),
              title: Text(chat.pinned ? 'Unpin chat' : 'Pin to the top'),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(
                  ref.read(chatActionsProvider).pin(chat.id, !chat.pinned),
                );
              },
            ),
            if (chat.unread > 0)
              ListTile(
                leading: const Icon(CupertinoIcons.checkmark_alt_circle),
                title: const Text('Mark as read'),
                onTap: () {
                  Navigator.pop(sheet);
                  unawaited(ref.read(chatActionsProvider).markRead(chat.id));
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = chat;
    final unread = c.unread > 0;
    final me = ref.watch(authUserIdProvider);
    final presence = ref.watch(chatPresenceProvider);
    final names = ref.watch(peopleProvider).value ?? const {};
    final typing = presence.typingIn(c.id, except: me);
    final typingText = typing.isEmpty
        ? null
        : c.isDirect
        ? 'typing…'
        : typing.length == 1
        ? '${(names[typing.first] ?? 'Someone').split(' ').first} is typing…'
        : '${typing.length} people are typing…';

    return GestureDetector(
      onLongPress: () => _menu(context, ref),
      onSecondaryTap: () => _menu(context, ref),
      child: SurfaceCard(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        color: selected ? BrandColors.maroon.withValues(alpha: 0.12) : null,
        onTap: onOpen,
        child: Row(
          children: [
            c.isDirect
                ? OnlineAvatar(
                    name: c.title,
                    online: presence.isOnline(c.otherUserId),
                  )
                : ChatGroupAvatar(chat: c),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: unread ? FontWeight.w800 : null,
                          ),
                        ),
                      ),
                      if (c.callLive)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            CupertinoIcons.phone_fill,
                            size: 14,
                            color: BrandColors.success,
                          ),
                        ),
                      if (c.pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            CupertinoIcons.pin_fill,
                            size: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (c.lastMessageAt != null)
                        Text(
                          chatTime(c.lastMessageAt!),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: unread ? BrandColors.maroon : null,
                            fontWeight: unread ? FontWeight.w700 : null,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          typingText ??
                              (c.callLive
                                  ? 'Call in progress · tap to join'
                                  : null) ??
                              c.preview ??
                              (c.isDirect
                                  ? 'Say hello'
                                  : '${c.memberCount} members'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: typingText != null
                                ? BrandColors.coral
                                : unread
                                ? theme.colorScheme.onSurface
                                : null,
                            fontStyle: typingText != null
                                ? FontStyle.italic
                                : null,
                            fontWeight: unread ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                      if (unread)
                        Container(
                          margin: const EdgeInsets.only(left: Space.xs),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: BrandColors.maroon,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            c.unread > 99 ? '99+' : '${c.unread}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
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

/// Pick someone for a direct chat, or (supervisors) make a group.
class _NewChatSheet extends ConsumerStatefulWidget {
  const _NewChatSheet();

  @override
  ConsumerState<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<_NewChatSheet> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _picked = <String>{};
  bool _group = false;
  bool _siteOnly = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _open(String userId) async {
    setState(() => _busy = true);
    try {
      final id = await ref.read(chatActionsProvider).openDirect(userId);
      if (!mounted) return;
      Navigator.pop(context);
      openChat(context, ref, id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AppError.from(e).message;
        });
      }
    }
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the group a name');
      return;
    }
    setState(() => _busy = true);
    try {
      final site = ref.read(currentSiteProvider);
      final id = await ref.read(chatActionsProvider).createGroup(
        _name.text,
        _siteOnly ? site?.id : null,
        [..._picked],
      );
      if (!mounted) return;
      Navigator.pop(context);
      openChat(context, ref, id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AppError.from(e).message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = ref.watch(chatPeopleProvider);
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final canGroup = session.can('chat.manage', siteId: site?.id);
    final q = _search.text.trim().toLowerCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _group ? 'New group' : 'New chat',
            style: theme.textTheme.headlineSmall,
          ),
          if (canGroup)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Direct'),
                    icon: Icon(CupertinoIcons.person),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Group'),
                    icon: Icon(CupertinoIcons.person_3),
                  ),
                ],
                selected: {_group},
                onSelectionChanged: (s) => setState(() => _group = s.first),
              ),
            ),
          if (_group) ...[
            const SizedBox(height: Space.sm),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Group name, e.g. Substation upgrade',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _siteOnly,
              onChanged: (v) => setState(() => _siteOnly = v),
              title: Text('Only people at ${site?.name ?? 'this site'}'),
            ),
          ],
          const SizedBox(height: Space.sm),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(CupertinoIcons.search),
              hintText: 'Search people',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: Space.xs),
          Flexible(
            child: people.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(Space.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Text(AppError.from(e).message),
              ),
              data: (list) {
                final shown = [
                  for (final p in list)
                    if (q.isEmpty || p.name.toLowerCase().contains(q)) p,
                ];
                return ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in shown)
                      _group
                          ? CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _picked.contains(p.id),
                              onChanged: (v) => setState(
                                () => v == true
                                    ? _picked.add(p.id)
                                    : _picked.remove(p.id),
                              ),
                              secondary: AppAvatar(name: p.name, size: 36),
                              title: Text(p.name),
                            )
                          : ListTile(
                              contentPadding: EdgeInsets.zero,
                              enabled: !_busy,
                              leading: AppAvatar(name: p.name, size: 36),
                              title: Text(p.name),
                              trailing: const Icon(
                                CupertinoIcons.chevron_right,
                                size: 16,
                              ),
                              onTap: () => _open(p.id),
                            ),
                  ],
                );
              },
            ),
          ),
          if (_group)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.md),
              child: FilledButton(
                onPressed: _busy ? null : _create,
                child: Text(
                  _picked.isEmpty
                      ? 'Create group'
                      : 'Create group with ${_picked.length}',
                ),
              ),
            )
          else
            const SizedBox(height: Space.md),
        ],
      ),
    );
  }
}
