import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_error.dart';
import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';

/// One kind of error (same fingerprint), across everyone who hit it.
typedef ErrorGroup = ({
  String fingerprint,
  String message,
  String? stack,
  String? route,
  int count,
  int people,
  DateTime lastSeen,
  Set<String> versions,
  Set<String> platforms,
});

final appErrorsProvider = FutureProvider.autoDispose<List<ErrorGroup>>((
  ref,
) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('client_errors')
      .select()
      .eq('is_archived', false)
      .order('last_seen', ascending: false)
      .limit(500);
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    (groups[r['fingerprint'] as String] ??= []).add(r);
  }
  return [
    for (final g in groups.entries)
      (
        fingerprint: g.key,
        message: g.value.first['message'] as String,
        stack: g.value.first['stack'] as String?,
        route: g.value.first['route'] as String?,
        count: g.value.fold(
          0,
          (n, r) => n + ((r['count'] as num?)?.toInt() ?? 1),
        ),
        people: {for (final r in g.value) r['user_id']}.length,
        lastSeen: DateTime.parse(g.value.first['last_seen'] as String)
            .toLocal(),
        versions: {for (final r in g.value) ?r['app_version'] as String?},
        platforms: {for (final r in g.value) ?r['platform'] as String?},
      ),
  ]..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
});

/// Errors from people's phones and browsers, newest first; mark one fixed
/// once a release deals with it (it comes back as new if it happens again).
class AppErrorsScreen extends ConsumerStatefulWidget {
  const AppErrorsScreen({super.key});

  @override
  ConsumerState<AppErrorsScreen> createState() => _AppErrorsScreenState();
}

class _AppErrorsScreenState extends ConsumerState<AppErrorsScreen> {
  final _open = <String>{};

  Future<void> _fixed(String fingerprint) async {
    try {
      await ref
          .read(supabaseProvider)
          .from('client_errors')
          .update({'is_archived': true})
          .eq('fingerprint', fingerprint)
          .eq('is_archived', false);
      ref.invalidate(appErrorsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AppError.from(e).message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errors = ref.watch(appErrorsProvider);
    final dates = MaterialLocalizations.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/settings'),
        title: const Text('App errors'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () async => ref.invalidate(appErrorsProvider),
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
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: errors.when(
                      loading: () => [
                        const Center(child: CircularProgressIndicator()),
                      ],
                      error: (e, _) => [
                        EmptyState(
                          icon: CupertinoIcons.wifi_slash,
                          title: 'Could not load errors',
                          message: AppError.from(e).message,
                        ),
                      ],
                      data: (list) => [
                        if (list.isEmpty)
                          const EmptyState(
                            icon: CupertinoIcons.checkmark_seal,
                            title: 'No errors reported',
                            message:
                                'Crashes and errors in the app show here, '
                                'grouped, with how often and for how many '
                                'people.',
                          ),
                        for (final e in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.sm),
                            child: SurfaceCard(
                              onTap: () => setState(
                                () => _open.contains(e.fingerprint)
                                    ? _open.remove(e.fingerprint)
                                    : _open.add(e.fingerprint),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.message.split('\n').first,
                                    style: theme.textTheme.titleSmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      '${e.count}× for ${e.people} '
                                          '${e.people == 1 ? 'person' : 'people'}',
                                      'last ${dates.formatShortMonthDay(e.lastSeen)} '
                                          '${TimeOfDay.fromDateTime(e.lastSeen).format(context)}',
                                      ...e.platforms,
                                      ...e.versions.map((v) => 'v$v'),
                                      ?e.route,
                                    ].join(' · '),
                                    style: theme.textTheme.labelSmall,
                                  ),
                                  if (_open.contains(e.fingerprint)) ...[
                                    const SizedBox(height: Space.sm),
                                    SelectableText(
                                      [e.message, ?e.stack].join('\n\n'),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(fontFamily: 'monospace'),
                                    ),
                                    const SizedBox(height: Space.sm),
                                    OutlinedButton.icon(
                                      onPressed: () => _fixed(e.fingerprint),
                                      icon: const Icon(
                                        CupertinoIcons.checkmark_alt,
                                      ),
                                      label: const Text('Mark fixed'),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
