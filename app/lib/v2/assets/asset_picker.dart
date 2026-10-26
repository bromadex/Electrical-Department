import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.dart';
import '../ui/bits.dart';
import 'models.dart';
import 'repository.dart';

/// Picks registered equipment at a site; clearing it leaves the equipment
/// to be typed in by hand.
class AssetPickerField extends StatelessWidget {
  const AssetPickerField({
    super.key,
    required this.siteId,
    required this.value,
    required this.onChanged,
    this.label = 'Equipment from the asset register',
  });

  final String siteId;
  final Asset? value;
  final ValueChanged<Asset?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.sm),
      onTap: () async {
        final picked = await showDialog<Asset>(
          context: context,
          builder: (_) => _AssetSearchDialog(siteId: siteId),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.precision_manufacturing_outlined),
          suffixIcon: value == null
              ? const Icon(Icons.search_rounded)
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => onChanged(null),
                ),
        ),
        child: Text(
          value?.label ?? 'Search the register…',
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _AssetSearchDialog extends ConsumerStatefulWidget {
  const _AssetSearchDialog({required this.siteId});

  final String siteId;

  @override
  ConsumerState<_AssetSearchDialog> createState() => _AssetSearchDialogState();
}

class _AssetSearchDialogState extends ConsumerState<_AssetSearchDialog> {
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(assetLookupProvider((widget.siteId, _query)));
    return AlertDialog(
      title: const Text('Choose equipment'),
      contentPadding: const EdgeInsets.fromLTRB(
        Space.md,
        Space.sm,
        Space.md,
        0,
      ),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Asset number, name or location',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () {
                  if (mounted) setState(() => _query = v.trim());
                });
              },
            ),
            const SizedBox(height: Space.xs),
            Expanded(
              child: AsyncView(
                value: results,
                onRetry: () => ref.invalidate(
                  assetLookupProvider((widget.siteId, _query)),
                ),
                data: (assets) => assets.isEmpty
                    ? const EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No equipment found',
                        message: 'Close this and type the equipment details by hand.',
                      )
                    : ListView.separated(
                        itemCount: assets.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final a = assets[i];
                          return ListTile(
                            title: Text(a.name),
                            subtitle: Text(
                              [
                                a.assetNo,
                                a.areaName ?? a.location,
                                a.categoryName,
                              ].whereType<String>().join(' · '),
                            ),
                            onTap: () => Navigator.pop(context, a),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
