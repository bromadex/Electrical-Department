import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../reference/reference_data.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/format.dart';
import '../ui/forms.dart';
import '../ui/panels.dart';
import '../ui/status.dart';
import 'repository.dart';

/// Settings for phase 2: when safety checks are required, the checklist
/// itself, and the escalation rules.
class SafetySettingsPanel extends ConsumerWidget {
  const SafetySettingsPanel({super.key, required this.data});

  final ReferenceData data;

  static const _policies = [
    ('off', 'Not required (record only)'),
    (
      'when_required',
      'Required when the assessment calls for isolation, a permit or lockout',
    ),
    ('always', 'Required on every job card'),
  ];

  static const _applies = [
    ('always', 'Every job card'),
    ('isolation', 'When isolation is required'),
    ('permit', 'When a permit to work is required'),
    ('loto', 'When lockout/tagout is required'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(safetyItemsProvider);
    final theme = Theme.of(context);
    return Panel(
      title: 'Safety checklist',
      subtitle:
          'Checks recorded before and after the work. They are a record and never '
          'replace the site\'s isolation, lockout/tagout and permit procedures.',
      icon: Icons.health_and_safety_outlined,
      actions: [
        TextButton.icon(
          onPressed: () => _edit(context, ref),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add check'),
        ),
        const SizedBox(width: Space.xs),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownField<String>(
            label: 'Before work can start',
            value: data.settings.safetyBeforeStart,
            items: _policies,
            helper:
                'When required, Start work is refused until the pre-work checks are recorded, '
                'and Submit until the post-work checks are.',
            onChanged: (v) async {
              if (v == null) return;
              try {
                await ref.read(adminActionsProvider).saveSafetyPolicy(v);
                if (context.mounted) showSnack(context, 'Safety policy saved');
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
          ),
          const SizedBox(height: Space.sm),
          AsyncView(
            value: items,
            onRetry: () => ref.invalidate(safetyItemsProvider),
            data: (list) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final phase in const ['before', 'after']) ...[
                  SectionHeader(
                    phase == 'before' ? 'Before the work' : 'After the work',
                  ),
                  for (final i in list.where((i) => i.phase == phase))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        i.label,
                        style: i.isArchived
                            ? const TextStyle(
                                decoration: TextDecoration.lineThrough,
                              )
                            : null,
                      ),
                      subtitle: Text(
                        [
                          _applies.firstWhere((a) => a.$1 == i.appliesWhen).$2,
                          if (i.needsReference) 'reference number needed',
                          if (i.categoryId != null)
                            'only ${data.jobCategories.where((c) => c.id == i.categoryId).firstOrNull?.name ?? 'one category'}',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _edit(context, ref, i),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    SafetyChecklistItem? i,
  ]) async {
    final label = TextEditingController(text: i?.label);
    final order = TextEditingController(text: '${i?.sortOrder ?? 100}');
    var phase = i?.phase ?? 'before';
    var applies = i?.appliesWhen ?? 'always';
    var needsRef = i?.needsReference ?? false;
    String? category = i?.categoryId;
    var archived = i?.isArchived ?? false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(i == null ? 'Add safety check' : 'Edit safety check'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: label,
                    decoration: const InputDecoration(labelText: 'Check'),
                  ),
                  const SizedBox(height: Space.sm),
                  DropdownField<String>(
                    label: 'When',
                    value: phase,
                    items: const [
                      ('before', 'Before the work'),
                      ('after', 'After the work'),
                    ],
                    onChanged: (v) => setState(() => phase = v ?? phase),
                  ),
                  const SizedBox(height: Space.sm),
                  DropdownField<String>(
                    label: 'Applies to',
                    value: applies,
                    items: _applies,
                    onChanged: (v) => setState(() => applies = v ?? applies),
                  ),
                  const SizedBox(height: Space.sm),
                  DropdownField<String>(
                    label: 'Job category (empty = all)',
                    value: category,
                    items: [
                      for (final c in data.activeJobCategories) (c.id, c.name),
                    ],
                    onChanged: (v) => setState(() => category = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Needs a reference number'),
                    value: needsRef,
                    onChanged: (v) => setState(() => needsRef = v),
                  ),
                  TextField(
                    controller: order,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Order'),
                  ),
                  if (i != null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Archived'),
                      value: archived,
                      onChanged: (v) => setState(() => archived = v),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await ref
                      .read(adminActionsProvider)
                      .saveSafetyItem(
                        id: i?.id,
                        categoryId: category,
                        phase: phase,
                        label: label.text,
                        appliesWhen: applies,
                        needsReference: needsRef,
                        sortOrder: int.tryParse(order.text.trim()) ?? 100,
                        archived: archived,
                      );
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class EscalationRulesPanel extends ConsumerWidget {
  const EscalationRulesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(escalationRulesProvider);
    return Panel(
      title: 'Escalation rules',
      subtitle:
          'Checked every ten minutes. Each rule tells people once per job card and '
          'deadline. P1 and critical alerts at registration are always sent.',
      icon: Icons.campaign_outlined,
      actions: [
        TextButton.icon(
          onPressed: () => _edit(context, ref),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add rule'),
        ),
        const SizedBox(width: Space.xs),
      ],
      child: AsyncView(
        value: rules,
        onRetry: () => ref.invalidate(escalationRulesProvider),
        data: (list) => Column(
          children: [
            for (final r in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: r.priorityCode == null
                    ? const Pill(
                        label: 'All',
                        dense: true,
                        color: AppColors.neutral,
                      )
                    : PriorityBadge(Priority.fromCode(r.priorityCode)),
                title: Text(
                  r.name,
                  style: r.isActive
                      ? null
                      : const TextStyle(color: AppColors.neutral),
                ),
                subtitle: Text(
                  '${_when(r)} → ${r.recipients}${r.isActive ? '' : ' · switched off'}',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _edit(context, ref, r),
              ),
          ],
        ),
      ),
    );
  }

  static String _when(EscalationRule r) {
    final after = r.afterMinutes;
    return switch (r.kind) {
      'not_acknowledged' =>
        after == null || after == 0
            ? 'Not acknowledged by the response target'
            : 'Not acknowledged ${fmtMinutes(after)} after the response target',
      'approaching_deadline' =>
        after == null
            ? 'Deadline approaching (at-risk threshold)'
            : 'Less than ${fmtMinutes(after)} before the deadline',
      'overdue' =>
        after == null || after == 0
            ? 'Overdue'
            : 'Overdue by ${fmtMinutes(after)}',
      'on_hold_too_long' =>
        after == null
            ? 'On hold longer than the alert hours in General'
            : 'On hold longer than ${fmtMinutes(after)}',
      _ => 'Waiting for review longer than ${fmtMinutes(after ?? 1440)}',
    };
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    EscalationRule? r,
  ]) async {
    final name = TextEditingController(text: r?.name);
    final after = TextEditingController(text: r?.afterMinutes?.toString());
    var kind = r?.kind ?? 'overdue';
    String? priority = r?.priorityCode;
    var responsible = r?.notifyResponsible ?? true;
    var assigner = r?.notifyAssigner ?? false;
    var engineers = r?.notifyEngineers ?? false;
    var contacts = r?.notifyContacts ?? false;
    var managers = r?.notifyManagers ?? false;
    var active = r?.isActive ?? true;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            r == null ? 'Add escalation rule' : 'Edit escalation rule',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: Space.sm),
                  DropdownField<String>(
                    label: 'Watch for',
                    value: kind,
                    items: escalationKinds,
                    onChanged: (v) => setState(() => kind = v ?? kind),
                  ),
                  const SizedBox(height: Space.sm),
                  DropdownField<String>(
                    label: 'Priority (empty = all)',
                    value: priority,
                    items: [
                      for (final p in Priority.values)
                        (p.code, '${p.code} ${p.name}'),
                    ],
                    onChanged: (v) => setState(() => priority = v),
                  ),
                  const SizedBox(height: Space.sm),
                  TextField(
                    controller: after,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'After (minutes)',
                      helperText:
                          'Empty uses the default for this kind of rule',
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Tell'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('The responsible person'),
                    value: responsible,
                    onChanged: (v) => setState(() => responsible = v ?? false),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('The engineer who assigned it'),
                    value: assigner,
                    onChanged: (v) => setState(() => assigner = v ?? false),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Electrical engineers at the site'),
                    value: engineers,
                    onChanged: (v) => setState(() => engineers = v ?? false),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Escalation contacts for the priority'),
                    value: contacts,
                    onChanged: (v) => setState(() => contacts = v ?? false),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Managers'),
                    value: managers,
                    onChanged: (v) => setState(() => managers = v ?? false),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Rule is on'),
                    value: active,
                    onChanged: (v) => setState(() => active = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (r != null)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.critical,
                ),
                onPressed: () => _save(
                  context,
                  ref,
                  r,
                  name.text,
                  kind,
                  priority,
                  after.text,
                  responsible,
                  assigner,
                  engineers,
                  contacts,
                  managers,
                  active,
                  archived: true,
                ),
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => _save(
                context,
                ref,
                r,
                name.text,
                kind,
                priority,
                after.text,
                responsible,
                assigner,
                engineers,
                contacts,
                managers,
                active,
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    EscalationRule? r,
    String name,
    String kind,
    String? priority,
    String after,
    bool responsible,
    bool assigner,
    bool engineers,
    bool contacts,
    bool managers,
    bool active, {
    bool archived = false,
  }) async {
    try {
      await ref
          .read(adminActionsProvider)
          .saveEscalationRule(
            id: r?.id,
            name: name,
            kind: kind,
            priority: priority,
            afterMinutes: int.tryParse(after.trim()),
            notifyResponsible: responsible,
            notifyAssigner: assigner,
            notifyEngineers: engineers,
            notifyContacts: contacts,
            notifyManagers: managers,
            active: active,
            sortOrder: r?.sortOrder ?? 100,
            archived: archived,
          );
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}
