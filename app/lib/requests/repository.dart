import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/app_error.dart';
import '../jobcards/repository.dart' show jobCardsLiveProvider;
import '../services/core_providers.dart';
import '../ui/media.dart';
import 'models.dart';

const _select =
    '*, site:sites(name), area:areas(name), department:departments(name), '
    'asset:assets(asset_no, name), '
    'requester:profiles!service_requests_requested_by_fkey(full_name), '
    'job:job_cards!service_requests_job_card_id_fkey(number, status)';

/// The electrical department's queue: submitted (and optionally returned)
/// requests at a site, or at all the user's sites when the site is null.
final incomingRequestsProvider = FutureProvider.autoDispose
    .family<List<ServiceRequest>, (String?, bool)>((ref, args) async {
      ref.watch(jobCardsLiveProvider);
      final (siteId, includeReturned) = args;
      var q = ref
          .watch(supabaseProvider)
          .from('service_requests')
          .select(_select)
          .eq('is_archived', false)
          .inFilter(
            'status',
            includeReturned ? ['submitted', 'returned'] : ['submitted'],
          );
      if (siteId != null) q = q.eq('site_id', siteId);
      final rows = await q.order('submitted_at');
      return [for (final r in rows) ServiceRequest(r)];
    });

/// Requests the signed-in user submitted, newest first.
final myRequestsProvider = FutureProvider.autoDispose<List<ServiceRequest>>((
  ref,
) async {
  ref.watch(jobCardsLiveProvider);
  final me = ref.watch(authUserIdProvider);
  if (me == null) return const [];
  final rows = await ref
      .watch(supabaseProvider)
      .from('service_requests')
      .select(_select)
      .eq('requested_by', me)
      .order('submitted_at', ascending: false)
      .limit(200);
  return [for (final r in rows) ServiceRequest(r)];
});

final serviceRequestProvider = FutureProvider.autoDispose
    .family<ServiceRequest, String>((ref, id) async {
      ref.watch(jobCardsLiveProvider);
      final row = await ref
          .watch(supabaseProvider)
          .from('service_requests')
          .select(_select)
          .eq('id', id)
          .maybeSingle();
      if (row == null) {
        throw const AppError(
          'NOT_FOUND',
          'Request not found, or you cannot see it.',
        );
      }
      return ServiceRequest(row);
    });

final requestTrackingProvider = FutureProvider.autoDispose
    .family<RequestTracking, String>((ref, id) async {
      ref.watch(jobCardsLiveProvider);
      final res = await ref
          .watch(supabaseProvider)
          .rpc('fn_request_tracking', params: {'p_request': id});
      return RequestTracking(Map<String, dynamic>.from(res as Map));
    });

final requestActionsProvider = Provider<RequestActions>(RequestActions.new);

class RequestActions {
  RequestActions(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  SupabaseClient get _client => _ref.read(supabaseProvider);
  static String? _t(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  Future<Map<String, dynamic>> _call(
    String fn,
    Map<String, dynamic> params,
  ) async {
    try {
      final res = await _client.rpc(fn, params: params);
      _ref.read(jobCardsLiveProvider.notifier).bumpNow();
      return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    } catch (e) {
      throw AppError.from(e);
    }
  }

  /// Submits a request and uploads its photos. Returns the request number.
  Future<String> submit({
    required String siteId,
    String? areaId,
    String? location,
    String? departmentId,
    required String reporterName,
    String? contact,
    String? assetId,
    String? equipment,
    required String title,
    required String description,
    required String impact,
    List<PickedFile> files = const [],
  }) async {
    final id = _uuid.v4();
    final row = await _call('fn_submit_request', {
      'p_client_ref': id,
      'p_site': siteId,
      'p_area': areaId,
      'p_location': _t(location),
      'p_department': departmentId,
      'p_reporter_name': reporterName.trim(),
      'p_contact': _t(contact),
      'p_asset': assetId,
      'p_equipment': _t(equipment),
      'p_title': title.trim(),
      'p_description': description.trim(),
      'p_impact': impact,
    });
    for (final f in files) {
      final ref = _uuid.v4();
      final safe = f.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '$siteId/request/$id/$ref-$safe';
      try {
        await _client.storage
            .from('job-files')
            .uploadBinary(
              path,
              f.bytes,
              fileOptions: FileOptions(contentType: f.contentType),
            );
      } catch (e) {
        throw AppError.from(e);
      }
      await _call('fn_add_request_attachment', {
        'p_client_ref': ref,
        'p_request': id,
        'p_path': path,
        'p_file_name': f.name,
        'p_content_type': f.contentType,
        'p_size': f.bytes.length,
      });
    }
    return row['request_no'] as String;
  }

  /// 'return' (needs more information) or 'reject', with a reason the
  /// requester will see.
  Future<void> triage(String id, String action, String reason) => _call(
    'fn_triage_request',
    {'p_request': id, 'p_action': action, 'p_reason': reason},
  );

  Future<void> resubmit(
    String id, {
    required String title,
    required String description,
    required String impact,
    required String note,
  }) => _call('fn_resubmit_request', {
    'p_request': id,
    'p_title': title.trim(),
    'p_description': description.trim(),
    'p_impact': impact,
    'p_note': note.trim(),
  });

  Future<void> withdraw(String id, String reason) =>
      _call('fn_withdraw_request', {'p_request': id, 'p_reason': reason});

  /// Signed URL (1 hour) for a request photo or file.
  Future<String?> fileUrl(String path) async {
    try {
      return await _client.storage
          .from('job-files')
          .createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }
}
