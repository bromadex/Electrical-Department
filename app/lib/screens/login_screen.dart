import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../widgets/brand_logo.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await ref
          .read(supabaseProvider)
          .auth
          .signInWithPassword(
            email: _email.text.trim(),
            password: _password.text,
          );
    } on AuthException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not sign in. Check your connection.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.desktop;

    final form = Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!wide) ...[
              const Center(child: BrandLogo(width: 140)),
              const SizedBox(height: Space.lg),
            ],
            Text('Sign in', style: theme.textTheme.headlineSmall),
            const SizedBox(height: Space.xxs),
            Text(
              'Electrical Department job cards and maintenance',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'Enter a valid email'
                  : null,
            ),
            const SizedBox(height: Space.sm),
            TextFormField(
              controller: _password,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _signIn(),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Enter your password' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.sm),
              Container(
                padding: const EdgeInsets.all(Space.sm),
                decoration: BoxDecoration(
                  color: AppColors.critical.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.critical,
                      size: 20,
                    ),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.critical),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: Space.lg),
            FilledButton(
              onPressed: _busy ? null : _signIn,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Sign in'),
            ),
            const SizedBox(height: Space.md),
            Text(
              'Forgot your password? Ask a system administrator to set a temporary one.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );

    final card = Card(
      child: Padding(padding: const EdgeInsets.all(Space.lg), child: form),
    );

    if (!wide) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: card,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          const Expanded(flex: 5, child: _BrandPanel()),
          Expanded(
            flex: 6,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Space.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: card,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Navy brand panel on the left of wide screens.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const muted = AppColors.rose;
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
          Icon(icon, color: muted, size: 20),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    return ColoredBox(
      color: AppColors.burgundyDeep,
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: const BrandLogo(width: 150),
            ),
            const SizedBox(height: Space.xl),
            Text(
              'Electrical Department',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Job Card & Maintenance Management',
              style: theme.textTheme.titleMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: Space.xl),
            point(
              Icons.assignment_outlined,
              'Every fault registered, numbered and timed',
            ),
            point(
              Icons.engineering_outlined,
              'Assessed, assigned and tracked to closure',
            ),
            point(
              Icons.fact_check_outlined,
              'Closed only after engineering review',
            ),
            point(Icons.insights_outlined, 'Live dashboard for every site'),
          ],
        ),
      ),
    );
  }
}
