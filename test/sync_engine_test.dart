import 'package:bookdna/core/db/database.dart';
import 'package:bookdna/core/models/book_status.dart';
import 'package:bookdna/core/sync/sync_engine.dart';
import 'package:bookdna/core/sync/sync_remote.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for Supabase: rows keyed by id per table, with a
/// monotonically increasing fake `server_updated_at`.
class FakeRemote implements SyncRemote {
  FakeRemote({this.userId = 'user-1'});

  @override
  String? userId;

  final Map<String, Map<String, Map<String, dynamic>>> tables = {};
  int _serverClock = 0;
  int upsertCalls = 0;

  String _nextStamp() {
    _serverClock++;
    return DateTime.utc(2026, 1, 1)
        .add(Duration(seconds: _serverClock))
        .toIso8601String();
  }

  /// Seed a row server-side (as another device would).
  void seed(String table, Map<String, dynamic> row) {
    final stamped = {...row, 'server_updated_at': _nextStamp()};
    tables.putIfAbsent(table, () => {})[row['id'] as String] = stamped;
  }

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    upsertCalls++;
    final t = tables.putIfAbsent(table, () => {});
    for (final row in rows) {
      t[row['id'] as String] = {...row, 'server_updated_at': _nextStamp()};
    }
  }

  @override
  Future<List<Map<String, dynamic>>> pullSince(
    String table,
    String? watermark, {
    int limit = 500,
  }) async {
    final rows = (tables[table] ?? {}).values.where((r) {
      if (watermark == null) return true;
      return (r['server_updated_at'] as String).compareTo(watermark) > 0;
    }).toList()
      ..sort((a, b) => (a['server_updated_at'] as String)
          .compareTo(b['server_updated_at'] as String));
    return rows.take(limit).toList();
  }
}

Map<String, dynamic> remoteBook(
  String id, {
  String title = 'Remote Book',
  int updatedAt = 1000,
  String? deletedAt,
}) =>
    {
      'id': id,
      'user_id': 'user-1',
      'title': title,
      'author': 'Author',
      'genre': 'Technology',
      'pages': 300,
      'year': 2020,
      'price': 500,
      'est_value': 650,
      'status': 'unread',
      'progress': 0.0,
      'current_page': 0,
      'rating': null,
      'hue_shift': 0,
      'isbn': null,
      'publisher': null,
      'language': 'English',
      'description': null,
      'cover_url': null,
      'added_at': '2026-01-01T00:00:00Z',
      'started_at': null,
      'finished_at': null,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
    };

