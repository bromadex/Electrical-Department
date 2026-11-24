import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/core_providers.dart';

export '../services/session_controller.dart'
    show siteFilterProvider, currentSiteProvider;
export '../widgets/site_picker.dart' show SiteFilterChip, SiteField;

/// The signed-in person's department, for prefilling requests. Version 1's
/// cached profile does not hold it, so it is read on demand.
final myDepartmentIdProvider = FutureProvider.autoDispose<String?>((ref) async {
  final userId = ref.watch(authUserIdProvider);
  if (userId == null) return null;
  final row = await ref
      .watch(supabaseProvider)
      .from('profiles')
      .select('department_id')
      .eq('id', userId)
      .maybeSingle();
  return row?['department_id'] as String?;
});
