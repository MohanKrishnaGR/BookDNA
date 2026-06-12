import 'package:drift/drift.dart';

import '../db/database.dart';
import '../models/book_status.dart';
import 'sync_remote.dart';

/// Offline-first replication: local Drift is the source of truth; this engine
/// pushes dirty rows and pulls remote changes per-table.
///
/// Conflict resolution is row-level last-writer-wins on the client clock
/// (`updated_at`, epoch ms): a dirty local row that is at least as new as the
/// incoming remote row is kept (it pushes next cycle); otherwise remote wins.
/// Pull progress is tracked by the server-set `server_updated_at` watermark,
/// which is immune to client clock skew.
class SyncEngine {
  SyncEngine(this.db, this.remote);

  final AppDatabase db;
  final SyncRemote remote;

  static const _chunk = 200;

  bool get canSync => remote.userId != null;

  /// Push all dirty rows, then pull everything newer than our watermarks.
  Future<void> syncNow() async {
    if (!canSync) return;
    await push();
    await pull();
  }

  /// Adopt-and-push: first sign-in on a device with existing local data —
  /// every row becomes the new user's and is queued for push.
  Future<void> adoptLocalData() async {
    final dirty = const BooksCompanion(isDirty: Value(true));
    await db.update(db.books).write(dirty);
    await db
        .update(db.notes)
        .write(const NotesCompanion(isDirty: Value(true)));
    await db
        .update(db.readingSessions)
        .write(const ReadingSessionsCompanion(isDirty: Value(true)));
    await db.update(db.lends).write(const LendsCompanion(isDirty: Value(true)));
    await db.update(db.goals).write(const GoalsCompanion(isDirty: Value(true)));
  }

  // ───────────────────────── push ─────────────────────────

  Future<void> push() async {
    final uid = remote.userId;
    if (uid == null) return;

    await _pushTable<Book>(
      table: 'books',
      dirtyRows: (db.select(db.books)..where((b) => b.isDirty.equals(true)))
          .get(),
      toRemote: (b) => _bookToRemote(b, uid),
      clock: (b) => b.updatedAt,
      clearDirty: (ids, clocks) => _clearDirty(db.books, ids, clocks),
    );
    await _pushTable<Note>(
      table: 'notes',
      dirtyRows: (db.select(db.notes)..where((n) => n.isDirty.equals(true)))
          .get(),
      toRemote: (n) => _noteToRemote(n, uid),
      clock: (n) => n.updatedAt,
      clearDirty: (ids, clocks) => _clearDirty(db.notes, ids, clocks),
    );
    await _pushTable<ReadingSession>(
      table: 'reading_sessions',
      dirtyRows: (db.select(db.readingSessions)
            ..where((s) => s.isDirty.equals(true)))
          .get(),
      toRemote: (s) => _sessionToRemote(s, uid),
      clock: (s) => s.updatedAt,
      clearDirty: (ids, clocks) => _clearDirty(db.readingSessions, ids, clocks),
    );
    await _pushTable<Lend>(
      table: 'lends',
      dirtyRows:
          (db.select(db.lends)..where((l) => l.isDirty.equals(true))).get(),
      toRemote: (l) => _lendToRemote(l, uid),
      clock: (l) => l.updatedAt,
      clearDirty: (ids, clocks) => _clearDirty(db.lends, ids, clocks),
    );
    await _pushTable<Goal>(
      table: 'goals',
      dirtyRows:
          (db.select(db.goals)..where((g) => g.isDirty.equals(true))).get(),
      toRemote: (g) => _goalToRemote(g, uid),
      clock: (g) => g.updatedAt,
      clearDirty: (ids, clocks) => _clearDirty(db.goals, ids, clocks),
    );
  }

  Future<void> _pushTable<T>({
    required String table,
    required Future<List<T>> dirtyRows,
    required Map<String, dynamic> Function(T) toRemote,
    required int Function(T) clock,
    required Future<void> Function(List<String> ids, Map<String, int> clocks)
        clearDirty,
  }) async {
    final rows = await dirtyRows;
    if (rows.isEmpty) return;
    final clocks = {
      for (final r in rows) (toRemote(r)['id'] as String): clock(r),
    };
    for (var i = 0; i < rows.length; i += _chunk) {
      final batch = rows.sublist(i, (i + _chunk).clamp(0, rows.length));
      await remote.upsert(table, batch.map(toRemote).toList());
      await clearDirty(
          batch.map((r) => toRemote(r)['id'] as String).toList(), clocks);
    }
  }

  /// Clear dirty only when the row is unchanged since the push snapshot —
  /// a concurrent local edit keeps its flag and pushes next cycle.
  Future<void> _clearDirty<Tbl extends Table, Row>(
    TableInfo<Tbl, Row> table,
    List<String> ids,
    Map<String, int> clocks,
  ) async {
    for (final id in ids) {
      await db.customUpdate(
        'UPDATE ${table.actualTableName} SET is_dirty = 0 '
        'WHERE id = ? AND updated_at = ?',
        variables: [Variable(id), Variable(clocks[id])],
        updates: {table},
      );
    }
  }

