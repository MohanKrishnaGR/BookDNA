import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final booksProvider = StreamProvider<List<Book>>(
    (ref) => ref.watch(databaseProvider).watchBooks());

final bookProvider = StreamProvider.family<Book?, String>(
    (ref, id) => ref.watch(databaseProvider).watchBook(id));

final currentlyReadingProvider = StreamProvider<List<Book>>(
    (ref) => ref.watch(databaseProvider).watchCurrentlyReading());

final allSessionsProvider = StreamProvider<List<ReadingSession>>(
    (ref) => ref.watch(databaseProvider).watchAllSessions());

final bookSessionsProvider = StreamProvider.family<List<ReadingSession>, String>(
    (ref, bookId) => ref.watch(databaseProvider).watchSessions(bookId));

final bookNotesProvider = StreamProvider.family<List<Note>, String>(
    (ref, bookId) => ref.watch(databaseProvider).watchNotes(bookId));

final lendsProvider = StreamProvider<List<Lend>>(
    (ref) => ref.watch(databaseProvider).watchLends());

final goalProvider = StreamProvider<Goal?>((ref) =>
    ref.watch(databaseProvider).watchGoal(DateTime.now().year));

final activitiesProvider = StreamProvider<List<Activity>>(
    (ref) => ref.watch(databaseProvider).watchActivities());

/// Dark mode preference, persisted in the local Prefs table.
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    ref.watch(databaseProvider).watchPref('darkMode').listen((v) {
      if (v != null) {
        state = v == '1' ? ThemeMode.dark : ThemeMode.light;
      }
    });
    return ThemeMode.light;
  }

  void toggle(bool dark) {
    state = dark ? ThemeMode.dark : ThemeMode.light;
    ref.read(databaseProvider).setPref('darkMode', dark ? '1' : '0');
  }
}

/// App phase gate: splash → onboarding → auth → app (prototype flow).
final appPhaseProvider =
    NotifierProvider<AppPhaseNotifier, String?>(AppPhaseNotifier.new);

class AppPhaseNotifier extends Notifier<String?> {
  @override
  String? build() {
    ref.read(databaseProvider).getPref('phase').then((v) {
      state = v ?? 'splash';
    });
    return null; // unknown until loaded
  }

  void advance(String phase) {
    state = phase;
    ref.read(databaseProvider).setPref('phase', phase);
  }
}
