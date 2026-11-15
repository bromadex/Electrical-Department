import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:floating/floating.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/env.dart';
import 'data/local_db.dart';
import 'chat/call_bar.dart';
import 'chat/call_controller.dart';
import 'router.dart';
import 'screens/setup_required_screen.dart';
import 'services/core_providers.dart';
import 'services/error_reporter.dart';
import 'services/incoming_calls.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Acceptance test builds (--dart-define=E2E=true) keep the accessibility
  // tree on, which is what the browser tests in e2e/ read and click.
  if (const bool.fromEnvironment('E2E')) {
    SemanticsBinding.instance.ensureSemantics();
  }

  if (!Env.hasSupabase) {
    runApp(const _Shell(home: SetupRequiredScreen()));
    return;
  }

  final (_, prefs, _) = await (
    Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    ),
    SharedPreferences.getInstance(),
    PushSupport.init(),
  ).wait;
  if (PushSupport.ready && IncomingCalls.supported) {
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessage);
  }
  // Errors go to the admins' App errors screen as well as the console.
  final reporter = ErrorReporter(Supabase.instance.client);
  final showError = FlutterError.onError;
  FlutterError.onError = (details) {
    showError?.call(details);
    reporter.report(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    reporter.report(error, stack);
    return false;
  };
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
  StreamSubscription<RemoteMessage>? _opened;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<Object?>? _answered;

  /// "Last seen": tells the server when the app goes to the background.
  AppLifecycleListener? _life;

  void _seen() {
    final db = ref.read(supabaseProvider);
    if (db.auth.currentUser == null) return;
    unawaited(db.rpc('fn_seen').then((_) {}, onError: (_) {}));
  }

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onHide: _seen, onDetach: _seen);
    ErrorReporter.currentRoute = () =>
        _router.routerDelegate.currentConfiguration.uri.toString();
    if (PushSupport.ready) {
      // A tapped push opens its job or chat, whether the app was in the
      // background or closed.
      _opened = FirebaseMessaging.onMessageOpenedApp.listen(_open);
      FirebaseMessaging.instance.getInitialMessage().then((m) {
        if (m != null) _open(m);
      });
      if (IncomingCalls.supported) {
        // A call while the app is open rings the same way.
        _foreground = FirebaseMessaging.onMessage.listen((m) {
          if (m.data['kind'] == 'call') IncomingCalls.ring(m.data);
        });
        _answered = IncomingCalls.listen(_router.push);
        IncomingCalls.askPermissions();
      }
    }
  }

  @override
  void dispose() {
    _opened?.cancel();
    _foreground?.cancel();
    _answered?.cancel();
    _life?.dispose();
    super.dispose();
  }

  void _open(RemoteMessage m) {
    final path = notificationPath(m.data['link'] as String?);
    if (path != null) _router.push(path);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(syncProvider);
    return MaterialApp.router(
      title: 'Bravura Electrical',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      themeAnimationDuration: const Duration(milliseconds: 400),
      routerConfig: _router,
      scrollBehavior: const _IosScrollBehavior(),
      // Acceptance test builds run as if the device asked for reduced motion:
      // the moving wallpaper behind the glass is redrawn every frame, which a
      // headless browser without a graphics card cannot keep up with.
      scaffoldMessengerKey: appMessenger,
      // The "return to call" bar while a call is minimised.
      builder: (context, child) {
        Widget app = CallBar(router: _router, child: child!);
        // Leaving the app during a call shows it in a small window.
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          app = PiPSwitcher(
            childWhenDisabled: app,
            childWhenEnabled: const CallPipView(),
          );
        }
        return const bool.fromEnvironment('E2E')
            ? MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: app,
              )
            : app;
      },
    );
  }
}

/// Bouncy, iPhone-like scrolling everywhere, and drag-to-scroll with a
/// mouse on the web.
class _IosScrollBehavior extends MaterialScrollBehavior {
  const _IosScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
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
