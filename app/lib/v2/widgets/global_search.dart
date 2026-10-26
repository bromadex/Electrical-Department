import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/app_error.dart';
import '../../services/core_providers.dart';

/// One result from fn_search.
class SearchHit {
  const SearchHit(this.kind, this.id, this.ref, this.title, this.subtitle);

  factory SearchHit.fromRow(Map<String, dynamic> r) => SearchHit(
    r['kind'] as String,
    r['id'] as String,
    r['ref'] as String,
    r['title'] as String,
    r['subtitle'] as String? ?? '',
  );

  final String kind;
  final String id;
  final String ref;
  final String title;
  final String subtitle;

  String get route => switch (kind) {
    'job_card' => '/v2/job-cards/$ref',
    'asset' => '/assets/$id',
    _ => '/v2/requests/$id',
  };

  IconData get icon => switch (kind) {
    'job_card' => Icons.assignment_outlined,
    'asset' => Icons.precision_manufacturing_outlined,
    _ => Icons.move_to_inbox_outlined,
  };
}

Future<Iterable<Widget>> _suggestions(
  BuildContext context,
  WidgetRef ref,
  SearchController controller,
) async {
  final q = controller.text.trim();
  if (q.length < 2) {
    return const [
      ListTile(
        leading: Icon(Icons.info_outline_rounded),
        title: Text(
          'Search by job card number, equipment, asset ID, description, technician or requester',
        ),
      ),
    ];
  }
  try {
    final rows = await ref
        .read(supabaseProvider)
        .rpc('fn_search', params: {'p_query': q});
    final hits = [
      for (final r in rows as List)
        SearchHit.fromRow(Map<String, dynamic>.from(r)),
    ];
    if (hits.isEmpty) {
      return [ListTile(title: Text('Nothing found for "$q"'))];
    }
    return [
      for (final h in hits)
        ListTile(
          leading: Icon(h.icon),
          title: Text(
            '${h.ref} · ${h.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: h.subtitle.isEmpty
              ? null
              : Text(h.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () {
            controller.closeView(null);
            context.go(h.route);
          },
        ),
    ];
  } catch (e) {
    return [
      ListTile(
        leading: const Icon(Icons.error_outline_rounded),
        title: Text(AppError.from(e).message),
      ),
    ];
  }
}

/// Search box for the desktop and tablet top bar.
class GlobalSearchField extends ConsumerWidget {
  const GlobalSearchField({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SearchAnchor(
      viewHintText: 'Job card no., equipment, asset ID, fault…',
      builder: (context, controller) => SearchBar(
        controller: controller,
        hintText: 'Search job cards, equipment, requests',
        leading: const Icon(Icons.search_rounded),
        elevation: const WidgetStatePropertyAll(0),
        constraints: const BoxConstraints(minHeight: 40, maxHeight: 40),
        side: WidgetStatePropertyAll(
          BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
        ),
        onTap: controller.openView,
        onChanged: (_) => controller.openView(),
      ),
      suggestionsBuilder: (context, controller) =>
          _suggestions(context, ref, controller),
    );
  }
}

/// Search icon for the phone top bar.
class GlobalSearchButton extends ConsumerWidget {
  const GlobalSearchButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SearchAnchor(
      viewHintText: 'Job card no., equipment, asset ID, fault…',
      builder: (context, controller) => IconButton(
        tooltip: 'Search',
        icon: const Icon(Icons.search_rounded),
        onPressed: controller.openView,
      ),
      suggestionsBuilder: (context, controller) =>
          _suggestions(context, ref, controller),
    );
  }
}
