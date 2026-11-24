import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/env.dart';

/// Checking for a newer Android app on GitHub Releases, where every release
/// is published (app.yml). The web app is always the latest, so only the
/// Android app checks.
///
/// Each release carries `latest.json` ({version, apk, notes}); the address
/// below always serves the newest one and is not rate-limited like the
/// GitHub API, which is the fallback for releases made before it existed.
class AppUpdate {
  static const repo = 'bromadex/Electrical-Department';
  static const latestJson =
      'https://github.com/$repo/releases/latest/download/latest.json';
  static const latestApi = 'https://api.github.com/repos/$repo/releases/latest';
  static const releasesPage = 'https://github.com/$repo/releases/latest';

  /// Only a released Android build (APP_VERSION set by the release) checks.
  static bool get supported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      parseVersion(Env.appVersion) != null;

  /// How often the app looks by itself while open.
  static const every = Duration(hours: 6);

  /// "Later" stops the pop-up for that version for this long.
  static const snooze = Duration(days: 1);
}

/// A published release.
class AppRelease {
  const AppRelease({required this.version, required this.apk, this.notes});

  /// Without the "v", e.g. 0.1.9.
  final String version;

  /// Where the APK downloads from.
  final String apk;

  /// What changed, one item per line (may be empty).
  final String? notes;

  static AppRelease? fromLatestJson(Map<String, dynamic> j) {
    final v = _bare('${j['version'] ?? ''}');
    final apk = '${j['apk'] ?? ''}';
    if (parseVersion(v) == null || !apk.startsWith('https://')) return null;
    final notes = '${j['notes'] ?? ''}'.trim();
    return AppRelease(
      version: v,
      apk: apk,
      notes: notes.isEmpty ? null : notes,
    );
  }

  /// From the GitHub API's latest release.
  static AppRelease? fromGitHub(Map<String, dynamic> j) {
    final v = _bare('${j['tag_name'] ?? ''}');
    if (parseVersion(v) == null) return null;
    String? apk;
    for (final a in (j['assets'] as List? ?? const [])) {
      final url = '${(a as Map)['browser_download_url'] ?? ''}';
      if (url.endsWith('.apk')) apk = url;
    }
    if (apk == null) return null;
    final body = '${j['body'] ?? ''}'.trim();
    return AppRelease(
      version: v,
      apk: apk,
      notes: body.isEmpty || body == j['tag_name'] ? null : body,
    );
  }

  static String _bare(String v) =>
      v.trim().startsWith('v') ? v.trim().substring(1) : v.trim();
}

/// 0.1.10 → [0, 1, 10]; null when it is not a version (e.g. "dev").
List<int>? parseVersion(String v) {
  final s = v.trim().startsWith('v') ? v.trim().substring(1) : v.trim();
  final parts = s.split('+').first.split('.');
  if (parts.isEmpty || parts.length > 4) return null;
  final out = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0) return null;
    out.add(n);
  }
  return out;
}

