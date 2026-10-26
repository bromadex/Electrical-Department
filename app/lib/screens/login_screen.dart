import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
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
  int _errorCount = 0;

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
      if (error != null) _errorCount++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final form = Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!wide) ...[
              const Center(child: Floating(child: BrandLogo(width: 150)))
                  .entrance(context),
              const SizedBox(height: Space.lg),
            ],
            Text(
              'Welcome back',
              style: theme.textTheme.headlineMedium,
            ).entrance(context, index: 1),
            const SizedBox(height: Space.xxs),
            Text(
              'Sign in to the Electrical Department',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ).entrance(context, index: 2),
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
            ).entrance(context, index: 3),
            const SizedBox(height: Space.sm),
            TextFormField(
              controller: _password,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: AnimatedSwitcher(
                    duration: Motion.of(context, Motion.fast),
                    child: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      key: ValueKey(_obscure),
                    ),
                  ),
                ),
              ),
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _signIn(),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Enter your password' : null,
            ).entrance(context, index: 4),
            AnimatedSize(
              duration: Motion.of(context, Motion.medium),
              curve: Motion.emphasized,
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: Space.sm),
                      child: Container(
                        padding: const EdgeInsets.all(Space.sm),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(Radii.md),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: scheme.onErrorContainer,
                              size: 20,
                            ),
                            const SizedBox(width: Space.xs),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: scheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: Space.lg),
            Pressable(
              onTap: _busy ? null : _signIn,
              child: FilledButton(
                onPressed: _busy ? null : _signIn,
                child: AnimatedSwitcher(
                  duration: Motion.of(context, Motion.medium),
                  child: _busy
                      ? SizedBox.square(
                          key: const ValueKey('busy'),
                          dimension: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Row(
                          key: ValueKey('idle'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Sign in'),
                            SizedBox(width: Space.xs),
                            Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                ),
              ),
            ).entrance(context, index: 5),
          ],
        ),
      ),
    );

    Widget card = GlassSurface(
      padding: const EdgeInsets.all(Space.lg + 4),
      child: form,
    );
    if (_errorCount > 0 && !Motion.reduced(context)) {
      card = card
          .animate(key: ValueKey(_errorCount))
          .shakeX(hz: 5, amount: 6, duration: 420.ms);
    }

    return Scaffold(
      body: MeshBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.lg),
              child: wide
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Row(
                        children: [
                          Expanded(child: const _Hero().entrance(context)),
                          const SizedBox(width: Space.xxl),
                          SizedBox(width: 420, child: card),
                        ],
                      ),
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: card,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Left-hand brand panel on wide screens.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Floating(child: BrandLogo(width: 220)),
        const SizedBox(height: Space.xl),
        Text(
          'Every job.\nEvery site.\nOne team.',
          style: theme.textTheme.displaySmall?.copyWith(height: 1.1),
        ),
        const SizedBox(height: Space.md),
        Text(
          'Jobs, checklists, tools, the store and the team chat for '
          'Bravura Electrical — on the phone and on the web.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
