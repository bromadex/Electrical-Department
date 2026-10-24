import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/format.dart';
import 'models.dart';

class RequestStatusPill extends StatelessWidget {
  const RequestStatusPill(this.status, {super.key});

  final RequestStatus status;

  @override
  Widget build(BuildContext context) => Pill(
    label: status.label,
    icon: status.icon,
    color: status.color,
    dense: true,
  );
}

class RequestTile extends StatelessWidget {
  const RequestTile({
    super.key,
    required this.request,
    this.onTap,
    this.actions = const [],
  });

  final ServiceRequest request;
  final VoidCallback? onTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = request;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: r.urgent ? AppColors.critical : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          padding: const EdgeInsets.all(Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  RecordCode(r.requestNo),
                  RequestStatusPill(r.status),
                  if (r.impact != null)
                    Pill(
                      label: r.impact!.label,
                      color: r.impact!.color,
                      icon: r.urgent ? Icons.report_rounded : null,
                      solid: r.urgent,
                      dense: true,
                    ),
                  if (r.jobNumber != null)
                    Pill(
                      label: r.jobNumber!,
                      icon: Icons.assignment_outlined,
                      color: AppColors.navy600,
                      dense: true,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(r.title, style: theme.textTheme.titleSmall),
              Text(
                [
                  r.equipment,
                  r.place,
                  r.departmentName,
                ].whereType<String>().join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'From ${r.requesterName ?? r.reporterName} · ${fmtRelative(r.submittedAt)} (${fmtDateTime(r.submittedAt)})',
                style: theme.textTheme.labelSmall,
              ),
              if (r.statusReason != null && r.status != RequestStatus.submitted)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '“${r.statusReason}”',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: Space.xs),
                Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xs,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
