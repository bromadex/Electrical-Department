import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/core_providers.dart';
import '../ui/format.dart';

class Department {
  const Department(
    this.id,
    this.code,
    this.name,
    this.isElectrical,
    this.isArchived,
  );

  factory Department.fromRow(Map<String, dynamic> r) => Department(
    r['id'] as String,
    r['code'] as String,
    r['name'] as String,
    r['is_electrical'] as bool? ?? false,
    r['is_archived'] as bool? ?? false,
  );

  final String id;
  final String code;
  final String name;
  final bool isElectrical;
  final bool isArchived;
}

/// A job or asset category (both tables have the same shape).
class Category {
  const Category(
    this.id,
    this.name,
    this.sortOrder,
    this.isArchived, {
    this.description,
  });

  factory Category.fromRow(Map<String, dynamic> r) => Category(
    r['id'] as String,
    r['name'] as String,
    (r['sort_order'] as num?)?.toInt() ?? 100,
    r['is_archived'] as bool? ?? false,
    description: r['description'] as String?,
  );

  final String id;
  final String name;
  final int sortOrder;
  final bool isArchived;
  final String? description;
}

class PriorityLevel {
  const PriorityLevel({
    required this.code,
    required this.name,
    required this.description,
    required this.responseMinutes,
    required this.completionMinutes,
    required this.targetsConfirmed,
  });

  factory PriorityLevel.fromRow(Map<String, dynamic> r) => PriorityLevel(
    code: r['code'] as String,
    name: r['name'] as String,
    description: r['description'] as String?,
    responseMinutes: (r['response_minutes'] as num).toInt(),
    completionMinutes: (r['completion_minutes'] as num).toInt(),
    targetsConfirmed: r['targets_confirmed'] as bool? ?? false,
  );

  final String code;
  final String name;
  final String? description;
  final int responseMinutes;
  final int completionMinutes;

  /// False until an administrator saves the targets (seeded defaults).
  final bool targetsConfirmed;
}

class SystemSettings {
  const SystemSettings({
    this.timezone = 'Africa/Harare',
    this.jobcardPrefix = 'EL-JC',
    this.requestPrefix = 'EL-SR',
    this.numberDigits = 4,
    this.numberResetYearly = true,
    this.responseEndsAt = 'acknowledged',
    this.atRiskPercent = 25,
    this.holdAlertHours = 48,
    this.handoverNoteRequired = true,
    this.companyName = 'Bravura',
    this.departmentName = 'Electrical Department',
    this.logoPath,
  });

  factory SystemSettings.fromRow(Map<String, dynamic>? r) => r == null
      ? const SystemSettings()
      : SystemSettings(
          timezone: r['timezone'] as String,
          jobcardPrefix: r['jobcard_prefix'] as String,
          requestPrefix: r['request_prefix'] as String,
          numberDigits: (r['number_digits'] as num).toInt(),
          numberResetYearly: r['number_reset_yearly'] as bool,
          responseEndsAt: r['response_ends_at'] as String,
          atRiskPercent: (r['at_risk_percent'] as num).toInt(),
          holdAlertHours: (r['hold_alert_hours'] as num).toInt(),
          handoverNoteRequired: r['handover_note_required'] as bool,
          companyName: r['company_name'] as String,
          departmentName: r['department_name'] as String,
          logoPath: r['logo_path'] as String?,
        );

  final String timezone;
  final String jobcardPrefix;
  final String requestPrefix;
  final int numberDigits;
  final bool numberResetYearly;
  final String responseEndsAt;
  final int atRiskPercent;
  final int holdAlertHours;
  final bool handoverNoteRequired;
  final String companyName;
  final String departmentName;
  final String? logoPath;
}

/// Lists and settings every screen needs, loaded once after sign-in.
class ReferenceData {
  const ReferenceData({
    required this.departments,
    required this.jobCategories,
    required this.assetCategories,
    required this.priorities,
    required this.settings,
    required this.transitions,
  });

  final List<Department> departments;
  final List<Category> jobCategories;
  final List<Category> assetCategories;
  final List<PriorityLevel> priorities;
  final SystemSettings settings;

  /// Allowed status changes: from → {to}.
  final Map<String, Set<String>> transitions;

  List<Department> get activeDepartments => [
    for (final d in departments)
      if (!d.isArchived) d,
  ];
  List<Category> get activeJobCategories => [
    for (final c in jobCategories)
      if (!c.isArchived) c,
  ];
  List<Category> get activeAssetCategories => [
    for (final c in assetCategories)
      if (!c.isArchived) c,
  ];

  bool canMove(String from, String to) =>
      transitions[from]?.contains(to) ?? false;

  PriorityLevel? priority(String code) {
    for (final p in priorities) {
      if (p.code == code) return p;
    }
    return null;
  }

  String? departmentName(String? id) {
    for (final d in departments) {
      if (d.id == id) return d.name;
    }
    return null;
  }
}

final referenceDataProvider = FutureProvider<ReferenceData>((ref) async {
  ref.watch(authUserIdProvider);
  final client = ref.watch(supabaseProvider);
  final results = await Future.wait<dynamic>([
    client.from('departments').select().order('name'),
    client.from('job_categories').select().order('sort_order').order('name'),
    client.from('asset_categories').select().order('sort_order').order('name'),
    client.from('priority_levels').select().order('sort_order'),
    client.from('system_settings').select().limit(1).maybeSingle(),
    client.from('job_status_transitions').select(),
  ]);
  final transitions = <String, Set<String>>{};
  for (final r in results[5] as List) {
    transitions
        .putIfAbsent(r['from_status'] as String, () => {})
        .add(r['to_status'] as String);
  }
  final data = ReferenceData(
    departments: [for (final r in results[0] as List) Department.fromRow(r)],
    jobCategories: [for (final r in results[1] as List) Category.fromRow(r)],
    assetCategories: [for (final r in results[2] as List) Category.fromRow(r)],
    priorities: [for (final r in results[3] as List) PriorityLevel.fromRow(r)],
    settings: SystemSettings.fromRow(results[4] as Map<String, dynamic>?),
    transitions: transitions,
  );
  SiteTime.configure(data.settings.timezone);
  return data;
});
