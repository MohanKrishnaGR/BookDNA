import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Six-axis diversity radar (CustomPainter port of the prototype `Radar`).
class RadarChart extends StatelessWidget {
  const RadarChart({super.key, required this.points, this.size = 230});

  final List<({String axis, double v})> points;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context)
        .textTheme
        .labelMedium!
        .copyWith(color: scheme.onSurfaceVariant);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => CustomPaint(
          painter: _RadarPainter(
            points: points,
            t: t,
            grid: scheme.outlineVariant,
            fill: scheme.primary.withValues(alpha: 0.22),
            stroke: scheme.primary,
            labelStyle: labelStyle,
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.points,
    required this.t,
    required this.grid,
    required this.fill,
    required this.stroke,
    required this.labelStyle,
  });

  final List<({String axis, double v})> points;
  final double t;
  final Color grid;
  final Color fill;
  final Color stroke;
  final TextStyle labelStyle;

  Offset _vertex(Offset center, double radius, int i, int n) {
    final angle = -math.pi / 2 + 2 * math.pi * i / n;
    return center + Offset(math.cos(angle), math.sin(angle)) * radius;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    if (n < 3) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 * 0.72;

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = grid;

    // Grid rings at 33 / 66 / 100%.
    for (final scale in [0.33, 0.66, 1.0]) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final p = _vertex(center, radius * scale, i, n);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }
    // Axes.
    for (var i = 0; i < n; i++) {
      canvas.drawLine(center, _vertex(center, radius, i, n), gridPaint);
    }

    // Data polygon.
    final dataPath = Path();
    for (var i = 0; i < n; i++) {
      final p = _vertex(center, radius * points[i].v * t, i, n);
      i == 0 ? dataPath.moveTo(p.dx, p.dy) : dataPath.lineTo(p.dx, p.dy);
    }
    dataPath.close();
    canvas.drawPath(dataPath, Paint()..color = fill);
    canvas.drawPath(
      dataPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = stroke,
    );

    // Vertex dots + labels.
    for (var i = 0; i < n; i++) {
      final p = _vertex(center, radius * points[i].v * t, i, n);
      canvas.drawCircle(p, 3, Paint()..color = stroke);

      final labelPos = _vertex(center, radius * 1.22, i, n);
      final tp = TextPainter(
        text: TextSpan(text: points[i].axis, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas, labelPos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.t != t || old.points != points;
}
