import 'package:bookdna/core/db/database.dart';
import 'package:bookdna/core/models/book_status.dart';
import 'package:bookdna/features/insights/logic/formulas.dart';
import 'package:bookdna/features/insights/logic/personality.dart';
import 'package:flutter_test/flutter_test.dart';

Book book({
  String id = 'b1',
  String title = 'Test Book',
  String author = 'Author',
  String genre = 'Technology',
  int pages = 300,
  int? year = 2020,
  double? price = 1000,
  double? estValue,
  BookStatus status = BookStatus.unread,
  double progress = 0,
  int currentPage = 0,
  String language = 'English',
  DateTime? addedAt,
  DateTime? finishedAt,
}) {
  return Book(
    id: id,
    title: title,
    author: author,
    genre: genre,
    pages: pages,
    year: year,
    price: price,
    estValue: estValue,
    status: status,
    progress: progress,
    currentPage: currentPage,
    rating: null,
    hueShift: 0,
    isbn: null,
    publisher: null,
    language: language,
    description: null,
    coverUrl: null,
    addedAt: addedAt ?? DateTime(2024, 1, 1),
    startedAt: null,
    finishedAt: finishedAt,
    updatedAt: 0,
    deletedAt: null,
    isDirty: false,
  );
}

ReadingSession session({
  String id = 's1',
  String bookId = 'b1',
  required DateTime date,
  int pages = 20,
  int minutes = 30,
}) {
  return ReadingSession(
    id: id,
    bookId: bookId,
    sessionDate: DateTime(date.year, date.month, date.day),
    pages: pages,
    minutes: minutes,
    createdAt: date,
    updatedAt: 0,
    deletedAt: null,
    isDirty: false,
  );
}

