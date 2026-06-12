import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../models/book_status.dart';
import 'database.dart';

/// Demo library from the design prototype (Mohan's persona: AI/ML-heavy, ₹).
/// Seeded on first launch so the app feels alive; removable in Settings.
class _SeedBook {
  const _SeedBook(
    this.n,
    this.title,
    this.author,
    this.genre,
    this.pages,
    this.year,
    this.price,
    this.status, {
    this.progress = 0,
    this.currentPage = 0,
    this.rating,
    this.hueShift = 0,
    required this.isbn,
    required this.publisher,
    required this.desc,
    required this.addedYear,
    this.finishedDaysAgo,
  });

  final int n;
  final String title;
  final String author;
  final String genre;
  final int pages;
  final int year;
  final double price;
  final BookStatus status;
  final double progress;
  final int currentPage;
  final int? rating;
  final int hueShift;
  final String isbn;
  final String publisher;
  final String desc;
  final int addedYear;
  final int? finishedDaysAgo;
}

// Demo rows get fresh random UUIDs per install: ids are globally unique
// primary keys server-side, so two installs sharing fixed seed ids would
// collide on push (RLS rightly rejects updating another user's rows).

const _seedBooks = [
  _SeedBook(1, 'Designing Data-Intensive Applications', 'Martin Kleppmann',
      'Technology', 616, 2017, 3200, BookStatus.reading,
      progress: 0.62,
      currentPage: 382,
      rating: 5,
      hueShift: 0,
      isbn: '9781449373320',
      publisher: "O'Reilly Media",
      desc:
          'The big ideas behind reliable, scalable, and maintainable systems — and the trade-offs between consistency, availability and performance.',
      addedYear: 2023),
  _SeedBook(2, 'Superintelligence', 'Nick Bostrom', 'AI & Science', 352, 2014,
      1450, BookStatus.read,
      rating: 4,
      hueShift: 150,
      isbn: '9780199678112',
      publisher: 'Oxford University Press',
      desc:
          'Paths, dangers and strategies for a world where machine intelligence surpasses our own.',
      addedYear: 2024,
      finishedDaysAgo: 90),
  _SeedBook(3, 'Zero to One', 'Peter Thiel', 'Business', 224, 2014, 850,
      BookStatus.read,
      rating: 5,
      hueShift: 60,
      isbn: '9780804139298',
      publisher: 'Crown Business',
      desc: 'Notes on startups, and how to build companies that create new things.',
      addedYear: 2020,
      finishedDaysAgo: 700),
  _SeedBook(4, 'Deep Learning', 'Ian Goodfellow', 'AI & Science', 800, 2016,
      4100, BookStatus.unread,
      hueShift: 150,
      isbn: '9780262035613',
      publisher: 'MIT Press',
      desc: 'The foundational mathematics and methods of modern deep learning.',
      addedYear: 2024),
  _SeedBook(5, 'Thinking, Fast and Slow', 'Daniel Kahneman', 'Psychology', 499,
      2011, 999, BookStatus.read,
      rating: 5,
      hueShift: 210,
      isbn: '9780374533557',
      publisher: 'Farrar, Straus and Giroux',
      desc:
          'How two systems of thought shape judgment, decisions and our predictable errors.',
      addedYear: 2021,
      finishedDaysAgo: 420),
  _SeedBook(6, 'The Hard Thing About Hard Things', 'Ben Horowitz', 'Business',
      304, 2014, 899, BookStatus.read,
      rating: 4,
      hueShift: 60,
      isbn: '9780062273208',
      publisher: 'Harper Business',
      desc: 'Building a business when there are no easy answers.',
      addedYear: 2022,
      finishedDaysAgo: 130),
  _SeedBook(7, 'Sapiens', 'Yuval Noah Harari', 'History', 498, 2011, 599,
      BookStatus.read,
      rating: 5,
      hueShift: 270,
      isbn: '9780062316097',
      publisher: 'Harper',
      desc: 'A brief history of humankind, from forager bands to data religions.',
      addedYear: 2019,
      finishedDaysAgo: 60),
  _SeedBook(8, 'Deep Work', 'Cal Newport', 'Self Help', 296, 2016, 650,
      BookStatus.read,
      rating: 4,
      hueShift: 320,
      isbn: '9781455586691',
      publisher: 'Grand Central',
      desc: 'Rules for focused success in a distracted world.',
      addedYear: 2019,
      finishedDaysAgo: 45),
  _SeedBook(9, 'The Lean Startup', 'Eric Ries', 'Business', 336, 2011, 799,
      BookStatus.read,
      rating: 4,
      hueShift: 60,
      isbn: '9780307887894',
      publisher: 'Crown Business',
      desc:
          'How relentless experimentation creates radically successful businesses.',
      addedYear: 2020,
      finishedDaysAgo: 540),
  _SeedBook(10, 'Clean Code', 'Robert C. Martin', 'Technology', 464, 2008,
      2800, BookStatus.read,
      rating: 4,
      hueShift: 0,
      isbn: '9780132350884',
      publisher: 'Prentice Hall',
      desc: 'A handbook of agile software craftsmanship.',
      addedYear: 2021,
      finishedDaysAgo: 365),
  _SeedBook(11, 'Life 3.0', 'Max Tegmark', 'AI & Science', 384, 2017, 1100,
      BookStatus.unread,
      hueShift: 150,
      isbn: '9781101946596',
      publisher: 'Knopf',
      desc: 'Being human in the age of artificial intelligence.',
      addedYear: 2025),
  _SeedBook(12, 'Atomic Habits', 'James Clear', 'Self Help', 320, 2018, 699,
      BookStatus.read,
      rating: 5,
      hueShift: 320,
      isbn: '9780735211292',
      publisher: 'Avery',
      desc: 'Tiny changes, remarkable results.',
      addedYear: 2022,
      finishedDaysAgo: 25),
  _SeedBook(13, 'The Pragmatic Programmer', 'David Thomas', 'Technology', 352,
      2019, 3000, BookStatus.reading,
      progress: 0.18,
      currentPage: 63,
      hueShift: 0,
      isbn: '9780135957059',
      publisher: 'Addison-Wesley',
      desc: 'Your journey to mastery — 20th anniversary edition.',
      addedYear: 2026),
  _SeedBook(14, 'AI 2041', 'Kai-Fu Lee', 'AI & Science', 480, 2021, 1250,
      BookStatus.unread,
      hueShift: 150,
      isbn: '9780593238295',
      publisher: 'Currency',
      desc: 'Ten visions for our future with artificial intelligence.',
      addedYear: 2026),
  _SeedBook(15, 'The Psychology of Money', 'Morgan Housel', 'Psychology', 256,
      2020, 450, BookStatus.read,
      rating: 5,
      hueShift: 210,
      isbn: '9780857197689',
      publisher: 'Harriman House',
      desc: 'Timeless lessons on wealth, greed and happiness.',
      addedYear: 2023,
      finishedDaysAgo: 15),
  _SeedBook(16, 'Hooked', 'Nir Eyal', 'Business', 256, 2014, 750,
      BookStatus.unread,
      hueShift: 60,
      isbn: '9781591847786',
      publisher: 'Portfolio',
      desc: 'How to build habit-forming products.',
      addedYear: 2025),
  _SeedBook(17, 'The Innovators', 'Walter Isaacson', 'Biography', 560, 2014,
      950, BookStatus.unread,
      hueShift: 30,
      isbn: '9781476708690',
      publisher: 'Simon & Schuster',
      desc:
          'How a group of hackers, geniuses and geeks created the digital revolution.',
      addedYear: 2024),
  _SeedBook(18, 'Steve Jobs', 'Walter Isaacson', 'Biography', 656, 2011, 899,
      BookStatus.read,
      rating: 4,
      hueShift: 30,
      isbn: '9781451648539',
      publisher: 'Simon & Schuster',
      desc: 'The exclusive biography.',
      addedYear: 2021,
      finishedDaysAgo: 600),
  _SeedBook(19, 'Probabilistic Machine Learning', 'Kevin P. Murphy',
      'AI & Science', 864, 2022, 5200, BookStatus.unread,
      hueShift: 150,
      isbn: '9780262046824',
      publisher: 'MIT Press',
      desc:
          'An introduction — the modern statistical view of machine learning.',
      addedYear: 2026),
  _SeedBook(20, 'Show Your Work!', 'Austin Kleon', 'Self Help', 224, 2014, 550,
      BookStatus.read,
      rating: 3,
      hueShift: 320,
      isbn: '9780761178972',
      publisher: 'Workman',
      desc: '10 ways to share your creativity and get discovered.',
      addedYear: 2023,
      finishedDaysAgo: 200),
];

