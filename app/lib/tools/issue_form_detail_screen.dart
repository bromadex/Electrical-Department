import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../data/app_error.dart';
import '../data/site_data.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/charts.dart' show GlassSegmented;
import '../ui/form_sheet.dart';
import '../ui/signature_pad.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'issue_form_pdf.dart';
import 'issue_forms_repository.dart';
import 'tools_repository.dart';
import 'tools_screen.dart';

String formStatusLabel(IssueForm f) => switch (f.status) {
  'returned' => 'Returned',
  'part_returned' => '${f.out} still out',
  _ => f.overdue ? 'Overdue' : 'Out',
};

Color formStatusColor(IssueForm f) => switch (f.status) {
  'returned' => BrandColors.success,
  _ => f.overdue ? Colors.red : BrandColors.info,
};

enum _Show { out, returned, all }

/// Tool issue forms at the current site.
class IssueFormsScreen extends ConsumerStatefulWidget {
  const IssueFormsScreen({super.key});

  @override
  ConsumerState<IssueFormsScreen> createState() => _IssueFormsScreenState();
}

class _IssueFormsScreenState extends ConsumerState<IssueFormsScreen> {
  _Show _show = _Show.out;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final site = ref.watch(currentSiteProvider);
    final session = ref.watch(sessionProvider);
    final canIssue =
        site != null && session.can('tools.issue', siteId: site.id);
    final forms = ref.watch(issueFormsProvider);
    final dates = MaterialLocalizations.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final q = _search.text.trim().toLowerCase();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/equipment?side=tools'),
        title: const Text('Tool issue forms'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      floatingActionButton: canIssue
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/tools/forms/new'),
              icon: const Icon(CupertinoIcons.add),
              label: const Text('New form'),
            )
          : null,
      body: MeshBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(Space.md, top + Space.md, Space.md, 120),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GlassSegmented<_Show>(
                      value: _show,
                      segments: const {
                        _Show.out: 'Out',
                        _Show.returned: 'Returned',
                        _Show.all: 'All',
                      },
                      onChanged: (s) => setState(() => _show = s),
                    ),
                    const SizedBox(height: Space.sm),
                    CupertinoSearchTextField(
                      controller: _search,
                      placeholder: 'Search name, company or TI- code',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: Space.md),
                    forms.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => EmptyState(
                        icon: CupertinoIcons.wifi_slash,
                        title: 'Forms load when you are online',
                        message: AppError.from(e).isRetryable
                            ? 'New forms you fill in now are kept and sent '
                                  'when the signal is back.'
                            : AppError.from(e).message,
                      ),
                      data: (list) {
                        final shown = [
                          for (final f in list)
                            if (switch (_show) {
                                  _Show.out => !f.returned,
                                  _Show.returned => f.returned,
                                  _Show.all => true,
                                } &&
                                (q.isEmpty ||
                                    f.code.toLowerCase().contains(q) ||
                                    f.recipientName.toLowerCase().contains(q) ||
                                    (f.company?.toLowerCase().contains(q) ??
                                        false)))
                              f,
                        ];
                        if (shown.isEmpty) {
                          return EmptyState(
                            icon: CupertinoIcons.doc_text,
                            title: list.isEmpty
                                ? 'No issue forms yet'
                                : 'Nothing here',
                            message: list.isEmpty
                                ? 'Issue several tools to one person, '
                                      'also someone from another company, '
                                      'with signatures and a PDF.'
                                : 'No forms match.',
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final f in shown)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Space.sm,
                                ),
                                child: SurfaceCard(
                                  onTap: () =>
                                      context.push('/tools/forms/${f.id}'),
                                  child: Row(
                                    children: [
                                      AppAvatar(name: f.recipientName),
                                      const SizedBox(width: Space.md),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              [
                                                f.recipientName,
                                                ?f.company,
                                              ].join(' · '),
                                              style: theme.textTheme.titleSmall,
                                            ),
                                            Text(
                                              [
                                                f.code,
                                                '${f.lines.length} tools',
                                                dates.formatMediumDate(
                                                  f.issuedAt,
                                                ),
                                                if (f.dueBack != null &&
                                                    !f.returned)
                                                  'back by ${dates.formatShortMonthDay(f.dueBack!)}',
                                              ].join(' · '),
                                              style: theme.textTheme.labelSmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Pill(
                                        label: formStatusLabel(f),
                                        color: formStatusColor(f),
                                        dense: true,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
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

/// One form: details, tools with condition out and back, signatures, the
/// PDF, and taking tools back.
class IssueFormDetailScreen extends ConsumerWidget {
  const IssueFormDetailScreen({super.key, required this.id});

  final String id;

  Future<void> _pdf(
    BuildContext context,
    WidgetRef ref,
    IssueForm f,
    Map<String, String> people,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Making the PDF…')));
    try {
      final storage = ref.read(supabaseProvider).storage.from('tool-files');
      final signatures = <String, Uint8List>{};
      for (final path in [
        f.issuerSignature,
        f.recipientSignature,
        f.leadSignature,
        f.returnIssuerSignature,
        f.returnRecipientSignature,
        f.returnLeadSignature,
      ]) {
        if (path == null) continue;
        try {
          signatures[path] = await storage.download(path);
        } catch (_) {
          // A signature still uploading is left blank on the PDF.
        }
      }
      final sites = ref.read(sessionProvider).sites;
      final bytes = await buildIssueFormPdf(
        form: f,
        siteName: sites.where((s) => s.id == f.siteId).firstOrNull?.name ?? '',
        issuedByName: people[f.issuedBy],
        receivedBackByName: people[f.receivedBackBy],
        signatures: signatures,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${f.code}-tool-issue-form.pdf',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not make the PDF. ($e)')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final form = ref.watch(issueFormProvider(id));
    final people = ref.watch(peopleProvider).value ?? const {};
    final session = ref.watch(sessionProvider);
    final dates = MaterialLocalizations.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final f = form.value;
    final canIssue = f != null && session.can('tools.issue', siteId: f.siteId);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/tools/forms'),
        title: Text(f?.code ?? 'Issue form'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
        actions: [
          if (f != null)
            TextButton.icon(
              onPressed: () => _pdf(context, ref, f, people),
              icon: const Icon(CupertinoIcons.doc_text),
              label: const Text('PDF'),
            ),
          const SizedBox(width: Space.xs),
        ],
      ),
      floatingActionButton: f != null && canIssue && !f.returned
          ? FloatingActionButton.extended(
              backgroundColor: BrandColors.success,
              foregroundColor: Colors.white,
              onPressed: () => showFormSheet(context, _TakeBackSheet(form: f)),
              icon: const Icon(CupertinoIcons.arrow_down_circle_fill),
              label: const Text('Take back'),
            )
          : null,
      body: MeshBackground(
        child: f == null
            ? Center(
                child: form.isLoading
                    ? const CircularProgressIndicator()
                    : EmptyState(
                        icon: CupertinoIcons.cloud_upload,
                        title: form.hasError
                            ? 'The form loads when you are online'
                            : 'Waiting to sync',
                        message: form.hasError
                            ? AppError.from(form.error!).message
                            : 'The form is saved on this phone and shows '
                                  'here once it reaches the server.',
                      ),
              )
            : RefreshIndicator(
                edgeOffset: top,
                onRefresh: () async => ref.invalidate(issueFormProvider(id)),
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
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _header(context, f, people, dates, theme),
                            SectionHeader(
                              'Tools · ${f.lines.length}'
                              '${f.out > 0 && f.out < f.lines.length ? ' · ${f.out} still out' : ''}',
                            ),
                            SurfaceCard(
                              padding: const EdgeInsets.symmetric(
                                vertical: Space.xs,
                              ),
                              child: Column(
                                children: [
                                  for (final (i, l) in f.lines.indexed)
                                    ListTile(
                                      onTap: () =>
                                          context.push('/tools/${l.toolId}'),
                                      leading: SizedBox(
                                        width: 24,
                                        child: Center(child: Text('${i + 1}')),
                                      ),
                                      title: Text(
                                        [
                                          l.name,
                                          if (l.qty > 1) '× ${l.qty}',
                                        ].join(' '),
                                      ),
                                      subtitle: Text(
                                        [
                                          ?l.code,
                                          if (l.serialNo != null)
                                            'S/N ${l.serialNo}',
                                          'out ${ToolCondition.parse(l.issueCondition ?? 'good').label.toLowerCase()}',
                                          if (l.back)
                                            'back ${dates.formatShortMonthDay(l.returnedAt!)} ${ToolCondition.parse(l.returnCondition ?? 'good').label.toLowerCase()}',
                                          ?l.returnNote,
                                        ].join(' · '),
                                        style: theme.textTheme.labelSmall,
                                      ),
                                      trailing: Icon(
                                        l.back
                                            ? CupertinoIcons
                                                  .checkmark_circle_fill
                                            : CupertinoIcons.arrow_up_right,
                                        color: l.back
                                            ? conditionColor(
                                                ToolCondition.parse(
                                                  l.returnCondition ?? 'good',
                                                ),
                                              )
                                            : BrandColors.info,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SectionHeader('Signed at issue'),
                            _signatures(context, [
                              (
                                'Issued by',
                                people[f.issuedBy],
                                f.issuerSignature,
                              ),
                              (
                                'Received by',
                                f.recipientName,
                                f.recipientSignature,
                              ),
                              ('Team lead', f.teamLead, f.leadSignature),
                            ]),
                            if (f.lines.any((l) => l.back)) ...[
                              const SectionHeader('Signed at return'),
                              _signatures(context, [
                                (
                                  'Received back by',
                                  people[f.receivedBackBy],
                                  f.returnIssuerSignature,
                                ),
                                (
                                  'Returned by',
                                  f.recipientName,
                                  f.returnRecipientSignature,
                                ),
                                (
                                  'Team lead',
                                  f.teamLead,
                                  f.returnLeadSignature,
                                ),
                              ]),
                            ],
                            if (f.remarks != null ||
                                f.returnRemarks != null) ...[
                              const SectionHeader('Remarks'),
                              SurfaceCard(
                                child: Text(
                                  [?f.remarks, ?f.returnRemarks].join('\n'),
                                ),
                              ),
                            ],
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

  Widget _header(
    BuildContext context,
    IssueForm f,
    Map<String, String> people,
    MaterialLocalizations dates,
    ThemeData theme,
  ) {
    Widget row(IconData icon, String text, {Color? color, VoidCallback? tap}) =>
        InkWell(
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Row(
              children: [
                Icon(icon, size: 16, color: color ?? theme.hintColor),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: color,
                      decoration: tap == null ? null : TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(name: f.recipientName, size: 48),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.recipientName, style: theme.textTheme.titleLarge),
                    Text(
                      [?f.recipientRole, ?f.company].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Pill(label: formStatusLabel(f), color: formStatusColor(f)),
            ],
          ),
          const SizedBox(height: Space.sm),
          row(
            CupertinoIcons.calendar,
            'Issued ${dates.formatMediumDate(f.issuedAt)}'
            '${people[f.issuedBy] == null ? '' : ' by ${people[f.issuedBy]}'}',
          ),
          if (f.dueBack != null)
            row(
              CupertinoIcons.clock,
              f.returned
                  ? 'Was due back ${dates.formatMediumDate(f.dueBack!)}'
                  : 'Back by ${dates.formatMediumDate(f.dueBack!)}',
              color: f.overdue ? Colors.red : null,
            ),
          if (f.returnedAt != null)
            row(
              CupertinoIcons.checkmark_seal,
              'All back ${dates.formatMediumDate(f.returnedAt!)}',
              color: BrandColors.success,
            ),
          if (f.teamLead != null)
            row(CupertinoIcons.person_2, 'Team lead: ${f.teamLead}'),
          if (f.location != null) row(CupertinoIcons.location, f.location!),
          if (f.jobCardNumber != null)
            row(
              CupertinoIcons.hammer,
              'For job card ${f.jobCardNumber}',
              tap: () => context.push('/jobs/${f.jobCardNumber}'),
            ),
        ],
      ),
    );
  }

  Widget _signatures(
    BuildContext context,
    List<(String, String?, String?)> signers,
  ) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final (role, name, path) in signers)
          SizedBox(
            width: 200,
            child: SurfaceCard(
              padding: const EdgeInsets.all(Space.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(role, style: theme.textTheme.labelMedium),
                  Text(
                    name ?? '—',
                    style: theme.textTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.xs),
                  Container(
                    height: 60,
                    width: double.infinity,
                    color: Colors.white,
                    child: path == null
                        ? Center(
                            child: Text(
                              'Not signed',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.black45,
                              ),
                            ),
                          )
                        : Consumer(
                            builder: (context, ref, _) => ref
                                .watch(toolFileUrlProvider(path))
                                .when(
                                  loading: () => const SizedBox.shrink(),
                                  error: (_, _) => const Center(
                                    child: Icon(
                                      CupertinoIcons.cloud_upload,
                                      color: Colors.black38,
                                    ),
                                  ),
                                  data: (url) => Image.network(
                                    url,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) => const Center(
                                      child: Icon(
                                        CupertinoIcons.cloud_upload,
                                        color: Colors.black38,
                                      ),
                                    ),
                                  ),
                                ),
                          ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Back {
  _Back(this.line);

  final IssueFormLine line;
  bool picked = true;
  ToolCondition condition = ToolCondition.good;
  final note = TextEditingController();
}

/// Takes back some or all of a form's tools, with condition per tool and
/// the return signatures.
class _TakeBackSheet extends ConsumerStatefulWidget {
  const _TakeBackSheet({required this.form});

  final IssueForm form;

  @override
  ConsumerState<_TakeBackSheet> createState() => _TakeBackSheetState();
}

class _TakeBackSheetState extends ConsumerState<_TakeBackSheet> {
  late final _items = [
    for (final l in widget.form.lines)
      if (!l.back) _Back(l),
  ];
  final _issuer = SignatureController();
  final _recipient = SignatureController();
  final _lead = SignatureController();
  final _remarks = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final i in _items) {
      i.note.dispose();
    }
    _issuer.dispose();
    _recipient.dispose();
    _lead.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final picked = _items.where((i) => i.picked).toList();
    String? fail;
    if (picked.isEmpty) {
      fail = 'Tick the tools that came back';
    } else if (picked.any(
      (i) => i.condition != ToolCondition.good && i.note.text.trim().isEmpty,
    )) {
      fail = 'Say what is wrong with each tool not in good condition';
    } else if (_issuer.isEmpty) {
      fail = 'Sign as the person receiving them back';
    }
    if (fail != null) {
      setState(() => _error = fail);
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    await ref
        .read(issueFormActionsProvider)
        .takeBack(
          widget.form,
          lines: [
            for (final i in picked)
              (
                toolId: i.line.toolId,
                condition: i.condition,
                note: i.note.text,
              ),
          ],
          signatures: (
            issuer: await _issuer.toPng(),
            recipient: _recipient.isEmpty ? null : await _recipient.toPng(),
            lead: _lead.isEmpty ? null : await _lead.toPng(),
          ),
          remarks: _remarks.text,
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = widget.form;
    Widget sign(String title, SignatureController c) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Space.xs),
          child: Text(title, style: theme.textTheme.labelLarge),
        ),
        SignaturePad(controller: c, height: 120),
        const SizedBox(height: Space.sm),
      ],
    );
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
          Text('Take back · ${f.code}', style: theme.textTheme.headlineSmall),
          Text(
            'Tick what came back and its condition. Damaged or lost tools '
            'alert the supervisors.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.md),
          for (final i in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: SurfaceCard(
                padding: const EdgeInsets.all(Space.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CheckboxListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: i.picked,
                      onChanged: (v) => setState(() => i.picked = v ?? false),
                      title: Text(i.line.name),
                      subtitle: Text(
                        [
                          ?i.line.code,
                          if (i.line.qty > 1) 'qty ${i.line.qty}',
                        ].join(' · '),
                      ),
                    ),
                    if (i.picked) ...[
                      ConditionPicker(
                        value: i.condition,
                        onChanged: (c) => setState(() {
                          i.condition = c;
                          _error = null;
                        }),
                      ),
                      if (i.condition != ToolCondition.good)
                        TextField(
                          controller: i.note,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'What is wrong with it?',
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          TextField(
            controller: _remarks,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Remarks (optional)'),
          ),
          const SizedBox(height: Space.md),
          sign('Received back by (you)', _issuer),
          sign('Returned by · ${f.recipientName} (optional)', _recipient),
          sign(
            'Team lead${f.teamLead == null ? '' : ' · ${f.teamLead}'} '
            '(optional)',
            _lead,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: BrandColors.success),
            onPressed: _busy ? null : _save,
            icon: const Icon(CupertinoIcons.arrow_down_circle_fill),
            label: Text('Take back ${_items.where((i) => i.picked).length}'),
          ),
        ],
      ),
    );
  }
}
