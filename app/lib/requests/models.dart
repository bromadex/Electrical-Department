import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../ui/format.dart';
import '../ui/status.dart';

enum RequestStatus {
  submitted(
    'submitted',
    'Waiting for review',
    Icons.schedule_rounded,
    AppColors.info,
  ),
  returned(
    'returned',
    'More information needed',
    Icons.reply_rounded,
    AppColors.warning,
  ),
  registered(
    'registered',
    'Registered as a job card',
    Icons.assignment_turned_in_outlined,
    AppColors.success,
  ),
  rejected('rejected', 'Not accepted', Icons.block_rounded, AppColors.neutral),
  withdrawn('withdrawn', 'Withdrawn', Icons.undo_rounded, AppColors.neutral);

  const RequestStatus(this.db, this.label, this.icon, this.color);

  final String db;
  final String label;
  final IconData icon;
  final Color color;

  static RequestStatus fromDb(String? s) =>
      values.firstWhere((v) => v.db == s, orElse: () => submitted);
}

class ServiceRequest {
  ServiceRequest(this.r)
    : id = r['id'] as String,
      requestNo = r['request_no'] as String,
      siteId = r['site_id'] as String,
      title = r['title'] as String,
      description = r['description'] as String,
      reporterName = r['reporter_name'] as String,
      status = RequestStatus.fromDb(r['status'] as String?),
      impact = Impact.fromDb(r['operational_impact'] as String?),
      submittedAt = parseTime(r['submitted_at'])!;

  final Map<String, dynamic> r;
  final String id;
  final String requestNo;
  final String siteId;
  final String title;
  final String description;
  final String reporterName;
  final RequestStatus status;
  final Impact? impact;
  final DateTime submittedAt;

  String? s(String key) {
    final v = r[key];
    return v is String && v.trim().isNotEmpty ? v : null;
  }

  String? get areaId => s('area_id');
  String? get location => s('location');
  String? get departmentId => s('department_id');
  String? get assetId => s('asset_id');
  String? get equipmentText => s('equipment_text');
  String? get contact => s('contact');
  String? get statusReason => s('status_reason');
  String? get clarificationNote => s('clarification_note');
  String? get jobCardId => s('job_card_id');
  String? get requestedBy => s('requested_by');
  DateTime? get reviewedAt => parseTime(r['reviewed_at']);

  String? get siteName => (r['site'] as Map?)?['name'] as String?;
  String? get areaName => (r['area'] as Map?)?['name'] as String?;
  String? get departmentName => (r['department'] as Map?)?['name'] as String?;
  String? get assetLabel {
    final a = r['asset'] as Map?;
    return a == null ? null : '${a['asset_no']} · ${a['name']}';
  }

  String? get requesterName =>
      (r['requester'] as Map?)?['full_name'] as String?;
  String? get jobNumber => (r['job'] as Map?)?['number'] as String?;
  String get place => areaName ?? location ?? '—';
  String? get equipment => assetLabel ?? equipmentText;
  bool get urgent =>
      impact == Impact.productionStopped || impact == Impact.safetyHazard;
}

/// What fn_request_tracking returns: the request, its job card's public
/// state and the updates the department chose to share.
class RequestTracking {
  RequestTracking(Map<String, dynamic> j)
    : request = ServiceRequest({
        ...Map<String, dynamic>.from(j['request'] as Map),
        'site': {'name': j['site_name']},
        'area': j['area_name'] == null ? null : {'name': j['area_name']},
        'department': j['department_name'] == null
            ? null
            : {'name': j['department_name']},
      }),
      job = j['job'] == null
          ? null
          : Map<String, dynamic>.from(j['job'] as Map),
      updates = [
        for (final u in j['updates'] as List)
          Map<String, dynamic>.from(u as Map),
      ],
      attachments = [
        for (final a in j['attachments'] as List)
          Map<String, dynamic>.from(a as Map),
      ];

  final ServiceRequest request;
  final Map<String, dynamic>? job;
  final List<Map<String, dynamic>> updates;
  final List<Map<String, dynamic>> attachments;

  JobStatus? get jobStatus =>
      job == null ? null : JobStatus.fromDb(job!['status'] as String?);
}
