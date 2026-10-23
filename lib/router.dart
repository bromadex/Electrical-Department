import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

GoRouter buildRouter(GoTrueClient auth) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthChanges(auth.onAuthStateChange),
    redirect: (context, state) {
      final signedIn = auth.currentSession != null;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn) return atLogin ? null : '/login';
      if (atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    ],
  );
}

/// Re-runs the router redirect whenever the Supabase session changes.
class _AuthChanges extends ChangeNotifier {
  _AuthChanges(Stream<AuthState> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
