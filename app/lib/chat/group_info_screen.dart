import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SignedUrlSuccess;
import 'package:url_launcher/url_launcher.dart';

import '../data/app_error.dart';
import '../data/site_data.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/media.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'chat_list_screen.dart' show ChatGroupAvatar;
import 'chat_media.dart';
import 'chat_repository.dart';
import 'chat_video.dart';
import 'downloads.dart';

/// Members of a chat with their role (owner or member).
final chatMemberRolesProvider = FutureProvider.autoDispose
    .family<List<({String id, String role})>, String>((ref, id) async {
      final rows = await ref
          .read(supabaseProvider)
          .from('conversation_members')
          .select('user_id, role')
          .eq('conversation_id', id)
          .eq('is_archived', false);
      return [
        for (final r in rows)
          (id: r['user_id'] as String, role: r['role'] as String? ?? 'member'),
      ];
    });

/// A signed link for the group's picture.
final groupPhotoProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  path,
) async {
  try {
    return await ref
        .read(supabaseProvider)
        .storage
        .from('chat-files')
        .createSignedUrl(path, 3600);
  } catch (_) {
    return null;
  }
});

/// Group (or chat) info: picture, name and description (owners and
/// supervisors edit), members with add and remove, shared media, files and
/// links, starred messages, mute, archive and leave.
class GroupInfoScreen extends ConsumerStatefulWidget {
  const GroupInfoScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  int _tab = 0;

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _run(Future<void> Function() f, {String? done}) async {
    try {
      await f();
      if (done != null && mounted) _snack(done);
    } catch (e) {
      if (!mounted) return;
      _snack(
        AppError.from(e).isRetryable
            ? 'That needs signal.'
            : AppError.from(e).message,
      );
    }
  }

  Future<String?> _ask(String title, String? value, {int lines = 1}) async {
    final c = TextEditingController(text: value);
    final out = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          minLines: 1,
          maxLines: lines,
          maxLength: lines > 1 ? 500 : 80,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, c.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    c.dispose();
    return out;
  }

  Future<void> _mute(Conversation chat) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (chat.muted)
              ListTile(
                leading: const Icon(CupertinoIcons.bell),
                title: const Text('Unmute'),
                onTap: () => Navigator.pop(s, 'off'),
              ),
            for (final (k, label) in const [
              ('8h', '8 hours'),
              ('1w', '1 week'),
              ('always', 'Always'),
            ])
              ListTile(
                leading: const Icon(CupertinoIcons.bell_slash),
                title: Text('Mute for $label'),
                onTap: () => Navigator.pop(s, k),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final a = ref.read(chatActionsProvider);
    await _run(
      () => switch (choice) {
        'off' => a.mute(chat.id),
        '8h' => a.mute(chat.id, until: const Duration(hours: 8)),
        '1w' => a.mute(chat.id, until: const Duration(days: 7)),
        _ => a.mute(chat.id, always: true),
      },
      done: choice == 'off' ? 'Unmuted' : 'Muted',
    );
  }

