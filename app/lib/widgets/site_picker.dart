import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_db.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/motion.dart';

/// "Site: All ▾" inside a page: filters the page's list to one site, or
/// shows every site (the default). The choice carries to the other pages
/// until you change it. Hidden when there is only one site.
///
/// A page that needs one site (the roster) passes [value] and [onChanged]
/// with [allowAll] off, and keeps the choice itself.
class SiteFilterChip extends ConsumerWidget {
  const SiteFilterChip({
    super.key,
    this.value,
    this.onChanged,
    this.allowAll = true,
  });

  final String? value;
  final ValueChanged<String?>? onChanged;
  final bool allowAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sites = ref.watch(sessionProvider.select((s) => s.mySites));
    if (sites.length < 2) return const SizedBox.shrink();
    final id = onChanged != null ? value : ref.watch(siteFilterProvider);
    LocalSite? picked;
    for (final s in sites) {
      if (s.id == id) picked = s;
    }
    final narrow = MediaQuery.sizeOf(context).width < 380;
    return FilterChip(
      avatar: Icon(
        picked == null ? Icons.public_rounded : Icons.place_rounded,
        size: 18,
      ),
      label: Text(
        picked == null ? 'All sites' : (narrow ? picked.code : picked.name),
      ),
      selected: picked != null,
      showCheckmark: false,
      onSelected: (_) => _open(context, ref),
      deleteIcon: const Icon(Icons.expand_more_rounded, size: 18),
      onDeleted: () => _open(context, ref),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final theme = Theme.of(context);
          final session = ref.watch(sessionProvider);
          final current = onChanged != null
              ? value
              : ref.watch(siteFilterProvider);
          void pick(String? id) {
            if (onChanged != null) {
              onChanged!(id);
            } else {
              ref.read(siteFilterProvider.notifier).set(id);
            }
            Navigator.pop(context);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: Space.sm),
                  child: Text('Show', style: theme.textTheme.titleLarge),
                ),
                if (allowAll)
                  _SiteRow(
                    code: 'ALL',
                    name: 'All sites',
                    detail: 'Everything, from every site',
                    selected: current == null,
                    onTap: () => pick(null),
                  ).entrance(context, index: 0),
                for (final (i, s) in session.mySites.indexed)
                  _SiteRow(
                    code: s.code,
                    name: s.name,
                    detail: session.areasAt(s.id).length == 1
                        ? '1 area'
                        : '${session.areasAt(s.id).length} areas',
                    selected: s.id == current,
                    onTap: () => pick(s.id),
                  ).entrance(context, index: i + 1),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SiteRow extends StatelessWidget {
  const _SiteRow({
    required this.code,
    required this.name,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final String name;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.1)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.md),
        child: ListTile(
          onTap: onTap,
          leading: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? scheme.primary : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Text(
              code,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
          ),
          title: Text(name, style: theme.textTheme.titleMedium),
          subtitle: Text(detail),
          trailing: AnimatedScale(
            scale: selected ? 1 : 0,
            duration: Motion.of(context, Motion.medium),
            curve: Motion.spring,
            child: Icon(Icons.check_circle_rounded, color: scheme.primary),
          ),
        ),
      ),
    );
  }
}

/// The "Site" field in forms that create something: every site, starting at
/// [value]. Hidden when there is only one site.
class SiteField extends ConsumerWidget {
  const SiteField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Site',
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sites = ref.watch(sessionProvider.select((s) => s.mySites));
    if (sites.length < 2) return const SizedBox.shrink();
    return DropdownButtonFormField<String>(
      initialValue: sites.any((s) => s.id == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.place_rounded),
      ),
      items: [
        for (final s in sites)
          DropdownMenuItem(value: s.id, child: Text('${s.name} (${s.code})')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
