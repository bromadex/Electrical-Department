import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../data/app_error.dart';
import '../data/local_db.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/form_sheet.dart';
import '../ui/surfaces.dart';
import 'tools_repository.dart';

/// Calibration certificates of a tool (API.md 11b): PDFs or photos with the
/// date until which the calibration is valid. The newest one sets the
/// tool's calibration due date.
class ToolCertificate {
  ToolCertificate.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      path = j['path'] as String,
      fileName = j['file_name'] as String?,
      issuedOn = j['issued_on'] == null
          ? null
          : DateTime.parse(j['issued_on'] as String),
      validUntil = DateTime.parse(j['valid_until'] as String),
      uploadedAt = DateTime.parse(j['uploaded_at'] as String).toLocal();

  final String id;
  final String path;
  final String? fileName;
  final DateTime? issuedOn;
  final DateTime validUntil;
  final DateTime uploadedAt;
}

final toolCertificatesProvider = FutureProvider.autoDispose
    .family<List<ToolCertificate>, String>((ref, toolId) async {
      // Reload when the tool changes (a new certificate moves its due date).
      ref.watch(
        toolProvider(toolId)
            .select((t) => (t.value?.calibrationDue, t.value?.pending)),
      );
      final rows = await ref
          .watch(supabaseProvider)
          .from('tool_certificates')
          .select()
          .eq('tool_id', toolId)
          .eq('is_archived', false)
          .order('valid_until', ascending: false);
      return [for (final r in rows) ToolCertificate.fromJson(r)];
    });

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Queues the file and the certificate; works offline.
Future<void> addToolCertificate(
  WidgetRef ref,
  LocalTool tool, {
  required String fileName,
  required Uint8List bytes,
  DateTime? issuedOn,
  required DateTime validUntil,
}) async {
  final id = const Uuid().v4();
  final ext = fileName.contains('.')
      ? fileName.split('.').last.toLowerCase()
      : 'pdf';
  final path = '${tool.siteId}/tool/${tool.id}/cert-$id.$ext';
  await ref
      .read(outboxProvider)
      .enqueueUpload(
        id: id,
        bucket: 'tool-files',
        path: path,
        bytes: bytes,
        contentType: switch (ext) {
          'pdf' => 'application/pdf',
          'png' => 'image/png',
          _ => 'image/jpeg',
        },
      );
  final actions = ref.read(toolActionsProvider);
  if (tool.calibrationDue == null ||
      !tool.calibrationDue!.isAfter(validUntil)) {
    await actions.patch(
      tool.id,
      LocalToolsCompanion(calibrationDue: Value(validUntil)),
    );
  }
  await actions.queue('fn_add_tool_certificate', {
    'p_client_ref': id,
    'p_tool': tool.id,
    'p_path': path,
    'p_file_name': fileName,
    'p_issued_on': issuedOn == null ? null : _day(issuedOn),
    'p_valid_until': _day(validUntil),
  }, clientRef: id);
}

/// The certificates panel on a tool's Details tab.
class ToolCertificatesPanel extends ConsumerWidget {
  const ToolCertificatesPanel({super.key, required this.tool});

  final LocalTool tool;

