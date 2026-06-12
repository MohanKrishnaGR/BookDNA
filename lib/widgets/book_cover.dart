import 'package:flutter/material.dart';

import '../app/theme/book_accent.dart';

/// Procedural typographic book cover — BookDNA's visual signature
/// (port of the prototype's `BookCover`).
///
/// Three layout variants chosen by a stable hash of the title:
///   0: top-aligned title on accent container
///   1: centered, inverted colors (onContainer background)
///   2: bottom-aligned with a rule line near the top
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.title,
    required this.author,
    required this.hueShift,
    this.width = 96,
    this.radius,
    this.shadow = true,
  });

  final String title;
  final String author;
  final int hueShift;
  final double width;
  final double? radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    // Covers always use the light-mode accent (like a printed object).
    final a = accentFor(hueShift, Brightness.light);
    final h = width * 1.5;
    final variant = title.hashCode.abs() % 3;
    final bg = variant == 1 ? a.onContainer : a.container;
    final fg = variant == 1 ? a.container : a.onContainer;
    final fs = (width * 0.115).clamp(9.0, double.infinity);

    return Container(
      width: width,
      height: h,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bg,
        borderRadius:
            BorderRadius.circular(radius ?? (width * 0.06).clamp(4.0, 24.0)),
        boxShadow: shadow
            ? const [
                BoxShadow(
                    color: Color(0x2E000000),
                    blurRadius: 6,
                    offset: Offset(0, 2)),
                BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 2,
                    offset: Offset(0, 1)),
              ]
            : null,
      ),
      child: Stack(
        children: [
          // Spine strip.
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: (width * 0.045).clamp(3.0, double.infinity),
            child: const ColoredBox(color: Color(0x2E000000)),
          ),
          if (variant == 2)
            Positioned(
              left: 0,
              right: 0,
              top: h * 0.12,
              height: h * 0.03,
              child: ColoredBox(color: fg.withValues(alpha: 0.85)),
            ),
          Positioned(
            top: h * 0.1,
            right: width * 0.11,
            bottom: h * 0.08,
            left: width * 0.14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: switch (variant) {
                0 => MainAxisAlignment.start,
                1 => MainAxisAlignment.center,
                _ => MainAxisAlignment.end,
              },
              children: [
                Text(
                  title,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: fs * 1.25,
                    height: 1.18,
                    letterSpacing: -0.1,
                  ),
                ),
                SizedBox(height: width * 0.06),
                Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w500,
                    fontSize: fs * 0.9,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
