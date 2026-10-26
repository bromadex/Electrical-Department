import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'bits.dart';

/// Job card statuses, exactly as stored (job_cards.status).
enum JobStatus {
  registered('registered', 'New', Icons.fiber_new_outlined, AppColors.info),
  awaitingClarification(
    'awaiting_clarification',
    'Needs clarification',
    Icons.help_outline_rounded,
    AppColors.warning,
  ),
  awaitingAssignment(
    'awaiting_assignment',
    'Awaiting assignment',
    Icons.person_search_outlined,
    AppColors.warning,
  ),
  assigned(
    'assigned',
    'Assigned',
    Icons.assignment_ind_outlined,
    AppColors.info,
  ),
  accepted('accepted', 'Accepted', Icons.task_alt_rounded, AppColors.info),
  inProgress(
    'in_progress',
    'In progress',
    Icons.construction_rounded,
    AppColors.info,
  ),
  onHold(
    'on_hold',
    'On hold',
    Icons.pause_circle_outline_rounded,
    AppColors.warning,
  ),
  awaitingMaterials(
    'awaiting_materials',
    'Awaiting materials',
    Icons.inventory_2_outlined,
    AppColors.warning,
  ),
  awaitingIsolation(
    'awaiting_isolation',
    'Awaiting isolation',
    Icons.power_off_outlined,
    AppColors.warning,
  ),
  awaitingSpecialist(
    'awaiting_specialist',
    'Awaiting specialist',
    Icons.engineering_outlined,
    AppColors.warning,
  ),
  awaitingProductionClearance(
    'awaiting_production_clearance',
    'Awaiting production clearance',
    Icons.factory_outlined,
    AppColors.warning,
  ),
  awaitingReview(
    'awaiting_review',
    'Awaiting engineering review',
    Icons.fact_check_outlined,
    AppColors.review,
  ),
  reopened('reopened', 'Reopened', Icons.replay_rounded, AppColors.warning),
  closed(
    'closed',
    'Closed',
    Icons.check_circle_outline_rounded,
    AppColors.success,
  ),
  cancelled('cancelled', 'Cancelled', Icons.cancel_outlined, AppColors.neutral);

  const JobStatus(this.db, this.label, this.icon, this.color);

  final String db;
  final String label;
  final IconData icon;
  final Color color;

  static JobStatus fromDb(String? s) =>
      values.firstWhere((v) => v.db == s, orElse: () => registered);

  /// Work stopped for a recorded reason.
  static const holds = {
    onHold,
    awaitingMaterials,
    awaitingIsolation,
    awaitingSpecialist,
    awaitingProductionClearance,
  };

  bool get isHold => holds.contains(this);
  bool get isOpen => this != closed && this != cancelled;
  bool get isActive =>
      this == assigned ||
      this == accepted ||
      this == inProgress ||
      this == reopened ||
      isHold;
}

/// P1–P4 (priority_levels.code).
enum Priority {
  p1('P1', 'Emergency', Icons.bolt_rounded, AppColors.critical),
  p2('P2', 'High', Icons.keyboard_double_arrow_up_rounded, AppColors.warning),
  p3('P3', 'Medium', Icons.drag_handle_rounded, AppColors.info),
  p4('P4', 'Low', Icons.keyboard_arrow_down_rounded, AppColors.neutral);

  const Priority(this.code, this.name, this.icon, this.color);

  final String code;
  final String name;
  final IconData icon;
  final Color color;

  static Priority fromCode(String? c) =>
      values.firstWhere((v) => v.code == c, orElse: () => p3);
}

/// Deadline performance (v_job_cards.sla_state).
enum SlaState {
  onTime('on_time', 'On time', Icons.schedule_rounded, AppColors.success),
  atRisk('at_risk', 'At risk', Icons.warning_amber_rounded, AppColors.warning),
  overdue('overdue', 'Overdue', Icons.alarm_rounded, AppColors.critical),
  completedOnTime(
    'completed_on_time',
    'Completed on time',
    Icons.verified_outlined,
    AppColors.success,
  ),
  completedLate(
    'completed_late',
    'Completed late',
    Icons.history_toggle_off_rounded,
    AppColors.warning,
  ),
  noTarget('no_target', 'No target', Icons.remove_rounded, AppColors.neutral),
  cancelled('cancelled', 'Cancelled', Icons.cancel_outlined, AppColors.neutral);

  const SlaState(this.db, this.label, this.icon, this.color);

  final String db;
  final String label;
  final IconData icon;
  final Color color;

  static SlaState fromDb(String? s) =>
      values.firstWhere((v) => v.db == s, orElse: () => noTarget);
}

/// How the fault affects operations.
enum Impact {
  none('none', 'No impact', AppColors.neutral),
  minor('minor', 'Minor', AppColors.info),
  reducedOutput('reduced_output', 'Reduced output', AppColors.warning),
  productionStopped(
    'production_stopped',
    'Production stopped',
    AppColors.critical,
  ),
  safetyHazard('safety_hazard', 'Safety hazard', AppColors.critical);

  const Impact(this.db, this.label, this.color);

  final String db;
  final String label;
  final Color color;

  static Impact? fromDb(String? s) {
    for (final v in values) {
      if (v.db == s) return v;
    }
    return null;
  }
}

/// Readable label for a snake_case value from the database.
String humanize(String? s) {
  if (s == null || s.isEmpty) return '—';
  final t = s.replaceAll('_', ' ');
  return t[0].toUpperCase() + t.substring(1);
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.dense = false});

  final JobStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) => Pill(
    label: status.label,
    icon: status.icon,
    color: status.color,
    dense: dense,
  );
}

class PriorityBadge extends StatelessWidget {
  const PriorityBadge(this.priority, {super.key, this.showName = false});

  final Priority priority;
  final bool showName;

  @override
  Widget build(BuildContext context) => Pill(
    label: showName ? '${priority.code} · ${priority.name}' : priority.code,
    icon: priority.icon,
    color: priority.color,
    solid: priority == Priority.p1,
    dense: true,
  );
}

class SlaChip extends StatelessWidget {
  const SlaChip(this.state, {super.key});

  final SlaState state;

  @override
  Widget build(BuildContext context) => Pill(
    label: state.label,
    icon: state.icon,
    color: state.color,
    dense: true,
  );
}

/// Red "Critical" marker for P1 and escalated jobs.
class CriticalFlag extends StatelessWidget {
  const CriticalFlag({super.key});

  @override
  Widget build(BuildContext context) => const Pill(
    label: 'Critical',
    icon: Icons.report_rounded,
    color: AppColors.critical,
    solid: true,
    dense: true,
  );
}
