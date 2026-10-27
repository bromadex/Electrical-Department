import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/core_providers.dart';
import '../services/session_controller.dart';

/// True when the user chose "All my sites" on a job card screen.
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

/// The site the job card lists and statistics show; null means all the
/// user's sites.
final siteFilterProvider = Provider<String?>((ref) {
  if (ref.watch(allSitesProvider)) return null;
  return ref.watch(currentSiteProvider)?.id;
});

/// Shows every site the person can see on the job card list, statistics and
/// incoming requests. The rest of the app keeps working with the site picked
/// in the header, so the choice lives here, not in the shared site picker.
/// Hidden for people with one site.
class AllSitesChip extends ConsumerWidget {
  const AllSitesChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sites = ref.watch(sessionProvider.select((s) => s.mySites.length));
    if (sites < 2) return const SizedBox.shrink();
    return FilterChip(
      label: const Text('All my sites'),
      avatar: const Icon(Icons.public_rounded, size: 18),
      selected: ref.watch(allSitesProvider),
      showCheckmark: false,
      onSelected: (on) => ref.read(allSitesProvider.notifier).set(on),
    );
  }
}

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
