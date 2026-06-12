import 'package:drift/drift.dart';

import '../models/book_status.dart';

/// Columns shared by every synced table (offline-first LWW sync).
mixin SyncColumns on Table {
  /// Client LWW clock — epoch milliseconds, set on every local mutation.
  IntColumn get updatedAt => integer()();

  /// Soft-delete tombstone.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Local-only: row has unpushed changes.
  BoolColumn get isDirty => boolean().withDefault(const Constant(true))();
}

class Books extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get author => text().withDefault(const Constant(''))();
  TextColumn get genre => text().withDefault(const Constant('Other'))();
  IntColumn get pages => integer().withDefault(const Constant(0))();
  IntColumn get year => integer().nullable()();
  RealColumn get price => real().nullable()();
  RealColumn get estValue => real().nullable()();
  TextColumn get status => textEnum<BookStatus>()();
  RealColumn get progress => real().withDefault(const Constant(0))();
  IntColumn get currentPage => integer().withDefault(const Constant(0))();
  IntColumn get rating => integer().nullable()();
  IntColumn get hueShift => integer().withDefault(const Constant(0))();
  TextColumn get isbn => text().nullable()();
  TextColumn get publisher => text().nullable()();
  TextColumn get language => text().withDefault(const Constant('English'))();
  TextColumn get description => text().nullable()();
  TextColumn get coverUrl => text().nullable()();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get finishedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Notes extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get bookId => text().references(Books, #id)();
  TextColumn get body => text()();
  IntColumn get page => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class ReadingSessions extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get bookId => text().references(Books, #id)();

  /// User-local calendar date of the session (time component zeroed).
  DateTimeColumn get sessionDate => dateTime()();
  IntColumn get pages => integer()();
  IntColumn get minutes => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Lends extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get bookId => text().nullable().references(Books, #id)();
  TextColumn get bookTitle => text()();
  TextColumn get toName => text()();
  DateTimeColumn get lentOn => dateTime()();
  DateTimeColumn get dueOn => dateTime().nullable()();
  DateTimeColumn get returnedOn => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Goals extends Table with SyncColumns {
  TextColumn get id => text()();
  IntColumn get year => integer()();
  IntColumn get target => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {year},
      ];
}

/// Local activity feed shown on Home ("Read 24 pages of …", "Scanned …").
class Activities extends Table {
  TextColumn get id => text()();
  TextColumn get icon => text()();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Per-table pull watermarks for the sync engine (local-only).
class SyncMeta extends Table {
  TextColumn get entity => text()();

  /// Highest `server_updated_at` seen for this table (ISO-8601).
  TextColumn get pullWatermark => text().nullable()();

  @override
  Set<Column> get primaryKey => {entity};
}

/// Simple local key-value store for preferences and app flags.
class Prefs extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
