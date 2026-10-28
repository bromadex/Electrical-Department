import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../services/core_providers.dart';
import '../services/session_controller.dart';

/// A personal reminder (API.md section 8b): at [remindAt] the person gets a
/// notification with [note] that opens [link] (`jobcard:<id>`, `tool:<id>`…).
class Reminder {
  const Reminder({
    required this.id,
    required this.remindAt,
    required this.note,
    this.link,
    this.notifiedAt,
    this.pending = false,
  });

  Reminder.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      remindAt = DateTime.parse(j['remind_at'] as String).toLocal(),
      note = j['note'] as String,
      link = j['link'] as String?,
      notifiedAt = j['notified_at'] == null
          ? null
          : DateTime.parse(j['notified_at'] as String).toLocal(),
      pending = false;

  final String id;
  final DateTime remindAt;
  final String note;
  final String? link;
  final DateTime? notifiedAt;

  /// Set on this phone, not on the server yet (no signal).
  final bool pending;

  bool get done => notifiedAt != null;
}

/// Reminders set on this phone that have not reached the server yet.
final _pendingRemindersProvider =
    NotifierProvider<_PendingReminders, List<Reminder>>(_PendingReminders.new);

class _PendingReminders extends Notifier<List<Reminder>> {
  @override
  List<Reminder> build() => const [];

  void add(Reminder r) => state = [...state, r];
  void remove(String id) => state = [
    for (final r in state)
      if (r.id != id) r,
  ];
}

/// Your reminders: upcoming first (soonest first), then recent ones that
/// went off. Online, plus any still waiting to be sent from this phone.
final myRemindersProvider = FutureProvider.autoDispose<List<Reminder>>((
  ref,
) async {
  final me = ref.watch(authUserIdProvider);
  final pending = ref.watch(_pendingRemindersProvider);
  if (me == null) return const [];
  final rows = await ref
      .watch(supabaseProvider)
      .from('reminders')
      .select()
      .eq('user_id', me)
      .eq('is_archived', false)
      .order('remind_at', ascending: false)
      .limit(100);
  final server = [for (final r in rows) Reminder.fromJson(r)];
  final known = {for (final r in server) r.id};
  final all = [
    ...server,
    for (final p in pending)
      if (!known.contains(p.id)) p,
  ];
  final upcoming = all.where((r) => !r.done).toList()
    ..sort((a, b) => a.remindAt.compareTo(b.remindAt));
  final past = all.where((r) => r.done).toList()
    ..sort((a, b) => b.remindAt.compareTo(a.remindAt));
  return [...upcoming, ...past];
});

final reminderActionsProvider = Provider((ref) => ReminderActions(ref));

/// Setting and cancelling reminders; both wait in the outbox offline.
class ReminderActions {
  ReminderActions(this._ref);

  final Ref _ref;

  Future<void> create({
    required DateTime at,
    required String note,
    String? link,
  }) async {
    final id = const Uuid().v4();
    _ref
        .read(_pendingRemindersProvider.notifier)
        .add(
          Reminder(
            id: id,
            remindAt: at,
            note: note.trim(),
            link: link,
            pending: true,
          ),
        );
    await _ref.read(outboxProvider).enqueue('fn_create_reminder', {
      'p_client_ref': id,
      'p_remind_at': at.toUtc().toIso8601String(),
      'p_note': note.trim(),
      'p_link': link,
      'p_site': _ref.read(currentSiteProvider)?.id,
    }, clientRef: id);
    await _settle();
  }

  Future<void> cancel(Reminder r) async {
    _ref.read(_pendingRemindersProvider.notifier).remove(r.id);
    await _ref.read(outboxProvider).enqueue('fn_cancel_reminder', {
      'p_reminder': r.id,
    });
    await _settle();
  }

  /// Sends what is queued (when there is signal), then reloads the list.
  Future<void> _settle() async {
    _ref.invalidate(myRemindersProvider);
    try {
      await _ref.read(outboxProvider).flush();
    } catch (_) {
      // Offline: the reminder waits in the outbox and shows as pending.
    }
    _ref.invalidate(myRemindersProvider);
  }
}
