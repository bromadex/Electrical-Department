import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../reference/reference_data.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/forms.dart';
import '../ui/page.dart';
import '../ui/panels.dart';
import 'models.dart';
import 'repository.dart';

/// Add or edit equipment in the register.
class AssetFormScreen extends ConsumerWidget {
  const AssetFormScreen({super.key, this.id});

  final String? id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (id == null) return const _AssetForm();
    return AsyncView(
      value: ref.watch(assetProvider(id!)),
      onRetry: () => ref.invalidate(assetProvider(id!)),
      data: (a) => _AssetForm(asset: a),
    );
  }
}

class _AssetForm extends ConsumerStatefulWidget {
  const _AssetForm({this.asset});

  final Asset? asset;

  @override
  ConsumerState<_AssetForm> createState() => _AssetFormState();
}

class _AssetFormState extends ConsumerState<_AssetForm> {
  final _form = GlobalKey<FormState>();
  late final a = widget.asset;
  late final _assetNo = TextEditingController(text: a?.assetNo);
  late final _name = TextEditingController(text: a?.name);
  late final _location = TextEditingController(text: a?.location);
  late final _manufacturer = TextEditingController(text: a?.manufacturer);
  late final _model = TextEditingController(text: a?.model);
  late final _serial = TextEditingController(text: a?.serialNo);
  late final _rating = TextEditingController(text: a?.rating);
  late final _voltage = TextEditingController(text: a?.voltage?.toString());
  late final _current = TextEditingController(text: a?.current?.toString());
  late final _power = TextEditingController(text: a?.power?.toString());
  late final _frequency = TextEditingController(text: a?.maintenanceFrequency);
  late final _warrantyNotes = TextEditingController(text: a?.warrantyNotes);
  late final _notes = TextEditingController(text: a?.notes);
  late String? _siteId = a?.siteId ?? ref.read(currentSiteProvider)?.id;
  late String? _areaId = a?.areaId;
  late String? _categoryId = a?.categoryId;
  late String? _departmentId = a?.departmentId;
  late String _status = a?.status.db ?? AssetStatus.inService.db;
  late String _criticality = a?.criticality ?? 'medium';
  late DateTime? _installed = a?.installedOn;
  late DateTime? _warranty = a?.warrantyExpiresOn;
  bool _busy = false;

  Future<void> _save({bool archive = false}) async {
    if (!archive && !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final id = await ref
          .read(assetActionsProvider)
          .save(
            id: a?.id,
            siteId: _siteId!,
            areaId: _areaId,
            assetNo: _assetNo.text,
            name: _name.text,
            categoryId: _categoryId,
            location: _location.text,
            manufacturer: _manufacturer.text,
            model: _model.text,
            serialNo: _serial.text,
            rating: _rating.text,
            voltage: num.tryParse(_voltage.text.trim()),
            current: num.tryParse(_current.text.trim()),
            power: num.tryParse(_power.text.trim()),
            installedOn: _installed,
            status: _status,
            criticality: _criticality,
            departmentId: _departmentId,
            maintenanceFrequency: _frequency.text,
            warrantyExpiresOn: _warranty,
            warrantyNotes: _warrantyNotes.text,
            notes: _notes.text,
            archived: archive,
          );
      if (!mounted) return;
      showSnack(context, archive ? 'Equipment archived' : 'Equipment saved');
      context.go(archive ? '/assets' : '/assets/$id');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final data = ref.watch(referenceDataProvider).value;
    final sites = [
      for (final s in session.mySites)
        if (session.can('assets.manage', siteId: s.id)) s,
    ];
    if (sites.isEmpty) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'You cannot manage equipment',
        message: 'Ask a system administrator if you should be able to.',
      );
    }
    if (_siteId == null || !sites.any((s) => s.id == _siteId)) {
      _siteId = sites.first.id;
    }
    final areas = session.areasAt(_siteId!);

