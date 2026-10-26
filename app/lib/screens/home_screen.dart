import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../chat/chat_repository.dart';
import '../checklists/checklists_repository.dart';
import '../data/local_db.dart';
import '../documents/documents_repository.dart';
import '../jobs/job_rules.dart';
import '../jobs/jobs_repository.dart';
import '../requests/requests_screen.dart';
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
import '../widgets/create_sheet.dart';
import '../widgets/push_prompt.dart';
import 'jobs_screen.dart';

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
        await Future.wait([
          ref.read(sessionProvider.notifier).refresh(),
          ref.read(notificationsProvider.notifier).refresh(),
          ref.read(jobsSyncProvider.notifier).refresh(),
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

typedef _Item = ({
  IconData icon,
  Color color,
  String title,
  String? subtitle,
  VoidCallback onTap,
});

/// Everything waiting on me, most pressing first.
class _ToDo extends ConsumerWidget {
  const _ToDo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final me = ref.watch(authUserIdProvider);
    final jobs = ref.watch(siteJobsProvider).value ?? const <LocalJob>[];
    final tools = ref.watch(siteToolsProvider).value ?? const <LocalTool>[];
    final templates = ref.watch(checklistTemplatesProvider).value ?? const [];
    final status = ref.watch(checklistStatusProvider).value ?? const {};
    final toSign = ref.watch(toSignCountProvider);
    final requests = ref.watch(newRequestCountProvider);
    final isSuper = site != null && session.can('jobs.assign', siteId: site.id);
    final now = DateTime.now();

    final open = [
      for (final j in jobs)
        if (j.status != 'done' && j.status != 'cancelled') j,
    ];
    final mine = [
      for (final j in open)
        if (j.assigneeId == me) j,
    ]..sort(compareJobs);
    final urgentFree = open
        .where((j) => j.priority == 'urgent' && j.assigneeId == null)
        .length;
    final rounds = [
      for (final t in templates)
        if (status[t.id] case final s?
            when !s.done && _sameDay(s.dueBy.toLocal(), now))
          if (t.assigneeId == null || t.assigneeId == me || isSuper) t,
    ];
    final myTools = [
      for (final t in tools)
        if (t.holderId == me) t,
    ];

    final items = <_Item>[
      if (urgentFree > 0 && isSuper)
        (
          icon: CupertinoIcons.exclamationmark_octagon_fill,
          color: const Color(0xFFE5484D),
          title: urgentFree == 1
              ? '1 urgent job has nobody'
              : '$urgentFree urgent jobs have nobody',
          subtitle: 'Assign someone now',
          onTap: () => openJobs(context, ref, JobFilter.unassigned),
        ),
      if (requests > 0)
        (
          icon: CupertinoIcons.tray_arrow_down_fill,
          color: BrandColors.info,
          title: requests == 1
              ? '1 work request to decide'
              : '$requests work requests to decide',
          subtitle: 'Accept or decline',
          onTap: () => context.push('/requests'),
        ),
      for (final j in mine.take(4))
        (
          icon: JobStatus.parse(j.status).icon,
          color: isOverdue(j)
              ? const Color(0xFFE5484D)
              : JobStatus.parse(j.status).color,
          title: j.title,
          subtitle: [
            ?j.code,
            JobStatus.parse(j.status).label,
            if (j.dueAt != null)
              isOverdue(j) ? 'overdue' : 'due ${relativeTime(j.dueAt!)}',
          ].join(' · '),
          onTap: () => context.push('/jobs/${j.id}'),
        ),
      if (mine.length > 4)
        (
          icon: CupertinoIcons.ellipsis_circle,
          color: BrandColors.maroon,
          title: '${mine.length - 4} more of my jobs',
          subtitle: null,
          onTap: () => openJobs(context, ref, JobFilter.mine),
        ),
      for (final t in rounds.take(3))
        (
          icon: CupertinoIcons.checkmark_rectangle,
          color: BrandColors.success,
          title: t.name,
          subtitle: 'Checklist due today',
          onTap: () => context.push('/checklists/${t.id}'),
        ),
      if (toSign > 0)
        (
          icon: CupertinoIcons.signature,
          color: BrandColors.coral,
          title: toSign == 1
              ? '1 document to read and sign'
              : '$toSign documents to read and sign',
          subtitle: 'SOPs and safety notices',
          onTap: () => context.push('/documents'),
        ),
      for (final t in myTools)
        (
          icon: CupertinoIcons.wrench_fill,
          color: toolOverdue(t) ? const Color(0xFFE5484D) : BrandColors.warning,
          title: 'Return ${t.name}',
          subtitle: t.dueBack == null
              ? t.code
              : toolOverdue(t)
              ? '${t.code} · was due back ${t.dueBack!.day}/${t.dueBack!.month}'
              : '${t.code} · due back ${t.dueBack!.day}/${t.dueBack!.month}',
          onTap: () => context.push('/tools/${t.id}'),
        ),
    ];

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('To do', style: theme.textTheme.titleMedium),
              const SizedBox(width: Space.xs),
              if (items.isNotEmpty)
                Pill(
                  label: '${items.length}',
                  color: BrandColors.maroon,
                  dense: true,
                ),
              const Spacer(),
              if (mine.isNotEmpty)
                TextButton(
                  onPressed: () => openJobs(context, ref, JobFilter.mine),
                  child: const Text('My jobs'),
                ),
            ],
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.lg),
              child: Column(
                children: [
                  const Icon(
                    CupertinoIcons.checkmark_seal_fill,
                    color: BrandColors.success,
                    size: 40,
                  ),
                  const SizedBox(height: Space.xs),
                  Text('All caught up', style: theme.textTheme.titleSmall),
                  Text(
                    'Nothing is waiting on you. Tap + to start something.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: Space.sm),
                  FilledButton.tonalIcon(
                    onPressed: () => showCreateSheet(context),
                    icon: const Icon(CupertinoIcons.add),
                    label: const Text('New'),
                  ),
                ],
              ),
            )
          else
            for (final (i, it) in items.indexed) ...[
              if (i > 0) const Divider(height: 1),
              _ToDoRow(item: it),
            ],
        ],
      ),
    );
  }
}

