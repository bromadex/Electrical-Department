import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../chat/chat_repository.dart';
import '../checklists/checklists_repository.dart';
import '../data/local_db.dart';
import '../documents/documents_repository.dart';
import '../services/core_providers.dart';
import '../services/notifications_controller.dart';
import '../services/push_service.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../tools/tools_repository.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/page.dart';
import '../ui/surfaces.dart';
import '../ui/tiles.dart';
import '../v2/dashboard/dashboard_data.dart';
import '../v2/dashboard/dashboard_screen.dart';
import '../v2/my_jobs/my_jobs_screen.dart' show myJobsProvider;
import '../v2/requests/models.dart';
import '../v2/requests/repository.dart';
import '../v2/requests/request_tile.dart';
import '../v2/site_filter.dart';
import '../widgets/push_prompt.dart';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Home: what I need to do now, the site in four numbers, and a way into
/// every part of the app.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return PageScroll(
      maxWidth: 1180,
      onRefresh: () async {
        ref.invalidate(checklistStatusProvider);
        ref.invalidate(dashboardProvider);
        ref.invalidate(myJobsProvider);
        await Future.wait([
          ref.read(sessionProvider.notifier).refresh(),
          ref.read(notificationsProvider.notifier).refresh(),
        ]);
      },
      children: [
        const PushPrompt(),
        _Greeting(session: session).entrance(context),
        const SizedBox(height: Space.md),
        LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _ToDo().entrance(context, index: 1),
                  const SizedBox(height: Space.md),
                  const _SiteNumbers().entrance(context, index: 2),
                  const _Shortcuts(),
                  const SizedBox(height: Space.md),
                  const _Latest().entrance(context, index: 4),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(flex: 3, child: _ToDo()),
                    const SizedBox(width: Space.md),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: const [
                          _SiteNumbers(),
                          SizedBox(height: Space.md),
                          _Latest(),
                        ],
                      ),
                    ),
                  ],
                ).entrance(context, index: 1),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting({required this.session});

  final SessionState session;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final site = ref.watch(currentSiteProvider);
    final now = harareNow();
    final first = (session.profile?.fullName ?? '').split(' ').first;
    final hello = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 4, top: Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            first.isEmpty ? hello : '$hello, $first',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '${_days[now.weekday - 1]} ${now.day} ${_months[now.month - 1]}'
            '${site == null ? '' : ' · ${site.name}'}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// What needs me: job cards first (critical, overdue, to assign, to verify,
/// mine), then checklists due, documents to sign and tools to return.
class _ToDo extends ConsumerWidget {
  const _ToDo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final me = ref.watch(authUserIdProvider);
    final tools = ref.watch(siteToolsProvider).value ?? const <LocalTool>[];
    final templates = ref.watch(checklistTemplatesProvider).value ?? const [];
    final status = ref.watch(checklistStatusProvider).value ?? const {};
    final toSign = ref.watch(toSignCountProvider);
    bool can(String code) => site != null && session.can(code, siteId: site.id);
    final now = DateTime.now();

    final extra = <NeedsYouItem>[
      for (final t in templates)
        if (status[t.id] case final s?
            when !s.done && _sameDay(s.dueBy.toLocal(), now))
          if (t.assigneeId == null ||
              t.assigneeId == me ||
              can('checklists.manage'))
            (
              icon: CupertinoIcons.checkmark_rectangle,
              color: BrandColors.success,
              title: t.name,
              detail: 'Checklist due today',
              onTap: () => context.push('/checklists/${t.id}'),
            ),
      if (toSign > 0)
        (
          icon: CupertinoIcons.signature,
          color: BrandColors.coral,
          title: toSign == 1
              ? '1 document to read and sign'
              : '$toSign documents to read and sign',
          detail: 'SOPs and safety notices',
          onTap: () => context.push('/documents'),
        ),
      for (final t in tools)
        if (t.holderId == me)
          (
            icon: CupertinoIcons.wrench_fill,
            color: toolOverdue(t)
                ? const Color(0xFFE5484D)
                : BrandColors.warning,
            title: 'Return ${t.name}',
            detail: t.dueBack == null
                ? t.code
                : '${t.code} · ${toolOverdue(t) ? 'was due' : 'due'} back '
                      '${t.dueBack!.day}/${t.dueBack!.month}',
            onTap: () => context.push('/tools/${t.id}'),
          ),
    ];

    if (!can('jc.view')) return _MyRequests(extra: extra);

    final data = ref.watch(
      dashboardProvider((
        ref.watch(siteFilterProvider),
        ref.watch(dashRangeProvider),
      )),
    );
    final incoming = data.value?.incomingRequests ?? 0;
    if (can('req.triage') && incoming > 0) {
      extra.insert(0, (
        icon: CupertinoIcons.tray_arrow_down_fill,
        color: BrandColors.info,
        title: incoming == 1
            ? '1 request to register'
            : '$incoming requests to register',
        detail: 'From other departments',
        onTap: () => context.push('/requests'),
      ));
    }
    return switch (data) {
      AsyncValue(:final value?) => NeedsYouCard(data: value, extra: extra),
      AsyncError() => SurfaceCard(
        child: Text(
          'Job cards load when you are connected.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      _ => const SurfaceCard(child: Skeleton(height: 120)),
    };
  }
}

/// Home for people who only request work: their requests and how they stand.
class _MyRequests extends ConsumerWidget {
  const _MyRequests({required this.extra});

