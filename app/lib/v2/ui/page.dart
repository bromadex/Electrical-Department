import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Page title, subtitle and actions above the page content.
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

    final header = Wrap(
      spacing: Space.sm,
      runSpacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: Space.xs)],
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: phone
                        ? theme.textTheme.titleLarge
                        : theme.textTheme.headlineSmall,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
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
        padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: Space.md),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: Space.md),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
