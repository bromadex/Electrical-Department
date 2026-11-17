import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../widgets/app_back_button.dart';
import 'chat_list_screen.dart' show ChatGroupAvatar;
import 'chat_repository.dart';
import 'wallpaper.dart';

/// One call in the calls list (fn_my_calls, migration 0045).
class CallLogEntry {
  const CallLogEntry({
    required this.callId,
    required this.conversationId,
    required this.title,
    required this.isDirect,
    required this.video,
    required this.direction,
    required this.startedAt,
    required this.seconds,
    required this.live,
  });

  factory CallLogEntry.fromRow(Map<String, dynamic> r) => CallLogEntry(
    callId: r['call_id'] as String,
    conversationId: r['conversation_id'] as String,
    title: r['title'] as String? ?? 'Call',
    isDirect: r['is_direct'] as bool? ?? false,
    video: r['video'] as bool? ?? false,
    direction: r['direction'] as String? ?? 'incoming',
    startedAt: DateTime.parse(r['started_at'] as String).toLocal(),
    seconds: (r['seconds'] as num?)?.toInt() ?? 0,
    live: r['live'] as bool? ?? false,
  );

  final String callId;
  final String conversationId;
  final String title;
  final bool isDirect;
  final bool video;

  /// outgoing (you started it), incoming (you joined) or missed.
  final String direction;
  final DateTime startedAt;
  final int seconds;
  final bool live;

  bool get missed => direction == 'missed' && !live;
}

/// "4 min", "1 h 5 min", "45 s"; empty when nobody answered.
String callLengthLabel(int seconds) {
  if (seconds <= 0) return '';
  if (seconds < 60) return '$seconds s';
  final m = seconds ~/ 60;
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${m % 60} min';
}

final myCallsProvider = FutureProvider.autoDispose<List<CallLogEntry>>((
  ref,
) async {
  final rows =
      await ref
              .read(supabaseProvider)
              .rpc('fn_my_calls', params: {'p_limit': 150})
          as List;
  return [
    for (final r in rows) CallLogEntry.fromRow(Map<String, dynamic>.from(r)),
  ];
});

/// Missed calls since the calls list was last opened (the badge). Checked
/// again whenever the chat list changes (a missed call posts to the chat).
final missedCallsProvider = FutureProvider<int>((ref) async {
  ref.watch(conversationsProvider);
  try {
    final n = await ref.read(supabaseProvider).rpc('fn_missed_call_count');
    return (n as num?)?.toInt() ?? 0;
  } catch (_) {
    return 0;
  }
});

/// Calls across all chats, newest first: ↙ incoming, ↗ outgoing, missed in
/// red, with the time and length. Tap to call back.
class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key});

  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends ConsumerState<CallsScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the list clears the missed-call badge.
    unawaited(
      ref
          .read(supabaseProvider)
          .rpc('fn_calls_seen')
          .then((_) => ref.invalidate(missedCallsProvider), onError: (_) {}),
    );
  }

  String _when(BuildContext context, DateTime t) {
    final now = DateTime.now();
    final time = TimeOfDay.fromDateTime(t).format(context);
    if (DateUtils.isSameDay(t, now)) return 'Today, $time';
    if (DateUtils.isSameDay(t, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday, $time';
    }
    // "Sun, Nov 15" already names the day.
    return '${MaterialLocalizations.of(context).formatMediumDate(t)}, $time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final calls = ref.watch(myCallsProvider);
    final chats = {
      for (final c in ref.watch(conversationsProvider).value ?? const [])
        c.id: c,
    };
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/chat'),
        title: const Text('Calls'),
      ),
      body: ChatPlain(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () => ref.refresh(myCallsProvider.future),
          child: calls.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ListView(
              padding: EdgeInsets.only(top: top + Space.lg),
              children: [
                EmptyState(
                  icon: CupertinoIcons.wifi_slash,
                  title: 'Could not load calls',
                  message: AppError.from(e).isRetryable
                      ? 'Calls load when you are connected.'
                      : AppError.from(e).message,
                ),
              ],
            ),
            data: (list) => list.isEmpty
                ? ListView(
                    padding: EdgeInsets.only(top: top + Space.lg),
                    children: const [
                      EmptyState(
                        icon: CupertinoIcons.phone,
                        title: 'No calls yet',
                        message:
                            'Calls you make and get in any chat show here.',
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      Space.md,
                      top + Space.sm,
                      Space.md,
                      Space.xl,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final c = list[i];
                      final chat = chats[c.conversationId];
                      final red = theme.colorScheme.error;
                      final length = callLengthLabel(c.seconds);
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: Space.xs,
                            ),
                            leading: chat != null && !chat.isDirect
                                ? ChatGroupAvatar(chat: chat, size: 44)
                                : AppAvatar(name: c.title, size: 44),
                            title: Text(
                              c.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: c.missed
                                  ? TextStyle(
                                      color: red,
                                      fontWeight: FontWeight.w600,
                                    )
                                  : null,
                            ),
                            subtitle: Row(
                              children: [
                                Icon(
                                  c.direction == 'outgoing'
                                      ? CupertinoIcons.arrow_up_right
                                      : CupertinoIcons.arrow_down_left,
                                  size: 14,
                                  color: c.missed
                                      ? red
                                      : const Color(0xFF2FBF71),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    [
                                      if (c.live) 'On now',
                                      _when(context, c.startedAt),
                                      if (length.isNotEmpty) length,
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              tooltip: c.live
                                  ? 'Join'
                                  : c.video
                                  ? 'Video call'
                                  : 'Call',
                              onPressed: () => context.push(
                                '/chat/${c.conversationId}/call?join=1'
                                '${c.video ? '&video=1' : ''}',
                              ),
                              icon: Icon(
                                c.video
                                    ? CupertinoIcons.video_camera_solid
                                    : CupertinoIcons.phone_fill,
                                color: c.live
                                    ? const Color(0xFF2FBF71)
                                    : BrandColors.info,
                              ),
                            ),
                            onTap: () =>
                                context.push('/chat/${c.conversationId}'),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
