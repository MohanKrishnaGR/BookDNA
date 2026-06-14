import 'package:flutter/material.dart';

import '../core/haptics/haptics.dart';

/// Section heading with optional trailing action (prototype section titles).
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (action != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  action!,
                  style: theme.textTheme.labelLarge!
                      .copyWith(color: theme.colorScheme.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Animated count-up number (prototype `Counter`).
class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({
    super.key,
    required this.value,
    this.format,
    this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  final num value;
  final String Function(num)? format;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final shown = value is int ? v.round() : v;
        return Text(
          format?.call(shown) ?? shown.toString(),
          style: style,
        );
      },
    );
  }
}

/// Plus/minus stepper row used in bottom sheets (prototype `Stepper`).
class StepperRow extends StatelessWidget {
  const StepperRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999,
    this.step = 1,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: value > min
              ? () {
                  Haptics.selection();
                  onChanged((value - step).clamp(min, max));
                }
              : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 64,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton.filledTonal(
          onPressed: value < max
              ? () {
                  Haptics.selection();
                  onChanged((value + step).clamp(min, max));
                }
              : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

/// Empty-state placeholder.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(icon, size: 44, color: theme.colorScheme.outline),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium!
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(milliseconds: 2600),
    ));
}

/// Maps prototype Material Symbols names to Flutter rounded icons
/// (used by the activity feed, which stores icon names as strings).
IconData iconFromName(String name) => switch (name) {
      'auto_stories' => Icons.auto_stories_rounded,
      'barcode_scanner' => Icons.qr_code_scanner_rounded,
      'military_tech' => Icons.military_tech_rounded,
      'star' => Icons.star_rounded,
      'edit_note' => Icons.edit_note_rounded,
      'swap_horiz' => Icons.swap_horiz_rounded,
      'flag' => Icons.flag_rounded,
      'local_fire_department' => Icons.local_fire_department_rounded,
      'check_circle' => Icons.check_circle_rounded,
      _ => Icons.bookmark_rounded,
    };
