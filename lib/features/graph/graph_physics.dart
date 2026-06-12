import 'dart:math' as math;
import 'dart:ui';

import '../../core/db/database.dart';

/// Force-directed graph of genre hubs + books, physics ported 1:1 from the
/// design prototype: pairwise repulsion, spring edges, center gravity,
/// velocity damping, and a sleep state once the layout settles.
class GraphNode {
  GraphNode({
    required this.label,
    required this.hueShift,
    required this.radius,
    required this.isHub,
    this.book,
    required this.pos,
  });

  final String label;
  final int hueShift;
  final double radius;
  final bool isHub;
  final Book? book;

  Offset pos;
  Offset vel = Offset.zero;
}

enum EdgeKind { genre, theme }

class GraphEdge {
  GraphEdge(this.a, this.b, this.kind, {this.bridge = false});

  final int a;
  final int b;
  final EdgeKind kind;

  /// Theme edge whose endpoints live in different genre clusters.
  final bool bridge;
}

class GraphSim {
  GraphSim({
    required this.nodes,
    required this.edges,
    required this.bounds,
  });

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  Size bounds;

  int _frames = 0;
  bool asleep = false;

  static const _repulsionHub = 1500.0;
  static const _repulsionBook = 620.0;
  static const _repulsionCutoff = 26000.0; // d² beyond which we skip
  static const _springK = 0.02;
  static const _restGenre = 56.0;
  static const _restTheme = 74.0;
  static const _gravity = 0.0022;
  static const _damping = 0.86;
  static const _sleepEnergy = 1.2;
  static const _warmupFrames = 60;
  static const _maxFrames = 1200;

  /// Re-arm the simulation after an interaction.
  void wake() {
    asleep = false;
    _frames = math.min(_frames, _maxFrames - 240);
  }

  void step({int? pinned}) {
    if (asleep) return;
    _frames++;

    final n = nodes.length;
    final forces = List<Offset>.filled(n, Offset.zero);

    // Pairwise repulsion.
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final d = nodes[i].pos - nodes[j].pos;
        var d2 = d.distanceSquared;
        if (d2 > _repulsionCutoff) continue;
        if (d2 < 1) d2 = 1;
        final strength = (nodes[i].isHub || nodes[j].isHub)
            ? _repulsionHub
            : _repulsionBook;
        final push = d / math.sqrt(d2) * (strength / d2);
        forces[i] += push;
        forces[j] -= push;
      }
    }

    // Spring forces along edges.
    for (final e in edges) {
      final rest = e.kind == EdgeKind.genre ? _restGenre : _restTheme;
      final d = nodes[e.b].pos - nodes[e.a].pos;
      final dist = math.max(1.0, d.distance);
      final pull = d / dist * ((dist - rest) * _springK);
      forces[e.a] += pull;
      forces[e.b] -= pull;
    }

    // Center gravity.
    final center = Offset(bounds.width / 2, bounds.height / 2);
    for (var i = 0; i < n; i++) {
      forces[i] += (center - nodes[i].pos) * _gravity;
    }

    // Integrate.
    var energy = 0.0;
    for (var i = 0; i < n; i++) {
      if (i == pinned) continue;
      final node = nodes[i];
      node.vel = (node.vel + forces[i]) * _damping;
      node.pos += node.vel;

      // Keep within bounds.
      final m = node.radius + 6;
      node.pos = Offset(
        node.pos.dx.clamp(m, bounds.width - m),
        node.pos.dy.clamp(m, bounds.height - m),
      );
      energy += node.vel.distance;
    }

    if (_frames >= _maxFrames ||
        (_frames >= _warmupFrames && energy < _sleepEnergy)) {
      asleep = true;
    }
  }

  /// Indices of [node] plus everything sharing an edge with it.
  Set<int> neighborhood(int node) {
    final set = {node};
    for (final e in edges) {
      if (e.a == node) set.add(e.b);
      if (e.b == node) set.add(e.a);
    }
    return set;
  }

  int degree(int node) =>
      edges.where((e) => e.a == node || e.b == node).length;

  int bridgeCount(int node) => edges
      .where((e) => e.bridge && (e.a == node || e.b == node))
      .length;
}

