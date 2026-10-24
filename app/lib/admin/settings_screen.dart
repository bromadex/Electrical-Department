import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../reference/reference_data.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/format.dart';
import '../ui/forms.dart';
import '../ui/page.dart';
import '../ui/panels.dart';
import '../ui/status.dart';
import 'repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (!session.perms.canEverywhere('settings.manage')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Administrators only',
        message: 'Only a system administrator can change settings.',
      );
    }
    return AsyncView(
      value: ref.watch(referenceDataProvider),
      onRetry: () => ref.invalidate(referenceDataProvider),
      data: (data) => AppPage(
        title: 'Settings',
        subtitle: 'How job cards are numbered, timed and classified',
        maxWidth: 1100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GeneralSettings(settings: data.settings),
            const SizedBox(height: Space.md),
            _Priorities(priorities: data.priorities),
            const SizedBox(height: Space.md),
            _ListPanel(
              title: 'Departments',
              subtitle: 'Who can request work',
              items: [
                for (final d in data.departments)
                  _Item(
                    d.id,
                    '${d.name} (${d.code})',
                    d.isArchived,
                    d.isElectrical ? 'Electrical' : null,
                  ),
              ],
              onAdd: () => _departmentDialog(context, ref),
              onEdit: (id) => _departmentDialog(
                context,
                ref,
                data.departments.firstWhere((d) => d.id == id),
              ),
            ),
            const SizedBox(height: Space.md),
            _ListPanel(
              title: 'Job categories',
              items: [
                for (final c in data.jobCategories)
                  _Item(c.id, c.name, c.isArchived, null),
              ],
              onAdd: () => _categoryDialog(context, ref, job: true),
              onEdit: (id) => _categoryDialog(
                context,
                ref,
                job: true,
                existing: data.jobCategories.firstWhere((c) => c.id == id),
              ),
            ),
            const SizedBox(height: Space.md),
            _ListPanel(
              title: 'Equipment categories',
              items: [
                for (final c in data.assetCategories)
                  _Item(c.id, c.name, c.isArchived, null),
              ],
              onAdd: () => _categoryDialog(context, ref, job: false),
              onEdit: (id) => _categoryDialog(
                context,
                ref,
                job: false,
                existing: data.assetCategories.firstWhere((c) => c.id == id),
              ),
            ),
            const SizedBox(height: Space.md),
            const _Areas(),
            const SizedBox(height: Space.md),
            const _EscalationContacts(),
          ],
        ),
      ),
    );
  }

  static Future<void> _departmentDialog(
    BuildContext context,
    WidgetRef ref, [
    Department? d,
  ]) async {
    final code = TextEditingController(text: d?.code);
    final name = TextEditingController(text: d?.name);
    var electrical = d?.isElectrical ?? false;
    var archived = d?.isArchived ?? false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(d == null ? 'Add department' : 'Edit department'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Code (2–10 letters or digits)',
                  ),
                ),
                const SizedBox(height: Space.sm),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Electrical department'),
                  value: electrical,
                  onChanged: (v) => setState(() => electrical = v),
                ),
                if (d != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Archived'),
                    value: archived,
                    onChanged: (v) => setState(() => archived = v),
                  ),
              ],
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
                      .saveDepartment(
                        id: d?.id,
                        code: code.text,
                        name: name.text,
                        isElectrical: electrical,
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

  static Future<void> _categoryDialog(
    BuildContext context,
    WidgetRef ref, {
    required bool job,
    Category? existing,
  }) async {
    final name = TextEditingController(text: existing?.name);
    final order = TextEditingController(text: '${existing?.sortOrder ?? 100}');
    var archived = existing?.isArchived ?? false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            '${existing == null ? 'Add' : 'Edit'} ${job ? 'job' : 'equipment'} category',
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: Space.sm),
                TextField(
                  controller: order,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sort order'),
                ),
                if (existing != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Archived'),
                    value: archived,
                    onChanged: (v) => setState(() => archived = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final admin = ref.read(adminActionsProvider);
                final sort = int.tryParse(order.text.trim()) ?? 100;
                try {
                  if (job) {
                    await admin.saveJobCategory(
                      id: existing?.id,
                      name: name.text,
                      sortOrder: sort,
                      archived: archived,
                    );
                  } else {
                    await admin.saveAssetCategory(
                      id: existing?.id,
                      name: name.text,
                      sortOrder: sort,
                      archived: archived,
                    );
                  }
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

class _GeneralSettings extends ConsumerStatefulWidget {
  const _GeneralSettings({required this.settings});

  final SystemSettings settings;

  @override
  ConsumerState<_GeneralSettings> createState() => _GeneralSettingsState();
}

class _GeneralSettingsState extends ConsumerState<_GeneralSettings> {
  final _form = GlobalKey<FormState>();
  late final s = widget.settings;
  late final _company = TextEditingController(text: s.companyName);
  late final _department = TextEditingController(text: s.departmentName);
  late final _timezone = TextEditingController(text: s.timezone);
  late final _jobPrefix = TextEditingController(text: s.jobcardPrefix);
  late final _reqPrefix = TextEditingController(text: s.requestPrefix);
  late final _atRisk = TextEditingController(text: '${s.atRiskPercent}');
  late final _holdHours = TextEditingController(text: '${s.holdAlertHours}');
  late int _digits = s.numberDigits;
  late bool _yearly = s.numberResetYearly;
  late String _responseEnds = s.responseEndsAt;
  late bool _handover = s.handoverNoteRequired;
  bool _busy = false;

  String get _preview {
    final year = _yearly ? '${SiteTime.now().year}-' : '';
    return '${_jobPrefix.text.toUpperCase()}-$year${'1'.padLeft(_digits, '0')} · '
        '${_reqPrefix.text.toUpperCase()}-$year${'1'.padLeft(_digits, '0')}';
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(adminActionsProvider)
          .saveSettings(
            timezone: _timezone.text,
            jobcardPrefix: _jobPrefix.text,
            requestPrefix: _reqPrefix.text,
            numberDigits: _digits,
            numberResetYearly: _yearly,
            responseEndsAt: _responseEnds,
            atRiskPercent: int.parse(_atRisk.text.trim()),
            holdAlertHours: int.parse(_holdHours.text.trim()),
            handoverNoteRequired: _handover,
            companyName: _company.text,
            departmentName: _department.text,
            logoPath: s.logoPath,
          );
      if (mounted) showSnack(context, 'Settings saved');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zones = SiteTime.zoneNames();
    String? intRange(String? v, int min, int max, String what) {
      final n = int.tryParse(v?.trim() ?? '');
      return n == null || n < min || n > max
          ? '$what must be a whole number from $min to $max'
          : null;
    }

    return Panel(
      title: 'General',
      icon: Icons.tune_rounded,
      actions: [
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
        const SizedBox(width: Space.xs),
      ],
      child: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormSection(
              title: 'Organisation and time',
              children: [
                TextFormField(
                  controller: _company,
                  decoration: const InputDecoration(labelText: 'Company name'),
                  validator: Valid.length(2, 120, 'The company name'),
                ),
                TextFormField(
                  controller: _department,
                  decoration: const InputDecoration(
                    labelText: 'Department name',
                  ),
                  validator: Valid.length(2, 120, 'The department name'),
                ),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: _timezone.text),
                  optionsBuilder: (v) => zones
                      .where(
                        (z) => z.toLowerCase().contains(v.text.toLowerCase()),
                      )
                      .take(30),
                  onSelected: (z) => _timezone.text = z,
                  fieldViewBuilder: (context, controller, focus, onSubmit) =>
                      TextFormField(
                        controller: controller,
                        focusNode: focus,
                        onChanged: (v) => _timezone.text = v,
                        decoration: const InputDecoration(
                          labelText: 'Site time zone',
                          helperText:
                              'All "today" figures and times use this zone',
                        ),
                        validator: (v) => zones.contains(v?.trim())
                            ? null
                            : 'Choose a time zone from the list',
                      ),
                ),
              ],
            ),
            FormSection(
              title: 'Numbering',
              subtitle:
                  'Next numbers look like $_preview. Numbers are never reused.',
              children: [
                TextFormField(
                  controller: _jobPrefix,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Job card prefix',
                  ),
                  validator: (v) =>
                      RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]{0,11}$')
                          .hasMatch(v?.trim() ?? '')
                      ? null
                      : 'Letters, digits and dashes (up to 12)',
                ),
                TextFormField(
                  controller: _reqPrefix,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Request prefix',
                  ),
                  validator: (v) =>
                      RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]{0,11}$')
                          .hasMatch(v?.trim() ?? '')
                      ? null
                      : 'Letters, digits and dashes (up to 12)',
                ),
                DropdownField<int>(
                  label: 'Number of digits',
                  value: _digits,
                  items: [for (var i = 3; i <= 8; i++) (i, '$i')],
                  onChanged: (v) => setState(() => _digits = v ?? 4),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Restart numbering each year'),
                  value: _yearly,
                  onChanged: (v) => setState(() => _yearly = v),
                ),
              ],
            ),
            FormSection(
              title: 'Response and deadlines',
              children: [
                DropdownField<String>(
                  label: 'Response time ends when the job is…',
                  value: _responseEnds,
                  items: const [
                    ('acknowledged', 'Accepted by the assignee'),
                    ('assessed', 'Assessed by an engineer'),
                    ('assigned', 'Assigned'),
                  ],
                  onChanged: (v) =>
                      setState(() => _responseEnds = v ?? 'acknowledged'),
                ),
                TextFormField(
                  controller: _atRisk,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'At risk when this % of the time remains',
                  ),
                  validator: (v) => intRange(v, 1, 90, 'The threshold'),
                ),
                TextFormField(
                  controller: _holdHours,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Alert when on hold longer than (hours)',
                  ),
                  validator: (v) => intRange(v, 1, 2160, 'The hours'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Require a handover note when reassigning work in progress',
                  ),
                  value: _handover,
                  onChanged: (v) => setState(() => _handover = v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Priorities extends ConsumerWidget {
  const _Priorities({required this.priorities});

  final List<PriorityLevel> priorities;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Panel(
      title: 'Priority targets',
      subtitle:
          'Response and completion targets set each job card\'s deadline when it is registered. '
          'Changes apply to job cards registered from now on.',
      icon: Icons.flag_outlined,
      child: Column(
        children: [
          for (final p in priorities)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: PriorityBadge(Priority.fromCode(p.code)),
              title: Text(p.name),
              subtitle: Text(
                'Respond within ${fmtMinutes(p.responseMinutes)} · complete within ${fmtMinutes(p.completionMinutes)}',
              ),
              trailing: Wrap(
                spacing: Space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!p.targetsConfirmed)
                    const Pill(
                      label: 'Default — confirm',
                      color: AppColors.warning,
                      dense: true,
                    ),
                  OutlinedButton(
                    onPressed: () => _edit(context, ref, p),
                    child: const Text('Edit'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    PriorityLevel p,
  ) async {
    final name = TextEditingController(text: p.name);
    final description = TextEditingController(text: p.description);
    final response = TextEditingController(text: '${p.responseMinutes}');
    final completion = TextEditingController(text: '${p.completionMinutes}');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${p.code} targets'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: Space.sm),
              TextField(
                controller: description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Examples / description',
                ),
              ),
              const SizedBox(height: Space.sm),
              TextField(
                controller: response,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Response target (minutes)',
                ),
              ),
              const SizedBox(height: Space.sm),
              TextField(
                controller: completion,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Completion target (minutes)',
                  helperText: '1 day = 1440, 1 week = 10080',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final r = int.tryParse(response.text.trim());
              final c = int.tryParse(completion.text.trim());
              if (r == null || c == null) {
                showSnack(context, 'Targets must be whole numbers of minutes.');
                return;
              }
              try {
                await ref
                    .read(adminActionsProvider)
                    .savePriority(
                      p.code,
                      name: name.text,
                      description: description.text,
                      responseMinutes: r,
                      completionMinutes: c,
                    );
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
            child: const Text('Save targets'),
          ),
        ],
      ),
    );
  }
}

class _Item {
  const _Item(this.id, this.label, this.archived, this.tag);

  final String id;
  final String label;
  final bool archived;
  final String? tag;
}

class _ListPanel extends StatelessWidget {
  const _ListPanel({
    required this.title,
    this.subtitle,
    required this.items,
    required this.onAdd,
    required this.onEdit,
  });

  final String title;
  final String? subtitle;
  final List<_Item> items;
  final VoidCallback onAdd;
  final ValueChanged<String> onEdit;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: title,
      subtitle: subtitle,
      icon: Icons.list_alt_rounded,
      actions: [
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add'),
        ),
        const SizedBox(width: Space.xs),
      ],
      child: Wrap(
        spacing: Space.xs,
        runSpacing: Space.xs,
        children: [
          for (final i in items)
            InputChip(
              label: Text(i.label),
              avatar: i.tag == null
                  ? null
                  : const Icon(Icons.bolt_rounded, size: 16),
              onPressed: () => onEdit(i.id),
              backgroundColor: i.archived
                  ? Theme.of(context).colorScheme.surfaceContainer
                  : null,
              labelStyle: i.archived
                  ? const TextStyle(decoration: TextDecoration.lineThrough)
                  : null,
            ),
        ],
      ),
    );
  }
}

