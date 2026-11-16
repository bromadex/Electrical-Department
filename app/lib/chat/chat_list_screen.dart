import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
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
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'camera_screen.dart';
import 'chat_media.dart';
import 'chat_video.dart';
import 'group_info_screen.dart';
import '../meetings/meetings_list_screen.dart';
import 'calls_screen.dart';
import 'chat_repository.dart';
import 'conversation_screen.dart';
import 'presence.dart';
import 'wallpaper.dart';

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
void openChat(
  BuildContext context,
  WidgetRef ref,
  String id, {
  bool fromOutside = false,
}) {
  if (chatTwoPanes(context)) {
    ref.read(selectedChatProvider.notifier).open(id);
    // From outside Chat (the ➕ sheet), go to Chat to show it.
    if (fromOutside) context.push('/chat');
  } else {
    context.push('/chat/$id');
  }
}

/// Chat as its own page (from the floating chat button), like WhatsApp for
/// iPhone: Chats, Calls, Meetings and Starred along the bottom. Back
/// returns to the screen you were on.
class ChatHomeScreen extends ConsumerStatefulWidget {
  const ChatHomeScreen({super.key});

  @override
  ConsumerState<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends ConsumerState<ChatHomeScreen> {
  int _tab = 0;

  static const _tabs = [
    (CupertinoIcons.chat_bubble_2, CupertinoIcons.chat_bubble_2_fill, 'Chats'),
    (CupertinoIcons.phone, CupertinoIcons.phone_fill, 'Calls'),
    (CupertinoIcons.person_3, CupertinoIcons.person_3_fill, 'Meetings'),
    (CupertinoIcons.star, CupertinoIcons.star_fill, 'Starred'),
  ];

  @override
  Widget build(BuildContext context) {
    return ChatThemed(
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final unread = ref.watch(chatUnreadProvider);
          final missed = ref.watch(missedCallsProvider).value ?? 0;
          final body = IndexedStack(
            index: _tab,
            children: const [
              ChatListScreen(),
              CallsScreen(),
              MeetingsListScreen(plain: true),
              StarredScreen(),
            ],
          );
          // Computers: WhatsApp Desktop's layout, a thin icon rail on the
          // left, then the chat list and the open chat.
          if (MediaQuery.sizeOf(context).width >= 1000) {
            return Scaffold(
              body: Row(
                children: [
                  _Rail(
                    tab: _tab,
                    tabs: _tabs,
                    unread: unread,
                    missed: missed,
                    onTab: (i) => setState(() => _tab = i),
                  ),
                  VerticalDivider(width: 1, color: theme.dividerColor),
                  Expanded(child: body),
                ],
              ),
            );
          }
          return Scaffold(
            body: IndexedStack(
              index: _tab,
              children: const [
                ChatListScreen(),
                CallsScreen(),
                MeetingsListScreen(plain: true),
                StarredScreen(),
              ],
            ),
            extendBody: true,
            // A floating frosted tab bar, as in WhatsApp's liquid-glass look.
            bottomNavigationBar: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: ChatFrost(
                radius: 30,
                child: SizedBox(
                  height: 62,
                  child: Row(
                    children: [
                      for (final (i, t) in _tabs.indexed)
                        Expanded(
                          child: InkResponse(
                            onTap: () => setState(() => _tab = i),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Badge(
                                  isLabelVisible:
                                      (i == 0 && unread > 0) ||
                                      (i == 1 && missed > 0),
                                  label: Text('${i == 0 ? unread : missed}'),
                                  child: Icon(
                                    _tab == i ? t.$2 : t.$1,
                                    size: 26,
                                    color: _tab == i
                                        ? theme.colorScheme.onSurface
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  t.$3,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: _tab == i
                                        ? theme.colorScheme.onSurface
                                        : theme.colorScheme.onSurfaceVariant,
                                    fontWeight: _tab == i
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
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
        },
      ),
    );
  }
}

/// The left icon rail on computers: Chats, Calls, Meetings, Starred, and
/// at the bottom back to the app, Settings and your photo.
class _Rail extends ConsumerWidget {
  const _Rail({
    required this.tab,
    required this.tabs,
    required this.unread,
    required this.missed,
    required this.onTab,
  });

  final int tab;
  final List<(IconData, IconData, String)> tabs;
  final int unread;
  final int missed;
  final void Function(int) onTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final me = ref.watch(authUserIdProvider);
    final names = ref.watch(peopleProvider).value ?? const {};
    Widget item(
      IconData icon,
      String tip,
      VoidCallback onTap, {
      bool on = false,
      int badge = 0,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message: tip,
        child: Material(
          color: on
              ? (dark ? ChatColors.selectedDark : ChatColors.selected)
              : Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 44,
              child: Badge(
                isLabelVisible: badge > 0,
                label: Text(badge > 99 ? '99+' : '$badge'),
                child: Icon(
                  icon,
                  color: on
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Container(
      width: 64,
      color: dark ? const Color(0xFF111B21) : ChatColors.grouped,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            for (final (i, t) in tabs.indexed)
              item(
                tab == i ? t.$2 : t.$1,
                t.$3,
                () => onTab(i),
                on: tab == i,
                badge: i == 0
                    ? unread
                    : i == 1
                    ? missed
                    : 0,
              ),
            const Spacer(),
            item(
              CupertinoIcons.square_arrow_left,
              'Back to the app',
              () => context.canPop() ? context.pop() : context.go('/home'),
            ),
            item(
              CupertinoIcons.gear,
              'Settings',
              () => context.push('/settings'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 0, 14),
              child: AppAvatar(name: names[me] ?? 'You', size: 34),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The Chat tab is WhatsApp green; the rest of the app stays burgundy.
    return ChatThemed(child: _build(context, ref));
  }

  Widget _build(BuildContext context, WidgetRef ref) {
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

enum _Filter { all, unread, favourites, groups }

/// The chat list like WhatsApp for iPhone: a large "Chats" title that
/// shrinks into the bar, … / camera / green ➕, search, filter chips, the
/// Archived row, rows with ticks, green unread counts and dividers.
class _ChatListState extends ConsumerState<_ChatList> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  bool _archivedView = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _menu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.square_pencil),
              title: const Text('New chat or group'),
              onTap: () {
                Navigator.pop(sheet);
                showFormSheet(context, const NewChatSheet());
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.star),
              title: const Text('Starred messages'),
              onTap: () {
                Navigator.pop(sheet);
                context.push('/starred');
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.archivebox),
              title: const Text('Archived chats'),
              onTap: () {
                Navigator.pop(sheet);
                setState(() => _archivedView = true);
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.checkmark_alt_circle),
              title: const Text('Read all'),
              onTap: () {
                Navigator.pop(sheet);
                for (final c
                    in ref.read(conversationsProvider).value ?? const []) {
                  if (c.unread > 0) {
                    unawaited(ref.read(chatActionsProvider).markRead(c.id));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// The chat camera from the list: take it, pick a chat, send.
  Future<void> _camera() async {
    final shot = await Navigator.of(context).push<CameraShot>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const ChatCameraScreen(),
      ),
    );
    if (shot == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final chats = ref.read(conversationsProvider).value ?? const [];
    final to = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (s) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(s).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Send to')),
              for (final c in chats)
                ListTile(
                  leading: c.isDirect
                      ? AppAvatar(
                          name: c.title,
                          userId: c.otherUserId,
                          size: 40,
                        )
                      : ChatGroupAvatar(chat: c, size: 40),
                  title: Text(c.title),
                  onTap: () => Navigator.pop(s, c.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (to == null || !mounted) return;
    final actions = ref.read(chatActionsProvider);
    if (shot.video) {
      final v = await prepareChatVideo(shot.file, messenger: messenger);
      if (v == null) return;
      await actions.send(to, video: v);
    } else {
      await actions.send(
        to,
        photo: await compressPhoto(await shot.file.readAsBytes()),
      );
    }
    if (mounted) widget.onOpen(to);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chats = ref.watch(conversationsProvider);
    final session = ref.watch(sessionProvider);
    final canChat = session.can('chat.use');
    final q = _search.text.trim().toLowerCase();
    final all = chats.value ?? const <Conversation>[];
    final archived = [
      for (final c in all)
        if (c.archived) c,
    ];
    bool keep(Conversation c) {
      if (q.isNotEmpty) {
        return c.title.toLowerCase().contains(q) ||
            (c.preview?.toLowerCase().contains(q) ?? false);
      }
      if (_archivedView) return c.archived;
      if (c.archived) return false;
      return switch (_filter) {
        _Filter.all => true,
        _Filter.unread => c.unread > 0,
        _Filter.favourites => c.favourite,
        _Filter.groups => !c.isDirect,
      };
    }

    final shown = [
      for (final c in all)
        if (keep(c)) c,
    ];
    final sub = theme.colorScheme.onSurfaceVariant;

    Widget chip(_Filter f, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == f,
        onSelected: (_) => setState(() => _filter = f),
      ),
    );

    return RefreshIndicator(
      onRefresh: ref.read(conversationsProvider.notifier).refresh,
      child: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            pinned: true,
            leading: _archivedView
                ? IconButton(
                    tooltip: 'Back to chats',
                    onPressed: () => setState(() => _archivedView = false),
                    icon: const Icon(CupertinoIcons.chevron_back),
                  )
                : const AppBackButton(fallback: '/home'),
            title: Text(_archivedView ? 'Archived' : 'Chats'),
            actions: [
              if (canChat && !_archivedView) ...[
                IconButton(
                  tooltip: 'More',
                  onPressed: _menu,
                  icon: const Icon(CupertinoIcons.ellipsis_circle),
                ),
                if (!kIsWeb)
                  IconButton(
                    tooltip: 'Camera',
                    onPressed: _camera,
                    icon: const Icon(CupertinoIcons.camera),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton.filled(
                    tooltip: 'New chat',
                    onPressed: () =>
                        showFormSheet(context, const NewChatSheet()),
                    // White on green (the bar's icons are green).
                    icon: Icon(
                      CupertinoIcons.add,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: Icon(CupertinoIcons.search, color: sub),
                  hintText: 'Search',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  suffixIcon: q.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () => setState(_search.clear),
                          icon: Icon(
                            CupertinoIcons.xmark_circle_fill,
                            color: sub,
                          ),
                        ),
                ),
              ),
            ),
          ),
          if (!_archivedView && q.isEmpty)
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Row(
                  children: [
                    chip(_Filter.all, 'All'),
                    chip(_Filter.unread, 'Unread'),
                    chip(_Filter.favourites, 'Favourites'),
                    chip(_Filter.groups, 'Groups'),
                  ],
                ),
              ),
            ),
          if (!_archivedView &&
              q.isEmpty &&
              _filter == _Filter.all &&
              archived.isNotEmpty)
            SliverToBoxAdapter(
              child: InkWell(
                onTap: () => setState(() => _archivedView = true),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(30, 10, 16, 10),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.archivebox, color: sub, size: 22),
                      const SizedBox(width: 30),
                      Expanded(
                        child: Text(
                          'Archived',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '${archived.length}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (chats.isLoading && all.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (chats.hasError && all.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: CupertinoIcons.wifi_slash,
                title: 'Could not load chats',
                message: AppError.from(chats.error!).isRetryable
                    ? 'Chats load when you are connected.'
                    : AppError.from(chats.error!).message,
              ),
            )
          else if (shown.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: q.isNotEmpty
                    ? CupertinoIcons.search
                    : CupertinoIcons.chat_bubble_2,
                title: q.isNotEmpty
                    ? 'No chats match'
                    : all.isEmpty
                    ? 'No chats yet'
                    : switch (_filter) {
                        _Filter.unread => 'No unread chats',
                        _Filter.favourites => 'No favourites yet',
                        _Filter.groups => 'No groups',
                        _Filter.all => 'Nothing here',
                      },
                message: q.isNotEmpty
                    ? 'Nothing called "${_search.text.trim()}".'
                    : all.isEmpty
                    ? (canChat
                          ? 'Your site groups appear here. Tap ➕ to chat '
                                'with anyone in the department.'
                          : 'Chat is for the electrical team.')
                    : _filter == _Filter.favourites
                    ? 'Long-press a chat and choose Add to favourites.'
                    : '',
              ),
            )
          else
            SliverList.separated(
              itemCount: shown.length,
              separatorBuilder: (_, _) => const Divider(indent: 84),
              itemBuilder: (_, i) => _ChatTile(
                chat: shown[i],
                selected: shown[i].id == widget.selected,
                onOpen: () => widget.onOpen(shown[i].id),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.lock_fill, size: 12, color: sub),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        text: 'Messages stay inside ',
                        children: [
                          TextSpan(
                            text: 'Bravura Electrical',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      style: theme.textTheme.labelSmall,
                    ),
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

/// A person's avatar with a green dot while they have the app open.
class OnlineAvatar extends StatelessWidget {
  const OnlineAvatar({
    super.key,
    required this.name,
    required this.online,
    this.size = 48,
    this.userId,
  });

  final String name;
  final String? userId;
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
          AppAvatar(name: name, size: size, userId: userId),
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
    // WhatsApp's pale green group circle (everywhere).
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dark ? ChatColors.chipDark : ChatColors.chip,
      ),
      child: Icon(
        chat.siteId == null && chat.isDefault
            ? CupertinoIcons.bolt_fill
            : CupertinoIcons.person_3_fill,
        color: dark ? ChatColors.greenLight : ChatColors.greenDeep,
        size: size * 0.5,
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
            ListTile(
              leading: Icon(
                chat.favourite
                    ? CupertinoIcons.heart_slash
                    : CupertinoIcons.heart,
              ),
              title: Text(
                chat.favourite ? 'Remove from favourites' : 'Add to favourites',
              ),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(
                  ref
                      .read(chatActionsProvider)
                      .favourite(chat.id, !chat.favourite),
                );
              },
            ),
            ListTile(
              leading: Icon(
                chat.muted ? CupertinoIcons.bell : CupertinoIcons.bell_slash,
              ),
              title: Text(chat.muted ? 'Unmute' : 'Mute for 8 hours'),
              subtitle: chat.muted
                  ? null
                  : const Text('More choices in the chat\'s info'),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(
                  chat.muted
                      ? ref.read(chatActionsProvider).mute(chat.id)
                      : ref
                            .read(chatActionsProvider)
                            .mute(chat.id, until: const Duration(hours: 8)),
                );
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.archivebox),
              title: Text(chat.archived ? 'Unarchive' : 'Archive'),
              subtitle: chat.archived
                  ? null
                  : const Text('Hidden until a new message comes'),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(
                  ref
                      .read(chatActionsProvider)
                      .archive(chat.id, !chat.archived),
                );
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.info),
              title: Text(chat.isDirect ? 'Chat info' : 'Group info'),
              onTap: () {
                Navigator.pop(sheet);
                context.push('/chat/${chat.id}/info');
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
    final dark = theme.brightness == Brightness.dark;
    final c = chat;
    final unread = c.unread > 0;
    final me = ref.watch(authUserIdProvider);
    final presence = ref.watch(chatPresenceProvider);
    final names = ref.watch(peopleProvider).value ?? const {};
    final green = theme.colorScheme.primary;
    final sub = theme.colorScheme.onSurfaceVariant;
    final typing = presence.typingIn(c.id, except: me);
    final typingText = typing.isEmpty
        ? null
        : c.isDirect
        ? 'typing…'
        : typing.length == 1
        ? '${(names[typing.first] ?? 'Someone').split(' ').first} is typing…'
        : '${typing.length} people are typing…';
    final photo = c.photoPath == null
        ? null
        : ref.watch(groupPhotoProvider(c.photoPath!)).value;

    // The last message as WhatsApp shows it: "You:" or the sender's first
    // name in groups, a tick for yours, an icon for photos, videos, voice
    // notes and files.
    final mine = c.lastAuthorId != null && c.lastAuthorId == me;
    var body = c.preview ?? '';
    final colon = body.indexOf(': ');
    if (colon > 0 && colon < 60) body = body.substring(colon + 2);
    final isLocation = body.startsWith('📍');
    final isPoll = body.startsWith('📊');
    body = body
        .replaceFirst(RegExp(r'^(📷|🎥|🎤|📎|🔖|📞|📍|📊) ?'), '')
        .split('\n')
        .first;
    final who = c.isDirect || c.lastAuthorId == null
        ? null
        : mine
        ? 'You'
        : (names[c.lastAuthorId] ?? '').split(' ').first;
    final kindIcon = isLocation
        ? CupertinoIcons.location_solid
        : isPoll
        ? CupertinoIcons.chart_bar_alt_fill
        : switch (c.lastKind) {
            'photo' => CupertinoIcons.camera_fill,
            'video' => CupertinoIcons.video_camera_solid,
            'voice' => CupertinoIcons.mic_fill,
            'file' => CupertinoIcons.doc_fill,
            'record' => CupertinoIcons.tag_fill,
            _ => null,
          };
    final tick = !mine
        ? null
        : switch (c.lastTick) {
            'read' => (Icons.done_all_rounded, ChatColors.blueLight),
            'delivered' => (Icons.done_all_rounded, sub),
            _ => (Icons.done_rounded, sub),
          };

    final Widget preview;
    if (typingText != null) {
      preview = Text(
        typingText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: green,
          fontWeight: FontWeight.w500,
        ),
      );
    } else if (c.callLive) {
      preview = Row(
        children: [
          Icon(CupertinoIcons.phone_fill, size: 15, color: green),
          const SizedBox(width: 4),
          Text(
            'Call in progress · tap to join',
            style: theme.textTheme.bodyMedium?.copyWith(color: green),
          ),
        ],
      );
    } else {
      preview = Text.rich(
        TextSpan(
          children: [
            if (who != null && who.isNotEmpty) TextSpan(text: '$who: '),
            if (tick != null)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Icon(tick.$1, size: 17, color: tick.$2),
                ),
              ),
            if (kindIcon != null)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Icon(kindIcon, size: 15, color: sub),
                ),
              ),
            TextSpan(
              text: body.isNotEmpty
                  ? body
                  : (c.isDirect ? 'Say hello' : '${c.memberCount} members'),
            ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(color: sub, height: 1.25),
      );
    }

    return Material(
      color: selected
          ? (dark ? ChatColors.selectedDark : ChatColors.selected)
          : Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        onLongPress: () => _menu(context, ref),
        onSecondaryTap: () => _menu(context, ref),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              photo != null
                  ? CircleAvatar(
                      radius: 28,
                      backgroundImage: NetworkImage(photo),
                    )
                  : c.isDirect
                  ? OnlineAvatar(
                      name: c.title,
                      userId: c.otherUserId,
                      online: presence.isOnline(c.otherUserId),
                      size: 56,
                    )
                  : ChatGroupAvatar(chat: c, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (c.lastMessageAt != null)
                          Text(
                            chatTime(c.lastMessageAt!),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: unread ? green : sub,
                              fontWeight: unread ? FontWeight.w600 : null,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: preview),
                        if (c.muted)
                          Padding(
                            padding: const EdgeInsets.only(left: 6, top: 2),
                            child: Icon(
                              CupertinoIcons.bell_slash_fill,
                              size: 15,
                              color: sub,
                            ),
                          ),
                        if (c.mentions > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 6, top: 1),
                            child: CircleAvatar(
                              radius: 10,
                              backgroundColor: green,
                              child: Text(
                                '@',
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        if (unread)
                          Container(
                            margin: const EdgeInsets.only(left: 6, top: 1),
                            constraints: const BoxConstraints(minWidth: 20),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: c.muted ? sub : green,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              c.unread > 99 ? '99+' : '${c.unread}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.colorScheme.onPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        else if (c.pinned)
                          Padding(
                            padding: const EdgeInsets.only(left: 6, top: 2),
                            child: Icon(
                              CupertinoIcons.pin_fill,
                              size: 15,
                              color: sub,
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
      ),
    );
  }
}

/// Pick someone for a direct chat, or (supervisors) make a group.
/// [fromOutside]: opened from the ➕ sheet, so it goes to Chat afterwards.
class NewChatSheet extends ConsumerStatefulWidget {
  const NewChatSheet({super.key, this.fromOutside = false});

  final bool fromOutside;

  @override
  ConsumerState<NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<NewChatSheet> {
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
      openChat(context, ref, id, fromOutside: widget.fromOutside);
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
      openChat(context, ref, id, fromOutside: widget.fromOutside);
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
