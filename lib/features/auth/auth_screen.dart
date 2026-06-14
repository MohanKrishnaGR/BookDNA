import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics/haptics.dart';
import '../../core/providers.dart';
import '../../core/supabase/client.dart';
import '../../widgets/common.dart';
import 'auth_controller.dart';

/// Sign-in screen. Email + password and anonymous guest are live against
/// Supabase; Google/Apple buttons activate once their console config ships.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _enterApp() {
    ref.read(appPhaseProvider.notifier).advance('app');
    context.go('/home');
  }

  Future<void> _guest() async {
    setState(() => _busy = true);
    await ref.read(authControllerProvider).continueAsGuest();
    if (!mounted) return;
    Haptics.tap();
    _enterApp();
  }

  Future<void> _emailFlow() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      showToast(context, 'Enter your email address first');
      return;
    }
    final password = await _askPassword(email);
    if (password == null || password.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider).signInWithEmail(email, password);
      if (!mounted) return;
      Haptics.success();
      _enterApp();
    } on AuthException catch (e) {
      if (!mounted) return;
      Haptics.error();
      showToast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      Haptics.error();
      showToast(context, 'Sign-in failed — check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() => _busy = true);
    try {
      final ok = await ref.read(authControllerProvider).signInWithGoogle();
      if (!mounted) return;
      if (ok) {
        Haptics.success();
        _enterApp();
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      Haptics.error();
      showToast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      Haptics.error();
      showToast(context, 'Google sign-in failed — try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askPassword(String email) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final controller = TextEditingController();
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Password for $email',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'New here? This also creates your account.',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Password'),
                onSubmitted: (v) => Navigator.pop(sheetContext, v),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext, controller.text),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      // Scrolls instead of overflowing when the keyboard opens.
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.auto_stories_rounded,
                    size: 30,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Turn your bookshelf into insights',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Create an account to start decoding your reading life.',
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 30),
                _OAuthButton(
                  glyph: 'G',
                  label: 'Continue with Google',
                  onTap: _busy ? null : _google,
                ),
                const SizedBox(height: 10),
                _OAuthButton(
                  icon: Icons.apple_rounded,
                  label: 'Continue with Apple',
                  onTap: () => showToast(
                    context,
                    'Apple sign-in arrives with the iOS release',
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or', style: theme.textTheme.labelMedium),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(hintText: 'Email address'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _emailFlow,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Continue with email'),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: _busy ? null : _guest,
                  child: Text(
                    supabaseConfigured
                        ? 'Explore first — continue as guest'
                        : 'Explore first — continue without account',
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'By continuing you agree to the Terms of Service and Privacy Policy.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OAuthButton extends StatelessWidget {
  const _OAuthButton({this.glyph, this.icon, required this.label, this.onTap});

  final String? glyph;
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (glyph != null)
            Text(
              glyph!,
              style: theme.textTheme.titleMedium!.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          if (icon != null) Icon(icon, size: 22),
          const SizedBox(width: 10),
          Text(label, style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }
}
