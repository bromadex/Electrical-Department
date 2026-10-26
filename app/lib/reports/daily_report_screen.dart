import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../checklists/checklists_repository.dart';
import '../data/app_error.dart';
import '../jobs/jobs_repository.dart';
import '../jobs/media.dart';
import '../jobs/job_editor.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/charts.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import 'report_pdf.dart';
import 'reports_repository.dart';

enum _Range { day, week, month }

/// The daily report (R-): the day's figures, everyone's update with photos,
/// supervisor approval, PDF to share; plus week and month totals.
class DailyReportScreen extends ConsumerStatefulWidget {
  const DailyReportScreen({super.key});

  @override
  ConsumerState<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends ConsumerState<DailyReportScreen> {
  DateTime _day = DateTime.now();
  _Range _range = _Range.day;

  bool get _isToday {
    final n = DateTime.now();
    return _day.year == n.year && _day.month == n.month && _day.day == n.day;
  }

  @override
  Widget build(BuildContext context) {
    final site = ref.watch(currentSiteProvider);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final dates = MaterialLocalizations.of(context);
    final date = reportDate(_day);
    final day = ref.watch(dailyReportProvider(date));

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Daily report · ${site?.code ?? ''}'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
        actions: [
          if (_range == _Range.day && day.value != null)
            IconButton(
              tooltip: 'Share as PDF',
              icon: const Icon(CupertinoIcons.share),
              onPressed: () => _share(day.value!, site?.name ?? ''),
            ),
        ],
      ),
      floatingActionButton:
          _range == _Range.day &&
              day.value != null &&
              !day.value!.report.approved
          ? FloatingActionButton.extended(
              onPressed: () => showFormSheet(
                context,
                ReportUpdateForm(siteId: site!.id, date: date),
              ),
              icon: const Icon(CupertinoIcons.square_pencil),
              label: const Text("Add my update"),
            )
          : null,
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () async => ref.invalidate(dailyReportProvider(date)),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Space.md,
              top + Space.md,
              Space.md,
              120,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: GlassSegmented<_Range>(
                          value: _range,
                          segments: const {
                            _Range.day: 'Day',
                            _Range.week: 'Week',
                            _Range.month: 'Month',
                          },
                          onChanged: (r) => setState(() => _range = r),
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Earlier',
                            icon: const Icon(CupertinoIcons.chevron_left),
                            onPressed: () => setState(() => _day = _shift(-1)),
                          ),
                          Expanded(
                            child: Text(
                              _label(dates),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Later',
                            icon: const Icon(CupertinoIcons.chevron_right),
                            onPressed: _isToday
                                ? null
                                : () => setState(() {
                                    final next = _shift(1);
                                    _day = next.isAfter(DateTime.now())
                                        ? DateTime.now()
                                        : next;
                                  }),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.sm),
                      if (_range == _Range.day)
                        day.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.all(Space.xl),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (e, _) => EmptyState(
                            icon: CupertinoIcons.wifi_slash,
                            title: 'Could not load the report',
                            message: AppError.from(e).isRetryable
                                ? 'Reports load when you are connected.'
                                : AppError.from(e).message,
                          ),
                          data: (d) =>
                              d == null ? const SizedBox() : _DayView(day: d),
                        )
                      else
                        _TotalsView(range: _rangeDates()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  DateTime _shift(int dir) => switch (_range) {
    _Range.day => _day.add(Duration(days: dir)),
    _Range.week => _day.add(Duration(days: 7 * dir)),
    _Range.month => DateTime(_day.year, _day.month + dir, 1),
  };

  ({String from, String to}) _rangeDates() {
    if (_range == _Range.week) {
      final start = _day.subtract(Duration(days: _day.weekday - 1));
      return (
        from: reportDate(start),
        to: reportDate(start.add(const Duration(days: 6))),
      );
    }
    final start = DateTime(_day.year, _day.month, 1);
    final end = DateTime(_day.year, _day.month + 1, 0);
    return (from: reportDate(start), to: reportDate(end));
  }

  String _label(MaterialLocalizations dates) {
    switch (_range) {
      case _Range.day:
        return _isToday ? 'Today' : dates.formatFullDate(_day);
      case _Range.week:
        final r = _rangeDates();
        return 'Week of ${dates.formatMediumDate(DateTime.parse(r.from))}';
      case _Range.month:
        return dates.formatMonthYear(_day);
    }
  }

  Future<void> _share(ReportDay day, String siteName) async {
    final people = ref.read(peopleProvider).value ?? const {};
    final paths = [for (final u in day.updates) ...u.photoPaths];
    var urls = <String, String>{};
    try {
      urls = await ref.read(photoUrlsProvider(paths.join('|')).future);
    } catch (_) {}
    final bytes = await buildReportPdf(
      day: day,
      siteName: siteName,
      people: people,
      photoUrls: urls,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${day.report.code}-${reportDate(day.report.date)}.pdf',
    );
  }
}

class _DayView extends ConsumerWidget {
  const _DayView({required this.day});

  final ReportDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = day.report;
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final people = ref.watch(peopleProvider).value ?? const {};
    final canApprove = session.can('reports.approve', siteId: r.siteId);
    final opened = r.list('jobs_opened');
    final closed = r.list('jobs_closed');
    final done = r.list('checklists_done');
    final missed = r.names('checklists_missed');

    Widget stat(String label, String value, Color color) => Expanded(
      child: SurfaceCard(
        padding: const EdgeInsets.all(Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(color: color),
            ),
            Text(label, style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );

    Widget jobLine(Map<String, dynamic> j, String trailing) => ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: RecordCode(j['code'] as String? ?? 'J-'),
      title: Text(j['title'] as String? ?? ''),
      subtitle: Text(trailing),
      onTap: j['id'] == null ? null : () => context.push('/jobs/${j['id']}'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            RecordCode(r.code),
            const SizedBox(width: Space.xs),
            Pill(
              label: r.approved ? 'Approved' : 'Open',
              color: r.approved ? BrandColors.success : Colors.orange,
              dense: true,
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            stat('Opened', '${opened.length}', BrandColors.maroon),
            const SizedBox(width: Space.xs),
            stat('Closed', '${closed.length}', BrandColors.success),
            const SizedBox(width: Space.xs),
            stat('Still open', '${r.count('jobs_open_now')}', BrandColors.info),
          ],
        ),
        const SizedBox(height: Space.xs),
        Row(
          children: [
            stat('Rounds done', '${done.length}', BrandColors.success),
            const SizedBox(width: Space.xs),
            stat(
              'Missed',
              '${missed.length}',
              missed.isEmpty ? BrandColors.success : Colors.red,
            ),
            const SizedBox(width: Space.xs),
            stat('Tools out', '${r.count('tools_out')}', BrandColors.coral),
          ],
        ),
        const SectionHeader('Jobs closed'),
        SurfaceCard(
          child: closed.isEmpty
              ? const Text('None.')
              : Column(
                  children: [
                    for (final j in closed)
                      jobLine(
                        j,
                        [
                          if (j['by'] != null) 'by ${j['by']}',
                          if (j['note'] != null) '${j['note']}',
                        ].join(' · '),
                      ),
                  ],
                ),
        ),
        const SectionHeader('Jobs opened'),
        SurfaceCard(
          child: opened.isEmpty
              ? const Text('None.')
              : Column(
                  children: [
                    for (final j in opened)
                      jobLine(j, '${j['priority']} · ${j['status']}'),
                  ],
                ),
        ),
        const SectionHeader('Checklist rounds'),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (done.isEmpty && missed.isEmpty)
                const Text('No rounds were due.'),
              for (final c in done)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    CupertinoIcons.checkmark_seal_fill,
                    color: BrandColors.success,
                  ),
                  title: Text('${c['name']}'),
                  subtitle: Text(
                    [
                      if (c['by'] != null) '${c['by']}',
                      if ((c['failed'] as num? ?? 0) > 0)
                        '${c['failed']} failed',
                    ].join(' · '),
                  ),
                ),
              for (final m in missed)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    CupertinoIcons.xmark_seal_fill,
                    color: Colors.red,
                  ),
                  title: Text(m),
                  subtitle: const Text('Missed'),
                ),
            ],
          ),
        ),
        const SectionHeader("Today's updates"),
        if (day.updates.isEmpty)
          Text(
            r.approved
                ? 'No updates were added.'
                : 'Nobody has added an update yet.',
            style: theme.textTheme.bodySmall,
          ),
        for (final (i, u) in day.updates.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: _UpdateCard(update: u, name: people[u.userId]),
          ).entrance(context, index: i.clamp(0, 6)),
        const SectionHeader('Approval'),
        if (r.approved)
          SurfaceCard(
            color: BrandColors.success.withValues(alpha: 0.12),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.checkmark_seal_fill,
                  color: BrandColors.success,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'Approved by ${people[r.approvedBy] ?? 'a supervisor'}'
                    '${r.comment == null ? '' : '\n“${r.comment}”'}',
                  ),
                ),
              ],
            ),
          )
        else if (canApprove)
          _ApproveCard(report: r)
        else
          Text(
            'Waiting for a supervisor to approve.',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _UpdateCard extends ConsumerWidget {
  const _UpdateCard({required this.update, required this.name});

  final ReportUpdate update;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final urls = update.photoPaths.isEmpty
        ? const <String, String>{}
        : ref.watch(photoUrlsProvider(update.photoPaths.join('|'))).value ??
              const {};
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(name: name ?? '?', size: 30),
              const SizedBox(width: Space.xs),
              Text(name ?? 'Someone', style: theme.textTheme.titleSmall),
              const Spacer(),
              Text(
                TimeOfDay.fromDateTime(update.createdAt).format(context),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(update.body),
          if (update.photoPaths.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in update.photoPaths)
                  PhotoThumb(url: urls[p], size: 84),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ApproveCard extends ConsumerStatefulWidget {
  const _ApproveCard({required this.report});

  final DailyReport report;

  @override
  ConsumerState<_ApproveCard> createState() => _ApproveCardState();
}

class _ApproveCardState extends ConsumerState<_ApproveCard> {
  final _comment = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _comment,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Comment (optional)'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: Space.sm),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await ref
                          .read(reportActionsProvider)
                          .approve(widget.report, _comment.text);
                      HapticFeedback.mediumImpact();
                    } catch (e) {
                      setState(() {
                        _busy = false;
                        _error = AppError.from(e).message;
                      });
                    }
                  },
            icon: const Icon(CupertinoIcons.checkmark_seal),
            label: const Text('Approve report'),
          ),
        ],
      ),
    );
  }
}

