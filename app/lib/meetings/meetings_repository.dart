import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../services/core_providers.dart';

/// One action from the minutes.
class MeetingAction {
  const MeetingAction({
    required this.text,
    this.ownerId,
    this.ownerName,
    this.due,
  });

  factory MeetingAction.fromJson(Map<String, dynamic> j) => MeetingAction(
    text: j['text'] as String? ?? '',
    ownerId: j['owner_id'] as String?,
    ownerName: j['owner_name'] as String?,
    due: DateTime.tryParse(j['due'] as String? ?? ''),
  );

  final String text;
  final String? ownerId;
  final String? ownerName;
  final DateTime? due;

  Map<String, dynamic> toJson() => {
    'text': text,
    'owner_id': ownerId,
    'owner_name': ownerName,
    'due': due == null
        ? null
        : '${due!.year}-${due!.month.toString().padLeft(2, '0')}-${due!.day.toString().padLeft(2, '0')}',
  };
}

/// Summary, decisions and actions (API.md section 16c).
class Minutes {
  const Minutes({
    this.summary = '',
    this.decisions = const [],
    this.actions = const [],
  });

  factory Minutes.fromJson(Map<String, dynamic>? j) => j == null
      ? const Minutes()
      : Minutes(
          summary: j['summary'] as String? ?? '',
          decisions: [
            for (final d in (j['decisions'] as List? ?? const [])) '$d',
          ],
          actions: [
            for (final a in (j['actions'] as List? ?? const []))
              MeetingAction.fromJson(Map<String, dynamic>.from(a as Map)),
          ],
        );

  final String summary;
  final List<String> decisions;
  final List<MeetingAction> actions;

  bool get isEmpty => summary.trim().isEmpty;

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'decisions': decisions,
    'actions': [for (final a in actions) a.toJson()],
  };
}

class Meeting {
  Meeting.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      siteId = j['site_id'] as String,
      conversationId = j['conversation_id'] as String,
      code = j['code'] as String,
      title = j['title'] as String,
      agenda = j['agenda'] as String?,
      startsAt = DateTime.parse(j['starts_at'] as String).toLocal(),
      durationMin = (j['duration_min'] as num).toInt(),
      chairId = j['chair_id'] as String,
      cancelled = j['status'] == 'cancelled',
      recording = j['recording_status'] as String? ?? 'none',
      recordingError = j['recording_error'] as String?,
      audioPath = j['audio_path'] as String?,
      transcript = j['transcript'] as String?,
      minutes = Minutes.fromJson(
        j['minutes'] == null
            ? null
            : Map<String, dynamic>.from(j['minutes'] as Map),
      ),
      minutesStatus = j['minutes_status'] as String? ?? 'none';

  final String id;
  final String siteId;
  final String conversationId;
  final String code;
  final String title;
  final String? agenda;
  final DateTime startsAt;
  final int durationMin;
  final String chairId;
  final bool cancelled;

  /// none | recording | processing | ready | failed
  final String recording;
  final String? recordingError;
  final String? audioPath;
  final String? transcript;
  final Minutes minutes;

  /// none | draft | approved
  final String minutesStatus;

  DateTime get endsAt => startsAt.add(Duration(minutes: durationMin));
  bool get approved => minutesStatus == 'approved';

  /// From 15 minutes before until an hour after the planned end.
  bool get open {
    final now = DateTime.now();
    return !cancelled &&
        now.isAfter(startsAt.subtract(const Duration(minutes: 15))) &&
        now.isBefore(endsAt.add(const Duration(hours: 1)));
  }
}

/// One meeting, kept live over realtime.
final meetingProvider = StreamProvider.autoDispose.family<Meeting?, String>((
  ref,
  id,
) {
  final client = ref.watch(supabaseProvider);
  return client
      .from('meetings')
      .stream(primaryKey: ['id'])
      .eq('id', id)
      .map((rows) => rows.isEmpty ? null : Meeting.fromJson(rows.first));
});

