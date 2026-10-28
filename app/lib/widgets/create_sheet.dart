import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../documents/documents_screen.dart';
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
      if (can('jc.execute'))
        (
          icon: CupertinoIcons.person_crop_circle_badge_checkmark,
          title: 'My jobs',
          hint: 'Start, pause, submit',
          colors: const [Color(0xFF8E2D45), BrandColors.info],
          run: (c) => then(c, (h) => h.go('/jobs?mine=1')),
        ),
      if (can('jc.view'))
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
      if (can('jc.view'))
        (
          icon: CupertinoIcons.checkmark_rectangle_fill,
          title: 'Do a checklist',
          hint: 'Daily rounds',
          colors: const [BrandColors.success, Color(0xFF4CC195)],
          run: (c) => then(c, (h) => h.push('/checklists')),
        ),
      if (can('tools.issue'))
        (
          icon: CupertinoIcons.wrench_fill,
          title: 'Lend a tool',
          hint: 'Issue or take one back',
          colors: const [BrandColors.warning, Color(0xFFF2BE5C)],
          run: (c) => then(c, (h) => h.push('/equipment?side=tools')),
        ),
      if (session.can('chat.use'))
        (
          icon: CupertinoIcons.chat_bubble_2_fill,
          title: 'Send a message',
          hint: 'Team or one person',
          colors: const [Color(0xFF5B4B8A), BrandColors.info],
          run: (c) => then(c, (h) => h.go('/chat')),
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
      if (can('req.triage'))
        (
          icon: CupertinoIcons.tray_arrow_down_fill,
          title: 'Requests',
          hint: 'From other departments',
          colors: const [BrandColors.maroonDeep, BrandColors.maroon],
          run: (c) => then(c, (h) => h.push('/requests')),
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
