import 'dart:ui';

import 'package:bookdna/core/db/database.dart';
import 'package:bookdna/core/models/book_status.dart';
import 'package:bookdna/features/graph/graph_physics.dart';
import 'package:flutter_test/flutter_test.dart';

Book book(String id, {String genre = 'Technology', int pages = 300}) => Book(
      id: id,
      title: 'Book $id',
      author: 'Author',
      genre: genre,
      pages: pages,
      year: 2020,
      price: null,
      estValue: null,
      status: BookStatus.unread,
      progress: 0,
      currentPage: 0,
      rating: null,
      hueShift: 0,
      isbn: null,
      publisher: null,
      language: 'English',
      description: null,
      coverUrl: null,
      addedAt: DateTime(2024),
      startedAt: null,
      finishedAt: null,
      updatedAt: 0,
      deletedAt: null,
      isDirty: false,
    );

void main() {
  const bounds = Size(372, 560);

  GraphSim build() => buildGraph(
        books: [
          book('aaaaaaaa-1'),
          book('bbbbbbbb-1'),
          book('cccccccc-1', genre: 'History'),
          book('dddddddd-1', genre: 'History', pages: 900),
        ],
        themeShortIdPairs: const [
          ('aaaaaaaa', 'cccccccc'), // cross-genre → bridge
          ('aaaaaaaa', 'bbbbbbbb'), // same genre → plain theme edge
        ],
        bounds: bounds,
        maxBooks: 20,
      );

  test('builds hubs + books with genre and theme edges', () {
    final sim = build();
    expect(sim.nodes.where((n) => n.isHub).length, 2);
    expect(sim.nodes.where((n) => !n.isHub).length, 4);
    // 4 genre edges + 2 theme edges
    expect(sim.edges.length, 6);
    expect(sim.edges.where((e) => e.bridge).length, 1);
  });

  test('node radius scales with page count', () {
    final sim = build();
    final small = sim.nodes.firstWhere((n) => n.book?.id == 'aaaaaaaa-1');
    final large = sim.nodes.firstWhere((n) => n.book?.id == 'dddddddd-1');
    expect(large.radius, greaterThan(small.radius));
    expect(large.radius, lessThanOrEqualTo(13)); // 7 + capped 6
  });

  test('simulation settles to sleep and keeps nodes in bounds', () {
    final sim = build();
    for (var i = 0; i < 1300 && !sim.asleep; i++) {
      sim.step();
    }
    expect(sim.asleep, isTrue);
    for (final n in sim.nodes) {
      expect(n.pos.dx, inInclusiveRange(0, bounds.width));
      expect(n.pos.dy, inInclusiveRange(0, bounds.height));
    }
  });

  test('wake re-arms a sleeping simulation', () {
    final sim = build();
    for (var i = 0; i < 1300 && !sim.asleep; i++) {
      sim.step();
    }
    expect(sim.asleep, isTrue);
    sim.wake();
    expect(sim.asleep, isFalse);
  });

  test('neighborhood and degree reflect the edge set', () {
    final sim = build();
    final a =
        sim.nodes.indexWhere((n) => n.book?.id == 'aaaaaaaa-1');
    // a connects to: its hub, c (bridge), b (theme) → degree 3.
    expect(sim.degree(a), 3);
    expect(sim.bridgeCount(a), 1);
    expect(sim.neighborhood(a).length, 4); // self + 3
  });

  test('free limit keeps the most connected books', () {
    final sim = buildGraph(
      books: [
        for (var i = 0; i < 30; i++) book('id$i-padded-uuid'),
        book('connected-1'),
        book('connected-2'),
      ],
      themeShortIdPairs: const [('connecte', 'connecte')],
      bounds: bounds,
      maxBooks: 5,
    );
    expect(sim.nodes.where((n) => !n.isHub).length, 5);
  });
}
