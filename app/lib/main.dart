import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/env.dart';
import 'data/local_db.dart';
import 'router.dart';
import 'screens/setup_required_screen.dart';
import 'services/core_providers.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode.dart';
import 'ui/format.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Acceptance test builds (--dart-define=E2E=true) keep the accessibility
  // tree on, which is what the browser tests in e2e/ read and click.
  if (const bool.fromEnvironment('E2E')) {
    SemanticsBinding.instance.ensureSemantics();
  }
  // Until system_settings loads, show times in the default site zone.
  SiteTime.configure('Africa/Harare');

  if (!Env.hasSupabase) {
    runApp(const _Shell(home: SetupRequiredScreen()));
    return;
  }

  final (_, prefs) = await (
    Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    ),
    SharedPreferences.getInstance(),
  ).wait;
  runApp(
    ProviderScope(
      overrides: [
        supabaseProvider.overrideWithValue(Supabase.instance.client),
        localDbProvider.overrideWithValue(LocalDb()),
        sharedPrefsProvider.overrideWithValue(prefs),
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
      themeMode: ref.watch(themeModeProvider),
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
