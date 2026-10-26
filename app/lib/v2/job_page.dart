import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'reference/reference_data.dart';

/// Frame for a job card screen opened on top of the tabs: the main app's
/// glass title bar with a back button that always works.
class JobPage extends ConsumerWidget {
  const JobPage({
    super.key,
    required this.title,
    required this.child,
    this.fallback = '/jobs',
  });

  final String title;
  final Widget child;

  /// Where Back goes when the page was opened from a link.
  final String fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lists, settings and the site time zone the job card screens rely on.
    ref.watch(referenceDataProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: AppBackButton(fallback: fallback),
        title: Text(title),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(child: child),
    );
  }
}