/// Builds the graph: one hub per genre, the [maxBooks] most-connected books,
/// genre edges hub→book, and theme edges between books (short-id pairs from
/// the AI analysis).
GraphSim buildGraph({
  required List<Book> books,
  required List<(String, String)> themeShortIdPairs,
  required Size bounds,
  required int maxBooks,
}) {
  // Resolve theme pairs to full ids first; connection count drives selection.
  Book? byShort(String shortId) {
    for (final b in books) {
      if (b.id.startsWith(shortId)) return b;
    }
    return null;
  }

  final themePairs = <(Book, Book)>[];
  for (final (a, b) in themeShortIdPairs) {
    final ba = byShort(a), bb = byShort(b);
    if (ba != null && bb != null && ba.id != bb.id) {
      themePairs.add((ba, bb));
    }
  }

  final connections = <String, int>{};
  for (final (a, b) in themePairs) {
    connections[a.id] = (connections[a.id] ?? 0) + 1;
    connections[b.id] = (connections[b.id] ?? 0) + 1;
  }

  final selected = [...books]..sort((a, b) {
      final byConn =
          (connections[b.id] ?? 0).compareTo(connections[a.id] ?? 0);
      if (byConn != 0) return byConn;
      final byRating = (b.rating ?? 0).compareTo(a.rating ?? 0);
      if (byRating != 0) return byRating;
      return b.addedAt.compareTo(a.addedAt);
    });
  final shown = selected.take(maxBooks).toList();
  final shownIds = shown.map((b) => b.id).toSet();

  final genres = shown.map((b) => b.genre).toSet().toList()..sort();
  final rng = math.Random(42); // deterministic initial layout
  final center = Offset(bounds.width / 2, bounds.height / 2);

  final nodes = <GraphNode>[];
  final hubIndex = <String, int>{};
  for (var i = 0; i < genres.length; i++) {
    final angle = 2 * math.pi * i / genres.length - math.pi / 2;
    hubIndex[genres[i]] = nodes.length;
    nodes.add(GraphNode(
      label: genres[i],
      hueShift: _genreHue(genres[i]),
      radius: 17,
      isHub: true,
      pos: center +
          Offset(math.cos(angle) * bounds.width * 0.32,
              math.sin(angle) * bounds.height * 0.3),
    ));
  }

  final bookIndex = <String, int>{};
  final edges = <GraphEdge>[];
  for (final b in shown) {
    final hub = hubIndex[b.genre]!;
    bookIndex[b.id] = nodes.length;
    nodes.add(GraphNode(
      label: b.title,
      hueShift: b.hueShift,
      radius: 7 + math.min(6, b.pages / 140),
      isHub: false,
      book: b,
      pos: nodes[hub].pos +
          Offset(rng.nextDouble() * 92 - 46, rng.nextDouble() * 92 - 46),
    ));
    edges.add(GraphEdge(hub, bookIndex[b.id]!, EdgeKind.genre));
  }

  for (final (a, b) in themePairs) {
    if (!shownIds.contains(a.id) || !shownIds.contains(b.id)) continue;
    edges.add(GraphEdge(
      bookIndex[a.id]!,
      bookIndex[b.id]!,
      EdgeKind.theme,
      bridge: a.genre != b.genre,
    ));
  }

  return GraphSim(nodes: nodes, edges: edges, bounds: bounds);
}

int _genreHue(String genre) => switch (genre) {
      'Technology' => 0,
      'AI & Science' => 150,
      'Business' => 60,
      'Psychology' => 210,
      'Biography' => 30,
      'Self Help' => 320,
      'History' => 270,
      _ => genre.hashCode.abs() % 360,
    };
