import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/env.dart';
import 'data/local_db.dart';
import 'router.dart';
import 'screens/setup_required_screen.dart';
import 'services/core_providers.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.hasSupabase) {
    runApp(const _Shell(home: SetupRequiredScreen()));
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );
  runApp(
    ProviderScope(
      overrides: [
        supabaseProvider.overrideWithValue(Supabase.instance.client),
        localDbProvider.overrideWithValue(LocalDb()),
      ],
      child: const ElectricalDepartmentApp(),
    ),
  );
}

class ElectricalDepartmentApp extends ConsumerStatefulWidget {
  const ElectricalDepartmentApp({super.key});

  @override
  ConsumerState<ElectricalDepartmentApp> createState() =>
      _ElectricalDepartmentAppState();
}

class _ElectricalDepartmentAppState
    extends ConsumerState<ElectricalDepartmentApp> {
  late final GoRouter _router = buildRouter(ref);

  @override
  Widget build(BuildContext context) {
    ref.watch(syncProvider);
    return MaterialApp.router(
      title: 'Bravura Electrical',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: _router,
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bravura Electrical',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: home,
    );
  }
}
