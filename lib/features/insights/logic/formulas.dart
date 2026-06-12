import 'dart:math' as math;

import '../../../core/db/database.dart';
import '../../../core/models/book_status.dart';

/// Pure stat formulas computed from the local library —
/// the analytical heart of BookDNA. All date math uses local calendar days.

/// Default reading speed (pages/hour) when there is no session history,
/// matching the prototype.
const double kDefaultSpeed = 32;

class LibraryStats {
  const LibraryStats({
    required this.owned,
    required this.read,
    required this.unread,
    required this.reading,
    required this.totalPages,
    required this.pagesRead,
    required this.uniqueAuthors,
    required this.uniqueGenres,
    required this.libraryValue,
    required this.totalInvestment,
    required this.unreadPages,
    required this.unreadHours,
    required this.knowledgeAge,
    required this.readingHours,
  });

  final int owned;
  final int read;
  final int unread;
  final int reading;
  final int totalPages;
  final int pagesRead;
  final int uniqueAuthors;
  final int uniqueGenres;
  final double libraryValue;
  final double totalInvestment;
  final int unreadPages;
  final int unreadHours;
  final int knowledgeAge;
  final int readingHours;
}

LibraryStats computeLibraryStats(
  List<Book> books,
  List<ReadingSession> sessions,
) {
  final owned = books.length;
  final read = books.where((b) => b.status == BookStatus.read).length;
  final unread = books.where((b) => b.status == BookStatus.unread).length;
  final reading = books.where((b) => b.status == BookStatus.reading).length;
  final totalPages = books.fold(0, (s, b) => s + b.pages);
  final pagesRead = books.fold(
      0,
      (s, b) => s +
          (b.status == BookStatus.read
              ? b.pages
              : b.status == BookStatus.reading
                  ? b.currentPage
                  : 0));
  final authors =
      books.map((b) => b.author).where((a) => a.isNotEmpty).toSet();
  final genres = books.map((b) => b.genre).toSet();
  final value =
      books.fold(0.0, (s, b) => s + (b.estValue ?? b.price ?? 0));
  final invested = books.fold(0.0, (s, b) => s + (b.price ?? 0));
  final unreadPages = books
      .where((b) => b.status == BookStatus.unread)
      .fold(0, (s, b) => s + b.pages);
  final speed = readingSpeed(sessions);
  final years = books.map((b) => b.year).whereType<int>().toList()..sort();
  final knowledgeAge = years.isEmpty ? 0 : years[years.length ~/ 2];
  final minutes = sessions.fold(0, (s, x) => s + x.minutes);

  return LibraryStats(
    owned: owned,
    read: read,
    unread: unread,
    reading: reading,
    totalPages: totalPages,
    pagesRead: pagesRead,
    uniqueAuthors: authors.length,
    uniqueGenres: genres.length,
    libraryValue: value,
    totalInvestment: invested,
    unreadPages: unreadPages,
    unreadHours: (unreadPages / speed).round(),
    knowledgeAge: knowledgeAge,
    readingHours: (minutes / 60).round(),
  );
}

/// Pages per hour over the trailing [windowDays], falling back to
/// [kDefaultSpeed] when there is no usable history.
double readingSpeed(List<ReadingSession> sessions, {int windowDays = 90}) {
  final cutoff = DateTime.now().subtract(Duration(days: windowDays));
  var pages = 0, minutes = 0;
  for (final s in sessions) {
    if (s.sessionDate.isAfter(cutoff)) {
      pages += s.pages;
      minutes += s.minutes;
    }
  }
  if (minutes == 0) return kDefaultSpeed;
  return pages / minutes * 60;
}

