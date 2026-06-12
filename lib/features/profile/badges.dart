import 'package:flutter/material.dart';

import '../../core/db/database.dart';
import '../../core/models/book_status.dart';
import '../insights/logic/formulas.dart';

/// The eight BookDNA badges, evaluated locally from library state.
class BadgeSpec {
  const BadgeSpec(this.icon, this.name, this.hint);

  final IconData icon;
  final String name;

  /// Shown under locked badges: what it takes to earn it.
  final String hint;
}

class EarnedBadge {
  const EarnedBadge(this.spec, this.earned);

  final BadgeSpec spec;
  final bool earned;
}

const kBadges = [
  BadgeSpec(Icons.auto_stories_rounded, 'First Book', 'Finish your first book'),
  BadgeSpec(Icons.filter_1_rounded, '10 Books', 'Finish 10 books'),
  BadgeSpec(Icons.local_library_rounded, '100 Books', 'Finish 100 books'),
  BadgeSpec(Icons.explore_rounded, 'Genre Explorer', 'Finish books in 5 genres'),
  BadgeSpec(Icons.bolt_rounded, 'Reading Machine',
      'Read 1,000 pages in 30 days'),
  BadgeSpec(Icons.local_fire_department_rounded, '30-Day Streak',
      'Read every day for 30 days'),
  BadgeSpec(Icons.architecture_rounded, 'Knowledge Architect',
      'Add notes to 10 books'),
  BadgeSpec(Icons.public_rounded, 'World Reader',
      'Finish books in 3 languages'),
];

List<EarnedBadge> evaluateBadges({
  required List<Book> books,
  required List<ReadingSession> sessions,
  required List<Note> notes,
}) {
  final read = books.where((b) => b.status == BookStatus.read).toList();
  final genresRead = read.map((b) => b.genre).toSet().length;
  final languagesRead = read.map((b) => b.language).toSet().length;
  final notedBooks = notes.map((n) => n.bookId).toSet().length;
  final cutoff = DateTime.now().subtract(const Duration(days: 30));
  final pages30d = sessions
      .where((s) => s.sessionDate.isAfter(cutoff))
      .fold(0, (sum, s) => sum + s.pages);
  final best = bestStreak(sessions);

  final earned = [
    read.isNotEmpty,
    read.length >= 10,
    read.length >= 100,
    genresRead >= 5,
    pages30d >= 1000,
    best >= 30,
    notedBooks >= 10,
    languagesRead >= 3,
  ];
  return [
    for (var i = 0; i < kBadges.length; i++) EarnedBadge(kBadges[i], earned[i]),
  ];
}
