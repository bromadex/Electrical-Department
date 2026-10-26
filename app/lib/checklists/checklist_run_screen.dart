import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../ui/media.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import 'checklists_repository.dart';
import '../widgets/app_back_button.dart';

/// Doing a round on the phone: one card per item, then submit. Works
/// offline; failed items raise jobs once it reaches the server.
class ChecklistRunScreen extends ConsumerStatefulWidget {
  const ChecklistRunScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<ChecklistRunScreen> createState() => _ChecklistRunScreenState();
}

class _ChecklistRunScreenState extends ConsumerState<ChecklistRunScreen> {
  final _answers = <String, Answer>{};
  final _notes = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Answer _a(ChecklistItem i) => _answers.putIfAbsent(i.id!, Answer.new);

  bool _failed(ChecklistItem i) {
    final a = _a(i);
    if (i.kind == 'check') return a.ok == false;
    if (i.kind == 'number') {
      final v = double.tryParse(a.value.trim().replaceAll(',', '.'));
      if (v == null) return false;
      return (i.min != null && v < i.min!) || (i.max != null && v > i.max!);
    }
    return false;
  }

  String? _missing(ChecklistTemplate t) {
    for (final (n, i) in t.items.indexed) {
      final a = _a(i);
      final label = '${n + 1}. ${i.label}';
      if (i.kind == 'check' && a.ok == null) return 'Mark $label';
      if (i.kind == 'number' &&
          double.tryParse(a.value.trim().replaceAll(',', '.')) == null) {
        return 'Enter the reading for $label';
      }
      if (i.kind == 'text' && a.text.trim().isEmpty) return 'Fill in $label';
      if (i.photoRequired && a.photo == null) return 'Take a photo for $label';
    }
    return null;
  }

  Future<void> _submit(ChecklistTemplate t) async {
    final missing = _missing(t);
    if (missing != null) {
      setState(() => _error = missing);
      return;
    }
    final failed = t.items.where(_failed).length;
    if (failed > 0) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(failed == 1 ? '1 item failed' : '$failed items failed'),
          content: const Text(
            'A job will be raised for each failed item so it gets fixed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Check again'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() => _busy = true);
    HapticFeedback.heavyImpact();
    await ref
        .read(checklistActionsProvider)
        .submit(t, _answers, notes: _notes.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? '${t.name} done'
              : '${t.name} done · $failed jobs raised',
        ),
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(checklistTemplateProvider(widget.id));
    final loading = ref.watch(checklistTemplatesProvider).isLoading;
    final status = ref.watch(checklistStatusProvider).value?[widget.id];
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    ref.watch(sessionProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(t?.name ?? 'Checklist'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: t == null
            ? Center(
                child: loading
                    ? const CircularProgressIndicator()
                    : const EmptyState(
                        icon: CupertinoIcons.list_bullet,
                        title: 'Checklist not found',
                        message: 'It may have been stopped.',
                      ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  Space.md,
                  top + Space.md,
                  Space.md,
                  Space.xl + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (status?.done ?? false)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.sm),
                              child: SurfaceCard(
                                color: BrandColors.success.withValues(
                                  alpha: 0.12,
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      CupertinoIcons.checkmark_seal_fill,
                                      color: BrandColors.success,
                                    ),
                                    SizedBox(width: Space.sm),
                                    Expanded(
                                      child: Text(
                                        'Already done for this period. '
                                        'You can submit another round.',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (t.description != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.sm),
                              child: Text(
                                t.description!,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          for (final (n, item) in t.items.indexed)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.sm),
                              child: _ItemCard(
                                number: n + 1,
                                item: item,
                                answer: _a(item),
                                failed: _failed(item),
                                onChanged: () => setState(() => _error = null),
                              ),
                            ),
                          TextField(
                            controller: _notes,
                            minLines: 2,
                            maxLines: 4,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'Notes for the round (optional)',
                            ),
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: Space.sm),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          const SizedBox(height: Space.md),
                          FilledButton.icon(
                            onPressed: _busy ? null : () => _submit(t),
                            icon: const Icon(CupertinoIcons.checkmark_seal),
                            label: const Text('Submit round'),
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

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.number,
    required this.item,
    required this.answer,
    required this.failed,
    required this.onChanged,
  });

  final int number;
  final ChecklistItem item;
  final Answer answer;
  final bool failed;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      color: failed ? Colors.red.withValues(alpha: 0.08) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('$number.', style: theme.textTheme.titleSmall),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(item.label, style: theme.textTheme.titleSmall),
              ),
              if (item.limits != null) Pill(label: item.limits!, dense: true),
            ],
          ),
          const SizedBox(height: Space.sm),
          switch (item.kind) {
            'number' => TextFormField(
              initialValue: answer.value,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                hintText: 'Reading',
                suffixText: item.unit,
              ),
              onChanged: (v) {
                answer.value = v;
                onChanged();
              },
            ),
            'text' => TextFormField(
              initialValue: answer.text,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Write it here'),
              onChanged: (v) {
                answer.text = v;
                onChanged();
              },
            ),
            _ => Row(
              children: [
                Expanded(
                  child: _Choice(
                    label: 'OK',
                    icon: CupertinoIcons.checkmark_alt,
                    color: BrandColors.success,
                    selected: answer.ok == true,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      answer.ok = true;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: _Choice(
                    label: 'Not OK',
                    icon: CupertinoIcons.xmark,
                    color: Colors.red,
                    selected: answer.ok == false,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      answer.ok = false;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
          },
          if (failed) ...[
            const SizedBox(height: Space.sm),
            TextFormField(
              initialValue: answer.comment,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What is wrong? (goes on the job)',
              ),
              onChanged: (v) => answer.comment = v,
            ),
          ],
          if (item.photoRequired || failed) ...[
            const SizedBox(height: Space.sm),
            PhotoStrip(
              photos: [?answer.photo],
              label: item.photoRequired ? 'Photo (required)' : 'Add photo',
              onChanged: (p) {
                answer.photo = p.isEmpty ? null : p.last;
                onChanged();
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
        border: Border.all(
          color: selected
              ? color
              : Theme.of(context).colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: selected ? color : null, size: 20),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? color : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
