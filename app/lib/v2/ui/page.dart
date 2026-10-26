import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Subtitle and actions above the page content. The title is shown once, by
/// the tab's top bar or the page's title bar ([title] is kept for callers).
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.scroll = true,
    this.maxWidth = 1480,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget child;

  /// False for pages that manage their own scrolling (e.g. tabs).
  final bool scroll;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = MediaQuery.sizeOf(context).width < Breakpoints.phone;
    final pad = phone ? Space.sm : Space.lg;

    final inset = MediaQuery.paddingOf(context);
    final hasHeader = subtitle != null || actions.isNotEmpty || leading != null;
    final header = Wrap(
      spacing: Space.sm,
      runSpacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        if (leading != null || subtitle != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: Space.xs),
              ],
              if (subtitle != null)
                Flexible(
                  child: Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        if (actions.isNotEmpty)
          Wrap(spacing: Space.xs, runSpacing: Space.xs, children: actions),
      ],
    );

    if (!scroll) {
      return Padding(
        padding: EdgeInsets.fromLTRB(pad, inset.top + pad, pad, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasHeader) ...[header, const SizedBox(height: Space.md)],
                Expanded(child: child),
                SizedBox(height: inset.bottom),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        pad,
        inset.top + pad,
        pad,
        inset.bottom + pad,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasHeader) ...[header, const SizedBox(height: Space.md)],
              child,
            ],
          ),
        ),
      ),
    );
  }
}
