import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/core_providers.dart';

/// Everyone's profile photo as a signed link, by user id (migration 0050,
/// the private avatars bucket). Refreshed every 50 minutes, before the
/// links expire, and after you change your own.
final avatarUrlsProvider = FutureProvider<Map<String, String>>((ref) async {
  ref.watch(authUserIdProvider);
  final db = ref.read(supabaseProvider);
  final t = Timer(const Duration(minutes: 50), ref.invalidateSelf);
  ref.onDispose(t.cancel);
  try {
    final rows = await db
        .from('profiles')
        .select('id, avatar_url')
        .not('avatar_url', 'is', null);
    final byPath = {
      for (final r in rows) r['avatar_url'] as String: r['id'] as String,
    };
    if (byPath.isEmpty) return const {};
    final signed = await db.storage
        .from('avatars')
        .createSignedUrlsResult(byPath.keys.toList(), 3600);
    return {
      for (final s in signed.whereType<SignedUrlSuccess>())
        if (byPath[s.path] != null) byPath[s.path]!: s.signedUrl,
    };
  } catch (_) {
    return const {};
  }
});
