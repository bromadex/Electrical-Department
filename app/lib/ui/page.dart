import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Scrollable page body that clears the shell's top and bottom bars and
/// keeps content to a readable width on desktop.
class PageScroll extends StatelessWidget {
  const PageScroll({
    super.key,
    required this.children,
    this.maxWidth = 960,
    this.onRefresh,
  });

  final List<Widget> children;
  final double maxWidth;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context);
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        Space.md,
        inset.top + Space.xs,
        Space.md,
        inset.bottom + Space.lg,
      ),
      children: [
        for (final c in children)
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: c,
            ),
          ),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(
      onRefresh: onRefresh!,
      edgeOffset: inset.top,
      child: list,
    );
  }
}

/// The Africa/Harare clock (UTC+2, no daylight saving) used for "today".
DateTime harareNow() => DateTime.now().toUtc().add(const Duration(hours: 2));
