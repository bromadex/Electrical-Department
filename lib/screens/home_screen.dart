import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/brand_logo.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = Supabase.instance.client.auth;
    final email = auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Electrical Department'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: auth.signOut,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandLogo(width: 180),
              const SizedBox(height: 24),
              Text('Welcome', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(email, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