/// Current streak: consecutive local calendar days with at least one session,
/// counting back from today. A day without reading *today* does not break the
/// streak until midnight (grace), matching habit-tracker convention.
int currentStreak(List<ReadingSession> sessions, {DateTime? today}) {
  if (sessions.isEmpty) return 0;
  final days = sessions
      .map((s) => DateTime(
          s.sessionDate.year, s.sessionDate.month, s.sessionDate.day))
      .toSet();
  final now = today ?? DateTime.now();
  var cursor = DateTime(now.year, now.month, now.day);
  if (!days.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1)); // today's grace
    if (!days.contains(cursor)) return 0;
  }
  var streak = 0;
  while (days.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Longest streak ever.
int bestStreak(List<ReadingSession> sessions) {
  if (sessions.isEmpty) return 0;
  final days = sessions
      .map((s) => DateTime(
          s.sessionDate.year, s.sessionDate.month, s.sessionDate.day))
      .toSet()
      .toList()
    ..sort();
  var best = 1, run = 1;
  for (var i = 1; i < days.length; i++) {
    if (days[i].difference(days[i - 1]).inDays == 1) {
      run++;
      if (run > best) best = run;
    } else {
      run = 1;
    }
  }
  return best;
}

/// Pages per day over the trailing 30 days.
double velocityPagesPerDay(List<ReadingSession> sessions) {
  final cutoff = DateTime.now().subtract(const Duration(days: 30));
  final pages = sessions
      .where((s) => s.sessionDate.isAfter(cutoff))
      .fold(0, (sum, s) => sum + s.pages);
  return pages / 30;
}

/// Estimated days to finish a book (prototype tracker math):
/// `max(1, ceil(pagesLeft / max(10, avg pages per active day)))`.
int daysToFinish(Book book, List<ReadingSession> bookSessions) {
  final left = math.max(0, book.pages - book.currentPage);
  if (left == 0) return 0;
  final recent = bookSessions.take(14).toList();
  double avg = 10;
  if (recent.isNotEmpty) {
    final activeDays = recent
        .map((s) => DateTime(
            s.sessionDate.year, s.sessionDate.month, s.sessionDate.day))
        .toSet()
        .length;
    avg = math.max(10, recent.fold(0, (s, x) => s + x.pages) / activeDays);
  }
  return math.max(1, (left / avg).ceil());
}

/// Genre share of the library: top [top] genres + "Other".
List<({String name, double pct, int count})> genreBreakdown(
  List<Book> books, {
  int top = 4,
}) {
  if (books.isEmpty) return [];
  final counts = <String, int>{};
  for (final b in books) {
    counts[b.genre] = (counts[b.genre] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final result = <({String name, double pct, int count})>[];
  var otherCount = 0;
  for (var i = 0; i < entries.length; i++) {
    if (i < top) {
      result.add((
        name: entries[i].key,
        pct: entries[i].value / books.length * 100,
        count: entries[i].value,
      ));
    } else {
      otherCount += entries[i].value;
    }
  }
  if (otherCount > 0) {
    result.add((
      name: 'Other',
      pct: otherCount / books.length * 100,
      count: otherCount,
    ));
  }
  return result;
}

/// Normalized Shannon entropy of a share distribution, in [0, 1].
double normalizedEntropy(Iterable<int> counts, {required int maxCategories}) {
  final list = counts.where((c) => c > 0).toList();
  if (list.isEmpty || maxCategories <= 1) return 0;
  final total = list.fold(0, (s, c) => s + c);
  var h = 0.0;
  for (final c in list) {
    final p = c / total;
    h -= p * math.log(p);
  }
  return (h / math.log(maxCategories)).clamp(0.0, 1.0);
}

class DiversityAxes {
  const DiversityAxes({
    required this.genre,
    required this.author,
    required this.language,
    required this.era,
    required this.length,
    required this.breadth,
  });

  final double genre;
  final double author;
  final double language;
  final double era;
  final double length;
  final double breadth;

  List<({String axis, double v})> get points => [
        (axis: 'Genre', v: genre),
        (axis: 'Author', v: author),
        (axis: 'Language', v: language),
        (axis: 'Era', v: era),
        (axis: 'Length', v: length),
        (axis: 'Breadth', v: breadth),
      ];

  /// Overall diversity score, 0–100.
  int get score =>
      ((genre + author + language + era + length + breadth) / 6 * 100)
          .round();

  ({String axis, double v}) get weakest =>
      points.reduce((a, b) => a.v <= b.v ? a : b);
}

DiversityAxes computeDiversity(List<Book> books) {
  if (books.isEmpty) {
    return const DiversityAxes(
        genre: 0, author: 0, language: 0, era: 0, length: 0, breadth: 0);
  }

  Map<T, int> tally<T>(Iterable<T> xs) {
    final m = <T, int>{};
    for (final x in xs) {
      m[x] = (m[x] ?? 0) + 1;
    }
    return m;
  }

  final genreCounts = tally(books.map((b) => b.genre));
  final genre = normalizedEntropy(genreCounts.values, maxCategories: 8);

  final uniqueAuthors =
      books.map((b) => b.author).where((a) => a.isNotEmpty).toSet().length;
  final author = (uniqueAuthors / (0.8 * books.length)).clamp(0.0, 1.0);

  final uniqueLanguages = books.map((b) => b.language).toSet().length;
  final language = ((uniqueLanguages - 1) / 3 + 0.4).clamp(0.0, 1.0);

  final decadeCounts = tally(
      books.map((b) => b.year).whereType<int>().map((y) => y ~/ 10));
  final era = normalizedEntropy(decadeCounts.values, maxCategories: 6);

  int bucket(int pages) => pages < 200
      ? 0
      : pages < 400
          ? 1
          : pages < 600
              ? 2
              : 3;
  final lengthCounts = tally(books.map((b) => bucket(b.pages)));
  final length = normalizedEntropy(lengthCounts.values, maxCategories: 4);

  final breadth = (genreCounts.length / 10).clamp(0.0, 1.0);

  return DiversityAxes(
    genre: genre,
    author: author,
    language: language,
    era: era,
    length: length,
    breadth: breadth,
  );
}

/// Heatmap of pages read per day for the trailing [weeks] weeks.
/// Returns `weeks × 7` intensity levels 0–4, bucketed by quantiles.
List<List<int>> readingHeatmap(List<ReadingSession> sessions,
    {int weeks = 18, DateTime? today}) {
  final now = today ?? DateTime.now();
  final end = DateTime(now.year, now.month, now.day);
  final totalDays = weeks * 7;
  final start = end.subtract(Duration(days: totalDays - 1));

  final perDay = <DateTime, int>{};
  for (final s in sessions) {
    final d = DateTime(
        s.sessionDate.year, s.sessionDate.month, s.sessionDate.day);
    if (!d.isBefore(start) && !d.isAfter(end)) {
      perDay[d] = (perDay[d] ?? 0) + s.pages;
    }
  }

  final values = perDay.values.toList()..sort();
  // Percentile rank → level 1–4. Robust for small samples where quantile
  // cut-points collapse (the day's max always renders as level 4).
  int level(int pages) {
    if (pages == 0 || values.isEmpty) return 0;
    final rank = values.where((v) => v <= pages).length / values.length;
    return (rank * 4).ceil().clamp(1, 4);
  }

  return List.generate(weeks, (w) {
    return List.generate(7, (d) {
      final day = start.add(Duration(days: w * 7 + d));
      return level(perDay[day] ?? 0);
    });
  });
}

/// Top authors by owned count (with read counts).
List<({String name, int owned, int read})> topAuthors(List<Book> books,
    {int top = 5}) {
  final owned = <String, int>{};
  final read = <String, int>{};
  for (final b in books) {
    if (b.author.isEmpty) continue;
    owned[b.author] = (owned[b.author] ?? 0) + 1;
    if (b.status == BookStatus.read) {
      read[b.author] = (read[b.author] ?? 0) + 1;
    }
  }
  final entries = owned.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries
      .take(top)
      .map((e) => (name: e.key, owned: e.value, read: read[e.key] ?? 0))
      .toList();
}

/// Dominant genre per acquisition year + cumulative growth, for the
/// evolution curve. Value is cumulative books normalized to 0–100.
List<({String year, String topic, double v})> evolution(List<Book> books) {
  if (books.isEmpty) return [];
  final byYear = <int, List<Book>>{};
  for (final b in books) {
    byYear.putIfAbsent(b.addedAt.year, () => []).add(b);
  }
  final years = byYear.keys.toList()..sort();
  var cumulative = 0;
  final raw = <({String year, String topic, int cum})>[];
  for (final y in years) {
    final list = byYear[y]!;
    cumulative += list.length;
    final counts = <String, int>{};
    for (final b in list) {
      counts[b.genre] = (counts[b.genre] ?? 0) + 1;
    }
    final topic =
        counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    raw.add((year: '$y', topic: topic, cum: cumulative));
  }
  final max = raw.last.cum;
  return raw
      .map((r) => (year: r.year, topic: r.topic, v: r.cum / max * 100))
      .toList();
}

/// Books finished in [year].
int finishedInYear(List<Book> books, int year) => books
    .where((b) =>
        b.status == BookStatus.read && b.finishedAt?.year == year)
    .length;
