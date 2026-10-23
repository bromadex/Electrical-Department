import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/local_db.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import 'job_rules.dart';

/// Compact job card for the board.
class JobCard extends StatelessWidget {
  const JobCard({
    super.key,
    required this.job,
    required this.areaName,
    required this.assigneeName,
    required this.onTap,
    this.showStatus = false,
  });

  final LocalJob job;
  final String? areaName;
  final String? assigneeName;
  final VoidCallback onTap;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = JobStatus.parse(job.status);
    final priority = JobPriority.parse(job.priority);
    final overdue = isOverdue(job);
    final meta = [
      ?areaName,
      if (job.dueAt != null)
        overdue
            ? 'Overdue ${relativeTime(job.dueAt!).replaceFirst(' ago', '')}'
            : 'Due ${relativeTime(job.dueAt!)}',
    ];

    return Hero(
      tag: 'job-${job.id}',
      flightShuttleBuilder: (_, _, _, _, to) => to.widget,
      child: Pressable(
        onTap: onTap,
        child: SurfaceCard(
          radius: Radii.lg,
          padding: const EdgeInsets.all(Space.sm + 2),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (job.code != null)
                    RecordCode(job.code!)
                  else
                    const Pill(label: 'New', dense: true),
                  const SizedBox(width: Space.xs),
                  if (priority != JobPriority.normal)
                    Pill(
                      label: priority.label,
                      color: priority.color,
                      dense: true,
                      icon: priority == JobPriority.urgent
                          ? CupertinoIcons.exclamationmark
                          : null,
                    ),
                  const Spacer(),
                  if (showStatus)
                    Pill(
                      label: status.label,
                      color: status.color,
                      icon: status.icon,
                      dense: true,
                    ),
                  if (job.pending)
                    Padding(
                      padding: const EdgeInsets.only(left: Space.xs),
                      child: Tooltip(
                        message: 'Waiting to sync',
                        child: Icon(
                          CupertinoIcons.cloud_upload,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.xs),
              Text(
                job.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (status == JobStatus.waiting && job.waitingReason != null) ...[
                const SizedBox(height: 4),
                Text(
                  job.waitingReason!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: status.color,
                  ),
                ),
              ],
              const SizedBox(height: Space.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      meta.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: overdue
                            ? JobPriority.urgent.color
                            : scheme.onSurfaceVariant,
                        fontWeight: overdue ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                  if (assigneeName != null)
                    Tooltip(
                      message: assigneeName!,
                      child: AppAvatar(name: assigneeName!, size: 24),
                    )
                  else if (status == JobStatus.open)
                    Text(
                      'Unassigned',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder card while jobs load for the first time.
class JobCardSkeleton extends StatelessWidget {
  const JobCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SurfaceCard(
      radius: Radii.lg,
      padding: EdgeInsets.all(Space.sm + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(width: 52, height: 16, radius: 5),
          SizedBox(height: Space.xs),
          Skeleton(width: 200),
          SizedBox(height: 6),
          Skeleton(width: 120, height: 10),
        ],
      ),
    );
  }
}
