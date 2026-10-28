import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.dart';
import '../ui/form_sheet.dart';
import 'reminders_repository.dart';

/// "Remind me": quick times or a date and time of your own, with a note.
/// [link] makes the reminder open that record (`jobcard:<id>`, `tool:<id>`…).
Future<void> showRemindMe(
  BuildContext context, {
  String note = '',
  String? link,
}) async {
  final set = await showFormSheet<DateTime>(
    context,
    RemindMeSheet(note: note, link: link),
  );
  if (set == null || !context.mounted) return;
  final l = MaterialLocalizations.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Reminder set for ${l.formatMediumDate(set)}, '
        '${l.formatTimeOfDay(TimeOfDay.fromDateTime(set))}',
      ),
    ),
  );
}

class RemindMeSheet extends ConsumerStatefulWidget {
  const RemindMeSheet({super.key, this.note = '', this.link});

  final String note;
  final String? link;

  @override
  ConsumerState<RemindMeSheet> createState() => _RemindMeSheetState();
}

class _RemindMeSheetState extends ConsumerState<RemindMeSheet> {
  late final _note = TextEditingController(text: widget.note);
  DateTime? _at;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// In an hour, this afternoon, tomorrow morning, next Monday morning.
  List<(String, DateTime)> _quick() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow8 = today.add(const Duration(days: 1, hours: 8));
    final monday = today.add(
      Duration(
        days: (DateTime.monday - now.weekday + 7) % 7 == 0
            ? 7
            : (DateTime.monday - now.weekday + 7) % 7,
      ),
    );
    return [
      ('In 1 hour', now.add(const Duration(hours: 1))),
      ('In 3 hours', now.add(const Duration(hours: 3))),
      if (now.hour < 14) ('Today 14:00', today.add(const Duration(hours: 14))),
      ('Tomorrow 08:00', tomorrow8),
      ('Monday 08:00', monday.add(const Duration(hours: 8))),
    ];
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _at ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 364)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _at ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (time == null) return;
    setState(() {
      _at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      _error = null;
    });
  }

  Future<void> _save() async {
    final at = _at;
    if (at == null) {
      setState(() => _error = 'Pick when');
      return;
    }
    if (!at.isAfter(DateTime.now())) {
      setState(() => _error = 'That time has passed');
      return;
    }
    if (_note.text.trim().isEmpty) {
      setState(() => _error = 'Say what to remind you about');
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    await ref
        .read(reminderActionsProvider)
        .create(at: at, note: _note.text, link: widget.link);
    if (mounted) Navigator.pop(context, at);
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
          Text('Remind me', style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.md),
          TextField(
            controller: _note,
            maxLength: 300,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'About'),
          ),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final (label, at) in _quick())
                ChoiceChip(
                  label: Text(label),
                  selected: _at == at,
                  onSelected: (_) => setState(() {
                    _at = at;
                    _error = null;
                  }),
                ),
              ActionChip(
                avatar: const Icon(CupertinoIcons.calendar, size: 16),
                label: const Text('Pick a time'),
                onPressed: _pick,
              ),
            ],
          ),
          if (_at != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                '${l.formatFullDate(_at!)} at '
                '${l.formatTimeOfDay(TimeOfDay.fromDateTime(_at!))}',
                style: theme.textTheme.titleSmall,
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
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(CupertinoIcons.alarm),
            label: const Text('Set reminder'),
          ),
        ],
      ),
    );
  }
}
