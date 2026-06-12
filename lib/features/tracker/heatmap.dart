import 'package:flutter/material.dart';

/// GitHub-style reading heatmap: `weeks × 7` levels 0–4.
class HeatmapGrid extends StatelessWidget {
  const HeatmapGrid({
    super.key,
    required this.data,
    this.cell = 13,
    this.gap = 3,
  });

  final List<List<int>> data;
  final double cell;
  final double gap;

  Color _color(ColorScheme scheme, Brightness b, int level) {
    if (level == 0) return scheme.surfaceContainerHigh;
    final base = scheme.primary;
    final alpha = switch (level) {
      1 => 0.25,
      2 => 0.45,
      3 => 0.7,
      _ => 1.0,
    };
    return base.withValues(alpha: alpha);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final week in data)
            Padding(
              padding: EdgeInsets.only(right: gap),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final level in week)
                    Container(
                      width: cell,
                      height: cell,
                      margin: EdgeInsets.only(bottom: gap),
                      decoration: BoxDecoration(
                        color: _color(scheme, brightness, level),
                        borderRadius: BorderRadius.circular(cell * 0.25),
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