void main() {
  late AppDatabase db;
  late FakeRemote remote;
  late SyncEngine engine;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    remote = FakeRemote();
    engine = SyncEngine(db, remote);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertLocalBook(
    String id, {
    String title = 'Local Book',
    int updatedAt = 1000,
    bool dirty = true,
  }) {
    return db.into(db.books).insert(BooksCompanion.insert(
          id: id,
          title: title,
          status: BookStatus.unread,
          addedAt: DateTime(2026, 1, 1),
          updatedAt: updatedAt,
          isDirty: Value(dirty),
        ));
  }

  test('push uploads dirty rows and clears the dirty flag', () async {
    await insertLocalBook('b1');
    await engine.push();

    expect(remote.tables['books']!['b1']!['title'], 'Local Book');
    expect(remote.tables['books']!['b1']!['user_id'], 'user-1');
    final local = await db.getBook('b1');
    expect(local!.isDirty, false);
  });

  test('push skips when signed out', () async {
    remote.userId = null;
    await insertLocalBook('b1');
    await engine.syncNow();
    expect(remote.tables['books'], isNull);
  });

  test('pull inserts new remote rows and advances the watermark', () async {
    remote.seed('books', remoteBook('b2', title: 'From Other Device'));
    await engine.pull();

    final local = await db.getBook('b2');
    expect(local!.title, 'From Other Device');
    expect(local.isDirty, false);
    expect(await db.getWatermark('books'), isNotNull);
  });

  test('second pull is incremental (no rows re-applied)', () async {
    remote.seed('books', remoteBook('b2'));
    await engine.pull();
    final w1 = await db.getWatermark('books');
    await engine.pull(); // nothing new
    expect(await db.getWatermark('books'), w1);
  });

  test('conflict: dirty local row newer than remote is kept', () async {
    await insertLocalBook('b3', title: 'Local Edit', updatedAt: 2000);
    remote.seed('books', remoteBook('b3', title: 'Stale Remote', updatedAt: 1000));

    await engine.pull();

    final local = await db.getBook('b3');
    expect(local!.title, 'Local Edit'); // local wins
    expect(local.isDirty, true); // still pushes next cycle
  });

  test('conflict: newer remote row overwrites stale local edit', () async {
    await insertLocalBook('b4', title: 'Old Local', updatedAt: 1000);
    remote.seed('books', remoteBook('b4', title: 'Newer Remote', updatedAt: 2000));

    await engine.pull();

    final local = await db.getBook('b4');
    expect(local!.title, 'Newer Remote');
    expect(local.isDirty, false);
  });

  test('tombstones propagate: remote delete soft-deletes locally', () async {
    await insertLocalBook('b5', updatedAt: 1000, dirty: false);
    remote.seed(
        'books',
        remoteBook('b5',
            updatedAt: 2000, deletedAt: '2026-01-02T00:00:00Z'));

    await engine.pull();

    final local = await (db.select(db.books)
          ..where((b) => b.id.equals('b5')))
        .getSingleOrNull();
    expect(local!.deletedAt, isNotNull);

    // And it disappears from the visible library stream.
    final visible = await db.watchBooks().first;
    expect(visible.where((b) => b.id == 'b5'), isEmpty);
  });

  test('round trip: push then pull is stable (no echo overwrite)', () async {
    await insertLocalBook('b6', title: 'Mine', updatedAt: 1500);
    await engine.syncNow();

    final local = await db.getBook('b6');
    expect(local!.title, 'Mine');
    expect(local.isDirty, false);
  });

  test('adoptLocalData marks everything dirty for re-push', () async {
    await insertLocalBook('b7', dirty: false);
    await engine.adoptLocalData();
    final local = await db.getBook('b7');
    expect(local!.isDirty, true);
  });

  test('sessions, notes, lends and goals sync end to end', () async {
    await insertLocalBook('b8', dirty: true);
    await db.addSession(bookId: 'b8', pages: 20, minutes: 30);
    await db.addNote('b8', 'A thought', 12);
    await db.addLend(bookTitle: 'Local Book', bookId: 'b8', toName: 'Priya S');
    await db.setGoal(2026, 24);

    await engine.syncNow();

    expect(remote.tables['reading_sessions'], hasLength(1));
    expect(remote.tables['notes']!.values.first['body'], 'A thought');
    expect(remote.tables['lends']!.values.first['to_name'], 'Priya S');
    expect(remote.tables['goals']!.values.first['target'], 24);

    // A fresh device pulls the same library.
    final db2 = AppDatabase.forTesting(NativeDatabase.memory());
    final engine2 = SyncEngine(db2, remote);
    await engine2.pull();
    expect((await db2.watchBooks().first), hasLength(1));
    expect(await db2.watchSessions('b8').first, hasLength(1));
    expect(await db2.watchNotes('b8').first, hasLength(1));
    expect(await db2.watchLends().first, hasLength(1));
    final goal = await db2.watchGoal(2026).first;
    expect(goal!.target, 24);
    await db2.close();
  });

  test('large push batches in chunks of 200', () async {
    for (var i = 0; i < 450; i++) {
      await insertLocalBook('bulk-$i');
    }
    await engine.push();
    expect(remote.tables['books'], hasLength(450));
    expect(remote.upsertCalls, 3); // 200 + 200 + 50
  });
}
