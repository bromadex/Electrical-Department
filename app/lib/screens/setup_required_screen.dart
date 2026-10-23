import 'package:flutter/material.dart';

import '../widgets/brand_logo.dart';

/// Shown when the app was built without Supabase settings.
class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandLogo(width: 180),
                const SizedBox(height: 24),
                Text('Setup required', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                  'This build has no Supabase settings. Set SUPABASE_URL and '
                  'SUPABASE_ANON_KEY (as --dart-define values locally, or as '
                  'environment variables on Vercel) and rebuild.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
