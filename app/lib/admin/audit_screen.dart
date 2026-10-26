import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/data_table.dart';
import '../ui/format.dart';
import '../ui/forms.dart';
import '../ui/page.dart';
import '../ui/status.dart';

/// Kinds of record in the audit log, with readable names.
const auditTables = [
  ('job_cards', 'Job cards'),
  ('job_assignments', 'Assignments'),
  ('job_work_sessions', 'Work sessions'),
  ('job_time_corrections', 'Time corrections'),
  ('job_waits', 'Waits'),
  ('job_work_records', 'Work log'),
  ('job_safety_records', 'Safety checks'),
  ('job_submissions', 'Submissions'),
  ('job_reviews', 'Reviews'),
  ('job_closures', 'Closures'),
  ('job_comments', 'Comments'),
  ('job_attachments', 'Files'),
  ('service_requests', 'Requests'),
  ('assets', 'Equipment'),
  ('profiles', 'People'),
  ('user_roles', 'Roles'),
  ('system_settings', 'Settings'),
  ('priority_levels', 'Priorities'),
  ('escalation_rules', 'Escalation rules'),
  ('escalation_contacts', 'Escalation contacts'),
  ('safety_checklist_items', 'Safety checklist'),
  ('departments', 'Departments'),
  ('sites', 'Sites'),
  ('areas', 'Work areas'),
];

String _tableLabel(String t) =>
    auditTables.firstWhere((x) => x.$1 == t, orElse: () => (t, humanize(t))).$2;

class AuditEntry {
  AuditEntry(Map<String, dynamic> r)
    : at = parseTime(r['at'])!,
      userName = r['user_name'] as String? ?? 'System',
      table = r['table_name'] as String,
      recordLabel = r['record_label'] as String?,
      action = r['action'] as String,
      details = r['details'] is Map
          ? Map<String, dynamic>.from(r['details'] as Map)
          : const {},
      total = (r['total'] as num?)?.toInt() ?? 0;

  final DateTime at;
  final String userName;
  final String table;
  final String? recordLabel;
  final String action;
  final Map<String, dynamic> details;
  final int total;

  static const _hidden = {'id', 'created_at', 'updated_at', 'is_archived'};

  /// "status: in progress → on hold; reason: …" for changes; the main
  /// fields for new records.
  String get summary {
    if (action == 'insert') {
      final keys = details.keys.where(
        (k) => !_hidden.contains(k) && details[k] != null,
      );
      return keys
          .take(4)
          .map((k) => '${humanize(k)}: ${_short(details[k])}')
          .join('; ');
    }
    return details.entries
        .where((e) => !_hidden.contains(e.key))
        .map((e) {
          final change = e.value is Map ? e.value as Map : const {};
          return '${humanize(e.key)}: ${_short(change['from'])} → ${_short(change['to'])}';
        })
        .join('; ');
  }

  static String _short(Object? v) {
    if (v == null) return '—';
    final s = v is String ? v : jsonEncode(v);
    final t = s.replaceAll('_', ' ');
    return t.length > 60 ? '${t.substring(0, 57)}…' : t;
  }
}

typedef AuditQuery = ({int days, String? table, String search, int page});

final auditProvider = FutureProvider.autoDispose
    .family<List<AuditEntry>, AuditQuery>((ref, q) async {
      final rows = await ref
          .watch(supabaseProvider)
          .rpc(
            'fn_audit_log',
            params: {
              'p_from': q.days == 0
                  ? null
                  : DateTime.now()
                        .toUtc()
                        .subtract(Duration(days: q.days))
                        .toIso8601String(),
              'p_to': null,
              'p_table': q.table,
              'p_user': null,
              'p_query': q.search.trim().isEmpty ? null : q.search.trim(),
              'p_limit': AuditScreen.pageSize,
              'p_offset': q.page * AuditScreen.pageSize,
            },
          );
      return [
        for (final r in rows as List) AuditEntry(Map<String, dynamic>.from(r)),
      ];
    });

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  static const pageSize = 50;

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  int _days = 7;
  String? _table;
  String _search = '';
  int _page = 0;
  final _searchBox = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (!session.perms.canEverywhere('audit.view')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Audit log access needed',
        message: 'Department managers and system administrators can read the audit log.',
      );
    }
    final query = (days: _days, table: _table, search: _search, page: _page);
    final entries = ref.watch(auditProvider(query));
    final theme = Theme.of(context);

    return AppPage(
      title: 'Audit Logs',
      subtitle: 'Every change: who, what and when. Nothing here can be edited.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('24 h')),
                  ButtonSegment(value: 7, label: Text('7 d')),
                  ButtonSegment(value: 30, label: Text('30 d')),
                  ButtonSegment(value: 0, label: Text('All')),
                ],
                selected: {_days},
                onSelectionChanged: (s) => setState(() {
                  _days = s.first;
                  _page = 0;
                }),
              ),
              SizedBox(
                width: 240,
                child: DropdownField<String>(
                  label: 'Record type',
                  value: _table,
                  items: auditTables,
                  onChanged: (v) => setState(() {
                    _table = v;
                    _page = 0;
                  }),
                ),
              ),
              if (_table != null)
                TextButton(
                  onPressed: () => setState(() {
                    _table = null;
                    _page = 0;
                  }),
                  child: const Text('All types'),
                ),
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _searchBox,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    labelText: 'Search number, person or value',
                  ),
                  onSubmitted: (v) => setState(() {
                    _search = v;
                    _page = 0;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Card(
            clipBehavior: Clip.antiAlias,
            child: AsyncView(
              value: entries,
              onRetry: () => ref.invalidate(auditProvider(query)),
              data: (list) => PagedTable<AuditEntry>(
                rows: list,
                total: list.isEmpty ? 0 : list.first.total,
                page: _page,
                pageSize: AuditScreen.pageSize,
                onPage: (p) => setState(() => _page = p),
                emptyMessage: 'No changes match these filters.',
                cardBuilder: (e) => Card(
                  child: ListTile(
                    title: Text(
                      '${_tableLabel(e.table)} ${e.recordLabel ?? ''} · ${humanize(e.action)}',
                    ),
                    subtitle: Text(
                      '${e.userName} · ${fmtDateTime(e.at)}\n${e.summary}',
                    ),
                    isThreeLine: true,
                  ),
                ),
                columns: [
                  TableCol('When', (e) => Text(fmtDateTime(e.at))),
                  TableCol('Who', (e) => Text(e.userName)),
                  TableCol(
                    'What',
                    (e) =>
                        Text('${_tableLabel(e.table)} ${e.recordLabel ?? ''}'),
                  ),
                  TableCol(
                    'Action',
                    (e) => Pill(
                      label: humanize(e.action),
                      dense: true,
                      color: switch (e.action) {
                        'insert' => AppColors.success,
                        'status' => AppColors.info,
                        'archive' => AppColors.neutral,
                        _ => AppColors.warning,
                      },
                    ),
                  ),
                  TableCol(
                    'Changes',
                    (e) => SizedBox(
                      width: 460,
                      child: Text(
                        e.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
