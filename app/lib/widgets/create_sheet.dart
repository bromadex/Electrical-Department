import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../chat/chat_list_screen.dart' show NewChatSheet;
import '../chat/chat_repository.dart';
import '../documents/documents_screen.dart';
import '../meetings/meeting_screen.dart' show ScheduleMeetingSheet;
import '../projects/projects_screen.dart' show ProjectForm;
import '../reports/daily_report_screen.dart';
import '../ui/form_sheet.dart';
import '../reports/reports_repository.dart';
import '../services/session_controller.dart';
import '../reminders/remind_me_sheet.dart';
import '../theme/tokens.dart';
import '../ui/motion.dart';
import '../ui/page.dart';

/// One place to start anything: the + button in the middle of the tab bar
/// (and at the top of the desktop menu). Shows only what the user may do.
Future<void> showCreateSheet(BuildContext context) {
  HapticFeedback.mediumImpact();
  return showFormSheet(context, const _CreateSheet());
}

typedef _Action = ({
  IconData icon,
  String title,
  String hint,
  List<Color> colors,
  void Function(BuildContext context) run,
});

class _CreateSheet extends ConsumerWidget {
  const _CreateSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final at = site?.id;
    bool can(String code) => site != null && session.can(code, siteId: at);
    final works = session.worksAt(at);

    // Close this sheet, then open the next screen or form from the page
    // underneath so it is not stacked on top of the sheet.
    void then(BuildContext context, void Function(BuildContext) next) {
      final nav = Navigator.of(context);
      final host = nav.context;
      nav.pop();
      next(host);
    }

