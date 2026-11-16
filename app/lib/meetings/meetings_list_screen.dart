import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../chat/chat_repository.dart';
import '../data/app_error.dart';
import '../data/site_data.dart';
import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'meetings_repository.dart';

/// Every meeting in the caller's chats (row security keeps it to chats
/// they are in), newest first.
final allMeetingsProvider = FutureProvider.autoDispose<List<Meeting>>((
  ref,
) async {
  final rows = await ref
      .read(supabaseProvider)
      .from('meetings')
      .select()
      .order('starts_at', ascending: false)
      .limit(300);
  return [for (final r in rows) Meeting.fromJson(r)];
});

/// One place for meetings from all chats: on now and upcoming first, then
/// past ones, with the chat, chair and whether minutes are approved. Open
/// a meeting (minutes) or join its call.
class MeetingsListScreen extends ConsumerWidget {
  const MeetingsListScreen({super.key, this.plain = false});

  /// Inside chat: the plain chat background instead of the burgundy mesh.
  final bool plain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final meetings = ref.watch(allMeetingsProvider);
    final names = ref.watch(peopleProvider).value ?? const {};
    final chats = {
      for (final c in ref.watch(conversationsProvider).value ?? const [])
        c.id: c.title,
    };
    final loc = MaterialLocalizations.of(context);

    Widget tile(Meeting m) {
      final status = m.cancelled
          ? 'Cancelled'
          : m.approved
          ? 'Minutes approved'
          : m.minutesStatus == 'draft'
          ? 'Minutes in draft'
          : m.open
          ? 'On now'
          : m.startsAt.isAfter(DateTime.now())
          ? 'Upcoming'
          : 'No minutes yet';
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: m.open
              ? BrandColors.success.withValues(alpha: 0.2)
              : BrandColors.info.withValues(alpha: 0.15),
          child: Icon(
            m.open
                ? CupertinoIcons.dot_radiowaves_left_right
                : CupertinoIcons.calendar,
            color: m.open ? BrandColors.success : BrandColors.info,
          ),
        ),
        title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            '${loc.formatMediumDate(m.startsAt)} ${TimeOfDay.fromDateTime(m.startsAt).format(context)}',
            chats[m.conversationId] ?? 'Chat',
            'Chair: ${(names[m.chairId] ?? 'Someone').split(' ').first}',
            status,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: m.open
            ? FilledButton(
                onPressed: () =>
                    context.push('/chat/${m.conversationId}/call?join=1'),
                child: const Text('Join'),
              )
            : const Icon(CupertinoIcons.chevron_right),
        onTap: () => context.push('/meetings/${m.id}'),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/menu'),
        title: const Text('Meetings'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: (plain ? _plainBg : MeshBackground.new)(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () => ref.refresh(allMeetingsProvider.future),
          child: meetings.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ListView(
              padding: EdgeInsets.only(top: top + Space.lg),
              children: [
                EmptyState(
                  icon: CupertinoIcons.wifi_slash,
                  title: 'Could not load meetings',
                  message: AppError.from(e).isRetryable
                      ? 'Meetings load when you are connected.'
                      : AppError.from(e).message,
                ),
              ],
            ),
            data: (all) {
              final now = DateTime.now();
              final soon = [
                for (final m in all.reversed)
                  if (!m.cancelled && (m.open || m.startsAt.isAfter(now))) m,
              ];
              final past = [
                for (final m in all)
                  if (!soon.contains(m)) m,
              ];
              Widget label(String t) => Padding(
                padding: const EdgeInsets.fromLTRB(4, Space.md, 0, Space.xs),
                child: Text(
                  t.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  Space.md,
                  top + Space.sm,
                  Space.md,
                  Space.xl,
                ),
                children: [
                  if (all.isEmpty)
                    const EmptyState(
                      icon: CupertinoIcons.calendar,
                      title: 'No meetings yet',
                      message: 'Schedule one with ➕ New → Schedule a meeting.',
                    ),
                  if (soon.isNotEmpty) ...[
                    label('On now and upcoming'),
                    for (final m in soon) tile(m),
                  ],
                  if (past.isNotEmpty) ...[
                    label('Past'),
                    for (final m in past) tile(m),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Talking time per person in a meeting, from the live captions: each
/// caption counts at about 2.5 words a second (people who did not turn
/// captions on are not counted). Longest first.
List<({String userId, Duration time})> talkingTime(
  List<({String userId, String body})> captions,
) {
  final words = <String, int>{};
  for (final c in captions) {
    final n = c.body.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    words[c.userId] = (words[c.userId] ?? 0) + n.length;
  }
  final out = [
    for (final e in words.entries)
      (
        userId: e.key,
        time: Duration(milliseconds: (e.value / 2.5 * 1000).round()),
      ),
  ]..sort((a, b) => b.time.compareTo(a.time));
  return out;
}

/// "4 min 10 s", "45 s".
String talkingLabel(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return m == 0 ? '$s s' : '$m min $s s';
}

Widget _plainBg({Widget? child}) => Builder(
  builder: (context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: child,
  ),
);
