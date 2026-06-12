import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/models/book_status.dart';
import '../insights/logic/personality.dart';

/// A month of reading, condensed for the Wrapped story.
class WrappedStats {
  const WrappedStats({
    required this.month,
    required this.booksFinished,
    required this.pages,
    required this.hours,
    required this.topGenre,
    required this.topGenreShare,
    required this.topAuthor,
    required this.topAuthorFinished,
    required this.longestStreak,
    required this.archetype,
  });

  final DateTime month;
  final int booksFinished;
  final int pages;
  final int hours;
  final String? topGenre;
  final int topGenreShare; // % of the month's pages
  final String? topAuthor;
  final int topAuthorFinished;
  final int longestStreak;
  final String archetype;

  String get monthLabel => DateFormat('MMMM').format(month);
  String get monthYearLabel => DateFormat('MMMM yyyy').format(month);

  bool get isEmpty => pages == 0 && booksFinished == 0;

  /// Stats for [month]; falls back to the previous month when the current
  /// one has no activity yet (so Wrapped opened on the 1st still plays).
  static WrappedStats compute(
    List<Book> books,
    List<ReadingSession> sessions, {
    DateTime? month,
    bool allowFallback = true,
  }) {
    final now = DateTime.now();
    final m = month ?? DateTime(now.year, now.month);
    final stats = _computeFor(books, sessions, m);
    if (stats.isEmpty && allowFallback && month == null) {
      final prev = DateTime(m.year, m.month - 1);
      final prevStats = _computeFor(books, sessions, prev);
      if (!prevStats.isEmpty) return prevStats;
    }
    return stats;
  }

  static WrappedStats _computeFor(
    List<Book> books,
    List<ReadingSession> sessions,
    DateTime month,
  ) {
    bool inMonth(DateTime d) =>
        d.year == month.year && d.month == month.month;

    final monthSessions =
        sessions.where((s) => inMonth(s.sessionDate)).toList();
    final pages = monthSessions.fold(0, (sum, s) => sum + s.pages);
    final minutes = monthSessions.fold(0, (sum, s) => sum + s.minutes);

    final finished = books
        .where((b) =>
            b.status == BookStatus.read &&
            b.finishedAt != null &&
            inMonth(b.finishedAt!))
        .toList();

    // Top genre by pages read this month (sessions joined to books).
    final bookById = {for (final b in books) b.id: b};
    final genrePages = <String, int>{};
    for (final s in monthSessions) {
      final genre = bookById[s.bookId]?.genre;
      if (genre != null) {
        genrePages[genre] = (genrePages[genre] ?? 0) + s.pages;
      }
    }
    String? topGenre;
    var topGenreShare = 0;
    if (genrePages.isNotEmpty && pages > 0) {
      final top =
          genrePages.entries.reduce((a, b) => b.value > a.value ? b : a);
      topGenre = top.key;
      topGenreShare = (top.value / pages * 100).round();
    }

    // Top author by finished books, falling back to pages read.
    String? topAuthor;
    var topAuthorFinished = 0;
    if (finished.isNotEmpty) {
      final counts = <String, int>{};
      for (final b in finished) {
        if (b.author.isEmpty) continue;
        counts[b.author] = (counts[b.author] ?? 0) + 1;
      }
      if (counts.isNotEmpty) {
        final top =
            counts.entries.reduce((a, b) => b.value > a.value ? b : a);
        topAuthor = top.key;
        topAuthorFinished = top.value;
      }
    }

    // Longest consecutive-day run inside the month.
    final days = monthSessions
        .map((s) => DateTime(
            s.sessionDate.year, s.sessionDate.month, s.sessionDate.day))
        .toSet()
        .toList()
      ..sort();
    var longest = days.isEmpty ? 0 : 1, run = 1;
    for (var i = 1; i < days.length; i++) {
      if (days[i].difference(days[i - 1]).inDays == 1) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 1;
      }
    }

    return WrappedStats(
      month: month,
      booksFinished: finished.length,
      pages: pages,
      hours: (minutes / 60).round(),
      topGenre: topGenre,
      topGenreShare: topGenreShare,
      topAuthor: topAuthor,
      topAuthorFinished: topAuthorFinished,
      longestStreak: longest,
      archetype: computePersonality(books, sessions).archetype,
    );
  }
}