class ReportUpdateForm extends ConsumerStatefulWidget {
  const ReportUpdateForm({super.key, required this.siteId, required this.date});

  final String siteId;
  final String date;

  @override
  ConsumerState<ReportUpdateForm> createState() => _ReportUpdateFormState();
}

class _ReportUpdateFormState extends ConsumerState<ReportUpdateForm> {
  final _body = TextEditingController();
  List<Uint8List> _photos = [];
  bool _busy = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          Text("Today's update", style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.md),
          TextField(
            controller: _body,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText:
                  'What did you work on? Anything the next shift should know?',
            ),
          ),
          const SizedBox(height: Space.md),
          PhotoStrip(
            photos: _photos,
            onChanged: (p) => setState(() => _photos = p),
          ),
          const SizedBox(height: Space.lg),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    if (_body.text.trim().isEmpty) return;
                    setState(() => _busy = true);
                    HapticFeedback.mediumImpact();
                    await ref
                        .read(reportActionsProvider)
                        .addUpdate(
                          siteId: widget.siteId,
                          date: widget.date,
                          body: _body.text,
                          photos: _photos,
                        );
                    if (context.mounted) Navigator.pop(context);
                  },
            icon: const Icon(CupertinoIcons.paperplane_fill),
            label: const Text('Add to the report'),
          ),
        ],
      ),
    );
  }
}

class _TotalsView extends ConsumerWidget {
  const _TotalsView({required this.range});

  final ({String from, String to}) range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref
        .watch(reportTotalsProvider(range))
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text(AppError.from(e).message),
          data: (t) {
            final tiles = [
              ('Days reported', '${t.days}', BrandColors.info),
              ('Jobs opened', '${t.jobsOpened}', BrandColors.maroon),
              ('Jobs closed', '${t.jobsClosed}', BrandColors.success),
              ('Rounds done', '${t.roundsDone}', BrandColors.success),
              (
                'Rounds missed',
                '${t.roundsMissed}',
                t.roundsMissed == 0 ? BrandColors.success : Colors.red,
              ),
              ('Tools issued', '${t.toolsIssued}', BrandColors.coral),
              ('Reports approved', '${t.approved}/${t.days}', BrandColors.info),
            ];
            return Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                for (final (label, value, color) in tiles)
                  SizedBox(
                    width: 180,
                    child: SurfaceCard(
                      padding: const EdgeInsets.all(Space.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            value,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: color,
                            ),
                          ),
                          Text(label, style: theme.textTheme.labelMedium),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
  }
}
