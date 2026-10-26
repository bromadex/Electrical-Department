import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_error.dart';
import '../jobs/job_rules.dart';
import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';

final _targetsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) async {
    final rows = await ref
        .watch(supabaseProvider)
        .from('priority_targets')
        .select();
    const order = ['urgent', 'normal', 'low'];
    return [for (final r in rows) Map<String, dynamic>.from(r)]..sort(
      (a, b) =>
          order.indexOf(a['priority']).compareTo(order.indexOf(b['priority'])),
    );
  },
);

/// How fast each priority should be picked up and finished. New jobs
/// without a due time are due by the finish target.
class TargetsScreen extends ConsumerWidget {
  const TargetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(_targetsProvider);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Response times'),
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
                constraints: const BoxConstraints(maxWidth: 720),
                child: rows.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text(AppError.from(e).message),
                  data: (list) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Jobs posted without a due time are due by the finish '
                        'target. Urgent jobs nobody takes within the response '
                        'time alert supervisors.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: Space.md),
                      for (final r in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: _TargetCard(row: r),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetCard extends ConsumerStatefulWidget {
  const _TargetCard({required this.row});

  final Map<String, dynamic> row;

  @override
  ConsumerState<_TargetCard> createState() => _TargetCardState();
}

class _TargetCardState extends ConsumerState<_TargetCard> {
  late final _respond = TextEditingController(
    text: '${widget.row['respond_minutes']}',
  );
  late final _close = TextEditingController(
    text: '${widget.row['close_hours']}',
  );
  String? _msg;

  @override
  void dispose() {
    _respond.dispose();
    _close.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await ref
          .read(supabaseProvider)
          .rpc(
            'fn_set_priority_target',
            params: {
              'p_priority': widget.row['priority'],
              'p_respond_minutes': int.tryParse(_respond.text.trim()),
              'p_close_hours': int.tryParse(_close.text.trim()),
            },
          );
      HapticFeedback.mediumImpact();
      setState(() => _msg = 'Saved');
    } catch (e) {
      setState(() => _msg = AppError.from(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JobPriority.parse(widget.row['priority'] as String);
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.flag_fill, color: p.color),
              const SizedBox(width: Space.xs),
              Text(p.label, style: theme.textTheme.titleMedium),
              const Spacer(),
              if (_msg != null) Text(_msg!, style: theme.textTheme.labelMedium),
            ],
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _respond,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Respond within (minutes)',
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: TextField(
                  controller: _close,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Finish within (hours)',
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}
