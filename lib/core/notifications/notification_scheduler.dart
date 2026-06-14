import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show DateTimeComponents;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/insights/logic/formulas.dart';
import '../db/database.dart';
import '../models/book_status.dart';
import '../providers.dart';
import 'local_notifications.dart';

/// Re-derives all on-device reminders from current data. Kept alive by being
/// watched in the root widget; it also re-runs (debounced) whenever any local
/// table changes, so reminders stay in sync without manual refresh calls.
final notificationSchedulerProvider = Provider<NotificationScheduler>((ref) {
  final scheduler = NotificationScheduler(ref);
  final db = ref.read(databaseProvider);
  Timer? debounce;
  final sub = db.tableUpdates().listen((_) {
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 2), scheduler.refresh);
  });
  ref.onDispose(() {
    debounce?.cancel();
    sub.cancel();
  });
  return scheduler;
});

class NotificationScheduler {
  NotificationScheduler(this.ref);
  final Ref ref;

  bool _running = false;

  Future<void> refresh() async {
    if (_running) return;
    _running = true;
    try {
      await _refresh();
    } finally {
      _running = false;
    }
  }

  Future<void> _refresh() async {
    final db = ref.read(databaseProvider);

    // Only schedule once the user is actually in the app (not onboarding/auth);
    // request the OS permission a single time at that point.
    final phase = await db.getPref('phase');
    final master = (await db.getPref('notificationsEnabled')) != '0';
    if (phase != 'app' || !master) {
      await _cancelAll();
      return;
    }
    if ((await db.getPref('notifPermAsked')) != '1') {
      await db.setPref('notifPermAsked', '1');
      await LocalNotifications.requestPermission();
    }

    await _daily(db);
    await _streak(db);
    await _finish(db);
    await _lends(db);
  }

  // ── daily reading reminder (repeating) ──────────────────────────
  Future<void> _daily(AppDatabase db) async {
    if ((await db.getPref('notif_daily')) == '0') {
      await LocalNotifications.cancel(LocalNotifications.idDailyReminder);
      return;
    }
    final (h, m) = _time(await db.getPref('notif_daily_time'));
    await LocalNotifications.scheduleAt(
      LocalNotifications.idDailyReminder,
      'Time to read 📖',
      'A few pages now keeps the habit alive.',
      LocalNotifications.nextInstanceOf(h, m),
      payload: '/home',
      matchComponents: DateTimeComponents.time, // daily repeat
    );
  }

  // ── streak saver (one-shot, this evening) ───────────────────────
  Future<void> _streak(AppDatabase db) async {
    await LocalNotifications.cancel(LocalNotifications.idStreakSaver);
    if ((await db.getPref('notif_streak')) == '0') return;

    final sessions = await _sessions(db);
    final streak = currentStreak(sessions);
    if (streak <= 0) return;
    final today = localDate();
    if (sessions.any((s) => localDate(s.sessionDate) == today)) return; // read today

    final (h, m) = _time(await db.getPref('notif_daily_time'));
    final now = LocalNotifications.now();
    var when = LocalNotifications.todayAt(h, m);
    if (!when.isAfter(now)) when = LocalNotifications.todayAt(21, 30);
    if (!when.isAfter(now)) return; // too late to save it tonight

    await LocalNotifications.scheduleAt(
      LocalNotifications.idStreakSaver,
      '🔥 Keep your $streak-day streak',
      "You haven't read today — a few pages saves your streak.",
      when,
      payload: '/home',
    );
  }

  // ── finish-line nudge (one-shot, next evening) ──────────────────
  Future<void> _finish(AppDatabase db) async {
    await LocalNotifications.cancel(LocalNotifications.idFinishLine);
    if ((await db.getPref('notif_finish')) == '0') return;

    final reading = await (db.select(db.books)
          ..where((b) =>
              b.deletedAt.isNull() & b.status.equalsValue(BookStatus.reading)))
        .get();
    if (reading.isEmpty) return;

    final speed = readingSpeed(await _sessions(db)); // pages/hour
    final threshold = (speed * 0.75).clamp(15, 60).toInt(); // ~45 min of reading

    Book? pick;
    var bestLeft = 1 << 30;
    for (final b in reading) {
      final left = b.pages - b.currentPage;
      if (left <= 0 || left > threshold) continue;
      if (left < bestLeft) {
        bestLeft = left;
        pick = b;
      }
    }
    if (pick == null) return;

    await LocalNotifications.scheduleAt(
      LocalNotifications.idFinishLine,
      'So close! 📕',
      '${pick.title} — about $bestLeft pages to go. Finish it?',
      LocalNotifications.nextInstanceOf(19, 0),
      payload: '/tracker/${pick.id}',
    );
  }

  // ── overdue / due-soon lend reminders (one-shot per lend) ───────
  Future<void> _lends(AppDatabase db) async {
    for (var i = 0; i < LocalNotifications.lendMax; i++) {
      await LocalNotifications.cancel(LocalNotifications.lendBase + i);
    }
    if ((await db.getPref('notif_lend')) == '0') return;

    final lends = await (db.select(db.lends)
          ..where((l) => l.deletedAt.isNull() & l.returnedOn.isNull()))
        .get();
    final now = LocalNotifications.now();
    var i = 0;
    for (final l in lends) {
      if (i >= LocalNotifications.lendMax) break;
      final due = l.dueOn;
      if (due == null) continue;
      var when = LocalNotifications.onDate(due, 10, 0);
      if (!when.isAfter(now)) when = LocalNotifications.nextInstanceOf(10, 0);
      await LocalNotifications.scheduleAt(
        LocalNotifications.lendBase + i,
        '📚 Book due back',
        '${l.bookTitle} is due back from ${l.toName}.',
        when,
        payload: '/community',
      );
      i++;
    }
  }

  Future<void> _cancelAll() async {
    await LocalNotifications.cancel(LocalNotifications.idDailyReminder);
    await LocalNotifications.cancel(LocalNotifications.idStreakSaver);
    await LocalNotifications.cancel(LocalNotifications.idFinishLine);
    for (var i = 0; i < LocalNotifications.lendMax; i++) {
      await LocalNotifications.cancel(LocalNotifications.lendBase + i);
    }
  }

  Future<List<ReadingSession>> _sessions(AppDatabase db) =>
      (db.select(db.readingSessions)..where((s) => s.deletedAt.isNull())).get();

  (int, int) _time(String? v) {
    if (v != null) {
      final p = v.split(':');
      if (p.length == 2) {
        final h = int.tryParse(p[0]);
        final m = int.tryParse(p[1]);
        if (h != null && m != null) return (h, m);
      }
    }
    return (20, 0);
  }
}