  // ───────────────────────── pull ─────────────────────────

  Future<void> pull() async {
    if (!canSync) return;
    await _pullTable('books', _applyRemoteBook);
    await _pullTable('notes', _applyRemoteNote);
    await _pullTable('reading_sessions', _applyRemoteSession);
    await _pullTable('lends', _applyRemoteLend);
    await _pullTable('goals', _applyRemoteGoal);
  }

  Future<void> _pullTable(
    String table,
    Future<void> Function(Map<String, dynamic>) apply,
  ) async {
    var watermark = await db.getWatermark(table);
    while (true) {
      final rows = await remote.pullSince(table, watermark);
      if (rows.isEmpty) break;
      for (final row in rows) {
        await apply(row);
      }
      watermark = rows.last['server_updated_at'] as String;
      await db.setWatermark(table, watermark);
      if (rows.length < 500) break;
    }
  }

  /// LWW gate: returns true when the incoming remote row should overwrite
  /// the local one.
  bool _remoteWins({
    required int remoteClock,
    required int? localClock,
    required bool localDirty,
  }) {
    if (localClock == null) return true; // no local row
    if (localDirty) return remoteClock > localClock;
    return remoteClock >= localClock;
  }

  // ─────────────────── per-table mappers ───────────────────

  Map<String, dynamic> _bookToRemote(Book b, String uid) => {
        'id': b.id,
        'user_id': uid,
        'title': b.title,
        'author': b.author,
        'genre': b.genre,
        'pages': b.pages,
        'year': b.year,
        'price': b.price,
        'est_value': b.estValue,
        'status': b.status.name,
        'progress': b.progress,
        'current_page': b.currentPage,
        'rating': b.rating,
        'hue_shift': b.hueShift,
        'isbn': b.isbn,
        'publisher': b.publisher,
        'language': b.language,
        'description': b.description,
        'cover_url': b.coverUrl,
        'added_at': b.addedAt.toUtc().toIso8601String(),
        'started_at': b.startedAt?.toUtc().toIso8601String(),
        'finished_at': b.finishedAt?.toUtc().toIso8601String(),
        'updated_at': b.updatedAt,
        'deleted_at': b.deletedAt?.toUtc().toIso8601String(),
      };

  Future<void> _applyRemoteBook(Map<String, dynamic> r) async {
    final local = await db.getBook(r['id'] as String);
    if (!_remoteWins(
      remoteClock: r['updated_at'] as int,
      localClock: local?.updatedAt,
      localDirty: local?.isDirty ?? false,
    )) {
      return;
    }
    await db.into(db.books).insertOnConflictUpdate(BooksCompanion(
          id: Value(r['id'] as String),
          title: Value(r['title'] as String),
          author: Value(r['author'] as String? ?? ''),
          genre: Value(r['genre'] as String? ?? 'Other'),
          pages: Value((r['pages'] as num?)?.toInt() ?? 0),
          year: Value((r['year'] as num?)?.toInt()),
          price: Value((r['price'] as num?)?.toDouble()),
          estValue: Value((r['est_value'] as num?)?.toDouble()),
          status: Value(BookStatus.values.byName(r['status'] as String)),
          progress: Value((r['progress'] as num?)?.toDouble() ?? 0),
          currentPage: Value((r['current_page'] as num?)?.toInt() ?? 0),
          rating: Value((r['rating'] as num?)?.toInt()),
          hueShift: Value((r['hue_shift'] as num?)?.toInt() ?? 0),
          isbn: Value(r['isbn'] as String?),
          publisher: Value(r['publisher'] as String?),
          language: Value(r['language'] as String? ?? 'English'),
          description: Value(r['description'] as String?),
          coverUrl: Value(r['cover_url'] as String?),
          addedAt: Value(_ts(r['added_at'])!),
          startedAt: Value(_ts(r['started_at'])),
          finishedAt: Value(_ts(r['finished_at'])),
          updatedAt: Value(r['updated_at'] as int),
          deletedAt: Value(_ts(r['deleted_at'])),
          isDirty: const Value(false),
        ));
  }

  Map<String, dynamic> _noteToRemote(Note n, String uid) => {
        'id': n.id,
        'user_id': uid,
        'book_id': n.bookId,
        'body': n.body,
        'page': n.page,
        'created_at': n.createdAt.toUtc().toIso8601String(),
        'updated_at': n.updatedAt,
        'deleted_at': n.deletedAt?.toUtc().toIso8601String(),
      };