  Future<void> _addPeople(Conversation chat, Set<String> current) async {
    final people = await ref.read(chatPeopleProvider.future);
    if (!mounted) return;
    final picked = <String>{};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (s) => StatefulBuilder(
        builder: (s, set) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(s).height * 0.7,
            child: Column(
              children: [
                const Text('Add people'),
                Expanded(
                  child: ListView(
                    children: [
                      for (final p in people)
                        if (!current.contains(p.id))
                          CheckboxListTile(
                            value: picked.contains(p.id),
                            onChanged: (v) => set(
                              () => v == true
                                  ? picked.add(p.id)
                                  : picked.remove(p.id),
                            ),
                            secondary: AppAvatar(name: p.name, size: 34),
                            title: Text(p.name),
                          ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(s, true),
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || picked.isEmpty) return;
    await _run(
      () => ref
          .read(chatActionsProvider)
          .updateGroup(chat.id, add: picked.toList()),
      done: 'Added',
    );
    ref.invalidate(chatMemberRolesProvider(chat.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final chats = ref.watch(conversationsProvider).value ?? const [];
    final chat = chats.where((c) => c.id == widget.id).firstOrNull;
    final me = ref.watch(authUserIdProvider);
    final names = ref.watch(peopleProvider).value ?? const {};
    final members =
        ref.watch(chatMemberRolesProvider(widget.id)).value ?? const [];
    final iOwn = members.any((m) => m.id == me && m.role == 'owner');
    final canEdit =
        chat != null &&
        !chat.isDirect &&
        (iOwn ||
            ref.watch(sessionProvider).can('chat.manage', siteId: chat.siteId));
    final photo = chat?.photoPath == null
        ? null
        : ref.watch(groupPhotoProvider(chat!.photoPath!)).value;
    final media = ref.watch(chatMediaProvider(widget.id)).value ?? const [];
    final thread = ref.watch(chatThreadProvider(widget.id));

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: AppBackButton(fallback: '/chat/${widget.id}'),
        title: Text(chat?.isDirect ?? false ? 'Chat info' : 'Group info'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: chat == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  Space.md,
                  top + Space.md,
                  Space.md,
                  Space.xl,
                ),
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: !canEdit
                          ? null
                          : () async {
                              final picked = await PhotoPicking.pick(context);
                              if (picked.isEmpty) return;
                              final small = await compressPhoto(picked.first);
                              await _run(
                                () => ref
                                    .read(chatActionsProvider)
                                    .updateGroupInfo(chat.id, photo: small),
                                done: 'Picture changed',
                              );
                            },
                      child: photo != null
                          ? CircleAvatar(
                              radius: 52,
                              backgroundImage: NetworkImage(photo),
                            )
                          : chat.isDirect
                          ? AppAvatar(name: chat.title, size: 104)
                          : ChatGroupAvatar(chat: chat, size: 104),
                    ),
                  ),
                  if (canEdit)
                    Center(
                      child: Text(
                        'Tap the picture to change it',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  const SizedBox(height: Space.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          chat.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      if (canEdit && !chat.isDefault)
                        IconButton(
                          tooltip: 'Rename',
                          onPressed: () async {
                            final t = await _ask('Group name', chat.title);
                            if (t == null || t.trim().isEmpty) return;
                            await _run(
                              () => ref
                                  .read(chatActionsProvider)
                                  .updateGroup(chat.id, title: t),
                            );
                          },
                          icon: const Icon(CupertinoIcons.pencil),
                        ),
                    ],
                  ),
                  if (!chat.isDirect)
                    Center(
                      child: Text(
                        '${chat.memberCount} members'
                        '${chat.isDefault ? ' · site group (members follow roles)' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: Space.md),
                  if (!chat.isDirect)
                    Panel(
                      title: 'Description',
                      actions: [
                        if (canEdit)
                          IconButton(
                            tooltip: 'Edit description',
                            onPressed: () async {
                              final t = await _ask(
                                'Description',
                                chat.description,
                                lines: 5,
                              );
                              if (t == null) return;
                              await _run(
                                () => ref
                                    .read(chatActionsProvider)
                                    .updateGroupInfo(chat.id, description: t),
                              );
                            },
                            icon: const Icon(CupertinoIcons.pencil),
                          ),
                      ],
                      child: Text(
                        (chat.description ?? '').isEmpty
                            ? 'No description yet.'
                            : chat.description!,
                      ),
                    ),
                  const SizedBox(height: Space.md),
                  Panel(
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            chat.muted
                                ? CupertinoIcons.bell_slash_fill
                                : CupertinoIcons.bell,
                          ),
                          title: Text(chat.muted ? 'Muted' : 'Mute'),
                          subtitle: chat.muted
                              ? Text(
                                  chat.mutedUntil!.year > 9000
                                      ? 'Always'
                                      : 'Until ${MaterialLocalizations.of(context).formatShortDate(chat.mutedUntil!)} '
                                            '${TimeOfDay.fromDateTime(chat.mutedUntil!).format(context)}',
                                )
                              : const Text(
                                  'No push or sound; unread still shows',
                                ),
                          onTap: () => _mute(chat),
                        ),
                        ListTile(
                          leading: const Icon(CupertinoIcons.star),
                          title: const Text('Starred messages'),
                          trailing: Text('${thread.starred.length}'),
                          onTap: () => context.push('/chat/${chat.id}/starred'),
                        ),
                        ListTile(
                          leading: const Icon(CupertinoIcons.archivebox),
                          title: Text(
                            chat.archived ? 'Unarchive chat' : 'Archive chat',
                          ),
                          onTap: () => _run(
                            () => ref
                                .read(chatActionsProvider)
                                .archive(chat.id, !chat.archived),
                            done: chat.archived ? 'Unarchived' : 'Archived',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  if (!chat.isDirect)
                    Panel(
                      title: 'Members',
                      actions: [
                        if (canEdit && !chat.isDefault)
                          IconButton(
                            tooltip: 'Add people',
                            onPressed: () => _addPeople(chat, {
                              for (final m in members) m.id,
                            }),
                            icon: const Icon(CupertinoIcons.person_add),
                          ),
                      ],
                      child: Column(
                        children: [
                          for (final m in members)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: AppAvatar(
                                name: names[m.id] ?? '?',
                                size: 36,
                              ),
                              title: Text(
                                m.id == me ? 'You' : (names[m.id] ?? 'Someone'),
                              ),
                              subtitle: m.role == 'owner'
                                  ? const Text('Group owner')
                                  : null,
                              trailing: canEdit && !chat.isDefault && m.id != me
                                  ? IconButton(
                                      tooltip: 'Remove',
                                      onPressed: () async {
                                        await _run(
                                          () => ref
                                              .read(chatActionsProvider)
                                              .updateGroup(
                                                chat.id,
                                                remove: [m.id],
                                              ),
                                          done: 'Removed',
                                        );
                                        ref.invalidate(
                                          chatMemberRolesProvider(chat.id),
                                        );
                                      },
                                      icon: const Icon(
                                        CupertinoIcons.person_badge_minus,
                                      ),
                                    )
                                  : null,
                              onTap: m.id == me
                                  ? null
                                  : () async {
                                      final id = await ref
                                          .read(chatActionsProvider)
                                          .openDirect(m.id);
                                      if (context.mounted) {
                                        context.push('/chat/$id');
                                      }
                                    },
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: Space.md),
                  Panel(
                    title: 'Shared',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CupertinoSlidingSegmentedControl<int>(
                          groupValue: _tab,
                          onValueChanged: (v) => setState(() => _tab = v ?? 0),
                          children: const {
                            0: Text('Media'),
                            1: Text('Files'),
                            2: Text('Links'),
                          },
                        ),
                        const SizedBox(height: Space.sm),
                        _Shared(tab: _tab, items: media, thread: thread),
                      ],
                    ),
                  ),
                  if (!chat.isDirect && !chat.isDefault) ...[
                    const SizedBox(height: Space.md),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (d) => AlertDialog(
                            title: Text('Leave ${chat.title}?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(d, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(d, true),
                                child: const Text('Leave'),
                              ),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        await _run(
                          () => ref.read(chatActionsProvider).leave(chat.id),
                        );
                        if (context.mounted) context.go('/chat');
                      },
                      icon: const Icon(CupertinoIcons.square_arrow_left),
                      label: const Text('Leave group'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _Shared extends ConsumerWidget {
  const _Shared({required this.tab, required this.items, required this.thread});

  final int tab;
  final List<ChatMessage> items;
  final ChatThread thread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = RegExp(r'https?://\S+');
    final list = [
      for (final m in items)
        if (tab == 0 && (m.kind == 'photo' || m.kind == 'video'))
          m
        else if (tab == 1 && m.kind == 'file')
          m
        else if (tab == 2 && link.hasMatch(m.body ?? ''))
          m,
    ];
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(Space.md),
        child: Center(child: Text('Nothing shared yet.')),
      );
    }
    final urls = thread.photoUrls;
    if (tab == 0) {
      return _MediaGrid(items: list, urls: urls);
    }
    if (tab == 1) {
      return Column(
        children: [
          for (final m in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _SignedFile(message: m),
            ),
        ],
      );
    }
    return Column(
      children: [
        for (final m in list)
          for (final u in link.allMatches(m.body!).map((x) => x.group(0)!))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(CupertinoIcons.link),
              title: Text(u, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () =>
                  launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication),
            ),
      ],
    );
  }
}

/// Signed links for shared items not loaded in the thread.
final _signedProvider = FutureProvider.autoDispose
    .family<Map<String, String>, String>((ref, joined) async {
      final paths = joined.split('|').where((p) => p.isNotEmpty).toList();
      if (paths.isEmpty) return const {};
      final signed = await ref
          .read(supabaseProvider)
          .storage
          .from('chat-files')
          .createSignedUrlsResult(paths, 3600);
      return {
        for (final s in signed.whereType<SignedUrlSuccess>())
          s.path: s.signedUrl,
      };
    });

class _MediaGrid extends ConsumerWidget {
  const _MediaGrid({required this.items, required this.urls});

  final List<ChatMessage> items;
  final Map<String, String> urls;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paths = [
      for (final m in items)
        if (m.attachmentPath != null) m.attachmentPath!,
    ];
    final signed = {
      ...ref.watch(_signedProvider(paths.join('|'))).value ?? const {},
      ...urls,
    };
    final photos = [
      for (final m in items)
        if (m.kind == 'photo') m,
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: [
        for (final m in items)
          GestureDetector(
            onTap: () {
              final url = signed[m.attachmentPath];
              if (url == null) return;
              if (m.kind == 'video') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => VideoPlayerPage(url: url, caption: m.body),
                  ),
                );
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChatMediaViewer(
                      photos: photos,
                      urls: signed,
                      initial: photos.indexOf(m).clamp(0, photos.length - 1),
                      names: ref.read(peopleProvider).value ?? const {},
                      onForward: (_) {},
                      onShowInChat: (_) {},
                    ),
                  ),
                );
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: m.kind == 'video' || signed[m.attachmentPath] == null
                  ? Container(
                      color: Colors.black54,
                      child: Icon(
                        m.kind == 'video'
                            ? CupertinoIcons.play_circle_fill
                            : CupertinoIcons.photo,
                        color: Colors.white,
                      ),
                    )
                  : Image.network(signed[m.attachmentPath]!, fit: BoxFit.cover),
            ),
          ),
      ],
    );
  }
}

class _SignedFile extends ConsumerWidget {
  const _SignedFile({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = message.attachmentPath ?? '';
    final url = ref.watch(_signedProvider(p)).value?[p];
    return FileBubble(
      path: message.attachmentPath,
      url: url,
      name: message.attachmentName ?? 'File',
      size: message.attachmentSize,
      color: BrandColors.info,
    );
  }
}

/// Starred messages in one chat, or (no chat) across all chats.
class StarredScreen extends ConsumerWidget {
  const StarredScreen({super.key, this.conversationId});

  final String? conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final list = ref.watch(starredProvider(conversationId));
    final names = ref.watch(peopleProvider).value ?? const {};
    final chats = {
      for (final c in ref.watch(conversationsProvider).value ?? const [])
        c.id: c.title,
    };
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: AppBackButton(
          fallback: conversationId == null ? '/chat' : '/chat/$conversationId',
        ),
        title: const Text('Starred messages'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              AppError.from(e).isRetryable
                  ? 'Starred messages load when you are connected.'
                  : AppError.from(e).message,
            ),
          ),
          data: (items) => items.isEmpty
              ? const Center(
                  child: EmptyState(
                    icon: CupertinoIcons.star,
                    title: 'No starred messages',
                    message:
                        'Long-press a message and tap Star to keep it here.',
                  ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    Space.md,
                    top + Space.sm,
                    Space.md,
                    Space.xl,
                  ),
                  children: [
                    for (final m in items)
                      ListTile(
                        leading: AppAvatar(
                          name: names[m.authorId] ?? '?',
                          size: 36,
                        ),
                        title: Text(
                          [
                            names[m.authorId] ?? 'Someone',
                            if (conversationId == null)
                              chats[m.conversationId] ?? 'Chat',
                          ].join(' · '),
                          style: theme.textTheme.labelLarge,
                        ),
                        subtitle: Text(
                          m.body ??
                              switch (m.kind) {
                                'photo' => '📷 Photo',
                                'video' => '🎥 Video',
                                'voice' => '🎤 Voice note',
                                'file' => '📎 ${m.attachmentName ?? 'File'}',
                                _ => '',
                              },
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          MaterialLocalizations.of(context)
                              .formatShortMonthDay(m.createdAt),
                          style: theme.textTheme.labelSmall,
                        ),
                        onTap: () => context.push('/chat/${m.conversationId}'),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
