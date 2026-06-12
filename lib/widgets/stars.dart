import 'package:flutter/material.dart';

/// Interactive 5-star rating row (prototype `Stars`).
class Stars extends StatelessWidget {
  const Stars({super.key, this.rating = 0, this.size = 16, this.onRate});

  final int rating;
  final double size;
  final ValueChanged<int>? onRate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating;
        final star = Icon(
          filled ? Icons.star_rounded : Icons.star_outline_rounded,
          size: size,
          color: filled ? scheme.primary : scheme.outline,
        );
        if (onRate == null) return star;
        return InkWell(
          onTap: () => onRate!(i + 1),
          customBorder: const CircleBorder(),
          child: Padding(padding: const EdgeInsets.all(2), child: star),
        );
      }),
    );
  }
}