/// Whether [latest] is newer than [current] (0.1.10 is newer than 0.1.9).
bool isNewer(String latest, String current) {
  final a = parseVersion(latest), b = parseVersion(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 4; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// What the last check found.
class UpdateState {
  const UpdateState({
    this.checking = false,
    this.latest,
    this.checkedAt,
    this.failed = false,
  });

  final bool checking;
  final AppRelease? latest;
  final DateTime? checkedAt;

  /// The last check could not reach GitHub (no signal): try again later.
  final bool failed;

  /// A newer version than this one is out.
  AppRelease? get update {
    final l = latest;
    return l != null && isNewer(l.version, Env.appVersion) ? l : null;
  }
}

final appUpdateProvider = NotifierProvider<AppUpdateNotifier, UpdateState>(
  AppUpdateNotifier.new,
);

class AppUpdateNotifier extends Notifier<UpdateState> {
  @override
  UpdateState build() => const UpdateState();

  /// Looks for a newer release. With [quiet], skips when it looked in the
  /// last [AppUpdate.every].
  Future<AppRelease?> check({bool quiet = false}) async {
    if (!AppUpdate.supported || state.checking) return state.update;
    final last = state.checkedAt;
    if (quiet &&
        last != null &&
        !state.failed &&
        DateTime.now().difference(last) < AppUpdate.every) {
      return state.update;
    }
    state = UpdateState(
      checking: true,
      latest: state.latest,
      checkedAt: state.checkedAt,
    );
    AppRelease? found;
    var failed = false;
    try {
      found = await _fetch();
    } catch (e) {
      // No signal or GitHub is down: keep what we knew and try later.
      failed = true;
      debugPrint('Update check: $e');
    }
    state = UpdateState(
      latest: found ?? state.latest,
      checkedAt: DateTime.now(),
      failed: failed,
    );
    return state.update;
  }

  Future<AppRelease?> _fetch() async {
    const timeout = Duration(seconds: 15);
    final r = await http.get(Uri.parse(AppUpdate.latestJson)).timeout(timeout);
    if (r.statusCode == 200) {
      final j = jsonDecode(r.body);
      if (j is Map<String, dynamic>) {
        final rel = AppRelease.fromLatestJson(j);
        if (rel != null) return rel;
      }
    }
    // Releases from before latest.json existed.
    final g = await http
        .get(
          Uri.parse(AppUpdate.latestApi),
          headers: const {'Accept': 'application/vnd.github+json'},
        )
        .timeout(timeout);
    if (g.statusCode != 200) throw Exception('GitHub said ${g.statusCode}');
    final j = jsonDecode(g.body);
    return j is Map<String, dynamic> ? AppRelease.fromGitHub(j) : null;
  }
}

/// Downloads the new APK in the phone's browser; Android then offers to
/// install it over this one (same signing key, so data is kept).
Future<void> downloadUpdate(BuildContext context, AppRelease r) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await launchUrl(
    Uri.parse(r.apk),
    mode: LaunchMode.externalApplication,
  ).catchError((_) => false);
  if (!ok) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Could not open the download. Try again.')),
    );
    return;
  }
  messenger?.showSnackBar(
    const SnackBar(
      duration: Duration(seconds: 8),
      content: Text(
        'Downloading… When it finishes, tap the file and choose Install.',
      ),
    ),
  );
}

const _snoozeKey = 'update_snoozed';

/// Whether the pop-up for [version] was put off with "Later" recently.
bool updateSnoozed(SharedPreferences prefs, String version, DateTime now) {
  final s = prefs.getString(_snoozeKey);
  if (s == null) return false;
  final at = s.lastIndexOf('@');
  if (at < 0 || s.substring(0, at) != version) return false;
  final when = DateTime.tryParse(s.substring(at + 1));
  return when != null && now.difference(when) < AppUpdate.snooze;
}

Future<void> snoozeUpdate(SharedPreferences prefs, String version) =>
    prefs.setString(_snoozeKey, '$version@${DateTime.now().toIso8601String()}');

/// The "Update available" pop-up. Returns once it is closed.
Future<void> showUpdateDialog(
  BuildContext context,
  AppRelease r, {
  SharedPreferences? prefs,
}) async {
  final update = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        icon: const Icon(Icons.system_update_rounded),
        title: Text('Update available: v${r.version}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You have v${Env.appVersion}. The update keeps your sign-in '
                'and everything on this phone.',
                style: theme.textTheme.bodyMedium,
              ),
              if (r.notes != null) ...[
                const SizedBox(height: 12),
                Text("What's new", style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(r.notes!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Update'),
          ),
        ],
      );
    },
  );
  if (update == true) {
    if (context.mounted) await downloadUpdate(context, r);
  } else if (prefs != null) {
    await snoozeUpdate(prefs, r.version);
  }
}
