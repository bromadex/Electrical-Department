import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/core_providers.dart';
import '../services/session_controller.dart';

/// True when the user chose "All sites" in Version 2's site picker.
final allSitesProvider = NotifierProvider<AllSitesNotifier, bool>(
  AllSitesNotifier.new,
);

class AllSitesNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(authUserIdProvider);
    return false;
  }

  void set(bool value) => state = value;
}

/// The site Version 2's lists and dashboard show; null means all the user's
/// sites.
final siteFilterProvider = Provider<String?>((ref) {
  if (ref.watch(allSitesProvider)) return null;
  return ref.watch(currentSiteProvider)?.id;
});

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
