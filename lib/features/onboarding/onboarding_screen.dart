import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/book_accent.dart';
import '../../core/haptics/haptics.dart';

class _Page {
  const _Page(this.icon, this.title, this.desc, this.hue);
  final IconData icon;
  final String title;
  final String desc;
  final int hue;
}

const _pages = [
  _Page(
    Icons.qr_code_scanner_rounded,
    'Scan any book in seconds',
    'Point your camera at an ISBN barcode and BookDNA fills in everything — cover, pages, genre, even market value.',
    0,
  ),
  _Page(
    Icons.shelves,
    'Your whole shelf, digital',
    'Every physical book you own, organized, searchable and always in your pocket.',
    60,
  ),
  _Page(
    Icons.insights_rounded,
    'See your reading DNA',
    'Your shelf says more about you than you think. Genres, eras, gaps, growth — visualized.',
    150,
  ),
  _Page(
    Icons.auto_awesome_rounded,
    'AI that knows your shelf',
    'Ask your library questions. Get next reads picked from books you already own.',
    210,
  ),
  _Page(
    Icons.social_distance_rounded,
    'Read together',
    'Streaks, challenges and leaderboards with friends who read like you.',
    320,
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _index = 0;

  void _next() {
    if (_index < _pages.length - 1) {
      Haptics.selection();
      setState(() => _index++);
    } else {
      context.go('/auth');
    }
  }

  void _prev() {
    if (_index > 0) {
      Haptics.selection();
      setState(() => _index--);
    }
  }

  /// Swipe left → next slide, swipe right → previous slide.
  void _onHorizontalDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < 0) {
      _next();
    } else if (velocity > 0) {
      _prev();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final page = _pages[_index];
    final accent = accentFor(page.hue, brightness);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(
                  onPressed: () => context.go('/auth'),
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: _onHorizontalDrag,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: const Cubic(0.2, 0, 0, 1),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.96, end: 1.0).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Column(
                    key: ValueKey(_index),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 168,
                        height: 168,
                        decoration: BoxDecoration(
                          color: accent.container,
                          borderRadius: BorderRadius.circular(48),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned(
                              top: 18,
                              right: 22,
                              child: _circle(
                                accent.main.withValues(alpha: 0.25),
                                34,
                              ),
                            ),
                            Positioned(
                              bottom: 22,
                              left: 18,
                              child: _circle(
                                accent.main.withValues(alpha: 0.18),
                                24,
                              ),
                            ),
                            Icon(
                              page.icon,
                              size: 64,
                              color: accent.onContainer,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 34),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Column(
                          children: [
                            Text(
                              page.title,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 12),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 280),
                              child: Text(
                                page.desc,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge!.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Dot carousel.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                return GestureDetector(
                  onTap: () {
                    if (i != _index) Haptics.selection();
                    setState(() => _index = i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: const Cubic(0.2, 0, 0, 1),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 26 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
              child: Row(
                children: [
                  if (_index > 0)
                    IconButton.outlined(
                      onPressed: () => setState(() => _index--),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    child: Text(
                      _index == _pages.length - 1 ? 'Get started' : 'Next',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circle(Color color, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
