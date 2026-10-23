import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local_db.dart';
import 'notifications_controller.dart';
import 'outbox_service.dart';
import 'session_controller.dart';

/// Overridden in `main()` once Supabase is initialised.
final supabaseProvider = Provider<SupabaseClient>(
  (ref) => throw UnimplementedError('supabaseProvider must be overridden'),
);

/// Overridden in `main()`; tests pass an in-memory database.
final localDbProvider = Provider<LocalDb>(
  (ref) => throw UnimplementedError('localDbProvider must be overridden'),
);

final outboxProvider = Provider<OutboxService>((ref) {
  final client = ref.watch(supabaseProvider);
  return OutboxService(
    ref.watch(localDbProvider),
    (fn, params) => client.rpc(fn, params: params),
    (bucket, path, bytes, contentType) async {
      try {
        await client.storage
            .from(bucket)
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: contentType),
            );
      } on StorageException catch (e) {
        // Already uploaded on an earlier try whose reply was lost.
        if (e.statusCode == '409' || e.message.contains('already exists')) {
          return;
        }
        rethrow;
      }
    },
  );
});

/// The signed-in user's id, or null when signed out.
final authUserIdProvider = NotifierProvider<AuthUserIdNotifier, String?>(
  AuthUserIdNotifier.new,
);

class AuthUserIdNotifier extends Notifier<String?> {
  @override
  String? build() {
    final auth = ref.watch(supabaseProvider).auth;
    final sub = auth.onAuthStateChange.listen((s) {
      state = s.session?.user.id;
    });
    ref.onDispose(sub.cancel);
    return auth.currentUser?.id;
  }

  /// Sends queued changes first so nothing is lost, then signs out.
  Future<void> signOut() async {
    await ref.read(outboxProvider).flush();
    await ref.read(supabaseProvider).auth.signOut();
  }
}

/// Keeps data fresh while the app runs: retries the outbox every 30 seconds
/// and refreshes everything when the app comes back to the foreground.
final syncProvider = Provider<void>((ref) {
  void flush() => unawaited(ref.read(outboxProvider).flush());

  final timer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
  final lifecycle = AppLifecycleListener(
    onResume: () {
      if (ref.read(authUserIdProvider) == null) return;
      flush();
      unawaited(ref.read(sessionProvider.notifier).refresh());
      unawaited(ref.read(notificationsProvider.notifier).refresh());
    },
  );
  ref.onDispose(() {
    timer.cancel();
    lifecycle.dispose();
  });
});
