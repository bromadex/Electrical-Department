import 'package:flutter/material.dart';

import '../services/app_services.dart';
import '../widgets/brand_logo.dart';
import '../widgets/notifications_button.dart';
import '../widgets/sync_banner.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final session = services.session;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Electrical Department'),
        actions: [
          const NotificationsButton(),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: services.signOut,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) => RefreshIndicator(
          onRefresh: session.refresh,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const SyncBanner(),
              if (session.error != null)
                MaterialBanner(
                  leading: const Icon(Icons.wifi_off),
                  content: Text(
                    session.profile == null
                        ? session.error!.message
                        : 'Showing saved data. ${session.error!.message}',
                  ),
                  actions: [
                    TextButton(
                      onPressed: session.refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: _body(context, services),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppServices services) {
    final session = services.session;
    final theme = Theme.of(context);
    final profile = session.profile;

    if (profile == null) {
      if (session.loading || !session.refreshed) {
        return const Padding(
          padding: EdgeInsets.only(top: 80),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return const _Message(
        icon: Icons.person_off_outlined,
        title: 'Account not active',
        body:
            'Your account is not active or has not been set up yet. '
            'Ask an admin to activate it and give you a role.',
      );
    }

    final homeSite = session.siteById(profile.homeSiteId);
    final name = profile.fullName.isEmpty
        ? services.client.auth.currentUser?.email ?? ''
        : profile.fullName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: BrandLogo(width: 140)),
        const SizedBox(height: 16),
        Text(
          'Welcome, $name',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        if (homeSite != null)
          Text(
            'Home site: ${homeSite.name}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        const SizedBox(height: 24),
        if (session.permissions.isEmpty)
          const _Message(
            icon: Icons.lock_outline,
            title: 'No role yet',
            body: 'Ask an admin to give you a role so you can start working.',
          )
        else ...[
          Text('Your sites', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final site in session.activeSites)
            if (session.can('jobs.view', siteId: site.id) ||
                session.can('store.view', siteId: site.id) ||
                session.can('docs.view', siteId: site.id))
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text(site.code)),
                  title: Text(site.name),
                  subtitle: Text(
                    '${session.areas.where((a) => a.siteId == site.id && !a.isArchived).length} areas',
                  ),
                ),
              ),
          const SizedBox(height: 16),
          Text(
            'Jobs, checklists, tools and the store will appear here as each '
            'feature is built.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