void main() {
  group('currentStreak', () {
    final today = DateTime(2026, 6, 12);

    test('empty sessions → 0', () {
      expect(currentStreak([], today: today), 0);
    });

    test('counts consecutive days back from today', () {
      final sessions = [
        for (var i = 0; i < 5; i++)
          session(id: 's$i', date: today.subtract(Duration(days: i))),
      ];
      expect(currentStreak(sessions, today: today), 5);
    });

    test('today not yet read does not break the streak (grace)', () {
      final sessions = [
        for (var i = 1; i <= 3; i++)
          session(id: 's$i', date: today.subtract(Duration(days: i))),
      ];
      expect(currentStreak(sessions, today: today), 3);
    });

    test('gap two days ago breaks the streak', () {
      final sessions = [
        session(id: 'a', date: today),
        session(id: 'b', date: today.subtract(const Duration(days: 1))),
        // gap on day 2
        session(id: 'c', date: today.subtract(const Duration(days: 3))),
      ];
      expect(currentStreak(sessions, today: today), 2);
    });

    test('multiple sessions on one day count once', () {
      final sessions = [
        session(id: 'a', date: today),
        session(id: 'b', date: today),
      ];
      expect(currentStreak(sessions, today: today), 1);
    });
  });

  group('bestStreak', () {
    test('finds longest historical run', () {
      final base = DateTime(2026, 1, 1);
      final sessions = [
        // 3-day run
        for (var i = 0; i < 3; i++)
          session(id: 'x$i', date: base.add(Duration(days: i))),
        // 5-day run later
        for (var i = 0; i < 5; i++)
          session(id: 'y$i', date: base.add(Duration(days: 10 + i))),
      ];
      expect(bestStreak(sessions), 5);
    });
  });

  group('readingSpeed', () {
    test('no sessions → default speed', () {
      expect(readingSpeed([]), kDefaultSpeed);
    });

    test('computes pages per hour', () {
      final sessions = [
        session(date: DateTime.now(), pages: 30, minutes: 60),
        session(id: 's2', date: DateTime.now(), pages: 30, minutes: 60),
      ];
      expect(readingSpeed(sessions), 30);
    });
  });

  group('daysToFinish', () {
    test('finished book → 0', () {
      final b = book(pages: 300, currentPage: 300);
      expect(daysToFinish(b, []), 0);
    });

    test('no sessions → pagesLeft / 10 floor-protected', () {
      final b = book(pages: 100, currentPage: 50);
      expect(daysToFinish(b, []), 5); // 50 left / min-10 avg
    });

    test('at least 1 day when close to the end', () {
      final b = book(pages: 100, currentPage: 99);
      expect(daysToFinish(b, []), 1);
    });
  });

  group('computeLibraryStats', () {
    test('empty library', () {
      final s = computeLibraryStats([], []);
      expect(s.owned, 0);
      expect(s.libraryValue, 0);
      expect(s.knowledgeAge, 0);
    });

    test('counts statuses, values and pages', () {
      final books = [
        book(id: '1', status: BookStatus.read, pages: 200, price: 500),
        book(
            id: '2',
            status: BookStatus.reading,
            pages: 400,
            currentPage: 100,
            price: 1000,
            estValue: 1500),
        book(id: '3', status: BookStatus.unread, pages: 300, price: 800),
      ];
      final s = computeLibraryStats(books, []);
      expect(s.owned, 3);
      expect(s.read, 1);
      expect(s.reading, 1);
      expect(s.unread, 1);
      expect(s.pagesRead, 300); // 200 finished + 100 current
      expect(s.unreadPages, 300);
      expect(s.libraryValue, 500 + 1500 + 800); // estValue wins over price
      expect(s.totalInvestment, 2300);
    });

    test('knowledge age is the median publication year', () {
      final books = [
        book(id: '1', year: 2000),
        book(id: '2', year: 2010),
        book(id: '3', year: 2024),
      ];
      expect(computeLibraryStats(books, []).knowledgeAge, 2010);
    });
  });

  group('genreBreakdown', () {
    test('empty → empty', () {
      expect(genreBreakdown([]), isEmpty);
    });

    test('aggregates beyond top-N into Other', () {
      final books = [
        for (var i = 0; i < 5; i++) book(id: 't$i', genre: 'Technology'),
        for (var i = 0; i < 3; i++) book(id: 'p$i', genre: 'Psychology'),
        book(id: 'b1', genre: 'Business'),
        book(id: 'h1', genre: 'History'),
        book(id: 'f1', genre: 'Fiction'),
      ];
      final breakdown = genreBreakdown(books, top: 2);
      expect(breakdown.first.name, 'Technology');
      expect(breakdown.first.pct, closeTo(45.45, 0.1));
      expect(breakdown.last.name, 'Other');
      expect(breakdown.fold(0.0, (s, g) => s + g.pct), closeTo(100, 0.001));
    });
  });

  group('computeDiversity', () {
    test('empty library → zero axes', () {
      final d = computeDiversity([]);
      expect(d.score, 0);
    });

    test('single-genre library has zero genre entropy', () {
      final books = [
        for (var i = 0; i < 10; i++) book(id: 'b$i', genre: 'Technology'),
      ];
      expect(computeDiversity(books).genre, 0);
    });

    test('even spread across genres scores higher than skewed', () {
      final even = [
        for (var i = 0; i < 4; i++) book(id: 'a$i', genre: 'Technology'),
        for (var i = 0; i < 4; i++) book(id: 'b$i', genre: 'Psychology'),
        for (var i = 0; i < 4; i++) book(id: 'c$i', genre: 'History'),
        for (var i = 0; i < 4; i++) book(id: 'd$i', genre: 'Fiction'),
      ];
      final skewed = [
        for (var i = 0; i < 13; i++) book(id: 'a$i', genre: 'Technology'),
        book(id: 'b0', genre: 'Psychology'),
        book(id: 'c0', genre: 'History'),
        book(id: 'd0', genre: 'Fiction'),
      ];
      expect(computeDiversity(even).genre,
          greaterThan(computeDiversity(skewed).genre));
    });

    test('weakest axis identified', () {
      final books = [
        for (var i = 0; i < 6; i++)
          book(id: 'b$i', genre: 'G$i', author: 'Author $i', year: 1990 + i * 7),
      ];
      final d = computeDiversity(books);
      expect(d.weakest.v,
          d.points.map((p) => p.v).reduce((a, b) => a < b ? a : b));
    });
  });

  group('readingHeatmap', () {
    test('shape is weeks × 7', () {
      final grid = readingHeatmap([], weeks: 9);
      expect(grid.length, 9);
      expect(grid.every((w) => w.length == 7), isTrue);
      expect(grid.every((w) => w.every((d) => d == 0)), isTrue);
    });

    test('days with reading get nonzero levels', () {
      final today = DateTime(2026, 6, 12);
      final sessions = [
        session(date: today, pages: 50),
        session(id: 's2', date: today.subtract(const Duration(days: 1)), pages: 5),
      ];
      final grid = readingHeatmap(sessions, weeks: 2, today: today);
      final flat = grid.expand((w) => w).toList();
      expect(flat.where((l) => l > 0).length, 2);
      expect(flat.last, 4); // today = max quantile
    });
  });

  group('evolution', () {
    test('cumulative values normalized to 100 at the end', () {
      final books = [
        book(id: '1', addedAt: DateTime(2023, 3, 1), genre: 'Business'),
        book(id: '2', addedAt: DateTime(2024, 3, 1), genre: 'Technology'),
        book(id: '3', addedAt: DateTime(2024, 5, 1), genre: 'Technology'),
      ];
      final evo = evolution(books);
      expect(evo.length, 2);
      expect(evo.first.topic, 'Business');
      expect(evo.last.topic, 'Technology');
      expect(evo.last.v, 100);
    });
  });

  group('topAuthors', () {
    test('ranks by owned with read counts', () {
      final books = [
        book(id: '1', author: 'Isaacson', status: BookStatus.read),
        book(id: '2', author: 'Isaacson'),
        book(id: '3', author: 'Newport', status: BookStatus.read),
      ];
      final authors = topAuthors(books);
      expect(authors.first.name, 'Isaacson');
      expect(authors.first.owned, 2);
      expect(authors.first.read, 1);
    });
  });

  group('finishedInYear', () {
    test('only counts finished books in the given year', () {
      final books = [
        book(id: '1', status: BookStatus.read, finishedAt: DateTime(2026, 2, 1)),
        book(id: '2', status: BookStatus.read, finishedAt: DateTime(2025, 12, 31)),
        book(id: '3', status: BookStatus.reading),
      ];
      expect(finishedInYear(books, 2026), 1);
      expect(finishedInYear(books, 2025), 1);
    });
  });

  group('computePersonality', () {
    test('empty library → Newcomer', () {
      expect(computePersonality([], []).archetype, 'The Newcomer');
    });

    test('applied-heavy shelf → The Builder', () {
      final books = [
        for (var i = 0; i < 6; i++)
          book(
              id: 't$i',
              genre: 'Technology',
              pages: 500,
              status: BookStatus.read),
        book(id: 'h1', genre: 'History', pages: 300, status: BookStatus.read),
      ];
      expect(computePersonality(books, []).archetype, 'The Builder');
    });

    test('huge unread pile → The Collector', () {
      // Read mix chosen to dodge earlier rules: no applied genres (Builder),
      // no History/Psychology (Philosopher), no dominant genre (Specialist).
      final books = [
        book(id: 'r1', genre: 'Fiction', pages: 250, status: BookStatus.read),
        book(id: 'r2', genre: 'Self Help', pages: 250, status: BookStatus.read),
        book(id: 'r3', genre: 'Biography', pages: 250, status: BookStatus.read),
        for (var i = 0; i < 12; i++)
          book(id: 'u$i', genre: 'G${i % 5}', status: BookStatus.unread),
      ];
      expect(computePersonality(books, []).archetype, 'The Collector');
    });

    test('dominant single genre → The Specialist', () {
      final books = [
        for (var i = 0; i < 8; i++)
          book(
              id: 'h$i',
              genre: 'History',
              pages: 300,
              status: BookStatus.read),
        book(id: 'f1', genre: 'Fiction', pages: 300, status: BookStatus.read),
      ];
      // History+Psychology rule fires before Specialist? History alone = 88% of
      // pages ≥ 40% — but Specialist (top genre ≥ 50% by count) is checked
      // first... verify deterministic outcome:
      final p = computePersonality(books, []);
      expect(p.archetype, 'The Specialist');
    });
  });

  group('normalizedEntropy', () {
    test('uniform distribution maxes out', () {
      expect(normalizedEntropy([5, 5, 5, 5], maxCategories: 4),
          closeTo(1.0, 0.001));
    });

    test('single category → 0', () {
      expect(normalizedEntropy([10], maxCategories: 4), 0);
    });
  });
}
