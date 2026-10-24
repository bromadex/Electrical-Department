import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../assets/asset_picker.dart';
import '../assets/models.dart';
import '../reference/reference_data.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/forms.dart';
import '../ui/media.dart';
import '../ui/page.dart';
import '../ui/panels.dart';
import '../ui/status.dart';
import 'repository.dart';

/// A fault or work request from any department. It goes to the electrical
/// department's incoming queue; it is not a job card until they register it.
class SubmitRequestScreen extends ConsumerStatefulWidget {
  const SubmitRequestScreen({super.key});

  @override
  ConsumerState<SubmitRequestScreen> createState() =>
      _SubmitRequestScreenState();
}

class _SubmitRequestScreenState extends ConsumerState<SubmitRequestScreen> {
  final _form = GlobalKey<FormState>();
  late final _reporter = TextEditingController(
    text: ref.read(sessionProvider).profile?.fullName,
  );
  late final _contact = TextEditingController(
    text: ref.read(sessionProvider).profile?.phone,
  );
  final _location = TextEditingController();
  final _equipment = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  String? _siteId;
  String? _areaId;
  late String? _departmentId = ref.read(sessionProvider).profile?.departmentId;
  Asset? _asset;
  String? _impact;
  List<PickedFile> _files = const [];
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _reporter,
      _contact,
      _location,
      _equipment,
      _title,
      _description,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_impact == null) {
      showSnack(context, 'Choose how the fault affects operations.');
      return;
    }
    if (_areaId == null && _asset == null && _location.text.trim().isEmpty) {
      showSnack(
        context,
        'Say where the problem is: a work area, a location or the equipment.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final number = await ref
          .read(requestActionsProvider)
          .submit(
            siteId: _siteId!,
            areaId: _areaId,
            location: _location.text,
            departmentId: _departmentId,
            reporterName: _reporter.text,
            contact: _contact.text,
            assetId: _asset?.id,
            equipment: _asset == null ? _equipment.text : null,
            title: _title.text,
            description: _description.text,
            impact: _impact!,
            files: _files,
          );
      if (!mounted) return;
      showSnack(context, 'Request $number sent to the electrical department');
      context.go('/my-requests');
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
        if (session.can('req.submit', siteId: s.id)) s,
    ];
    if (sites.isEmpty) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'You cannot submit requests',
        message: 'Ask a system administrator if you should be able to.',
      );
    }
    _siteId ??= ref.read(currentSiteProvider)?.id;
    if (!sites.any((s) => s.id == _siteId)) _siteId = sites.first.id;
    final areas = session.areasAt(_siteId!);

    return AppPage(
      title: 'New request',
      subtitle: 'Report an electrical fault or ask for electrical work',
      maxWidth: 900,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormSection(
                    title: 'Who is asking',
                    children: [
                      TextFormField(
                        controller: _reporter,
                        decoration: const InputDecoration(
                          labelText: 'Name of the person reporting *',
                        ),
                        validator: Valid.length(2, 120, 'The name'),
                      ),
                      TextFormField(
                        controller: _contact,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Contact (phone or radio)',
                        ),
                      ),
                      DropdownField<String>(
                        label: 'Your department',
                        value: _departmentId,
                        required: true,
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
                    title: 'Where',
                    children: [
                      DropdownField<String>(
                        label: 'Site',
                        required: true,
                        value: _siteId,
                        items: [for (final s in sites) (s.id, s.name)],
                        onChanged: (v) => setState(() {
                          _siteId = v;
                          _areaId = null;
                          _asset = null;
                        }),
                      ),
                      DropdownField<String>(
                        label: 'Work area',
                        value: _areaId,
                        items: [for (final a in areas) (a.id, a.name)],
                        onChanged: (v) => setState(() => _areaId = v),
                      ),
                      FullWidth(
                        child: TextFormField(
                          controller: _location,
                          decoration: const InputDecoration(
                            labelText: 'Exact location',
                            hintText: 'e.g. Shift office B, east wall',
                          ),
                        ),
                      ),
                      FullWidth(
                        child: AssetPickerField(
                          siteId: _siteId!,
                          value: _asset,
                          label: 'Affected equipment (if you know it)',
                          onChanged: (a) => setState(() => _asset = a),
                        ),
                      ),
                      if (_asset == null)
                        FullWidth(
                          child: TextFormField(
                            controller: _equipment,
                            decoration: const InputDecoration(
                              labelText: 'Or describe the equipment',
                            ),
                          ),
                        ),
                    ],
                  ),
                  FormSection(
                    title: 'The problem',
                    children: [
                      FullWidth(
                        child: TextFormField(
                          controller: _title,
                          decoration: const InputDecoration(
                            labelText: 'Short title *',
                            hintText: 'e.g. Packing line lights out',
                          ),
                          validator: Valid.length(3, 120, 'The title'),
                        ),
                      ),
                      FullWidth(
                        child: TextFormField(
                          controller: _description,
                          minLines: 3,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            labelText: 'What is wrong? *',
                          ),
                          validator: Valid.length(5, 4000, 'The description'),
                        ),
                      ),
                      FullWidth(
                        child: ChoiceField<String>(
                          label: 'How does it affect operations? *',
                          value: _impact,
                          onChanged: (v) => setState(() => _impact = v),
                          options: [
                            for (final i in Impact.values)
                              (i.db, i.label, null, i.color),
                          ],
                        ),
                      ),
                      if (_impact == Impact.safetyHazard.db)
                        FullWidth(
                          child: Container(
                            padding: const EdgeInsets.all(Space.sm),
                            decoration: BoxDecoration(
                              color: AppColors.critical.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(Radii.sm),
                            ),
                            child: const Text(
                              'If anyone is in danger, make the area safe and follow the site emergency '
                              'procedure first. This request does not replace it.',
                            ),
                          ),
                        ),
                      FullWidth(
                        child: AttachmentPicker(
                          files: _files,
                          allowDocuments: false,
                          onChanged: (f) => setState(() => _files = f),
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
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => context.go('/my-requests'),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: const Text('Send request'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
