import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:url_launcher/url_launcher.dart';

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

enum _Tab { minutes, agenda, present }

class _MeetingScreenState extends ConsumerState<MeetingScreen> {
  _Tab _tab = _Tab.minutes;
  bool _busy = false;

  Future<void> _run(Future<void> Function() job, {String? done}) async {
    setState(() => _busy = true);
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
    } finally {
      if (mounted) setState(() => _busy = false);
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
                        if (m.recording == 'recording')
                          const Pill(
                            label: 'Recording',
                            color: Colors.red,
                            icon: CupertinoIcons.circle_fill,
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
                        if (canRun)
                          (
                            icon: m.recording == 'recording'
                                ? CupertinoIcons.stop_circle_fill
                                : CupertinoIcons.recordingtape,
                            label: m.recording == 'recording'
                                ? 'Stop recording'
                                : 'Record',
                            onTap: _busy || !m.open
                                ? null
                                : () => _run(
                                    () => actions.record(
                                      m.id,
                                      start: m.recording != 'recording',
                                    ),
                                    done: m.recording == 'recording'
                                        ? 'Recording stopped. Draft the '
                                              'minutes in a minute or two.'
                                        : 'Recording. Everyone in the call '
                                              'is told.',
                                  ),
                            color: Colors.red,
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
                    if (m.recording == 'failed' && m.recordingError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.sm),
                        child: Text(
                          'Recording failed: ${m.recordingError}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    if (canRun &&
                        !m.open &&
                        m.recording == 'none' &&
                        !m.cancelled)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.xs),
                        child: Text(
                          'Recording is possible from 15 minutes before the '
                          'start until an hour after the end.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: Space.md),
                    GlassSegmented<_Tab>(
                      value: _tab,
                      segments: const {
                        _Tab.minutes: 'Minutes',
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
  late bool _editing = !widget.meeting.minutes.isEmpty;
  bool _busy = false;

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
      _editing = true;
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    _summary.dispose();
    for (final c in _decisions) {
      c.dispose();
    }
    for (final a in _actions) {
      a.text.dispose();
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
          ),
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
    List<String> present = const [];
    try {
      present = [
        for (final p in await ref.read(meetingAttendanceProvider(m.id).future))
          p.name,
      ];
    } catch (_) {}
    final bytes = await buildMinutesPdf(
      meeting: m,
      chatName: widget.chatName,
      chairName: names[m.chairId] ?? '—',
      attendance: present,
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
              'Claude drafts a summary, decisions and actions with owners '
              'and dates. You check and change them before they go out.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: Space.md),
            if (m.audioPath != null) ...[
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _do(
                        () => actions.draftMinutes(m.id),
                        'Draft ready. Check it below.',
                      ),
                icon: const Icon(CupertinoIcons.waveform),
                label: Text(_busy ? 'Listening…' : 'Draft from the recording'),
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
                  onPressed: () => setState(() => _editing = true),
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
              Text('Summary', style: theme.textTheme.titleSmall),
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
        if (m.audioPath != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final url = await ref.read(
                  meetingAudioUrlProvider(m.audioPath!).future,
                );
                await launchUrl(Uri.parse(url));
              },
              icon: const Icon(CupertinoIcons.play_circle),
              label: const Text('Listen to the recording'),
            ),
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
  _ActionDraft({String text = '', this.ownerId, this.ownerName, this.due})
    : text = TextEditingController(text: text);

  factory _ActionDraft.from(MeetingAction a) => _ActionDraft(
    text: a.text,
    ownerId: a.ownerId,
    ownerName: a.ownerName,
    due: a.due,
  );

  final TextEditingController text;
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