  Future<void> _applyRemoteNote(Map<String, dynamic> r) async {
    final local = await (db.select(db.notes)
          ..where((n) => n.id.equals(r['id'] as String)))
        .getSingleOrNull();
    if (!_remoteWins(
      remoteClock: r['updated_at'] as int,
      localClock: local?.updatedAt,
      localDirty: local?.isDirty ?? false,
    )) {
      return;
    }
    await db.into(db.notes).insertOnConflictUpdate(NotesCompanion(
          id: Value(r['id'] as String),
          bookId: Value(r['book_id'] as String),
          body: Value(r['body'] as String),
          page: Value((r['page'] as num?)?.toInt()),
          createdAt: Value(_ts(r['created_at'])!),
          updatedAt: Value(r['updated_at'] as int),
          deletedAt: Value(_ts(r['deleted_at'])),
          isDirty: const Value(false),
        ));
  }

  Map<String, dynamic> _sessionToRemote(ReadingSession s, String uid) => {
        'id': s.id,
        'user_id': uid,
        'book_id': s.bookId,
        'session_date':
            s.sessionDate.toIso8601String().substring(0, 10),
        'pages': s.pages,
        'minutes': s.minutes,
        'created_at': s.createdAt.toUtc().toIso8601String(),
        'updated_at': s.updatedAt,
        'deleted_at': s.deletedAt?.toUtc().toIso8601String(),
      };

  Future<void> _applyRemoteSession(Map<String, dynamic> r) async {
    final local = await (db.select(db.readingSessions)
          ..where((s) => s.id.equals(r['id'] as String)))
        .getSingleOrNull();
    if (!_remoteWins(
      remoteClock: r['updated_at'] as int,
      localClock: local?.updatedAt,
      localDirty: local?.isDirty ?? false,
    )) {
      return;
    }
    final date = r['session_date'] as String;
    await db
        .into(db.readingSessions)
        .insertOnConflictUpdate(ReadingSessionsCompanion(
          id: Value(r['id'] as String),
          bookId: Value(r['book_id'] as String),
          sessionDate: Value(DateTime.parse(date)),
          pages: Value((r['pages'] as num).toInt()),
          minutes: Value((r['minutes'] as num).toInt()),
          createdAt: Value(_ts(r['created_at'])!),
          updatedAt: Value(r['updated_at'] as int),
          deletedAt: Value(_ts(r['deleted_at'])),
          isDirty: const Value(false),
        ));
  }

  Map<String, dynamic> _lendToRemote(Lend l, String uid) => {
        'id': l.id,
        'user_id': uid,
        'book_id': l.bookId,
        'book_title': l.bookTitle,
        'to_name': l.toName,
        'lent_on': l.lentOn.toUtc().toIso8601String(),
        'due_on': l.dueOn?.toUtc().toIso8601String(),
        'returned_on': l.returnedOn?.toUtc().toIso8601String(),
        'updated_at': l.updatedAt,
        'deleted_at': l.deletedAt?.toUtc().toIso8601String(),
      };

  Future<void> _applyRemoteLend(Map<String, dynamic> r) async {
    final local = await (db.select(db.lends)
          ..where((l) => l.id.equals(r['id'] as String)))
        .getSingleOrNull();
    if (!_remoteWins(
      remoteClock: r['updated_at'] as int,
      localClock: local?.updatedAt,
      localDirty: local?.isDirty ?? false,
    )) {
      return;
    }
    await db.into(db.lends).insertOnConflictUpdate(LendsCompanion(
          id: Value(r['id'] as String),
          bookId: Value(r['book_id'] as String?),
          bookTitle: Value(r['book_title'] as String),
          toName: Value(r['to_name'] as String),
          lentOn: Value(_ts(r['lent_on'])!),
          dueOn: Value(_ts(r['due_on'])),
          returnedOn: Value(_ts(r['returned_on'])),
          updatedAt: Value(r['updated_at'] as int),
          deletedAt: Value(_ts(r['deleted_at'])),
          isDirty: const Value(false),
        ));
  }

  Map<String, dynamic> _goalToRemote(Goal g, String uid) => {
        'id': g.id,
        'user_id': uid,
        'year': g.year,
        'target': g.target,
        'updated_at': g.updatedAt,
        'deleted_at': g.deletedAt?.toUtc().toIso8601String(),
      };

  Future<void> _applyRemoteGoal(Map<String, dynamic> r) async {
    final local = await (db.select(db.goals)
          ..where((g) => g.id.equals(r['id'] as String)))
        .getSingleOrNull();
    if (!_remoteWins(
      remoteClock: r['updated_at'] as int,
      localClock: local?.updatedAt,
      localDirty: local?.isDirty ?? false,
    )) {
      return;
    }
    await db.into(db.goals).insertOnConflictUpdate(GoalsCompanion(
          id: Value(r['id'] as String),
          year: Value((r['year'] as num).toInt()),
          target: Value((r['target'] as num).toInt()),
          updatedAt: Value(r['updated_at'] as int),
          deletedAt: Value(_ts(r['deleted_at'])),
          isDirty: const Value(false),
        ));
  }

  DateTime? _ts(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();
}
