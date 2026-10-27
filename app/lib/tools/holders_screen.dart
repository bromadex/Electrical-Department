import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/local_db.dart';
import '../data/site_data.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'issue_forms_repository.dart';
import 'tools_repository.dart';

/// One person holding tools: an app user or someone on an issue form.
class _Holder {
  _Holder(this.name, this.company);

  final String name;
  String? company;
  final tools = <LocalTool>[];

  int get overdue => tools.where(toolOverdue).length;
}

/// Who has what: every person holding tools right now, with their company
/// and what is overdue. What the site manager checks before someone goes on
/// leave or leaves the job.
class ToolHoldersScreen extends ConsumerStatefulWidget {
  const ToolHoldersScreen({super.key});

  @override
  ConsumerState<ToolHoldersScreen> createState() => _ToolHoldersScreenState();
}

class _ToolHoldersScreenState extends ConsumerState<ToolHoldersScreen> {
  final _search = TextEditingController();
  final _open = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tools = ref.watch(siteToolsProvider).value ?? const <LocalTool>[];
    final people = ref.watch(peopleProvider).value ?? const {};
    // Companies come from the forms (online); without signal the names
    // still show.
    final forms = ref.watch(issueFormsProvider).value ?? const <IssueForm>[];
    final companyByForm = {for (final f in forms) f.id: f.company};
    final dates = MaterialLocalizations.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    final holders = <String, _Holder>{};
    for (final t in tools) {
      if (!toolOut(t)) continue;
      final name = toolHolder(t, people) ?? 'Someone';
      final company = t.formId == null ? null : companyByForm[t.formId];
      final key = t.holderId ?? 'name:${name.toLowerCase()}|${company ?? ''}';
      final h = holders.putIfAbsent(key, () => _Holder(name, company));
      h.company ??= company;
      h.tools.add(t);
    }
    final q = _search.text.trim().toLowerCase();
    final shown =
        [
          for (final h in holders.values)
            if (q.isEmpty ||
                h.name.toLowerCase().contains(q) ||
                (h.company?.toLowerCase().contains(q) ?? false))
              h,
        ]..sort((a, b) {
          final o = b.overdue.compareTo(a.overdue);
          return o != 0 ? o : a.name.compareTo(b.name);
        });
    final out = holders.values.fold<int>(0, (n, h) => n + h.tools.length);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/equipment?side=tools'),
        title: const Text('Who has what'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            Space.md,
            top + Space.md,
            Space.md,
            Space.xl,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '$out tools out with ${holders.length} '
                      '${holders.length == 1 ? 'person' : 'people'}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                    CupertinoSearchTextField(
                      controller: _search,
                      placeholder: 'Search a name or company',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: Space.md),
                    if (shown.isEmpty)
                      EmptyState(
                        icon: CupertinoIcons.cube_box,
                        title: holders.isEmpty
                            ? 'Every tool is in the store'
                            : 'Nobody matches',
                        message: holders.isEmpty
                            ? 'People holding tools show here, with their '
                                  'company and anything overdue.'
                            : 'Try another name or company.',
                      ),
                    for (final h in shown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: SurfaceCard(
                          onTap: () => setState(
                            () => _open.contains(h.name)
                                ? _open.remove(h.name)
                                : _open.add(h.name),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  AppAvatar(name: h.name),
                                  const SizedBox(width: Space.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          h.name,
                                          style: theme.textTheme.titleSmall,
                                        ),
                                        Text(
                                          [
                                            ?h.company,
                                            '${h.tools.length} '
                                                '${h.tools.length == 1 ? 'tool' : 'tools'}',
                                          ].join(' · '),
                                          style: theme.textTheme.labelSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (h.overdue > 0)
                                    Pill(
                                      label: '${h.overdue} overdue',
                                      color: Colors.red,
                                      dense: true,
                                    ),
                                  Icon(
                                    _open.contains(h.name)
                                        ? CupertinoIcons.chevron_up
                                        : CupertinoIcons.chevron_down,
                                    size: 18,
                                  ),
                                ],
                              ),
                              if (_open.contains(h.name)) ...[
                                const SizedBox(height: Space.sm),
                                for (final t in h.tools)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    onTap: () => context.push('/tools/${t.id}'),
                                    title: Text(
                                      '${t.code ?? 'New'} · ${t.name}',
                                    ),
                                    subtitle: Text(
                                      [
                                        if (t.issuedAt != null)
                                          'since ${dates.formatShortMonthDay(t.issuedAt!)}',
                                        if (t.dueBack != null)
                                          '${toolOverdue(t) ? 'was due' : 'due'} '
                                              '${dates.formatShortMonthDay(t.dueBack!)}',
                                      ].join(' · '),
                                      style: TextStyle(
                                        color: toolOverdue(t)
                                            ? Colors.red
                                            : null,
                                      ),
                                    ),
                                    trailing: t.formId == null
                                        ? null
                                        : IconButton(
                                            tooltip: 'Issue form',
                                            icon: const Icon(
                                              CupertinoIcons.doc_text,
                                            ),
                                            onPressed: () => context.push(
                                              '/tools/forms/${t.formId}',
                                            ),
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
          ],
        ),
      ),
    );
  }
}
