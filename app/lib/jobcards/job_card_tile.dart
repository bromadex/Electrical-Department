import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/format.dart';
import '../ui/status.dart';
import 'models.dart';

/// A job card as a compact card: phone lists, My Jobs and alerts.
class JobCardTile extends StatelessWidget {
  const JobCardTile({super.key, required this.job, this.onTap, this.trailing});

  final JobCard job;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final edge = job.isOverdue || job.isCriticalOpen
        ? AppColors.critical
        : job.sla == SlaState.atRisk
        ? AppColors.warning
        : Colors.transparent;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: edge, width: 4)),
          ),
          padding: const EdgeInsets.all(Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  RecordCode(job.number),
                  const SizedBox(width: Space.xs),
                  PriorityBadge(job.priority),
                  if (job.isCriticalOpen) ...[
                    const SizedBox(width: 4),
                    const CriticalFlag(),
                  ],
                  const Spacer(),
                  Text(
                    fmtRelative(job.receivedAt),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                job.title,
                style: theme.textTheme.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                [job.equipment, job.place].whereType<String>().join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Space.xs),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusPill(job.status, dense: true),
                  if (job.status.isOpen && job.targetCompletionAt != null)
                    SlaChip(job.sla),
                  if (job.responsibleName != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          job.responsibleName!,
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  if (job.status.isOpen && job.targetCompletionAt != null)
                    Text(
                      job.isOverdue
                          ? 'Overdue by ${fmtMinutes(job.overdueMinutes)}'
                          : 'Due ${fmtDateTime(job.targetCompletionAt)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: job.isOverdue
                            ? AppColors.critical
                            : scheme.onSurfaceVariant,
                        fontWeight: job.isOverdue ? FontWeight.w700 : null,
                      ),
                    ),
                ],
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
