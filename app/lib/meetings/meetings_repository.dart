import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../services/core_providers.dart';

/// One action from the minutes: what, who is responsible, by when, and
/// where it stands (Ongoing, Awaiting drawings, ...).
class MeetingAction {
  const MeetingAction({
    required this.text,
    this.ownerId,
    this.ownerName,
    this.due,
    this.status = '',
  });

  factory MeetingAction.fromJson(Map<String, dynamic> j) => MeetingAction(
    text: j['text'] as String? ?? '',
    ownerId: j['owner_id'] as String?,
    ownerName: j['owner_name'] as String?,
    due: DateTime.tryParse(j['due'] as String? ?? ''),
    status: j['status'] as String? ?? '',
  );

  final String text;
  final String? ownerId;

  /// The responsible person or people as written ("L.K / T.C" is fine).
  final String? ownerName;
  final DateTime? due;
  final String status;

  Map<String, dynamic> toJson() => {
    'text': text,
    'owner_id': ownerId,
    'owner_name': ownerName,
    'due': due == null
        ? null
        : '${due!.year}-${due!.month.toString().padLeft(2, '0')}-${due!.day.toString().padLeft(2, '0')}',
    'status': status,
  };
}

/// Someone at the meeting, as listed under Attendance.
class Attendee {
  const Attendee({
    required this.name,
    this.position = '',
    this.organisation = 'Bravura',
  });

  factory Attendee.fromJson(Map<String, dynamic> j) => Attendee(
    name: j['name'] as String? ?? '',
    position: j['position'] as String? ?? '',
    organisation: j['organisation'] as String? ?? '',
  );

  final String name;
  final String position;
  final String organisation;

  /// "C. Mpala" from "Clement Mpala".
  String get shortName => minutesShortName(name);

  /// "C.M" from "Clement Mpala".
  String get initials => minutesInitials(name);

  Map<String, dynamic> toJson() => {
    'name': name,
    'position': position,
    'organisation': organisation,
  };
}

/// "C.M" from "Clement Mpala" (the department's minutes use initials).
String minutesInitials(String name) {
  final parts = name
      .replaceAll('.', ' ')
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0].toUpperCase()}.${parts.last[0].toUpperCase()}';
}

/// "C. Mpala" from "Clement Mpala".
String minutesShortName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return name.trim();
  return '${parts.first[0].toUpperCase()}. ${parts.sublist(1).join(' ')}';
}

/// One line of the project status table.
typedef StatusLine = ({String area, String status});

/// The minutes, in the department's format (API.md section 16c): details,
/// attendance, updates, executive summary, decisions, the numbered action
/// table, a project status table, the next meeting's agenda and sign-off.
class Minutes {
  const Minutes({
    this.summary = '',
    this.decisions = const [],
    this.actions = const [],
    this.meetingType = '',
    this.venue = '',
    this.minutesBy = '',
    this.attendance = const [],
    this.updates = '',
    this.statusSummary = const [],
    this.nextAgenda = const [],
    this.reviewedBy = '',
    this.approvedBy = '',
  });

  factory Minutes.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const Minutes();
    List<String> strings(String k) => [
      for (final d in (j[k] as List? ?? const [])) '$d',
    ];
    return Minutes(
      summary: j['summary'] as String? ?? '',
      decisions: strings('decisions'),
      actions: [
        for (final a in (j['actions'] as List? ?? const []))
          MeetingAction.fromJson(Map<String, dynamic>.from(a as Map)),
      ],
      meetingType: j['meeting_type'] as String? ?? '',
      venue: j['venue'] as String? ?? '',
      minutesBy: j['minutes_by'] as String? ?? '',
      attendance: [
        for (final a in (j['attendance'] as List? ?? const []))
          Attendee.fromJson(Map<String, dynamic>.from(a as Map)),
      ],
      updates: j['updates'] as String? ?? '',
      statusSummary: [
        for (final s in (j['status_summary'] as List? ?? const []))
          (area: '${(s as Map)['area'] ?? ''}', status: '${s['status'] ?? ''}'),
      ],
      nextAgenda: strings('next_agenda'),
      reviewedBy: j['reviewed_by'] as String? ?? '',
      approvedBy: j['approved_by'] as String? ?? '',
    );
  }

  /// The executive summary and overview.
  final String summary;
  final List<String> decisions;
  final List<MeetingAction> actions;
  final String meetingType;
  final String venue;

  /// Who took (prepared) the minutes.
  final String minutesBy;
  final List<Attendee> attendance;

  /// Site updates reported at the start of the meeting.
  final String updates;
  final List<StatusLine> statusSummary;
  final List<String> nextAgenda;
  final String reviewedBy;
  final String approvedBy;

  bool get isEmpty => summary.trim().isEmpty;

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'decisions': decisions,
    'actions': [for (final a in actions) a.toJson()],
    'meeting_type': meetingType,
    'venue': venue,
    'minutes_by': minutesBy,
    'attendance': [for (final a in attendance) a.toJson()],
    'updates': updates,
    'status_summary': [
      for (final s in statusSummary) {'area': s.area, 'status': s.status},
    ],
    'next_agenda': nextAgenda,
    'reviewed_by': reviewedBy,
    'approved_by': approvedBy,
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

  Meeting._copy(Meeting m, this.minutes)
    : id = m.id,
      siteId = m.siteId,
      conversationId = m.conversationId,
      code = m.code,
      title = m.title,
      agenda = m.agenda,
      startsAt = m.startsAt,
      durationMin = m.durationMin,
      chairId = m.chairId,
      cancelled = m.cancelled,
      recording = m.recording,
      recordingError = m.recordingError,
      audioPath = m.audioPath,
      transcript = m.transcript,
      minutesStatus = m.minutesStatus;

  /// The same meeting with other minutes (to preview a draft as PDF).
  Meeting withMinutes(Minutes minutes) => Meeting._copy(this, minutes);

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

/// A short-lived link to play a meeting's recording.
final meetingAudioUrlProvider = FutureProvider.autoDispose
    .family<String, String>(
      (ref, path) => ref
          .watch(supabaseProvider)
          .storage
          .from('meeting-audio')
          .createSignedUrl(path, 3600),
    );

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

  /// Asks AI to draft the minutes from the live captions or [notes].
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

  /// Starts or stops recording the meeting's audio (meeting-record edge
  /// function; needs the MEETING_S3_* secrets).
  Future<void> record(String id, {required bool start}) => _invoke(
    'meeting-record',
    {'meeting_id': id, 'action': start ? 'start' : 'stop'},
  );

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
