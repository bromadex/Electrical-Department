import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../assets/asset_picker.dart';
import '../assets/models.dart';
import '../assets/repository.dart' show assetProvider;
import '../reference/reference_data.dart';
import '../requests/models.dart';
import '../requests/repository.dart';
import '../../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/format.dart';
import '../ui/forms.dart';
import '../ui/media.dart';
import '../ui/page.dart';
import '../ui/panels.dart';
import '../ui/status.dart';
import 'repository.dart';

/// Stage 1: receive and register a job card, directly or from a request
/// another department submitted.
class RegisterJobCardScreen extends ConsumerWidget {
  const RegisterJobCardScreen({
    super.key,
    this.requestId,
    this.title,
    this.description,
    this.assetId,
  });

  final String? requestId;

  /// Prefill for a new job card started elsewhere (a chat message, an
  /// equipment page).
  final String? title;
  final String? description;
  final String? assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refData = ref.watch(referenceDataProvider);
    if (requestId == null) {
      return AsyncView(
        value: refData,
        onRetry: () => ref.invalidate(referenceDataProvider),
        data: (data) => _RegisterForm(
          reference: data,
          title: title,
          description: description,
          assetId: assetId,
        ),
      );
    }
    final request = ref.watch(serviceRequestProvider(requestId!));
    return AsyncView(
      value: refData,
      onRetry: () => ref.invalidate(referenceDataProvider),
      data: (data) => AsyncView(
        value: request,
        onRetry: () => ref.invalidate(serviceRequestProvider(requestId!)),
        data: (r) => _RegisterForm(reference: data, request: r),
      ),
    );
  }
}

class _RegisterForm extends ConsumerStatefulWidget {
  const _RegisterForm({
    required this.reference,
    this.request,
    this.title,
    this.description,
    this.assetId,
  });

  final ReferenceData reference;
  final ServiceRequest? request;
  final String? title;
  final String? description;
  final String? assetId;

  @override
  ConsumerState<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends ConsumerState<_RegisterForm> {
  final _form = GlobalKey<FormState>();
  late final _reporter = TextEditingController(
    text: widget.request?.reporterName,
  );
  late final _location = TextEditingController(text: widget.request?.location);
  late final _equipment = TextEditingController(
    text: widget.request?.equipmentText,
  );
  final _assetNo = TextEditingController();
  final _equipmentLocation = TextEditingController();
  late final _title = TextEditingController(
    text: widget.request?.title ?? widget.title,
  );
  late final _description = TextEditingController(
    text: widget.request?.description ?? widget.description,
  );

  String? _siteId;
  String? _areaId;
  String? _departmentId;
  String? _categoryId;
  Asset? _asset;
  String? _impact;
  String? _priority;
  DateTime? _receivedAt;
  DateTime? _requestedCompletion;
  List<PickedFile> _files = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final r = widget.request;
    _siteId = r?.siteId ?? ref.read(currentSiteProvider)?.id;
    _areaId = r?.areaId;
    _departmentId = r?.departmentId;
    _impact = r?.impact?.db;
    final assetId = widget.assetId;
    if (assetId != null) {
      ref.read(assetProvider(assetId).future).then((a) {
        if (mounted && _asset == null) {
          setState(() {
            _asset = a;
            _siteId = a.siteId;
          });
        }
      }, onError: (_) {});
    }
  }