    final actions = <_Action>[
      if (can('jc.register'))
        (
          icon: CupertinoIcons.exclamationmark_triangle_fill,
          title: 'Report a fault',
          hint: 'New job card',
          colors: const [BrandColors.maroon, BrandColors.coral],
          run: (c) => then(c, (h) => h.push('/jobs/new')),
        )
      else if (can('req.submit'))
        (
          icon: CupertinoIcons.paperplane_fill,
          title: 'Request work',
          hint: 'Ask the electrical team',
          colors: const [BrandColors.maroon, BrandColors.coral],
          run: (c) => then(c, (h) => h.push('/my-requests/new')),
        ),
      if (can('mr.create'))
        (
          icon: CupertinoIcons.cart_badge_plus,
          title: 'Request materials',
          hint: 'Cable, breakers, parts',
          colors: const [BrandColors.coral, BrandColors.info],
          run: (c) => then(c, (h) => h.push('/materials/new')),
        ),
      if (can('po.manage'))
        (
          icon: CupertinoIcons.bag_fill_badge_plus,
          title: 'New purchase',
          hint: 'Order from a supplier',
          colors: const [BrandColors.info, BrandColors.maroon],
          run: (c) => then(c, (h) => h.push('/purchases/new')),
        ),
      if (can('jc.execute'))
        (
          icon: CupertinoIcons.person_crop_circle_badge_checkmark,
          title: 'My jobs',
          hint: 'Start, pause, submit',
          colors: const [Color(0xFF8E2D45), BrandColors.info],
          run: (c) => then(c, (h) => h.go('/jobs?mine=1')),
        ),
      if (can('jc.view') && works)
        (
          icon: CupertinoIcons.square_pencil,
          title: 'Today\'s report',
          hint: 'What you did today',
          colors: const [BrandColors.info, Color(0xFF6A8FE8)],
          run: (c) => then(
            c,
            (h) => showFormSheet(
              h,
              ReportUpdateForm(siteId: site!.id, date: reportDate(harareNow())),
            ),
          ),
        ),
      if (can('tools.issue'))
        (
          icon: CupertinoIcons.wrench_fill,
          title: 'Lend a tool',
          hint: 'Issue or take one back',
          colors: const [BrandColors.warning, Color(0xFFF2BE5C)],
          run: (c) => then(c, (h) => h.push('/equipment?side=tools')),
        ),
      if (can('projects.manage'))
        (
          icon: CupertinoIcons.flag_fill,
          title: 'New project',
          hint: 'Plan, materials, BOQ',
          colors: const [BrandColors.maroon, BrandColors.blush],
          run: (c) => then(c, (h) => showFormSheet(h, const ProjectForm())),
        ),
      if (can('meetings.manage') && session.can('chat.use'))
        (
          icon: CupertinoIcons.calendar_badge_plus,
          title: 'Schedule a meeting',
          hint: 'In a group chat',
          colors: const [BrandColors.maroonDeep, BrandColors.info],
          run: (c) => then(c, (h) async {
            final id = await showFormSheet<String>(h, const _PickGroupSheet());
            if (id != null && h.mounted) {
              await showFormSheet(h, ScheduleMeetingSheet(conversationId: id));
            }
          }),
        ),
      if (session.can('chat.use'))
        (
          icon: CupertinoIcons.chat_bubble_2_fill,
          title: 'New chat or group',
          hint: 'One person or a team',
          colors: const [BrandColors.info, Color(0xFF6A8FE8)],
          run: (c) => then(
            c,
            (h) => showFormSheet(h, const NewChatSheet(fromOutside: true)),
          ),
        ),
      (
        icon: CupertinoIcons.alarm_fill,
        title: 'Reminder',
        hint: 'Remind me at a time',
        colors: const [BrandColors.coral, BrandColors.maroon],
        run: (c) => then(c, (h) => showRemindMe(h)),
      ),
      if (can('docs.manage'))
        (
          icon: CupertinoIcons.doc_text_fill,
          title: 'Add a document',
          hint: 'SOP or drawing',
          colors: const [BrandColors.coral, BrandColors.blush],
          run: (c) => then(c, (h) => showFormSheet(h, const DocumentForm())),
        ),
    ];

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.sm,
          Space.lg,
          Space.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('What do you want to do?', style: theme.textTheme.titleLarge),
            if (site != null)
              Text(
                'At ${site.name}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: Space.md),
            LayoutBuilder(
              builder: (context, c) {
                const gap = Space.sm;
                final w = (c.maxWidth - gap) / 2;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final (i, a) in actions.indexed)
                      SizedBox(
                        width: w,
                        child: _ActionCard(action: a)
                            .entrance(context, index: i.clamp(0, 8)),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action});

  final _Action action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = action;
    return Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        a.run(context);
      },
      child: Container(
        height: 112,
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.lg),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: a.colors,
          ),
          boxShadow: [
            BoxShadow(
              color: a.colors.first.withValues(alpha: 0.3),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(a.icon, color: Colors.white, size: 26),
            const Spacer(),
            Text(
              a.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              a.hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Schedule a meeting from ➕: first pick the group chat it belongs to
/// (groups where the user may run meetings). Pops the chat's id.
class _PickGroupSheet extends ConsumerWidget {
  const _PickGroupSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final here = ref.watch(currentSiteProvider)?.id;
    final chats = ref.watch(conversationsProvider);
    final groups = [
      for (final c in chats.value ?? const <Conversation>[])
        if (!c.isDirect &&
            !c.archived &&
            session.can('meetings.manage', siteId: c.siteId ?? here))
          c,
    ];
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.md,
              Space.lg,
              Space.xs,
            ),
            child: Text('Which group?', style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Text(
              'The meeting goes in its chat: everyone in it is invited.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          if (chats.isLoading && groups.isEmpty)
            const Padding(
              padding: EdgeInsets.all(Space.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Text(
                'No group chats where you can run meetings yet.',
                style: theme.textTheme.bodyMedium,
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: Space.md),
                children: [
                  for (final g in groups)
                    ListTile(
                      leading: const Icon(CupertinoIcons.person_3_fill),
                      title: Text(
                        g.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('${g.memberCount} people'),
                      trailing: const Icon(CupertinoIcons.chevron_right),
                      onTap: () => Navigator.pop(context, g.id),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
