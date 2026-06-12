import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/book_accent.dart';
import '../../core/providers.dart';
import '../../widgets/book_cover.dart';
import '../ai/ai_repository.dart';
import '../premium/entitlement.dart';
import 'graph_physics.dart';

const _freeBookLimit = 20;
const _premiumBookLimit = 150;

class GraphScreen extends ConsumerStatefulWidget {
  const GraphScreen({super.key});

  @override
  ConsumerState<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends ConsumerState<GraphScreen>
    with SingleTickerProviderStateMixin {
  GraphSim? _sim;
  Size _lastSize = Size.zero;
  late final Ticker _ticker;
  final _frame = ValueNotifier<int>(0);

  int? _selected;
  int? _dragging;
  Offset _dragStart = Offset.zero;
  bool _dragMoved = false;
  List<(String, String)> _themeEdges = const [];
  bool _hasAnalysis = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final sim = _sim;
      if (sim == null || sim.asleep) return;
      sim.step(pinned: _dragging);
      _frame.value++;
    })
      ..start();
    _loadAnalysisEdges();
  }

  Future<void> _loadAnalysisEdges() async {
    final cached =
        await ref.read(aiRepositoryProvider)?.cachedAnalysis();
    if (cached != null && mounted) {
      setState(() {
        _themeEdges = cached.themeEdges;
        _hasAnalysis = true;
        _sim = null; // rebuild with the richer edge set
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _sim = null;
      _selected = null;
    });
  }

  int? _hitTest(Offset p) {
    final sim = _sim;
    if (sim == null) return null;
    for (var i = sim.nodes.length - 1; i >= 0; i--) {
      if ((sim.nodes[i].pos - p).distance <= sim.nodes[i].radius + 8) {
        return i;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final books = ref.watch(booksProvider).value ?? const [];
    final premium = ref.watch(isPremiumProvider);
    final limit = premium ? _premiumBookLimit : _freeBookLimit;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge graph'),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          IconButton(
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _hasAnalysis
                      ? 'Top connected books · dashed edges bridge clusters'
                      : 'Genre clusters only — run the AI analysis to reveal '
                          'thematic bridges',
                  style: theme.textTheme.bodySmall!
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ]),
          ),
          if (!premium && books.length > _freeBookLimit)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                color: scheme.tertiaryContainer,
                child: ListTile(
                  dense: true,
                  onTap: () => context.push('/premium'),
                  leading: Icon(Icons.lock_open_rounded,
                      size: 20, color: scheme.onTertiaryContainer),
                  title: Text(
                    'Preview — unlock the full ${books.length}-book graph',
                    style: theme.textTheme.labelLarge!
                        .copyWith(color: scheme.onTertiaryContainer),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded,
                      color: scheme.onTertiaryContainer),
                ),
              ),
            ),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final size = constraints.biggest;
              if (_sim == null || _lastSize != size) {
                _lastSize = size;
                _sim = buildGraph(
                  books: books,
                  themeShortIdPairs: _themeEdges,
                  bounds: size,
                  maxBooks: limit,
                );
                _sim!.wake();
              }
              final sim = _sim!;
              return GestureDetector(
                onPanStart: (d) {
                  _dragging = _hitTest(d.localPosition);
                  _dragStart = d.localPosition;
                  _dragMoved = false;
                  if (_dragging != null) sim.wake();
                },
                onPanUpdate: (d) {
                  final i = _dragging;
                  if (i == null) return;
                  if ((d.localPosition - _dragStart).distance > 5) {
                    _dragMoved = true;
                  }
                  sim.nodes[i].pos = d.localPosition;
                  sim.wake();
                  _frame.value++;
                },
                onPanEnd: (_) {
                  final i = _dragging;
                  _dragging = null;
                  if (i != null && !_dragMoved) {
                    setState(() => _selected = _selected == i ? null : i);
                  }
                },
                onTapUp: (d) {
                  final i = _hitTest(d.localPosition);
                  setState(() => _selected = _selected == i ? null : i);
                },
                child: Stack(children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GraphPainter(
                        sim: sim,
                        selected: _selected,
                        brightness: theme.brightness,
                        scheme: scheme,
                        repaint: _frame,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14,
                    child: _detailCard(theme),
                  ),
                ]),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _detailCard(ThemeData theme) {
    final scheme = theme.colorScheme;
    final sim = _sim;
    final sel = _selected;

    if (sim == null || sel == null) {
      return Card(
        color: scheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(Icons.auto_awesome_rounded,
                size: 18, color: scheme.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tap or drag any node. Bigger circles are longer books; '
                'dashed edges cross genre clusters.',
                style: theme.textTheme.bodySmall!
                    .copyWith(color: scheme.onSecondaryContainer),
              ),
            ),
          ]),
        ),
      );
    }

    final node = sim.nodes[sel];
    final degree = sim.degree(sel);

    if (node.isHub) {
      final accent = accentFor(node.hueShift, theme.brightness);
      return Card(
        elevation: 2,
        child: ListTile(
          leading: CircleAvatar(backgroundColor: accent.main, radius: 18),
          title: Text(node.label),
          subtitle: Text('$degree books in this cluster'),
          trailing: FilledButton.tonal(
            onPressed: () => setState(() => _selected = null),
            child: const Text('Clear'),
          ),
        ),
      );
    }

    final book = node.book!;
    final bridges = sim.bridgeCount(sel);
    return Card(
      elevation: 2,
      child: ListTile(
        leading: BookCover(
            title: book.title,
            author: book.author,
            hueShift: book.hueShift,
            width: 40,
            radius: 4,
            shadow: false),
        title:
            Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '$degree connection${degree == 1 ? '' : 's'}'
          '${bridges > 0 ? ' · bridges $bridges cluster${bridges == 1 ? '' : 's'}' : ''}'
          ' · ${book.genre}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: FilledButton.tonal(
          onPressed: () => context.push('/book/${book.id}'),
          child: const Text('Open'),
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.sim,
    required this.selected,
    required this.brightness,
    required this.scheme,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final GraphSim sim;
  final int? selected;
  final Brightness brightness;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final neighborhood =
        selected != null ? sim.neighborhood(selected!) : null;
    final bridgeColor = accentFor(60, brightness).main; // amber bridges

    // Edges first.
    for (final e in sim.edges) {
      final active = neighborhood == null ||
          neighborhood.contains(e.a) && neighborhood.contains(e.b) ||
          e.a == selected ||
          e.b == selected;
      final paint = Paint()..style = PaintingStyle.stroke;
      if (e.bridge) {
        paint
          ..color = bridgeColor.withValues(alpha: active ? 0.9 : 0.12)
          ..strokeWidth = 1.8;
        _dashedLine(canvas, sim.nodes[e.a].pos, sim.nodes[e.b].pos, paint);
      } else if (e.kind == EdgeKind.theme) {
        paint
          ..color =
              scheme.onSurfaceVariant.withValues(alpha: active ? 0.9 : 0.10)
          ..strokeWidth = 1.4;
        canvas.drawLine(sim.nodes[e.a].pos, sim.nodes[e.b].pos, paint);
      } else {
        paint
          ..color =
              scheme.outlineVariant.withValues(alpha: active ? 0.55 : 0.12)
          ..strokeWidth = 1.0;
        canvas.drawLine(sim.nodes[e.a].pos, sim.nodes[e.b].pos, paint);
      }
    }

    // Nodes.
    for (var i = 0; i < sim.nodes.length; i++) {
      final node = sim.nodes[i];
      final accent = accentFor(node.hueShift, brightness);
      final dimmed = neighborhood != null && !neighborhood.contains(i);
      final alpha = dimmed ? 0.22 : 1.0;

      if (i == selected) {
        canvas.drawCircle(
          node.pos,
          node.radius + 6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = accent.main.withValues(alpha: 0.6),
        );
      }

      if (node.isHub) {
        canvas.drawCircle(node.pos, node.radius,
            Paint()..color = accent.main.withValues(alpha: alpha));
      } else {
        canvas.drawCircle(node.pos, node.radius,
            Paint()..color = accent.container.withValues(alpha: alpha));
        canvas.drawCircle(
          node.pos,
          node.radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = accent.main.withValues(alpha: alpha),
        );
      }

      // Labels: hubs always; books only when selected.
      if (node.isHub || i == selected) {
        final label = node.label.length > 24
            ? '${node.label.substring(0, 24)}…'
            : node.label;
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontSize: node.isHub ? 10.5 : 10,
              fontWeight: node.isHub ? FontWeight.w700 : FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: dimmed ? 0.3 : 1),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 160);
        final dy = node.isHub
            ? node.pos.dy + node.radius + 4
            : node.pos.dy - node.radius - tp.height - 4;
        tp.paint(canvas, Offset(node.pos.dx - tp.width / 2, dy));
      }
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0, gap = 3.0;
    final total = (b - a).distance;
    if (total < 1) return;
    final dir = (b - a) / total;
    var t = 0.0;
    while (t < total) {
      final end = (t + dash).clamp(0.0, total);
      canvas.drawLine(a + dir * t, a + dir * end, paint);
      t = end + gap;
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.selected != selected ||
      old.sim != sim ||
      old.brightness != brightness;
}