    return AppPage(
      title: a == null ? 'Add equipment' : 'Edit ${a!.assetNo}',
      maxWidth: 1000,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Panel(
              child: Column(
                children: [
                  FormSection(
                    title: 'Identification',
                    children: [
                      TextFormField(
                        controller: _assetNo,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Asset ID *',
                          hintText: 'e.g. KAM-GEN-03',
                        ),
                        validator: Valid.length(1, 40, 'The asset ID'),
                      ),
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Equipment name *',
                        ),
                        validator: Valid.length(2, 120, 'The name'),
                      ),
                      DropdownField<String>(
                        label: 'Category',
                        value: _categoryId,
                        items: [
                          for (final c
                              in data?.activeAssetCategories ??
                                  const <Category>[])
                            (c.id, c.name),
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                      TextFormField(
                        controller: _manufacturer,
                        decoration: const InputDecoration(
                          labelText: 'Manufacturer',
                        ),
                      ),
                      TextFormField(
                        controller: _model,
                        decoration: const InputDecoration(labelText: 'Model'),
                      ),
                      TextFormField(
                        controller: _serial,
                        decoration: const InputDecoration(
                          labelText: 'Serial number',
                        ),
                      ),
                    ],
                  ),
                  FormSection(
                    title: 'Location',
                    children: [
                      DropdownField<String>(
                        label: 'Site',
                        required: true,
                        value: _siteId,
                        items: [for (final s in sites) (s.id, s.name)],
                        onChanged: (v) => setState(() {
                          _siteId = v;
                          _areaId = null;
                        }),
                      ),
                      DropdownField<String>(
                        label: 'Work area',
                        value: _areaId,
                        items: [for (final ar in areas) (ar.id, ar.name)],
                        onChanged: (v) => setState(() => _areaId = v),
                      ),
                      TextFormField(
                        controller: _location,
                        decoration: const InputDecoration(
                          labelText: 'Exact location',
                        ),
                      ),
                      DropdownField<String>(
                        label: 'Responsible department',
                        value: _departmentId,
                        items: [
                          for (final d
                              in data?.activeDepartments ??
                                  const <Department>[])
                            (d.id, d.name),
                        ],
                        onChanged: (v) => setState(() => _departmentId = v),
                      ),
                    ],
                  ),
                  FormSection(
                    title: 'Ratings',
                    children: [
                      TextFormField(
                        controller: _rating,
                        decoration: const InputDecoration(
                          labelText: 'Electrical rating',
                          hintText: 'e.g. 1000 kVA, 11/0.4 kV',
                        ),
                      ),
                      TextFormField(
                        controller: _voltage,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Voltage (V)',
                        ),
                        validator: Valid.positiveNumber('Voltage'),
                      ),
                      TextFormField(
                        controller: _current,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Current rating (A)',
                        ),
                        validator: Valid.positiveNumber('Current'),
                      ),
                      TextFormField(
                        controller: _power,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Power rating (kW)',
                        ),
                        validator: Valid.positiveNumber('Power'),
                      ),
                    ],
                  ),
                  FormSection(
                    title: 'Status and maintenance',
                    children: [
                      FullWidth(
                        child: ChoiceField<String>(
                          label: 'Operational status',
                          value: _status,
                          onChanged: (v) => setState(() => _status = v),
                          options: [
                            for (final s in AssetStatus.values)
                              (s.db, s.label, null, null),
                          ],
                        ),
                      ),
                      FullWidth(
                        child: ChoiceField<String>(
                          label: 'Criticality',
                          value: _criticality,
                          onChanged: (v) => setState(() => _criticality = v),
                          options: const [
                            ('high', 'High', null, AppColors.critical),
                            ('medium', 'Medium', null, AppColors.warning),
                            ('low', 'Low', null, AppColors.neutral),
                          ],
                        ),
                      ),
                      DateTimeField(
                        label: 'Installed',
                        value: _installed,
                        dateOnly: true,
                        onChanged: (v) => setState(() => _installed = v),
                      ),
                      TextFormField(
                        controller: _frequency,
                        decoration: const InputDecoration(
                          labelText: 'Maintenance frequency',
                          hintText: 'e.g. Weekly run test',
                        ),
                      ),
                      DateTimeField(
                        label: 'Warranty until',
                        value: _warranty,
                        dateOnly: true,
                        onChanged: (v) => setState(() => _warranty = v),
                      ),
                      TextFormField(
                        controller: _warrantyNotes,
                        decoration: const InputDecoration(
                          labelText: 'Warranty notes',
                        ),
                      ),
                      FullWidth(
                        child: TextFormField(
                          controller: _notes,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(labelText: 'Notes'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.md),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                if (a != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.critical,
                    ),
                    onPressed: _busy ? null : () => _save(archive: true),
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Archive'),
                  ),
                OutlinedButton(
                  onPressed: _busy ? null : () => context.pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save equipment'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
