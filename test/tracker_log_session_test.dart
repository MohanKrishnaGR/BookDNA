import 'package:bookdna/core/db/database.dart';
import 'package:bookdna/core/models/book_status.dart';
import 'package:bookdna/features/tracker/tracker_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for `logReadingSession` (the session-log commit).
///
/// Bug 1: a book with an unknown page count (pages == 0, typical for manual
/// entries) was instantly marked *finished* by any logged session, because
/// `newPage.clamp(0, 0) >= 0` is always true.
/// Bug 2: logging a session on an unread book flipped it to `reading`
/// without ever recording `startedAt`.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<Book> insertBook({required String id, required int pages}) async {
    await db.upsertBook(BooksCompanion.insert(
      id: id,
      title: 'Test Book',
      pages: Value(pages),
      status: BookStatus.unread,
      addedAt: DateTime.now(),
      updatedAt: nowMs(),
    ));
    return (await db.getBook(id))!;
  }

  test('0-page book: logging a session must NOT mark it finished', () async {
    final book = await insertBook(id: 'b0', pages: 0);

    final finished =
        await logReadingSession(db, book, pages: 20, minutes: 30);

    expect(finished, isFalse,
        reason: 'a 0-page book must never auto-finish from a session log');
    final after = (await db.getBook('b0'))!;
    expect(after.status, BookStatus.reading);
    expect(after.finishedAt, isNull);
    expect(after.startedAt, isNotNull,
        reason: 'first session should start the reading clock');
    expect(after.currentPage, 20,
        reason: 'pages read still accumulate without a known total');
    expect(after.progress, 0);
  });

  test('normal book: crossing the last page finishes it', () async {
    await insertBook(id: 'b1', pages: 100);
    await db.updateBook(
        'b1',
        const BooksCompanion(
            currentPage: Value(90), status: Value(BookStatus.reading)));
    final book = (await db.getBook('b1'))!;

    final finished =
        await logReadingSession(db, book, pages: 20, minutes: 30);

    expect(finished, isTrue);
    final after = (await db.getBook('b1'))!;
    expect(after.status, BookStatus.read);
    expect(after.currentPage, 100, reason: 'clamped to the page count');
    expect(after.progress, 1.0);
    expect(after.finishedAt, isNotNull);
    expect(after.startedAt, isNotNull);
  });

  test('startedAt is preserved across later sessions', () async {
    final book = await insertBook(id: 'b2', pages: 300);
    await logReadingSession(db, book, pages: 10, minutes: 15);
    final firstStart = (await db.getBook('b2'))!.startedAt;
    expect(firstStart, isNotNull);

    await logReadingSession(db, (await db.getBook('b2'))!,
        pages: 10, minutes: 15);
    expect((await db.getBook('b2'))!.startedAt, firstStart,
        reason: 'later sessions must not move the original start date');
  });

  test('session row and activity are recorded', () async {
    final book = await insertBook(id: 'b3', pages: 200);
    await logReadingSession(db, book, pages: 25, minutes: 40);

    final sessions = await db.watchSessions('b3').first;
    expect(sessions, hasLength(1));
    expect(sessions.single.pages, 25);
    expect(sessions.single.minutes, 40);
  });
}
