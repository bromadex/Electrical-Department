import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local_db.dart';
import 'notifications_controller.dart';
import 'outbox_service.dart';
import 'session_controller.dart';

/// Creates the app's services and starts or stops them as the user signs
/// in and out.
class AppServices {
  AppServices(this.client, this.db)
    : outbox = OutboxService(
        db,
        (fn, params) => client.rpc(fn, params: params),
      ) {
    session = SessionController(client, db);
    notifications = NotificationsController(client, outbox);
  }

  static const _flushEvery = Duration(seconds: 30);

  final SupabaseClient client;
  final LocalDb db;
  final OutboxService outbox;
  late final SessionController session;
  late final NotificationsController notifications;

  StreamSubscription<AuthState>? _authSub;
  AppLifecycleListener? _lifecycle;
  Timer? _timer;
  String? _userId;

  void start() {
    _authSub = client.auth.onAuthStateChange.listen((state) {
      _onUser(state.session?.user.id);
    });
    _lifecycle = AppLifecycleListener(onResume: _sync);
    _timer = Timer.periodic(_flushEvery, (_) => outbox.flush());
    _onUser(client.auth.currentUser?.id);
  }

  Future<void> signOut() async {
    await outbox.flush();
    await client.auth.signOut();
  }

  void _onUser(String? userId) {
    if (userId == _userId) return;
    _userId = userId;
    if (userId == null) {
      unawaited(notifications.stop());
      unawaited(session.clear());
    } else {
      unawaited(session.load());
      unawaited(notifications.start(userId));
      unawaited(outbox.flush());
    }
  }

  void _sync() {
    if (_userId == null) return;
    unawaited(outbox.flush());
    unawaited(session.refresh());
    unawaited(notifications.refresh());
  }

  void dispose() {
    _authSub?.cancel();
    _lifecycle?.dispose();
    _timer?.cancel();
  }
}

/// Makes [AppServices] available to the widget tree.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
