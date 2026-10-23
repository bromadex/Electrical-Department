import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../ui/bits.dart';

/// Placeholder for a tab whose feature is not built yet.
class ComingSoon extends StatelessWidget {
  const ComingSoon({
    super.key,
    required this.icon,
    required this.title,
    required this.phase,
    required this.description,
    this.highlights = const [],
  });

  final IconData icon;
  final String title;
  final String phase;
  final String description;
  final List<(IconData, String)> highlights;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: MediaQuery.paddingOf(context) + const EdgeInsets.all(Space.lg),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight:
                MediaQuery.sizeOf(context).height -
                MediaQuery.paddingOf(context).vertical -
                Space.lg * 2,
          ),
          child: Center(
            child: EmptyState(
              icon: icon,
              title: title,
              message: description,
              badge: phase,
              action: highlights.isEmpty
                  ? null
                  : Wrap(
                      spacing: Space.xs,
                      runSpacing: Space.xs,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final (i, l) in highlights)
                          Pill(label: l, icon: i),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