  Future<void> _open(BuildContext context, WidgetRef ref, String path) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await ref
          .read(supabaseProvider)
          .storage
          .from('tool-files')
          .createSignedUrl(path, 600);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('The certificate opens once it has uploaded.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canIssue = ref
        .watch(sessionProvider)
        .can('tools.issue', siteId: tool.siteId);
    final certs = ref.watch(toolCertificatesProvider(tool.id));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return Panel(
      icon: CupertinoIcons.gauge,
      title: 'Calibration certificates',
      actions: [
        if (canIssue)
          TextButton.icon(
            onPressed: () =>
                showFormSheet(context, _CertificateSheet(tool: tool)),
            icon: const Icon(CupertinoIcons.arrow_up_doc, size: 18),
            label: const Text('Upload'),
          ),
      ],
      child: certs.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text(
          AppError.from(e).isRetryable
              ? 'Certificates load when you are online.'
              : AppError.from(e).message,
          style: theme.textTheme.labelMedium,
        ),
        data: (list) => list.isEmpty
            ? Text(
                'Upload the calibration certificate (PDF or photo) with the '
                'date it is valid until; reminders and the block on '
                'issuing expired tools follow it.',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : Column(
                children: [
                  for (final c in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      onTap: () => _open(context, ref, c.path),
                      leading: Icon(
                        CupertinoIcons.doc_text_fill,
                        color: c.validUntil.isBefore(today)
                            ? Colors.red
                            : BrandColors.success,
                      ),
                      title: Text(c.fileName ?? 'Certificate'),
                      subtitle: Text(
                        [
                          if (c.issuedOn != null)
                            'Issued ${dayWithYear(c.issuedOn!)}',
                          '${c.validUntil.isBefore(today) ? 'Expired' : 'Valid until'} '
                              '${dayWithYear(c.validUntil)}',
                        ].join(' · '),
                      ),
                      trailing: const Icon(CupertinoIcons.arrow_up_right),
                    ),
                ],
              ),
      ),
    );
  }
}

class _CertificateSheet extends ConsumerStatefulWidget {
  const _CertificateSheet({required this.tool});

  final LocalTool tool;

  @override
  ConsumerState<_CertificateSheet> createState() => _CertificateSheetState();
}

class _CertificateSheetState extends ConsumerState<_CertificateSheet> {
  ({String name, Uint8List bytes})? _file;
  DateTime? _issuedOn;
  DateTime? _validUntil;
  String? _error;
  bool _busy = false;

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
    );
    if (f == null) return;
    final bytes = await f.xFile.readAsBytes();
    if (bytes.length > 25 * 1024 * 1024) {
      setState(() => _error = 'That file is over 25 MB');
      return;
    }
    setState(() {
      _file = (name: f.name, bytes: bytes);
      _error = null;
    });
  }

  Future<DateTime?> _date(DateTime? initial, {bool future = false}) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate:
          initial ?? (future ? now.add(const Duration(days: 365)) : now),
      firstDate: now.subtract(const Duration(days: 3 * 365)),
      lastDate: now.add(const Duration(days: 6 * 365)),
    );
  }

  Future<void> _save() async {
    if (_file == null) {
      setState(() => _error = 'Pick the certificate file');
      return;
    }
    if (_validUntil == null) {
      setState(() => _error = 'Say until when it is valid');
      return;
    }
    if (_issuedOn != null && _issuedOn!.isAfter(_validUntil!)) {
      setState(() => _error = 'It cannot expire before it was issued');
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    await addToolCertificate(
      ref,
      widget.tool,
      fileName: _file!.name,
      bytes: _file!.bytes,
      issuedOn: _issuedOn,
      validUntil: _validUntil!,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Calibration certificate', style: theme.textTheme.headlineSmall),
          Text(
            '${widget.tool.code ?? ''} ${widget.tool.name}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.md),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(CupertinoIcons.paperclip),
            label: Text(_file?.name ?? 'Pick the PDF or photo'),
          ),
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(
            onPressed: () async {
              final d = await _date(_issuedOn);
              if (d != null) setState(() => _issuedOn = d);
            },
            icon: const Icon(CupertinoIcons.calendar),
            label: Text(
              _issuedOn == null
                  ? 'Date issued (optional)'
                  : 'Issued ${dayWithYear(_issuedOn!)}',
            ),
          ),
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(
            onPressed: () async {
              final d = await _date(_validUntil, future: true);
              if (d != null) {
                setState(() {
                  _validUntil = d;
                  _error = null;
                });
              }
            },
            icon: const Icon(CupertinoIcons.gauge),
            label: Text(
              _validUntil == null
                  ? 'Valid until'
                  : 'Valid until ${dayWithYear(_validUntil!)}',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: Space.lg),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(CupertinoIcons.arrow_up_doc_fill),
            label: const Text('Upload'),
          ),
        ],
      ),
    );
  }
}
