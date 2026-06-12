import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme/book_accent.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import 'wrapped_stats.dart';

const _slideDuration = Duration(milliseconds: 3400);
const _slideHues = [0, 60, 150, 210, 30, 320];

class _Slide {
  const _Slide({this.label, required this.big, required this.small});

  final String? label;
  final String big;
  final String small;
}

/// Full-screen auto-advancing monthly story (the prototype's Wrapped).
class WrappedScreen extends ConsumerStatefulWidget {
  const WrappedScreen({super.key});

  @override
  ConsumerState<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends ConsumerState<WrappedScreen> {
  int _index = 0;
  Timer? _timer;
  List<_Slide>? _slides;
  WrappedStats? _stats;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(_slideDuration, () {
      final slides = _slides;
      if (!mounted || slides == null) return;
      if (_index < slides.length - 1) {
        setState(() => _index++);
        _arm();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<_Slide> _build(WrappedStats s) => [
        _Slide(big: s.monthLabel, small: 'Your month in books'),
        if (s.pages > 0 || s.booksFinished > 0)
          _Slide(
            label: 'You read',
            big: s.booksFinished > 0
                ? '${s.booksFinished} book${s.booksFinished == 1 ? '' : 's'}'
                : '${formatNumber(s.pages)} pages',
            small: s.booksFinished > 0
                ? '${formatNumber(s.pages)} pages · ${s.hours} hours'
                : '${s.hours} hours with your nose in a book',
          )
        else
          const _Slide(
            label: 'A quiet month',
            big: 'The shelf waited',
            small: 'Every streak starts with one page',
          ),
        if (s.topGenre != null)
          _Slide(
            label: 'Your top genre',
            big: s.topGenre!,
            small: '${s.topGenreShare}% of your reading time',
          ),
        if (s.topAuthor != null)
          _Slide(
            label: 'Your top author',
            big: s.topAuthor!,
            small:
                '${s.topAuthorFinished} book${s.topAuthorFinished == 1 ? '' : 's'} finished',
          ),
        if (s.longestStreak > 1)
          _Slide(
            label: 'Longest streak',
            big: '${s.longestStreak} days',
            small: 'Back to back, every single day',
          ),
        _Slide(
          label: 'Your reading personality',
          big: s.archetype,
          small: 'See the full picture in Insights',
        ),
      ];

  void _tap(TapUpDetails details, double width, int slideCount) {
    if (details.localPosition.dx < width / 3) {
      if (_index > 0) {
        setState(() => _index--);
        _arm();
      }
    } else {
      if (_index < slideCount - 1) {
        setState(() => _index++);
        _arm();
      } else {
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(booksProvider).value ?? [];
    final sessions = ref.watch(allSessionsProvider).value ?? [];
    final stats =
        _stats ??= WrappedStats.compute(books, sessions);
    final slides = _slides ??= _build(stats);
    final slide = slides[_index.clamp(0, slides.length - 1)];
    final theme = Theme.of(context);

    final hue = _slideHues[_index % _slideHues.length];
    final seedHue = Hct.fromInt(kSeedColorValue).hue;
    final bg = Color(Hct.from((seedHue + hue) % 360, 12, 16).toInt());
    final accent = accentFor(hue, Brightness.dark);
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _tap(d, width, slides.length),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          color: bg,
          child: SafeArea(
            child: Column(
              children: [
                // Progress segments.
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: Row(children: [
                    for (var i = 0; i < slides.length; i++)
                      Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: i < _index
                              ? Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                )
                              : i == _index
                                  ? TweenAnimationBuilder<double>(
                                      key: ValueKey(_index),
                                      tween: Tween(begin: 0, end: 1),
                                      duration: _slideDuration,
                                      builder: (context, t, _) =>
                                          FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: t,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                        ),
                      ),
                  ]),
                ),
                // Close + share.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () {
                        final text =
                            'My ${stats.monthLabel} in books — ${stats.booksFinished} finished, '
                            '${formatNumber(stats.pages)} pages, ${stats.hours}h'
                            '${stats.topGenre != null ? ', mostly ${stats.topGenre}' : ''}. '
                            'Tracked with BookDNA.';
                        SharePlus.instance.share(ShareParams(text: text));
                      },
                      icon: const Icon(Icons.ios_share_rounded,
                          color: Colors.white),
                    ),
                    IconButton(
                      onPressed: () => context.pop(),
                      style: IconButton.styleFrom(
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.14)),
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ],
                ),
                // Slide content.
                Expanded(
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      switchInCurve: const Cubic(0.2, 0, 0, 1),
                      transitionBuilder: (child, animation) =>
                          FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(
                                  begin: const Offset(0, 0.06),
                                  end: Offset.zero)
                              .animate(animation),
                          child: child,
                        ),
                      ),
                      child: Padding(
                        key: ValueKey(_index),
                        padding: const EdgeInsets.symmetric(horizontal: 36),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (slide.label != null) ...[
                              Text(
                                slide.label!,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium!.copyWith(
                                    color:
                                        Colors.white.withValues(alpha: 0.7)),
                              ),
                              const SizedBox(height: 14),
                            ],
                            Text(
                              slide.big,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.displayMedium!.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              slide.small,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium!
                                  .copyWith(color: accent.dim),
                            ),
                            if (_index == 0) ...[
                              const SizedBox(height: 30),
                              Text(
                                'Tap to begin →',
                                style: theme.textTheme.labelLarge!.copyWith(
                                    color:
                                        Colors.white.withValues(alpha: 0.5)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Footer.
                Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          size: 14, color: Colors.white54),
                      const SizedBox(width: 6),
                      Text(
                        'BookDNA Wrapped · ${stats.monthYearLabel}',
                        style: theme.textTheme.labelMedium!
                            .copyWith(color: Colors.white54),
                      ),
                    ],
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