class _Areas extends ConsumerWidget {
  const _Areas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Panel(
      title: 'Work areas and plant sections',
      icon: Icons.place_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final site in session.sites.where((s) => !s.isArchived))
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${site.name} (${site.code})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: Space.xs,
                    runSpacing: Space.xs,
                    children: [
                      for (final a in session.areas.where(
                        (a) => a.siteId == site.id,
                      ))
                        InputChip(
                          label: Text(a.name),
                          labelStyle: a.isArchived
                              ? const TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                )
                              : null,
                          onPressed: () => _edit(
                            context,
                            ref,
                            siteId: site.id,
                            id: a.id,
                            name: a.name,
                            archived: a.isArchived,
                          ),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add area'),
                        onPressed: () => _edit(context, ref, siteId: site.id),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    required String siteId,
    String? id,
    String? name,
    bool archived = false,
  }) async {
    final controller = TextEditingController(text: name);
    var isArchived = archived;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(id == null ? 'Add work area' : 'Edit work area'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Plant – MCC room',
                  ),
                ),
                if (id != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Archived'),
                    value: isArchived,
                    onChanged: (v) => setState(() => isArchived = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (controller.text.trim().length < 2) return;
                try {
                  await ref
                      .read(adminActionsProvider)
                      .saveArea(
                        id: id,
                        siteId: siteId,
                        name: controller.text,
                        archived: isArchived,
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

class _EscalationContacts extends ConsumerWidget {
  const _EscalationContacts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(escalationContactsProvider);
    return Panel(
      title: 'Escalation contacts',
      subtitle:
          'Also alerted at once when a job card of this priority becomes critical, '
          'together with the site\'s electrical engineers.',
      icon: Icons.campaign_outlined,
      actions: [
        TextButton.icon(
          onPressed: () => _add(context, ref),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add'),
        ),
        const SizedBox(width: Space.xs),
      ],
      child: AsyncView(
        value: contacts,
        onRetry: () => ref.invalidate(escalationContactsProvider),
        data: (list) => list.isEmpty
            ? const Text(
                'No escalation contacts. P1 alerts go to the site\'s electrical engineers only.',
              )
            : Column(
                children: [
                  for (final c in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: PriorityBadge(
                        Priority.fromCode(c['priority_code'] as String?),
                      ),
                      title: Text(
                        (c['person'] as Map?)?['full_name'] as String? ??
                            'Someone',
                      ),
                      subtitle: Text(
                        (c['site'] as Map?)?['name'] as String? ?? 'All sites',
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        onPressed: () async {
                          try {
                            await ref
                                .read(adminActionsProvider)
                                .saveEscalationContact(
                                  id: c['id'] as String,
                                  siteId: c['site_id'] as String?,
                                  priority: c['priority_code'] as String,
                                  userId: c['user_id'] as String,
                                  archived: true,
                                );
                          } catch (e) {
                            if (context.mounted) showError(context, e);
                          }
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final users = await ref.read(adminUsersProvider.future);
    if (!context.mounted) return;
    final sites = ref
        .read(sessionProvider)
        .sites
        .where((s) => !s.isArchived)
        .toList();
    String? userId;
    String? siteId;
    var priority = 'P1';
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add escalation contact'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownField<String>(
                  label: 'Person',
                  value: userId,
                  items: [
                    for (final u in users)
                      if (u.active)
                        (u.id, u.fullName.isEmpty ? u.email : u.fullName),
                  ],
                  onChanged: (v) => setState(() => userId = v),
                ),
                const SizedBox(height: Space.sm),
                DropdownField<String>(
                  label: 'Priority',
                  value: priority,
                  items: [
                    for (final p in Priority.values)
                      (p.code, '${p.code} ${p.name}'),
                  ],
                  onChanged: (v) => setState(() => priority = v ?? 'P1'),
                ),
                const SizedBox(height: Space.sm),
                DropdownButtonFormField<String?>(
                  initialValue: siteId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Site'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All sites'),
                    ),
                    for (final s in sites)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: (v) => setState(() => siteId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: userId == null
                  ? null
                  : () async {
                      try {
                        await ref
                            .read(adminActionsProvider)
                            .saveEscalationContact(
                              siteId: siteId,
                              priority: priority,
                              userId: userId!,
                            );
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) showError(context, e);
                      }
                    },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}
