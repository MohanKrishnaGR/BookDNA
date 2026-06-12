import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2000), _advance);
  }

  void _advance() {
    if (!mounted) return;
    final phase =
        ref.read(databaseProvider).getPref('phase');
    phase.then((p) {
      if (!mounted) return;
      context.go(p == 'app' ? '/home' : '/onboarding');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        _timer?.cancel();
        _advance();
      },
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: const Cubic(0.2, 0, 0, 1),
                builder: (context, v, child) => Opacity(
                  opacity: v,
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * v,
                    child: Transform.rotate(angle: -0.14 * (1 - v), child: child),
                  ),
                ),
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(Icons.auto_stories_rounded,
                      size: 46, color: scheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: 22),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 850),
                curve: Curves.easeOutCubic,
                builder: (context, v, child) => Opacity(
                  opacity: v,
                  child: Transform.translate(
                      offset: Offset(0, 10 * (1 - v)), child: child),
                ),
                child: Column(
                  children: [
                    Text('BookDNA',
                        style: theme.textTheme.headlineMedium!.copyWith(
                            fontWeight: FontWeight.w600, letterSpacing: -0.5)),
                    const SizedBox(height: 6),
                    Text(
                      'Understand your reading life',
                      style: theme.textTheme.bodyMedium!.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.75)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
