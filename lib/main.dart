import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/env.dart';
import 'data/local_db.dart';
import 'router.dart';
import 'screens/setup_required_screen.dart';
import 'services/app_services.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.hasSupabase) {
    runApp(const _Shell(child: SetupRequiredScreen()));
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );
  final services = AppServices(Supabase.instance.client, LocalDb())..start();
  runApp(ElectricalDepartmentApp(services: services));
}

class ElectricalDepartmentApp extends StatefulWidget {
  const ElectricalDepartmentApp({super.key, required this.services});

  final AppServices services;

  @override
  State<ElectricalDepartmentApp> createState() =>
      _ElectricalDepartmentAppState();
}

class _ElectricalDepartmentAppState extends State<ElectricalDepartmentApp> {
  late final _router = buildRouter(widget.services.client.auth);

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: widget.services,
      child: MaterialApp.router(
        title: 'Bravura Electrical',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        routerConfig: _router,
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bravura Electrical',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: child,
    );
  }
}