Future<void> seedDemoData(AppDatabase db) async {
  final now = DateTime.now();
  final ts = nowMs();
  final bookIds = {for (final b in _seedBooks) b.n: newId()};

  await db.batch((batch) {
    // Books.
    for (final b in _seedBooks) {
      batch.insert(
        db.books,
        BooksCompanion.insert(
          id: bookIds[b.n]!,
          title: b.title,
          author: Value(b.author),
          genre: Value(b.genre),
          pages: Value(b.pages),
          year: Value(b.year),
          price: Value(b.price),
          estValue: Value(b.price * 1.3),
          status: b.status,
          progress: Value(b.status == BookStatus.read ? 1 : b.progress),
          currentPage: Value(
              b.status == BookStatus.read ? b.pages : b.currentPage),
          rating: Value(b.rating),
          hueShift: Value(b.hueShift),
          isbn: Value(b.isbn),
          publisher: Value(b.publisher),
          description: Value(b.desc),
          addedAt: DateTime(b.addedYear, (b.n * 5) % 12 + 1, (b.n * 7) % 27 + 1),
          startedAt: Value(b.status == BookStatus.unread
              ? null
              : now.subtract(Duration(days: (b.finishedDaysAgo ?? 30) + 40))),
          finishedAt: Value(b.finishedDaysAgo == null
              ? null
              : now.subtract(Duration(days: b.finishedDaysAgo!))),
          updatedAt: ts,
        ),
      );
    }

    // Reading sessions across the past 18 weeks (prototype heatmap pattern),
    // attributed to the two currently-reading books.
    final sessionBooks = [bookIds[1]!, bookIds[13]!];
    for (var daysAgo = 125; daysAgo >= 23; daysAgo--) {
      final w = daysAgo ~/ 7, d = daysAgo % 7;
      final x = math.sin(w * 3.7 + d * 5.3) * math.cos(w * 1.3 - d * 2.1);
      final level = x > 0.55
          ? 4
          : x > 0.25
              ? 3
              : x > -0.1
                  ? 2
                  : x > -0.5
                      ? 1
                      : 0;
      if (level == 0) continue;
      final pages = 6 + level * 7 + (daysAgo % 5);
      batch.insert(
        db.readingSessions,
        ReadingSessionsCompanion.insert(
          id: newId(),
          bookId: sessionBooks[daysAgo % 2],
          sessionDate: localDate(now.subtract(Duration(days: daysAgo))),
          pages: pages,
          minutes: pages * 2,
          createdAt: now.subtract(Duration(days: daysAgo)),
          updatedAt: ts,
        ),
      );
    }
    // A live 23-day streak ending today (prototype: streak = 23).
    for (var daysAgo = 22; daysAgo >= 0; daysAgo--) {
      final pages = 10 + (daysAgo * 3) % 18;
      batch.insert(
        db.readingSessions,
        ReadingSessionsCompanion.insert(
          id: newId(),
          bookId: sessionBooks[daysAgo % 2],
          sessionDate: localDate(now.subtract(Duration(days: daysAgo))),
          pages: pages,
          minutes: pages * 2,
          createdAt: now.subtract(Duration(days: daysAgo)),
          updatedAt: ts,
        ),
      );
    }

    // Notes on the active book.
    batch.insert(
      db.notes,
      NotesCompanion.insert(
        id: newId(),
        bookId: bookIds[1]!,
        body:
            'The hardest part of distributed systems isn\'t the algorithms — it\'s reasoning about partial failure.',
        page: const Value(287),
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: ts,
      ),
    );
    batch.insert(
      db.notes,
      NotesCompanion.insert(
        id: newId(),
        bookId: bookIds[1]!,
        body: '"Data outlives code." Design schemas for evolution.',
        page: const Value(132),
        createdAt: now.subtract(const Duration(days: 18)),
        updatedAt: ts,
      ),
    );

    // Lends (Zero to One overdue, Atomic Habits on time).
    batch.insert(
      db.lends,
      LendsCompanion.insert(
        id: newId(),
        bookId: Value(bookIds[3]),
        bookTitle: 'Zero to One',
        toName: 'Arjun K',
        lentOn: now.subtract(const Duration(days: 30)),
        dueOn: Value(now.subtract(const Duration(days: 9))),
        updatedAt: ts,
      ),
    );
    batch.insert(
      db.lends,
      LendsCompanion.insert(
        id: newId(),
        bookId: Value(bookIds[12]),
        bookTitle: 'Atomic Habits',
        toName: 'Sneha R',
        lentOn: now.subtract(const Duration(days: 14)),
        dueOn: Value(now.add(const Duration(days: 7))),
        updatedAt: ts,
      ),
    );

    // Reading goal for the current year.
    batch.insert(
      db.goals,
      GoalsCompanion.insert(
        id: newId(),
        year: now.year,
        target: 12,
        updatedAt: ts,
      ),
    );

    // Recent activity feed.
    final activitySeed = [
      ('auto_stories', 'Read 24 pages of Designing Data-Intensive Applications', 2),
      ('barcode_scanner', 'Scanned AI 2041 into your library', 26),
      ('military_tech', 'Earned the "Genre Explorer" badge', 30),
      ('star', 'Rated The Psychology of Money ★★★★★', 50),
    ];
    var j = 0;
    for (final (icon, body, hoursAgo) in activitySeed) {
      batch.insert(
        db.activities,
        ActivitiesCompanion.insert(
          id: 'seed-a-${j++}',
          icon: icon,
          body: body,
          createdAt: now.subtract(Duration(hours: hoursAgo)),
        ),
      );
    }
  });
}
