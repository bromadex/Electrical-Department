import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../ui/form_sheet.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/page.dart';
import '../ui/surfaces.dart';
import 'chat_repository.dart';

/// Chat tab: the department, site and private groups plus direct chats.
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final chats = ref.watch(conversationsProvider);
    final session = ref.watch(sessionProvider);
    final canChat = session.can('chat.use');

    return PageScroll(
      maxWidth: 720,
      onRefresh: ref.read(conversationsProvider.notifier).refresh,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Chats', style: theme.textTheme.headlineMedium),
            ),
            if (canChat)
              FilledButton.icon(
                onPressed: () => showFormSheet(context, const _NewChatSheet()),
                icon: const Icon(CupertinoIcons.square_pencil, size: 18),
                label: const Text('New chat'),
              ),
          ],
        ),
        const SizedBox(height: Space.md),
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
          data: (list) => list.isEmpty
              ? [
                  EmptyState(
                    icon: CupertinoIcons.chat_bubble_2,
                    title: 'No chats yet',
                    message: canChat
                        ? 'Your site groups appear here. Start a chat with '
                              'anyone in the department.'
                        : 'Chat is for the electrical team.',
                  ),
                ]
              : [
                  for (final (i, c) in list.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: _ChatTile(chat: c),
                    ).entrance(context, index: i.clamp(0, 8)),
                ],
        ),
      ],
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

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat});

  final Conversation chat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = chat;
    final unread = c.unread > 0;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      onTap: () => context.push('/chat/${c.id}'),
      child: Row(
        children: [
          c.isDirect
              ? AppAvatar(name: c.title, size: 48)
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
                        c.preview ??
                            (c.isDirect
                                ? 'Say hello'
                                : '${c.memberCount} members'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: unread ? theme.colorScheme.onSurface : null,
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
      context.push('/chat/$id');
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
      context.push('/chat/$id');
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
