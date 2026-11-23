import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_error.dart';
import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../ui/surfaces.dart';
import '../widgets/brand_logo.dart';
import '../widgets/sign_out.dart';

/// Whether the signed-in person still has the temporary password an admin
/// set (user metadata must_change_password, set by the admin-users
/// function when it creates an account or resets a password).
bool mustChangePassword(User? user) =>
    user?.userMetadata?['must_change_password'] == true || cameByEmailLink;

/// Whether the app was opened from an emailed invitation or password-reset
/// link (Supabase adds `type=invite` or `type=recovery` to the address).
/// Such a person is signed in but has no password yet: they choose one
/// first. Read once in main() before the address is tidied up.
bool cameByEmailLink = false;

/// Why an emailed link could not sign you in (it expired or was already
/// used), shown on the sign-in page; null when there was no such link.
String? emailLinkProblem;

/// The problem Supabase put in the address of a failed email link.
String? emailLinkError(Uri uri) {
  final f = uri.fragment.startsWith('/')
      ? uri.fragment.substring(1)
      : uri.fragment;
  Map<String, String> p;
  try {
    p = {...Uri.splitQueryString(uri.query), ...Uri.splitQueryString(f)};
  } catch (_) {
    return null;
  }
  if (p['error'] == null && p['error_code'] == null) return null;
  if (p['error_code'] == 'otp_expired') {
    return 'That email link has expired or was already used. Ask an admin '
        'to send a new invitation, or sign in if you have a password.';
  }
  return p['error_description'] ?? 'That email link did not work.';
}

/// Whether [uri] is an invitation or password-reset link.
bool isEmailLink(Uri uri) {
  final parts = '${uri.fragment}&${uri.query}'.split(RegExp('[&#?]'));
  return parts.contains('type=invite') || parts.contains('type=recovery');
}

/// Shown instead of the app until someone with a temporary password chooses
/// their own. There is no way past it except changing the password or
/// signing out.
class FirstPasswordScreen extends ConsumerStatefulWidget {
  const FirstPasswordScreen({super.key});

  @override
  ConsumerState<FirstPasswordScreen> createState() =>
      _FirstPasswordScreenState();
}

class _FirstPasswordScreenState extends ConsumerState<FirstPasswordScreen> {
  final _new = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _new.dispose();
    _again.dispose();
    super.dispose();
  }

  static String? problem(String password, String again, String? email) =>
      FirstPasswordScreenRules.problem(password, again, email);

  Future<void> _save() async {
    final auth = ref.read(supabaseProvider).auth;
    final issue = problem(_new.text, _again.text, auth.currentUser?.email);
    if (issue != null) {
      setState(() => _error = issue);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final wasLink = cameByEmailLink;
    try {
      // Changing the password and clearing the flag in one call; the
      // router lets the person in as soon as the user is updated.
      // Cleared first: the router re-checks as soon as the user updates.
      cameByEmailLink = false;
      await auth.updateUser(
        UserAttributes(
          password: _new.text,
          data: {'must_change_password': false},
        ),
      );
    } catch (e) {
      cameByEmailLink = wasLink;
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is AuthException
              ? (e.message.toLowerCase().contains('same')
                    ? 'Choose a password different from the temporary one'
                    : e.message)
              : AppError.from(e).message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(supabaseProvider).auth.currentUser;
    final name = '${user?.userMetadata?['full_name'] ?? ''}'.trim();
    InputDecoration field(String label) => InputDecoration(
      labelText: label,
      suffixIcon: IconButton(
        tooltip: _show ? 'Hide' : 'Show',
        icon: Icon(_show ? CupertinoIcons.eye_slash : CupertinoIcons.eye),
        onPressed: () => setState(() => _show = !_show),
      ),
    );
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: MeshBackground(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Space.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: GlassSurface(
                    padding: const EdgeInsets.all(Space.lg + 4),
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Center(child: BrandLogo(width: 140)),
                          const SizedBox(height: Space.md),
                          Text(
                            name.isEmpty
                                ? 'Choose your password'
                                : 'Welcome, ${name.split(' ').first}',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: Space.xs),
                          Text(
                            '${cameByEmailLink ? 'You opened your email link.' : 'You signed in with a temporary password.'} '
                            'Choose your own to continue: at least 8 '
                            'characters, with letters and a number. Only you '
                            'will know it.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: Space.md),
                          TextField(
                            controller: _new,
                            obscureText: !_show,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: field('New password'),
                          ),
                          const SizedBox(height: Space.sm),
                          TextField(
                            controller: _again,
                            obscureText: !_show,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: field('New password again'),
                            onSubmitted: (_) => _save(),
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: Space.sm),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          const SizedBox(height: Space.lg),
                          FilledButton(
                            onPressed: _busy ? null : _save,
                            child: Text(
                              _busy ? 'Saving…' : 'Save and continue',
                            ),
                          ),
                          const SizedBox(height: Space.xs),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => signOutWithCheck(context, ref),
                            child: const Text('Sign out'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The rules for a new password; null when it is fine.
class FirstPasswordScreenRules {
  static String? problem(String password, String again, String? email) {
    if (password.length < 8) return 'Use at least 8 characters';
    if (password.length > 72) return 'Use at most 72 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return 'Use letters and at least one number';
    }
    if (email != null &&
        email.contains('@') &&
        password.toLowerCase().contains(email.split('@').first.toLowerCase())) {
      return 'Do not use your email name in the password';
    }
    if (password != again) return 'The two passwords are different';
    return null;
  }
}