/// A chat's meetings, newest first.
final chatMeetingsProvider = StreamProvider.autoDispose
    .family<List<Meeting>, String>((ref, conversationId) {
      final client = ref.watch(supabaseProvider);
      return client
          .from('meetings')
          .stream(primaryKey: ['id'])
          .eq('conversation_id', conversationId)
          .order('starts_at')
          .map((rows) => [for (final r in rows) Meeting.fromJson(r)]);
    });

/// Who joined the chat's call during the meeting.
final meetingAttendanceProvider = FutureProvider.autoDispose
    .family<List<({String id, String name})>, String>((ref, id) async {
      final rows =
          await ref
                  .watch(supabaseProvider)
                  .rpc('fn_meeting_attendance', params: {'p_meeting': id})
              as List;
      return [
        for (final r in rows)
          (id: r['user_id'] as String, name: r['full_name'] as String),
      ];
    });

/// A short-lived link to play the recording.
final meetingAudioUrlProvider = FutureProvider.autoDispose
    .family<String, String>(
      (ref, path) => ref
          .watch(supabaseProvider)
          .storage
          .from('meeting-audio')
          .createSignedUrl(path, 3600),
    );

final meetingActionsProvider = Provider((ref) => MeetingActions(ref));

/// Meetings are office work: these are online only and throw [Exception]s
/// whose message reads well on screen.
class MeetingActions {
  MeetingActions(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  SupabaseClient get _db => _ref.read(supabaseProvider);

  Future<String> create({
    required String conversationId,
    required String? siteId,
    required String title,
    required String agenda,
    required DateTime startsAt,
    required int durationMin,
  }) async {
    final row = await _db.rpc(
      'fn_create_meeting',
      params: {
        'p_client_ref': _uuid.v4(),
        'p_conversation': conversationId,
        'p_site': siteId,
        'p_title': title,
        'p_agenda': agenda,
        'p_starts_at': startsAt.toUtc().toIso8601String(),
        'p_duration_min': durationMin,
      },
    );
    return (row as Map)['id'] as String;
  }

  Future<void> update(
    String id, {
    String? title,
    String? agenda,
    DateTime? startsAt,
    int? durationMin,
    bool cancel = false,
  }) => _db.rpc(
    'fn_update_meeting',
    params: {
      'p_meeting': id,
      'p_title': title,
      'p_agenda': agenda,
      'p_starts_at': startsAt?.toUtc().toIso8601String(),
      'p_duration_min': durationMin,
      'p_cancel': cancel,
    },
  );

  /// Starts or stops the recording (meeting-record edge function).
  Future<void> record(String id, {required bool start}) => _invoke(
    'meeting-record',
    {'meeting_id': id, 'action': start ? 'start' : 'stop'},
  );

  /// Asks Claude to draft the minutes from the recording or [notes].
  Future<void> draftMinutes(String id, {String? notes}) =>
      _invoke('meeting-minutes', {
        'meeting_id': id,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes,
      });

  Future<void> saveMinutes(String id, Minutes minutes) => _db.rpc(
    'fn_save_minutes',
    params: {
      'p_meeting': id,
      'p_transcript': null,
      'p_minutes': minutes.toJson(),
    },
  );

  Future<void> approve(String id) =>
      _db.rpc('fn_approve_minutes', params: {'p_meeting': id});

  Future<void> _invoke(String fn, Map<String, dynamic> body) async {
    try {
      await _db.functions.invoke(fn, body: body);
    } on FunctionException catch (e) {
      final d = e.details;
      final msg = d is Map ? '${d['error'] ?? ''}' : '$d';
      throw Exception(
        msg.isEmpty
            ? 'Something went wrong (${e.status}).'
            : msg.startsWith('UNAVAILABLE')
            ? '${msg.replaceFirst(RegExp(r'^[A-Z_]+: '), '')}. An admin adds '
                  'the keys in Supabase (API.md 16c).'
            : msg.replaceFirst(RegExp(r'^[A-Z_]+: '), ''),
      );
    }
  }
}
