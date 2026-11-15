import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../chat/chat_repository.dart';
import '../data/app_error.dart';
import '../data/site_data.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/charts.dart' show GlassSegmented;
import '../ui/form_sheet.dart';
import '../ui/motion.dart';
import '../ui/record_hero.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'captions.dart';
import 'meeting_pdf.dart';
import 'meetings_repository.dart';

/// A readable error: the server's message, or ours from MeetingActions.
String _message(Object e) => e is Exception && e is! PostgrestException
    ? '$e'.replaceFirst('Exception: ', '')
    : AppError.from(e).message;

String _when(BuildContext context, DateTime t) {
  final l = MaterialLocalizations.of(context);
  return '${l.formatFullDate(t)} · ${l.formatTimeOfDay(TimeOfDay.fromDateTime(t))}';
}

/// A meeting (M-): when and where, join the chat's call, record, and the
/// minutes the chair drafts (with AI), edits and publishes.
class MeetingScreen extends ConsumerStatefulWidget {
  const MeetingScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<MeetingScreen> createState() => _MeetingScreenState();
}

enum _Tab { minutes, transcript, agenda, present }

class _MeetingScreenState extends ConsumerState<MeetingScreen> {
  _Tab _tab = _Tab.minutes;

  Future<void> _run(Future<void> Function() job, {String? done}) async {
    try {
      await job();
      if (done != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text(_message(e)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(meetingProvider(widget.id)).value;
    final session = ref.watch(sessionProvider);
    final me = ref.watch(authUserIdProvider);
    final names = ref.watch(peopleProvider).value ?? const {};
    final chats = ref.watch(conversationsProvider).value ?? const [];
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    if (m == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: const AppBackButton(fallback: '/chat'),
          title: const Text('Meeting'),
        ),
        body: const MeshBackground(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final chat = chats.where((c) => c.id == m.conversationId).firstOrNull;
    final canRun =
        m.chairId == me || session.can('meetings.manage', siteId: m.siteId);
    final actions = ref.read(meetingActionsProvider);
    final now = DateTime.now();
    final status = m.cancelled
        ? ('Cancelled', Colors.grey)
        : m.open
        ? ('Now', BrandColors.success)
        : now.isBefore(m.startsAt)
        ? ('Upcoming', BrandColors.info)
        : ('Held', Colors.blueGrey);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: AppBackButton(fallback: '/chat/${m.conversationId}'),
        title: Text(m.code),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
        actions: [
          if (canRun && !m.cancelled)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) async {
                if (v == 'edit') {
                  await showFormSheet(
                    context,
                    ScheduleMeetingSheet(
                      conversationId: m.conversationId,
                      meeting: m,
                    ),
                  );
                } else if (v == 'cancel') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('Cancel this meeting?'),
                      content: const Text('The chat is told it is cancelled.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(d, false),
                          child: const Text('Keep it'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: const Text('Cancel meeting'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await _run(() => actions.update(m.id, cancel: true));
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Text('Change time or agenda'),
                ),
                PopupMenuItem(value: 'cancel', child: Text('Cancel meeting')),
              ],
            ),
        ],
      ),
      body: MeshBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(Space.md, top + Space.md, Space.md, 80),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RecordHero(
                      icon: CupertinoIcons.calendar,
                      code: m.code,
                      title: m.title,
                      pills: [
                        Pill(label: status.$1, color: status.$2, dense: true),
                        if (m.open)
                          const Pill(
                            label: 'Live captions',
                            color: Colors.red,
                            icon: CupertinoIcons.captions_bubble_fill,
                            dense: true,
                          ),
                        if (m.minutesStatus != 'none')
                          Pill(
                            label: m.approved ? 'Minutes out' : 'Minutes draft',
                            color: m.approved
                                ? BrandColors.success
                                : BrandColors.warning,
                            dense: true,
                          ),
                      ],
                      facts: [
                        (
                          icon: CupertinoIcons.clock,
                          text:
                              '${_when(context, m.startsAt)} · ${m.durationMin} min',
                          color: null,
                        ),
                        (
                          icon: CupertinoIcons.chat_bubble_2,
                          text: chat?.title ?? 'Group chat',
                          color: null,
                        ),
                        (
                          icon: CupertinoIcons.person,
                          text: 'Chair: ${names[m.chairId] ?? 'someone'}',
                          color: null,
                        ),
                      ],
                    ).entrance(context),
                    const SizedBox(height: Space.sm),
                    QuickActions(
                      actions: [
                        (
                          icon: CupertinoIcons.phone_fill,
                          label: 'Join',
                          onTap: m.cancelled
                              ? null
                              : () => context.push(
                                  '/chat/${m.conversationId}/call?join=1',
                                ),
                          color: BrandColors.success,
                        ),
                        (
                          icon: CupertinoIcons.chat_bubble_2_fill,
                          label: 'Chat',
                          onTap: () =>
                              context.push('/chat/${m.conversationId}'),
                          color: BrandColors.info,
                        ),
                      ],
                    ).entrance(context, index: 1),
                    const SizedBox(height: Space.md),
                    GlassSegmented<_Tab>(
                      value: _tab,
                      segments: const {
                        _Tab.minutes: 'Minutes',
                        _Tab.transcript: 'Said',
                        _Tab.agenda: 'Agenda',
                        _Tab.present: 'Present',
                      },
                      onChanged: (t) => setState(() => _tab = t),
                    ),
                    const SizedBox(height: Space.md),
                    switch (_tab) {
                      _Tab.minutes => _MinutesPanel(
                        key: ValueKey('${m.id}-${m.minutesStatus}'),
                        meeting: m,
                        canRun: canRun,
                        chatName: chat?.title ?? 'Group chat',
                      ),
                      _Tab.agenda => SurfaceCard(
                        child: Text(
                          (m.agenda ?? '').isEmpty
                              ? 'No agenda was given.'
                              : m.agenda!,
                        ),
                      ),
                      _Tab.present => _Present(meetingId: m.id),
                      _Tab.transcript => _Transcript(meetingId: m.id),
                    },
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything said in the meeting, live, with names.
class _Transcript extends ConsumerWidget {
  const _Transcript({required this.meetingId});

  final String meetingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final names = ref.watch(peopleProvider).value ?? const {};
    final lines = ref.watch(meetingCaptionsProvider(meetingId));
    return lines.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const Text('Loads when you are online.'),
      data: (list) => list.isEmpty
          ? const EmptyState(
              icon: CupertinoIcons.captions_bubble,
              title: 'Nothing said yet',
              message:
                  'During the meeting, what each person in the call says '
                  'appears here with their name.',
            )
          : SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final c in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 44,
                            child: Text(
                              MaterialLocalizations.of(context).formatTimeOfDay(
                                TimeOfDay.fromDateTime(c.spokenAt),
                                alwaysUse24HourFormat: true,
                              ),
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${names[c.userId] ?? 'Someone'}: ',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: BrandColors.coral,
                                    ),
                                  ),
                                  TextSpan(text: c.body),
                                ],
                              ),
                            ),
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

class _Present extends ConsumerWidget {
  const _Present({required this.meetingId});

  final String meetingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(meetingAttendanceProvider(meetingId));
    return list.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const Text('Loads when you are online.'),
      data: (people) => people.isEmpty
          ? const EmptyState(
              icon: CupertinoIcons.person_2,
              title: 'Nobody has joined yet',
              message:
                  'People who join the chat\'s call during the meeting '
                  'show here.',
            )
          : SurfaceCard(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Column(
                children: [
                  for (final p in people)
                    ListTile(
                      leading: AppAvatar(name: p.name, size: 34),
                      title: Text(p.name),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Read the minutes, or (the chair) draft them with AI, edit and publish.
class _MinutesPanel extends ConsumerStatefulWidget {
  const _MinutesPanel({
    super.key,
    required this.meeting,
    required this.canRun,
    required this.chatName,
  });

  final Meeting meeting;
  final bool canRun;
  final String chatName;

  @override
  ConsumerState<_MinutesPanel> createState() => _MinutesPanelState();
}

class _MinutesPanelState extends ConsumerState<_MinutesPanel> {
  final _notes = TextEditingController();
  late final _summary = TextEditingController(
    text: widget.meeting.minutes.summary,
  );
  late final _decisions = [
    for (final d in widget.meeting.minutes.decisions)
      TextEditingController(text: d),
  ];
  late final _actions = [
    for (final a in widget.meeting.minutes.actions) _ActionDraft.from(a),
  ];
  late final _type = TextEditingController(
    text: widget.meeting.minutes.meetingType,
  );
  late final _venue = TextEditingController(text: widget.meeting.minutes.venue);
  late final _minutesBy = TextEditingController(
    text: widget.meeting.minutes.minutesBy,
  );
  late final _reviewedBy = TextEditingController(
    text: widget.meeting.minutes.reviewedBy,
  );
  late final _approvedBy = TextEditingController(
    text: widget.meeting.minutes.approvedBy,
  );
  late final _updates = TextEditingController(
    text: widget.meeting.minutes.updates,
  );
  late final _attendance = [
    for (final a in widget.meeting.minutes.attendance) _AttendeeDraft.from(a),
  ];
  late final _statusLines = [
    for (final l in widget.meeting.minutes.statusSummary) _StatusDraft.from(l),
  ];
  late final _nextAgenda = [
    for (final a in widget.meeting.minutes.nextAgenda)
      TextEditingController(text: a),
  ];
  late bool _editing = !widget.meeting.minutes.isEmpty;
  bool _busy = false;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _prefill());
    }
  }

  /// Fills what the department's format needs and the draft lacks:
  /// attendance from who joined the call (positions as in this chat's last
  /// minutes), meeting type and venue as last time, and who takes the
  /// minutes. Never overwrites what is already there.
  Future<void> _prefill() async {
    if (_prefilled || !mounted) return;
    _prefilled = true;
    final m = widget.meeting;
    Minutes? last;
    try {
      final all = await ref.read(chatMeetingsProvider(m.conversationId).future);
      final earlier = [
        for (final x in all)
          if (x.id != m.id &&
              x.startsAt.isBefore(m.startsAt) &&
              x.minutes.attendance.isNotEmpty)
            x,
      ]..sort((a, b) => b.startsAt.compareTo(a.startsAt));
      last = earlier.firstOrNull?.minutes;
    } catch (_) {}
    List<({String id, String name})> joined = const [];
    if (_attendance.isEmpty) {
      try {
        joined = await ref.read(meetingAttendanceProvider(m.id).future);
      } catch (_) {}
    }
    if (!mounted) return;
    final me = ref.read(sessionProvider).profile?.fullName ?? '';
    setState(() {
      if (_attendance.isEmpty) {
        for (final p in joined) {
          final before = last?.attendance
              .where((a) => a.name.toLowerCase() == p.name.toLowerCase())
              .firstOrNull;
          _attendance.add(
            _AttendeeDraft.from(
              before ?? Attendee(name: p.name, organisation: 'Bravura'),
            ),
          );
        }
      }
      if (_type.text.trim().isEmpty) {
        _type.text = last?.meetingType ?? '';
      }
      if (_venue.text.trim().isEmpty) {
        _venue.text = (last?.venue ?? '').isNotEmpty
            ? last!.venue
            : 'Online Meeting';
      }
      if (_minutesBy.text.trim().isEmpty && me.isNotEmpty) {
        _minutesBy.text = minutesShortName(me);
      }
    });
  }

  @override
  void didUpdateWidget(_MinutesPanel old) {
    super.didUpdateWidget(old);
    // A fresh AI draft arrived: load it into the editor.
    if (old.meeting.minutes.summary != widget.meeting.minutes.summary &&
        _summary.text.trim().isEmpty) {
      _load(widget.meeting.minutes);
    }
  }

  void _load(Minutes m) {
    setState(() {
      _summary.text = m.summary;
      _decisions
        ..clear()
        ..addAll([for (final d in m.decisions) TextEditingController(text: d)]);
      _actions
        ..clear()
        ..addAll([for (final a in m.actions) _ActionDraft.from(a)]);
      if (m.updates.trim().isNotEmpty) _updates.text = m.updates;
      if (m.statusSummary.isNotEmpty) {
        _statusLines
          ..clear()
          ..addAll([for (final l in m.statusSummary) _StatusDraft.from(l)]);
      }
      if (m.nextAgenda.isNotEmpty) {
        _nextAgenda
          ..clear()
          ..addAll([
            for (final a in m.nextAgenda) TextEditingController(text: a),
          ]);
      }
      _editing = true;
    });
    _prefill();
  }

  @override
  void dispose() {
    _notes.dispose();
    _summary.dispose();
    for (final c in [
      _type,
      _venue,
      _minutesBy,
      _reviewedBy,
      _approvedBy,
      _updates,
      ..._nextAgenda,
    ]) {
      c.dispose();
    }
    for (final a in _attendance) {
      a.dispose();
    }
    for (final l in _statusLines) {
      l.dispose();
    }
    for (final c in _decisions) {
      c.dispose();
    }
    for (final a in _actions) {
      a.text.dispose();
      a.status.dispose();
    }
    super.dispose();
  }

  Minutes _current(Map<String, String> names) => Minutes(
    summary: _summary.text.trim(),
    decisions: [
      for (final c in _decisions)
        if (c.text.trim().isNotEmpty) c.text.trim(),
    ],
    actions: [
      for (final a in _actions)
        if (a.text.text.trim().isNotEmpty)
          MeetingAction(
            text: a.text.text.trim(),
            ownerId: a.ownerId,
            ownerName: names[a.ownerId] ?? a.ownerName,
            due: a.due,
            status: a.status.text.trim(),
          ),
    ],
    meetingType: _type.text.trim(),
    venue: _venue.text.trim(),
    minutesBy: _minutesBy.text.trim(),
    reviewedBy: _reviewedBy.text.trim(),
    approvedBy: _approvedBy.text.trim(),
    updates: _updates.text.trim(),
    attendance: [
      for (final a in _attendance)
        if (a.name.text.trim().isNotEmpty)
          Attendee(
            name: a.name.text.trim(),
            position: a.position.text.trim(),
            organisation: a.organisation.text.trim(),
          ),
    ],
    statusSummary: [
      for (final l in _statusLines)
        if (l.area.text.trim().isNotEmpty || l.status.text.trim().isNotEmpty)
          (area: l.area.text.trim(), status: l.status.text.trim()),
    ],
    nextAgenda: [
      for (final c in _nextAgenda)
        if (c.text.trim().isNotEmpty) c.text.trim(),
    ],
  );

  Future<void> _do(Future<void> Function() job, String done) async {
    setState(() => _busy = true);
    try {
      await job();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text(_message(e)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pdf(Map<String, String> names) async {
    final m = widget.meeting;
    final bytes = await buildMinutesPdf(
      meeting: m,
      chairName: names[m.chairId] ?? '—',
    );
    await Printing.sharePdf(bytes: bytes, filename: '${m.code}-minutes.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = widget.meeting;
    final names = ref.watch(peopleProvider).value ?? const {};
    final actions = ref.read(meetingActionsProvider);
    final session = ref.watch(sessionProvider);
    final canJob = session.can('jc.register', siteId: m.siteId);
    final said = ref.watch(meetingCaptionsProvider(m.id)).value?.length ?? 0;

    // Read-only: published minutes, or not the chair.
    if (m.approved || !widget.canRun) {
      if (m.minutes.isEmpty || (!m.approved && !widget.canRun)) {
        return const EmptyState(
          icon: CupertinoIcons.doc_text,
          title: 'No minutes yet',
          message: 'The chair publishes them here and in the chat.',
        );
      }
      final min = m.minutes;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (min.updates.trim().isNotEmpty) ...[
                  Text('Updates', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  SelectableText(min.updates),
                  const SizedBox(height: Space.md),
                ],
                Text('Summary', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                SelectableText(min.summary),
                if (min.decisions.isNotEmpty) ...[
                  const SizedBox(height: Space.md),
                  Text('Decisions', style: theme.textTheme.titleSmall),
                  for (final d in min.decisions)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            CupertinoIcons.checkmark_seal_fill,
                            size: 16,
                            color: BrandColors.success,
                          ),
                          const SizedBox(width: 6),
                          Expanded(child: Text(d)),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (min.actions.isNotEmpty) ...[
            const SectionHeader('Actions'),
            for (final a in min.actions)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: SurfaceCard(
                  padding: const EdgeInsets.all(Space.sm),
                  child: Row(
                    children: [
                      AppAvatar(name: a.ownerName ?? '?', size: 34),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.text),
                            Text(
                              [
                                a.ownerName ?? 'No one named',
                                if (a.due != null)
                                  'by ${MaterialLocalizations.of(context).formatMediumDate(a.due!)}',
                                if (a.status.isNotEmpty) a.status,
                              ].join(' · '),
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      if (canJob)
                        TextButton(
                          onPressed: () => context.push(
                            Uri(
                              path: '/jobs/new',
                              queryParameters: {
                                'title': a.text.length > 120
                                    ? a.text.substring(0, 120)
                                    : a.text,
                                'description':
                                    '${a.text}\n\nFrom ${m.code} · ${m.title}'
                                    '${a.ownerName == null ? '' : ' · ${a.ownerName}'}'
                                    '${a.due == null ? '' : ' · due ${a.due!.toIso8601String().substring(0, 10)}'}',
                              },
                            ).toString(),
                          ),
                          child: const Text('Job card'),
                        ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(
            onPressed: () => _pdf(names),
            icon: const Icon(CupertinoIcons.doc_richtext),
            label: const Text('PDF to share or print'),
          ),
        ],
      );
    }

    // The chair, before there is anything: ways to start.
    if (!_editing) {
      return SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Draft the minutes', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'AI drafts a summary, decisions and actions with owners and '
              'dates from what was said. You check and change them before '
              'they go out.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: Space.md),
            if (said > 0) ...[
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _do(
                        () => actions.draftMinutes(m.id),
                        'Draft ready. Check it below.',
                      ),
                icon: const Icon(CupertinoIcons.captions_bubble),
                label: Text(
                  _busy ? 'Reading…' : 'Draft from what was said ($said lines)',
                ),
              ),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.all(Space.sm),
                    child: Text('or', style: theme.textTheme.labelSmall),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
            ],
            TextField(
              controller: _notes,
              minLines: 4,
              maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText:
                    'Type rough notes: what was discussed, agreed, and '
                    'who will do what by when.',
              ),
            ),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () => _do(
                            () =>
                                actions.draftMinutes(m.id, notes: _notes.text),
                            'Draft ready. Check it below.',
                          ),
                    icon: const Icon(CupertinoIcons.sparkles),
                    label: const Text('Draft from my notes'),
                  ),
                ),
                const SizedBox(width: Space.sm),
                TextButton(
                  onPressed: () {
                    setState(() => _editing = true);
                    _prefill();
                  },
                  child: const Text('Write them myself'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // The editor.
    final members =
        ref.watch(chatMembersProvider(m.conversationId)).value ??
        const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Details', style: theme.textTheme.titleSmall),
              const SizedBox(height: Space.xs),
              TextField(
                controller: _type,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Meeting type',
                  hintText: 'e.g. Technical Project Review Meeting',
                ),
              ),
              TextField(
                controller: _venue,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Venue'),
              ),
              TextField(
                controller: _minutesBy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Minutes taken by',
                ),
              ),
              const SizedBox(height: Space.md),
              Text('Attendance', style: theme.textTheme.titleSmall),
              for (final (i, a) in _attendance.indexed)
                Padding(
                  key: ObjectKey(a),
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: a.name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.xs),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: a.position,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Position',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.xs),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: a.organisation,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Organisation',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        onPressed: () =>
                            setState(() => _attendance.removeAt(i)),
                        icon: const Icon(CupertinoIcons.minus_circle),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(
                    () => _attendance.add(
                      _AttendeeDraft.from(
                        const Attendee(name: '', organisation: 'Bravura'),
                      ),
                    ),
                  ),
                  icon: const Icon(CupertinoIcons.person_add),
                  label: const Text('Add a person'),
                ),
              ),
              const SizedBox(height: Space.sm),
              Text('Updates', style: theme.textTheme.titleSmall),
              const SizedBox(height: Space.xs),
              TextField(
                controller: _updates,
                minLines: 2,
                maxLines: 10,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Site updates reported at the start (optional)',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Executive summary & overview',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: Space.xs),
              TextField(
                controller: _summary,
                minLines: 3,
                maxLines: 10,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: Space.md),
              Text('Decisions', style: theme.textTheme.titleSmall),
              for (final (i, c) in _decisions.indexed)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: c,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => setState(() => _decisions.removeAt(i)),
                      icon: const Icon(CupertinoIcons.minus_circle),
                    ),
                  ],
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _decisions.add(TextEditingController())),
                  icon: const Icon(CupertinoIcons.add),
                  label: const Text('Add a decision'),
                ),
              ),
            ],
          ),
        ),
        const SectionHeader('Actions'),
        for (final (i, a) in _actions.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: SurfaceCard(
              padding: const EdgeInsets.all(Space.sm),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: a.text,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'What needs doing',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        onPressed: () => setState(() => _actions.removeAt(i)),
                        icon: const Icon(CupertinoIcons.minus_circle),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.xs),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: members.contains(a.ownerId)
                              ? a.ownerId
                              : null,
                          isExpanded: true,
                          isDense: true,
                          decoration: const InputDecoration(labelText: 'Who'),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('No one yet'),
                            ),
                            for (final id in members)
                              if ((names[id] ?? '').isNotEmpty)
                                DropdownMenuItem(
                                  value: id,
                                  child: Text(names[id]!),
                                ),
                          ],
                          onChanged: (v) => setState(() => a.ownerId = v),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      OutlinedButton.icon(
                        icon: const Icon(CupertinoIcons.calendar, size: 16),
                        label: Text(
                          a.due == null
                              ? 'By when'
                              : MaterialLocalizations.of(context)
                                    .formatShortMonthDay(a.due!),
                        ),
                        onPressed: () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(
                            context: context,
                            initialDate:
                                a.due ?? now.add(const Duration(days: 7)),
                            firstDate: now.subtract(const Duration(days: 30)),
                            lastDate: now.add(const Duration(days: 365)),
                          );
                          if (d != null) setState(() => a.due = d);
                        },
                      ),
                    ],
                  ),
                  TextField(
                    controller: a.status,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      hintText: 'e.g. Ongoing, Awaiting drawings',
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _actions.add(_ActionDraft())),
            icon: const Icon(CupertinoIcons.add),
            label: const Text('Add an action'),
          ),
        ),
        const SectionHeader('Project status summary'),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, l) in _statusLines.indexed)
                Padding(
                  key: ObjectKey(l),
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: l.area,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Area',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.xs),
                      Expanded(
                        flex: 5,
                        child: TextField(
                          controller: l.status,
                          minLines: 1,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Current status',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        onPressed: () =>
                            setState(() => _statusLines.removeAt(i)),
                        icon: const Icon(CupertinoIcons.minus_circle),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(
                    () => _statusLines.add(
                      _StatusDraft.from((area: '', status: '')),
                    ),
                  ),
                  icon: const Icon(CupertinoIcons.add),
                  label: const Text('Add an area'),
                ),
              ),
            ],
          ),
        ),
        const SectionHeader('Next meeting – proposed agenda'),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, c) in _nextAgenda.indexed)
                Row(
                  key: ObjectKey(c),
                  children: [
                    Expanded(
                      child: TextField(
                        controller: c,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => setState(() => _nextAgenda.removeAt(i)),
                      icon: const Icon(CupertinoIcons.minus_circle),
                    ),
                  ],
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _nextAgenda.add(TextEditingController())),
                  icon: const Icon(CupertinoIcons.add),
                  label: const Text('Add an item'),
                ),
              ),
            ],
          ),
        ),
        const SectionHeader('Sign-off'),
        SurfaceCard(
          child: Column(
            children: [
              TextField(
                controller: _reviewedBy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Document reviewed by',
                ),
              ),
              TextField(
                controller: _approvedBy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Minutes approved by',
                  hintText: 'Leave empty to show the chair',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
        OutlinedButton.icon(
          onPressed: () async {
            final saved = Minutes.fromJson(_current(names).toJson());
            final bytes = await buildMinutesPdf(
              meeting: m.withMinutes(saved),
              chairName: names[m.chairId] ?? '—',
            );
            await Printing.sharePdf(
              bytes: bytes,
              filename: '${m.code}-minutes-draft.pdf',
            );
          },
          icon: const Icon(CupertinoIcons.eye),
          label: const Text('Preview PDF'),
        ),
        if ((m.transcript ?? '').isNotEmpty)
          ExpansionTile(
            title: const Text('Transcript'),
            children: [
              Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: SelectableText(m.transcript!),
              ),
            ],
          ),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _do(
                        () => actions.saveMinutes(m.id, _current(names)),
                        'Draft saved',
                      ),
                child: const Text('Save draft'),
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () => _do(() async {
                        await actions.saveMinutes(m.id, _current(names));
                        await actions.approve(m.id);
                      }, 'Minutes posted to the chat'),
                child: const Text('Approve and post'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionDraft {
  _ActionDraft({
    String text = '',
    this.ownerId,
    this.ownerName,
    this.due,
    String status = '',
  }) : text = TextEditingController(text: text),
       status = TextEditingController(text: status);

  factory _ActionDraft.from(MeetingAction a) => _ActionDraft(
    text: a.text,
    ownerId: a.ownerId,
    ownerName: a.ownerName,
    due: a.due,
    status: a.status,
  );

  final TextEditingController text;
  final TextEditingController status;
  String? ownerId;
  String? ownerName;
  DateTime? due;
}

/// Schedule a meeting in a group chat, or change one.
class ScheduleMeetingSheet extends ConsumerStatefulWidget {
  const ScheduleMeetingSheet({
    super.key,
    required this.conversationId,
    this.meeting,
  });

  final String conversationId;
  final Meeting? meeting;

  @override
  ConsumerState<ScheduleMeetingSheet> createState() =>
      _ScheduleMeetingSheetState();
}

class _ScheduleMeetingSheetState extends ConsumerState<ScheduleMeetingSheet> {
  late final _title = TextEditingController(text: widget.meeting?.title);
  late final _agenda = TextEditingController(text: widget.meeting?.agenda);
  late DateTime _day = widget.meeting?.startsAt ?? _nextHalfHour();
  late TimeOfDay _time = TimeOfDay.fromDateTime(_day);
  late int _minutes = widget.meeting?.durationMin ?? 60;
  bool _busy = false;
  String? _error;

  static DateTime _nextHalfHour() {
    final n = DateTime.now().add(const Duration(minutes: 30));
    return DateTime(
      n.year,
      n.month,
      n.day,
      n.hour,
      n.minute < 30 ? 30 : 0,
    ).add(Duration(hours: n.minute < 30 ? 0 : 1));
  }

  @override
  void dispose() {
    _title.dispose();
    _agenda.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final starts = DateTime(
      _day.year,
      _day.month,
      _day.day,
      _time.hour,
      _time.minute,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final actions = ref.read(meetingActionsProvider);
      if (widget.meeting == null) {
        final id = await actions.create(
          conversationId: widget.conversationId,
          siteId: ref.read(currentSiteProvider)?.id,
          title: _title.text,
          agenda: _agenda.text,
          startsAt: starts,
          durationMin: _minutes,
        );
        if (!mounted) return;
        Navigator.pop(context);
        unawaited(context.push('/meetings/$id'));
      } else {
        await actions.update(
          widget.meeting!.id,
          title: _title.text,
          agenda: _agenda.text,
          startsAt: starts,
          durationMin: _minutes,
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = MaterialLocalizations.of(context);
    return SingleChildScrollView(
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
          Text(
            widget.meeting == null
                ? 'Schedule a meeting'
                : 'Change the meeting',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Everyone in this chat is invited and joins with the chat\'s call.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'e.g. Weekly planning',
            ),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(CupertinoIcons.calendar),
                  label: Text(l.formatMediumDate(_day)),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _day.isBefore(now) ? now : _day,
                      firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _day = d);
                  },
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(CupertinoIcons.clock),
                  label: Text(l.formatTimeOfDay(_time)),
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: _time,
                    );
                    if (t != null) setState(() => _time = t);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.xs,
            children: [
              for (final d in const [15, 30, 45, 60, 90, 120])
                ChoiceChip(
                  label: Text(
                    d < 60 ? '$d min' : '${d / 60} h'.replaceAll('.0', ''),
                  ),
                  selected: _minutes == d,
                  onSelected: (_) => setState(() => _minutes = d),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _agenda,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Agenda (optional)',
              hintText: 'One point per line',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(
              _busy
                  ? 'Saving…'
                  : widget.meeting == null
                  ? 'Schedule and tell the chat'
                  : 'Save changes',
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendeeDraft {
  _AttendeeDraft.from(Attendee a)
    : name = TextEditingController(text: a.name),
      position = TextEditingController(text: a.position),
      organisation = TextEditingController(text: a.organisation);

  final TextEditingController name;
  final TextEditingController position;
  final TextEditingController organisation;

  void dispose() {
    name.dispose();
    position.dispose();
    organisation.dispose();
  }
}

class _StatusDraft {
  _StatusDraft.from(StatusLine l)
    : area = TextEditingController(text: l.area),
      status = TextEditingController(text: l.status);

  final TextEditingController area;
  final TextEditingController status;

  void dispose() {
    area.dispose();
    status.dispose();
  }
}
