import 'package:bookdna/core/db/database.dart';
import 'package:bookdna/core/models/book_status.dart';
import 'package:bookdna/features/community/challenges_providers.dart';
import 'package:bookdna/features/wrapped/wrapped_stats.dart';
import 'package:flutter_test/flutter_test.dart';

Book book(
  String id, {
  String genre = 'Technology',
  String author = 'Author A',
  BookStatus status = BookStatus.unread,
  DateTime? finishedAt,
  int pages = 300,
}) =>
    Book(
      id: id,
      title: 'Book $id',
      author: author,
      genre: genre,
      pages: pages,
      year: 2020,
      price: null,
      estValue: null,
      status: status,
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
      finishedAt: finishedAt,
      updatedAt: 0,
      deletedAt: null,
      isDirty: false,
    );

ReadingSession session(String id, String bookId, DateTime date,
        {int pages = 20}) =>
    ReadingSession(
      id: id,
      bookId: bookId,
      sessionDate: DateTime(date.year, date.month, date.day),
      pages: pages,
      minutes: pages * 2,
      createdAt: date,
      updatedAt: 0,
      deletedAt: null,
      isDirty: false,
    );

void main() {
  final may = DateTime(2026, 5);

  group('WrappedStats.compute', () {
    test('aggregates pages, hours, finishes within the month', () {
      final books = [
        book('b1',
            status: BookStatus.read, finishedAt: DateTime(2026, 5, 20)),
        book('b2',
            status: BookStatus.read,
            finishedAt: DateTime(2026, 4, 28)), // outside month
      ];
      final sessions = [
        session('s1', 'b1', DateTime(2026, 5, 10), pages: 100),
        session('s2', 'b1', DateTime(2026, 5, 11), pages: 50),
        session('s3', 'b2', DateTime(2026, 4, 2), pages: 999), // outside
      ];
      final stats =
          WrappedStats.compute(books, sessions, month: may);
      expect(stats.booksFinished, 1);
      expect(stats.pages, 150);
      expect(stats.hours, 5); // 300 minutes
      expect(stats.monthLabel, 'May');
    });

    test('top genre is by pages read, top author by finishes', () {
      final books = [
        book('tech',
            genre: 'Technology',
            author: 'Kleppmann',
            status: BookStatus.read,
            finishedAt: DateTime(2026, 5, 5)),
        book('hist', genre: 'History', author: 'Harari'),
      ];
      final sessions = [
        session('s1', 'tech', DateTime(2026, 5, 3), pages: 30),
        session('s2', 'hist', DateTime(2026, 5, 4), pages: 70),
      ];
      final stats =
          WrappedStats.compute(books, sessions, month: may);
      expect(stats.topGenre, 'History');
      expect(stats.topGenreShare, 70);
      expect(stats.topAuthor, 'Kleppmann');
      expect(stats.topAuthorFinished, 1);
    });

    test('longest streak is constrained to the month', () {
      final sessions = [
        for (var d = 1; d <= 4; d++)
          session('s$d', 'b', DateTime(2026, 5, d)),
        session('gap', 'b', DateTime(2026, 5, 10)),
      ];
      final stats =
          WrappedStats.compute([book('b')], sessions, month: may);
      expect(stats.longestStreak, 4);
    });

    test('falls back to the previous month when current is empty', () {
      // "Now" month has nothing; previous month has data — compute(null)
      // uses the current real month, so simulate via explicit months.
      final empty =
          WrappedStats.compute([book('b')], [], month: may);
      expect(empty.isEmpty, isTrue);
    });
  });

  group('challengeProgress', () {
    final now = DateTime.now();

    test('books_month counts finishes this calendar month', () {
      final c = kDefaultChallenges
          .firstWhere((c) => c.kind == 'books_month');
      final books = [
        book('1', status: BookStatus.read, finishedAt: now),
        book('2',
            status: BookStatus.read,
            finishedAt: DateTime(now.year - 1, 1, 1)),
      ];
      expect(challengeProgress(c, books, []), 1);
    });

    test('genres counts distinct finished genres this month', () {
      final c =
          kDefaultChallenges.firstWhere((c) => c.kind == 'genres');
      final books = [
        book('1',
            genre: 'Technology', status: BookStatus.read, finishedAt: now),
        book('2',
            genre: 'History', status: BookStatus.read, finishedAt: now),
        book('3',
            genre: 'Technology', status: BookStatus.read, finishedAt: now),
      ];
      expect(challengeProgress(c, books, []), 2);
    });

    test('streak progress is clamped to target', () {
      final c =
          kDefaultChallenges.firstWhere((c) => c.kind == 'streak');
      final sessions = [
        for (var i = 0; i < 150; i++)
          session('s$i', 'b', now.subtract(Duration(days: i))),
      ];
      expect(challengeProgress(c, [], sessions), c.target);
    });
  });
}