  final List<NeedsYouItem> extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final requests = ref.watch(myRequestsProvider).value ?? const [];
    final open = [
      for (final r in requests)
        if (r.status != RequestStatus.rejected &&
            r.status != RequestStatus.withdrawn)
          r,
    ];
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('My requests', style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () => context.push('/my-requests'),
                child: const Text('See all'),
              ),
            ],
          ),
          if (open.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.md),
              child: Column(
                children: [
                  Text(
                    'Need electrical work done?',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: Space.sm),
                  FilledButton.icon(
                    onPressed: () => context.push('/my-requests/new'),
                    icon: const Icon(CupertinoIcons.paperplane),
                    label: const Text('Request work'),
                  ),
                ],
              ),
            )
          else
            for (final r in open.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: RequestTile(
                  request: r,
                  onTap: () => context.push('/requests/${r.id}'),
                ),
              ),
          for (final e in extra)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(e.icon, color: e.color),
              title: Text(e.title),
              subtitle: e.detail == null ? null : Text(e.detail!),
              onTap: e.onTap,
            ),
        ],
      ),
    );
  }
}

/// The four job card numbers for the site.
class _SiteNumbers extends ConsumerWidget {
  const _SiteNumbers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = ref.watch(currentSiteProvider);
    final session = ref.watch(sessionProvider);
    if (site == null || !session.can('jc.view', siteId: site.id)) {
      return const SizedBox.shrink();
    }
    final data = ref.watch(
      dashboardProvider((
        ref.watch(siteFilterProvider),
        ref.watch(dashRangeProvider),
      )),
    );
    final d = data.value;
    if (d == null) return const SizedBox.shrink();
    return JobCardNumbers(data: d, siteName: site.name);
  }
}

/// A way into every part of the app (phones; the desktop menu has these).
class _Shortcuts extends ConsumerWidget {
  const _Shortcuts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final unreadChat = ref.watch(chatUnreadProvider);
    bool can(String code) => site != null && session.can(code, siteId: site.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Go to'),
        TileGrid(
          tiles: [
            if (can('jobs.view')) ...[
              ShortcutTile(
                icon: Icons.fact_check_outlined,
                title: 'Checklists',
                subtitle: 'Daily rounds',
                colors: const [BrandColors.success, Color(0xFF4CC195)],
                onTap: () => context.push('/checklists'),
              ),
              ShortcutTile(
                icon: Icons.summarize_outlined,
                title: 'Daily report',
                subtitle: 'Today and past days',
                colors: const [BrandColors.maroon, BrandColors.coral],
                onTap: () => context.push('/reports'),
              ),
              ShortcutTile(
                icon: Icons.electrical_services_outlined,
                title: 'Equipment',
                subtitle: 'Plant and history',
                colors: const [BrandColors.maroonDeep, BrandColors.maroon],
                onTap: () => context.push('/equipment?side=equipment'),
              ),
            ],
            if (can('tools.view'))
              ShortcutTile(
                icon: Icons.handyman_outlined,
                title: 'Tools',
                subtitle: 'Who has what',
                colors: const [BrandColors.warning, Color(0xFFF2BE5C)],
                onTap: () => context.push('/equipment?side=tools'),
              ),
            if (can('docs.view'))
              ShortcutTile(
                icon: Icons.menu_book_outlined,
                title: 'Documents',
                subtitle: 'SOPs and drawings',
                colors: const [BrandColors.coral, BrandColors.blush],
                onTap: () => context.push('/documents'),
              ),
            if (session.can('chat.use'))
              ShortcutTile(
                icon: Icons.forum_outlined,
                title: 'Chat',
                subtitle: unreadChat > 0 ? '$unreadChat unread' : 'Your team',
                badge: unreadChat,
                colors: const [Color(0xFF5B4B8A), BrandColors.info],
                onTap: () => context.go('/chat'),
              ),
            if (can('req.submit'))
              ShortcutTile(
                icon: Icons.outbox_outlined,
                title: 'My requests',
                subtitle: 'Work you asked for',
                colors: const [BrandColors.info, Color(0xFF6A8FE8)],
                onTap: () => context.push('/my-requests'),
              ),
          ],
        ),
      ],
    );
  }
}

class _Latest extends ConsumerWidget {
  const _Latest();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notes = ref.watch(notificationsProvider);
    if (notes.items.isEmpty) return const SizedBox.shrink();
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.xs, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Latest', style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () => context.push('/notifications'),
                child: const Text('See all'),
              ),
            ],
          ),
          for (final n in notes.items.take(3))
            ListTile(
              contentPadding: const EdgeInsets.only(right: Space.sm),
              dense: true,
              leading: Icon(
                n.isRead ? CupertinoIcons.bell : CupertinoIcons.bell_fill,
                color: n.isRead
                    ? theme.colorScheme.onSurfaceVariant
                    : BrandColors.maroon,
              ),
              title: Text(
                n.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700,
                ),
              ),
              subtitle: n.body == null
                  ? null
                  : Text(n.body!, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                ref.read(notificationsProvider.notifier).markRead([n.id]);
                final path = notificationPath(n.link);
                if (path != null) context.push(path);
              },
            ),
        ],
      ),
    );
  }
}
