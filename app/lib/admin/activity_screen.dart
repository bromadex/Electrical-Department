import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../ui/time.dart';
import '../data/site_data.dart';
import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';

/// What each logged table is called, and where its records open.
const _tables = {
  'jobs': ('Jobs', CupertinoIcons.wrench, '/jobs/'),
  'tools': ('Tools', CupertinoIcons.hammer, '/tools/'),
  'documents': ('Documents', CupertinoIcons.doc_text, '/documents/'),
  'assets': ('Assets', CupertinoIcons.gear_alt, '/assets/'),
  'checklist_templates': (
    'Checklists',
    CupertinoIcons.list_bullet,
    '/checklists/',
  ),
  'daily_reports': ('Reports', CupertinoIcons.chart_bar, null),
  'profiles': ('People', CupertinoIcons.person, null),
  'user_roles': ('Roles', CupertinoIcons.shield, null),
};

typedef _Filter = ({String? table, String query});

final _activityProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String?>((ref, table) async {
      var q = ref.watch(supabaseProvider).from('activity').select();
      if (table != null) q = q.eq('table_name', table);
      final rows = await q.order('at', ascending: false).limit(300);
      return [for (final r in rows) Map<String, dynamic>.from(r)];
    });

/// Audit log for system administrators: every change, who made it, when.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  _Filter _f = (table: null, query: '');

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(_activityProvider(_f.table));
    final people = ref.watch(peopleProvider).value ?? const {};
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    String describe(Map<String, dynamic> r) {
      final d = (r['details'] as Map?) ?? const {};
      return switch (r['action']) {
        'insert' => 'added',
        'archive' => 'removed',
        _ => d.isEmpty ? 'changed' : 'changed ${d.keys.take(4).join(', ')}',
      };
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Activity log'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () async => ref.invalidate(_activityProvider(_f.table)),
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
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CupertinoSearchTextField(
                        placeholder: 'Search people or changes',
                        onChanged: (v) =>
                            setState(() => _f = (table: _f.table, query: v)),
                      ),
                      const SizedBox(height: Space.sm),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final t in [null, ..._tables.keys])
                              Padding(
                                padding: const EdgeInsets.only(right: Space.xs),
                                child: ChoiceChip(
                                  label: Text(
                                    t == null ? 'All' : _tables[t]!.$1,
                                  ),
                                  selected: _f.table == t,
                                  onSelected: (_) => setState(
                                    () => _f = (table: t, query: _f.query),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      rows.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => EmptyState(
                          icon: CupertinoIcons.exclamationmark_shield,
                          title: 'Could not load the log',
                          message: AppError.from(e).message,
                        ),
                        data: (list) {
                          final q = _f.query.toLowerCase();
                          final shown = [
                            for (final r in list)
                              if (q.isEmpty ||
                                  (people[r['user_id']] ?? '')
                                      .toLowerCase()
                                      .contains(q) ||
                                  describe(r).toLowerCase().contains(q) ||
                                  (r['table_name'] as String).contains(q))
                                r,
                          ];
                          if (shown.isEmpty) {
                            return const EmptyState(
                              icon: CupertinoIcons.clock,
                              title: 'Nothing logged',
                              message: 'Changes show here as people work.',
                            );
                          }
                          return SurfaceCard(
                            padding: const EdgeInsets.symmetric(
                              vertical: Space.xs,
                            ),
                            child: Column(
                              children: [
                                for (final r in shown)
                                  Builder(
                                    builder: (context) {
                                      final t = _tables[r['table_name']];
                                      final route = t?.$3;
                                      final at = DateTime.parse(
                                        r['at'] as String,
                                      ).toLocal();
                                      return ListTile(
                                        dense: true,
                                        leading: Icon(
                                          t?.$2 ?? CupertinoIcons.circle,
                                          size: 20,
                                        ),
                                        title: Text(
                                          '${people[r['user_id']] ?? (r['user_id'] == null ? 'System' : 'Someone')} '
                                          '${describe(r)}',
                                        ),
                                        subtitle: Text(
                                          '${t?.$1 ?? r['table_name']} · ${relativeTime(at)}',
                                          style: theme.textTheme.labelSmall,
                                        ),
                                        trailing: route == null
                                            ? null
                                            : const Icon(
                                                CupertinoIcons.chevron_right,
                                                size: 16,
                                              ),
                                        onTap: route == null
                                            ? null
                                            : () => context.push(
                                                '$route${r['record_id']}',
                                              ),
                                      );
                                    },
                                  ),
                              ],
                            ),
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
      ),
    );
  }
}