  @override
  void dispose() {
    for (final c in [
      _reporter,
      _location,
      _equipment,
      _assetNo,
      _equipmentLocation,
      _title,
      _description,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_impact == null || _priority == null) {
      showSnack(context, 'Choose the operational impact and the priority.');
      return;
    }
    if (_areaId == null &&
        _asset == null &&
        _location.text.trim().isEmpty &&
        widget.request?.assetId == null) {
      showSnack(
        context,
        'Say where the work is: a work area, a location or the equipment.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final number = await ref
          .read(jobCardActionsProvider)
          .register(
            requestId: widget.request?.id,
            siteId: _siteId!,
            areaId: _areaId,
            location: _location.text,
            receivedAt: widget.request == null ? _receivedAt : null,
            reporterName: _reporter.text,
            departmentId: _departmentId,
            assetId: _asset?.id,
            equipmentName: _asset == null ? _equipment.text : null,
            equipmentAssetNo: _asset == null ? _assetNo.text : null,
            equipmentLocation: _asset == null ? _equipmentLocation.text : null,
            categoryId: _categoryId,
            title: _title.text,
            description: _description.text,
            impact: _impact,
            priority: _priority!,
            requestedCompletionAt: _requestedCompletion,
            files: _files,
          );
      if (!mounted) return;
      showSnack(context, 'Registered $number');
      context.pushReplacement('/jobs/$number');
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
    final data = widget.reference;
    final request = widget.request;
    final sites = [
      for (final s in session.mySites)
        if (session.can('jc.register', siteId: s.id)) s,
    ];
    if (sites.isEmpty) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'You cannot register job cards',
        message: 'Ask a system administrator if you should be able to.',
      );
    }
    if (_siteId == null || !sites.any((s) => s.id == _siteId)) {
      _siteId = sites.first.id;
    }
    final areas = session.areasAt(_siteId!);
    final priority = _priority == null ? null : data.priority(_priority!);

    return AppPage(
      title: request == null ? 'New job card' : 'Register ${request.requestNo}',
      subtitle: request == null
          ? 'Receive and register an electrical fault or maintenance job'
          : 'Submitted by ${request.requesterName ?? request.reporterName} · ${fmtDateTime(request.submittedAt)}',
      maxWidth: 1000,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (request != null) ...[
              Panel(
                title: 'The request',
                icon: Icons.move_to_inbox_outlined,
                child: Text(
                  'The request becomes a job card only when you register it here. '
                  'Fields are filled in from the request; correct anything that is wrong.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: Space.sm),
            ],
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormSection(
                    title: 'Reception',
                    children: [
                      DropdownField<String>(
                        label: 'Site',
                        required: true,
                        value: _siteId,
                        items: [
                          for (final s in sites)
                            (s.id, '${s.name} (${s.code})'),
                        ],
                        onChanged: request != null
                            ? null
                            : (v) => setState(() {
                                _siteId = v;
                                _areaId = null;
                                _asset = null;
                              }),
                      ),
                      if (request == null)
                        DateTimeField(
                          label: 'Date and time received',
                          value: _receivedAt,
                          helper: _receivedAt == null
                              ? 'Now, unless you set an earlier time'
                              : null,
                          lastDate: SiteTime.now(),
                          onChanged: (v) => setState(() => _receivedAt = v),
                        ),
                      TextFormField(
                        controller: _reporter,
                        decoration: const InputDecoration(
                          labelText: 'Reported by *',
                        ),
                        validator: Valid.length(
                          2,
                          120,
                          'The name of the person reporting',
                        ),
                      ),
                      DropdownField<String>(
                        label: 'Requesting department',
                        value: _departmentId,
                        items: [
                          for (final d in data.activeDepartments)
                            (d.id, d.name),
                        ],
                        onChanged: (v) => setState(() => _departmentId = v),
                      ),
                    ],
                  ),
                  FormSection(
                    title: 'Where',
                    subtitle:
                        'A work area, a location or the equipment is required.',
                    children: [
                      DropdownField<String>(
                        label: 'Work area / plant section',
                        value: _areaId,
                        items: [for (final a in areas) (a.id, a.name)],
                        onChanged: (v) => setState(() => _areaId = v),
                      ),
                      TextFormField(
                        controller: _location,
                        decoration: const InputDecoration(
                          labelText: 'Location details',
                        ),
                      ),
                    ],
                  ),
                  FormSection(
                    title: 'Equipment',
                    children: [
                      FullWidth(
                        child: AssetPickerField(
                          siteId: _siteId!,
                          value: _asset,
                          onChanged: (a) => setState(() => _asset = a),
                        ),
                      ),
                      if (_asset == null) ...[
                        TextFormField(
                          controller: _equipment,
                          decoration: const InputDecoration(
                            labelText: 'Equipment name',
                            helperText: 'If it is not in the register',
                          ),
                        ),
                        TextFormField(
                          controller: _assetNo,
                          decoration: const InputDecoration(
                            labelText: 'Asset ID',
                          ),
                        ),
                        TextFormField(
                          controller: _equipmentLocation,
                          decoration: const InputDecoration(
                            labelText: 'Equipment location',
                          ),
                        ),
                      ],
                    ],
                  ),
                  FormSection(
                    title: 'Fault or work',
                    children: [
                      FullWidth(
                        child: TextFormField(
                          controller: _title,
                          decoration: const InputDecoration(
                            labelText: 'Short title *',
                            hintText: 'e.g. MCC-2 isolator handle broken',
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
                            labelText: 'Detailed description *',
                          ),
                          validator: Valid.length(5, 4000, 'The description'),
                        ),
                      ),
                      DropdownField<String>(
                        label: 'Job category',
                        value: _categoryId,
                        items: [
                          for (final c in data.activeJobCategories)
                            (c.id, c.name),
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                      FullWidth(
                        child: ChoiceField<String>(
                          label: 'Operational impact *',
                          value: _impact,
                          onChanged: (v) => setState(() => _impact = v),
                          options: [
                            for (final i in Impact.values)
                              (i.db, i.label, null, i.color),
                          ],
                        ),
                      ),
                    ],
                  ),
                  FormSection(
                    title: 'Priority and timing',
                    children: [
                      FullWidth(
                        child: ChoiceField<String>(
                          label: 'Priority *',
                          value: _priority,
                          onChanged: (v) => setState(() => _priority = v),
                          helper: priority == null
                              ? null
                              : '${priority.description ?? ''}  Target: respond within '
                                    '${fmtMinutes(priority.responseMinutes)}, complete within '
                                    '${fmtMinutes(priority.completionMinutes)}.',
                          options: [
                            for (final p in Priority.values)
                              (p.code, '${p.code} ${p.name}', p.icon, p.color),
                          ],
                        ),
                      ),
                      if (_priority == 'P1')
                        FullWidth(
                          child: Container(
                            padding: const EdgeInsets.all(Space.sm),
                            decoration: BoxDecoration(
                              color: AppColors.critical.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(Radii.sm),
                              border: Border.all(
                                color: AppColors.critical.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.report_rounded,
                                  color: AppColors.critical,
                                ),
                                SizedBox(width: Space.xs),
                                Expanded(
                                  child: Text(
                                    'A P1 job card alerts the electrical engineers and escalation contacts '
                                    'at once. It does not replace the site\'s emergency response procedure: '
                                    'make the area safe and follow that procedure first.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      DateTimeField(
                        label: 'Requested completion (optional)',
                        value: _requestedCompletion,
                        onChanged: (v) =>
                            setState(() => _requestedCompletion = v),
                      ),
                    ],
                  ),
                  FormSection(
                    title: 'Photos and files',
                    children: [
                      FullWidth(
                        child: AttachmentPicker(
                          files: _files,
                          photoKind: 'photo_before',
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
                  onPressed: _busy ? null : () => context.pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.assignment_add),
                  label: const Text('Register job card'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
