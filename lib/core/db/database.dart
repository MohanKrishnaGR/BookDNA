import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/book_status.dart';
import 'seed_data.dart';
import 'tables.dart';

part 'database.g.dart';

const _uuid = Uuid();

String newId() => _uuid.v7();

int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// Today's local calendar date with the time component zeroed.
DateTime localDate([DateTime? of]) {
  final d = of ?? DateTime.now();
  return DateTime(d.year, d.month, d.day);
}

@DriftDatabase(
  tables: [Books, Notes, ReadingSessions, Lends, Goals, Activities, Prefs, SyncMeta],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase()
      : seedOnCreate = true,
        super(driftDatabase(name: 'bookdna'));

  AppDatabase.forTesting(super.e) : seedOnCreate = false;

  final bool seedOnCreate;

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(syncMeta);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          if (details.wasCreated && seedOnCreate) {
            await seedDemoData(this);
          }
        },
      );

  // ───────────────────────── Books ─────────────────────────

  Stream<List<Book>> watchBooks() => (select(books)
        ..where((b) => b.deletedAt.isNull())
        ..orderBy([(b) => OrderingTerm.desc(b.addedAt)]))
      .watch();

  Stream<Book?> watchBook(String id) =>
      (select(books)..where((b) => b.id.equals(id))).watchSingleOrNull();

  Future<Book?> getBook(String id) =>
      (select(books)..where((b) => b.id.equals(id))).getSingleOrNull();

  Stream<List<Book>> watchCurrentlyReading() => (select(books)
        ..where((b) =>
            b.deletedAt.isNull() & b.status.equalsValue(BookStatus.reading))
        ..orderBy([(b) => OrderingTerm.desc(b.updatedAt)]))
      .watch();

  Future<void> upsertBook(BooksCompanion entry) =>
      into(books).insertOnConflictUpdate(entry);

  Future<void> updateBook(String id, BooksCompanion changes) =>
      (update(books)..where((b) => b.id.equals(id))).write(
        changes.copyWith(
          updatedAt: Value(nowMs()),
          isDirty: const Value(true),
        ),
      );

  Future<void> softDeleteBook(String id) => updateBook(
        id,
        BooksCompanion(deletedAt: Value(DateTime.now())),
      );

  // ───────────────────────── Notes ─────────────────────────

  Stream<List<Note>> watchNotes(String bookId) => (select(notes)
        ..where((n) => n.bookId.equals(bookId) & n.deletedAt.isNull())
        ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]))
      .watch();

  Future<void> addNote(String bookId, String body, int? page) =>
      into(notes).insert(NotesCompanion.insert(
        id: newId(),
        bookId: bookId,
        body: body,
        page: Value(page),
        createdAt: DateTime.now(),
        updatedAt: nowMs(),
      ));

  // ─────────────────────── Sessions ────────────────────────

  Stream<List<ReadingSession>> watchSessions(String bookId) =>
      (select(readingSessions)
            ..where((s) => s.bookId.equals(bookId) & s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
          .watch();

  Stream<List<ReadingSession>> watchAllSessions() => (select(readingSessions)
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.desc(s.sessionDate)]))
      .watch();

  Future<void> addSession({
    required String bookId,
    required int pages,
    required int minutes,
    DateTime? date,
  }) =>
      into(readingSessions).insert(ReadingSessionsCompanion.insert(
        id: newId(),
        bookId: bookId,
        sessionDate: localDate(date),
        pages: pages,
        minutes: minutes,
        createdAt: DateTime.now(),
        updatedAt: nowMs(),
      ));

  // ───────────────────────── Lends ─────────────────────────

  Stream<List<Lend>> watchLends() => (select(lends)
        ..where((l) => l.deletedAt.isNull() & l.returnedOn.isNull())
        ..orderBy([(l) => OrderingTerm.desc(l.lentOn)]))
      .watch();

  Future<void> addLend({
    required String bookTitle,
    String? bookId,
    required String toName,
    DateTime? dueOn,
  }) =>
      into(lends).insert(LendsCompanion.insert(
        id: newId(),
        bookId: Value(bookId),
        bookTitle: bookTitle,
        toName: toName,
        lentOn: DateTime.now(),
        dueOn: Value(dueOn ?? DateTime.now().add(const Duration(days: 21))),
        updatedAt: nowMs(),
      ));

  Future<void> returnLend(String id) =>
      (update(lends)..where((l) => l.id.equals(id))).write(LendsCompanion(
        returnedOn: Value(DateTime.now()),
        updatedAt: Value(nowMs()),
        isDirty: const Value(true),
      ));

  // ───────────────────────── Goals ─────────────────────────

  Stream<Goal?> watchGoal(int year) =>
      (select(goals)..where((g) => g.year.equals(year))).watchSingleOrNull();

  Future<void> setGoal(int year, int target) async {
    final existing = await (select(goals)..where((g) => g.year.equals(year)))
        .getSingleOrNull();
    if (existing == null) {
      await into(goals).insert(GoalsCompanion.insert(
        id: newId(),
        year: year,
        target: target,
        updatedAt: nowMs(),
      ));
    } else {
      await (update(goals)..where((g) => g.year.equals(year)))
          .write(GoalsCompanion(
        target: Value(target),
        updatedAt: Value(nowMs()),
        isDirty: const Value(true),
      ));
    }
  }

  // ─────────────────────── Activities ──────────────────────

  Stream<List<Activity>> watchActivities({int limit = 6}) =>
      (select(activities)
            ..orderBy([(a) => OrderingTerm.desc(a.createdAt)])
            ..limit(limit))
          .watch();

  Future<void> logActivity(String icon, String body) =>
      into(activities).insert(ActivitiesCompanion.insert(
        id: newId(),
        icon: icon,
        body: body,
        createdAt: DateTime.now(),
      ));

  Stream<List<Note>> watchAllNotes() =>
      (select(notes)..where((n) => n.deletedAt.isNull())).watch();

  // ──────────────────────── Sync meta ──────────────────────

  Future<String?> getWatermark(String table) async {
    final row = await (select(syncMeta)
          ..where((m) => m.entity.equals(table)))
        .getSingleOrNull();
    return row?.pullWatermark;
  }

  Future<void> setWatermark(String table, String watermark) =>
      into(syncMeta).insertOnConflictUpdate(SyncMetaCompanion.insert(
        entity: table,
        pullWatermark: Value(watermark),
      ));

  // ───────────────────────── Prefs ─────────────────────────

  Future<String?> getPref(String key) async {
    final row = await (select(prefs)..where((p) => p.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Stream<String?> watchPref(String key) => (select(prefs)
        ..where((p) => p.key.equals(key)))
      .watchSingleOrNull()
      .map((row) => row?.value);

  Future<void> setPref(String key, String value) =>
      into(prefs).insertOnConflictUpdate(PrefsCompanion.insert(
        key: key,
        value: value,
      ));
}