class _ToDoRow extends StatelessWidget {
  const _ToDoRow({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(item.icon, color: item.color, size: 20),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (item.subtitle != null)
                    Text(
                      item.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Four numbers for the site; each opens the matching jobs.
class _SiteNumbers extends ConsumerWidget {
  const _SiteNumbers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final jobs = ref.watch(siteJobsProvider).value ?? const <LocalJob>[];
    final site = ref.watch(currentSiteProvider);
    final now = DateTime.now();
    final open = [
      for (final j in jobs)
        if (j.status != 'done' && j.status != 'cancelled') j,
    ];
    final numbers = [
      ('Open', open.length, BrandColors.maroon, JobFilter.active),
      (
        'Urgent',
        open.where((j) => j.priority == 'urgent').length,
        const Color(0xFFE5484D),
        JobFilter.urgent,
      ),
      (
        'Overdue',
        open.where(isOverdue).length,
        BrandColors.warning,
        JobFilter.overdue,
      ),
      (
        'Done today',
        jobs
            .where(
              (j) =>
                  j.status == 'done' &&
                  j.closedAt != null &&
                  _sameDay(j.closedAt!.toLocal(), now),
            )
            .length,
        BrandColors.success,
        JobFilter.done,
      ),
    ];

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Jobs at ${site?.name ?? 'this site'}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              for (final (label, value, color, filter) in numbers)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.md),
                    onTap: () => openJobs(context, ref, filter),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          AnimatedCount(
                            value: value,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: value > 0 ? color : null,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            label,
                            maxLines: 1,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
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
            if (session.can('jc.view') || session.can('req.submit'))
              ShortcutTile(
                icon: Icons.assignment_outlined,
                title: 'Job cards',
                subtitle: 'New system · trial',
                colors: const [Color(0xFF7B1E3A), Color(0xFFD8A7B1)],
                onTap: () => context.go('/v2'),
              ),
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
                icon: Icons.precision_manufacturing_outlined,
                title: 'Equipment',
                subtitle: 'Plant and history',
                colors: const [BrandColors.maroonDeep, BrandColors.maroon],
                onTap: () => context.push('/assets'),
              ),
            ],
            if (can('tools.view'))
              ShortcutTile(
                icon: Icons.handyman_outlined,
                title: 'Tools',
                subtitle: 'Who has what',
                colors: const [BrandColors.warning, Color(0xFFF2BE5C)],
                onTap: () => context.push('/tools'),
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
            if (can('req.create') && !can('jobs.view'))
              ShortcutTile(
                icon: Icons.move_to_inbox_outlined,
                title: 'My requests',
                subtitle: 'Track your requests',
                colors: const [BrandColors.info, Color(0xFF6A8FE8)],
                onTap: () => context.push('/requests'),
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
