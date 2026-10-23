import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/env.dart';
import '../services/core_providers.dart';
import '../services/notifications_controller.dart';
import '../services/session_controller.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final unread = ref.watch(notificationsProvider.select((s) => s.unread));
    final profile = session.profile;
    final email = ref.read(supabaseProvider).auth.currentUser?.email ?? '';
    final homeSite = session.siteById(profile?.homeSiteId);
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: ref.read(sessionProvider.notifier).refresh,
      child: ListView(
        children: [
          ListTile(
            leading: CircleAvatar(
              child: Text(_initials(profile?.fullName ?? email)),
            ),
            title: Text(
              (profile?.fullName.isNotEmpty ?? false)
                  ? profile!.fullName
                  : email,
            ),
            subtitle: Text(
              [
                email,
                if (homeSite != null) 'Home site: ${homeSite.name}',
              ].join('\n'),
            ),
            isThreeLine: homeSite != null,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            trailing: unread > 0 ? Badge(label: Text('$unread')) : null,
            onTap: () => context.push('/notifications'),
          ),
          ExpansionTile(
            leading: const Icon(Icons.location_city_outlined),
            title: const Text('My sites'),
            children: [
              for (final site in session.mySites)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text(
                      site.code,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                  title: Text(site.name),
                  subtitle: Text('${session.areasAt(site.id).length} areas'),
                ),
            ],
          ),
          ExpansionTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('My permissions'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final code in session.perms.codes.toList()..sort())
                      Chip(
                        label: Text(code),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => ref.read(authUserIdProvider.notifier).signOut(),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Bravura Electrical · ${Env.flavor}',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'[\s@.]+'));
    return parts.take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
  }
}
