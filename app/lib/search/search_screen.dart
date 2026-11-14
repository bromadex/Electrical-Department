import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../chat/chat_repository.dart' show recordSearchProvider;
import '../data/app_error.dart';
import '../services/push_service.dart' show notificationPath;
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';

/// Search every record by code or name: job cards, equipment, tools,
/// documents, inventory, projects, material requests and purchases, at
/// every site the person may see (issue #36). Needs signal.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _query = '';
  Timer? _typing;

  @override
  void dispose() {
    _typing?.cancel();
    super.dispose();
  }

  void _changed(String v) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 350), () {
      if (mounted && v.trim() != _query) setState(() => _query = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final hits = _query.length < 2
        ? null
        : ref.watch(recordSearchProvider(_query));
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/home'),
        title: const Text('Search'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            Space.md,
            top + Space.md,
            Space.md,
            Space.xl,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CupertinoSearchTextField(
                      autofocus: true,
                      placeholder:
                          'Code or name, e.g. EL-JC-2026-0042, GEN-03, cable',
                      onChanged: _changed,
                      onSubmitted: (v) => setState(() => _query = v.trim()),
                    ),
                    const SizedBox(height: Space.md),
                    if (hits == null)
                      Text(
                        'Finds job cards, equipment, tools, documents, '
                        'inventory, projects, material requests and '
                        'purchases at every site.',
                        style: theme.textTheme.labelMedium,
                      )
                    else
                      ...hits.when(
                        loading: () => [
                          const Center(child: CircularProgressIndicator()),
                        ],
                        error: (e, _) => [
                          EmptyState(
                            icon: CupertinoIcons.wifi_slash,
                            title: 'Could not search',
                            message: AppError.from(e).message,
                          ),
                        ],
                        data: (list) => [
                          if (list.isEmpty)
                            EmptyState(
                              icon: CupertinoIcons.search,
                              title: 'Nothing matches "$_query"',
                              message: 'Try part of the code or the name.',
                            ),
                          for (final h in list)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.xs),
                              child: SurfaceCard(
                                onTap: () {
                                  final path = notificationPath(h.link);
                                  if (path != null) context.push(path);
                                },
                                child: Row(
                                  children: [
                                    Icon(
                                      searchIcon(h.link),
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: Space.sm),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            h.title,
                                            style: theme.textTheme.titleSmall,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            [
                                              h.code,
                                              if (h.status.isNotEmpty) h.status,
                                            ].join(' · '),
                                            style: theme.textTheme.labelSmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (h.siteCode.isNotEmpty)
                                      Pill(label: h.siteCode, dense: true),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The icon for a search result's kind of record.
IconData searchIcon(String link) => switch (link.split(':').first) {
  'jobcard' => CupertinoIcons.doc_text_fill,
  'asset' => Icons.electrical_services_rounded,
  'tool' => CupertinoIcons.wrench_fill,
  'doc' => CupertinoIcons.book_fill,
  'item' => CupertinoIcons.cube_box_fill,
  'project' => CupertinoIcons.briefcase_fill,
  'mr' => CupertinoIcons.cart_fill,
  'po' => CupertinoIcons.doc_plaintext,
  _ => CupertinoIcons.tag_fill,
};
