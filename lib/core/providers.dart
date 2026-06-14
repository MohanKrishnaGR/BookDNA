import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/database.dart';
import 'haptics/haptics.dart';

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

/// Haptic feedback preference, persisted in the local Prefs table (default on).
/// Keeps the [Haptics] facade's static switch in sync so call sites stay simple.
final hapticsEnabledProvider =
    NotifierProvider<HapticsNotifier, bool>(HapticsNotifier.new);

class HapticsNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(databaseProvider).watchPref('hapticsEnabled').listen((v) {
      final on = v != '0'; // null/'1' → on, '0' → off
      state = on;
      Haptics.enabled = on;
    });
    return Haptics.enabled;
  }

  void toggle(bool on) {
    state = on;
    Haptics.enabled = on;
    ref.read(databaseProvider).setPref('hapticsEnabled', on ? '1' : '0');
  }
}

/// Generic on/off preference backed by the Prefs table (key/value), reactive.
class BoolPrefNotifier extends Notifier<bool> {
  BoolPrefNotifier(this._key, this._fallback);
  final String _key;
  final bool _fallback;

  @override
  bool build() {
    ref.watch(databaseProvider).watchPref(_key).listen((v) {
      state = v == null ? _fallback : v == '1';
    });
    return _fallback;
  }

  void set(bool on) {
    state = on;
    ref.read(databaseProvider).setPref(_key, on ? '1' : '0');
  }
}

/// Time-of-day preference stored as "H:M".
class TimePrefNotifier extends Notifier<TimeOfDay> {
  TimePrefNotifier(this._key, this._fallback);
  final String _key;
  final TimeOfDay _fallback;

  @override
  TimeOfDay build() {
    ref.watch(databaseProvider).watchPref(_key).listen((v) {
      state = _parse(v) ?? _fallback;
    });
    return _fallback;
  }

  void set(TimeOfDay t) {
    state = t;
    ref.read(databaseProvider).setPref(_key, '${t.hour}:${t.minute}');
  }

  static TimeOfDay? _parse(String? v) {
    if (v == null) return null;
    final parts = v.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    return (h == null || m == null) ? null : TimeOfDay(hour: h, minute: m);
  }
}

// Notification preferences — all default on; daily reminder defaults to 20:00.
final notificationsEnabledProvider = NotifierProvider<BoolPrefNotifier, bool>(
    () => BoolPrefNotifier('notificationsEnabled', true));
final dailyReminderEnabledProvider = NotifierProvider<BoolPrefNotifier, bool>(
    () => BoolPrefNotifier('notif_daily', true));
final dailyReminderTimeProvider =
    NotifierProvider<TimePrefNotifier, TimeOfDay>(
        () => TimePrefNotifier('notif_daily_time', const TimeOfDay(hour: 20, minute: 0)));
final streakRemindersProvider = NotifierProvider<BoolPrefNotifier, bool>(
    () => BoolPrefNotifier('notif_streak', true));
final finishRemindersProvider = NotifierProvider<BoolPrefNotifier, bool>(
    () => BoolPrefNotifier('notif_finish', true));
final lendRemindersProvider = NotifierProvider<BoolPrefNotifier, bool>(
    () => BoolPrefNotifier('notif_lend', true));

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
