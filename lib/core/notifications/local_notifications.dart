import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Thin wrapper over flutter_local_notifications for on-device reminders.
///
/// Pure local scheduling — no backend. [onNavigate] is wired up at startup so a
/// tapped notification deep-links through the router without this core module
/// importing the app layer.
class LocalNotifications {
  LocalNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Set by the app layer: routes a tapped notification's payload.
  static void Function(String route)? onNavigate;

  // Stable ids so a re-derive replaces rather than duplicates.
  static const int idDailyReminder = 1001;
  static const int idStreakSaver = 1002;
  static const int idFinishLine = 1003;
  static const int lendBase = 2000;
  static const int lendMax = 40;

  static Future<void> init() async {
    if (_ready) return;
    tz_data.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Fall back to UTC if the platform timezone can't be resolved.
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (r) {
        final p = r.payload;
        if (p != null && p.isNotEmpty) onNavigate?.call(p);
      },
    );
    _ready = true;
  }

  /// Navigate if the app was cold-launched by tapping a notification.
  static Future<void> handleLaunchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      final p = details!.notificationResponse?.payload;
      if (p != null && p.isNotEmpty) onNavigate?.call(p);
    }
  }

  /// Ask for the OS notification permission (Android 13+ / iOS). Returns granted.
  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final a = await android?.requestNotificationsPermission() ?? true;
    final i = await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
        true;
    return a && i;
  }

  static const AndroidNotificationDetails _android = AndroidNotificationDetails(
    'reading_reminders',
    'Reading reminders',
    channelDescription:
        'Daily reminders, streak saves, finish-line and lend nudges',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const NotificationDetails _details =
      NotificationDetails(android: _android, iOS: DarwinNotificationDetails());

  /// Show immediately (used to render FCM messages that arrive in foreground).
  static Future<void> showNow(int id, String title, String body,
      {String? payload}) async {
    if (!_ready) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _details,
      payload: payload,
    );
  }

  /// Schedule [id] at [when]; pass [matchComponents] = DateTimeComponents.time
  /// for a daily repeat. Inexact scheduling avoids the exact-alarm permission.
  static Future<void> scheduleAt(
    int id,
    String title,
    String body,
    tz.TZDateTime when, {
    String? payload,
    DateTimeComponents? matchComponents,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
        matchDateTimeComponents: matchComponents,
      );
    } catch (e) {
      debugPrint('scheduleAt failed for $id: $e');
    }
  }

  static Future<void> cancel(int id) async {
    if (_ready) await _plugin.cancel(id: id);
  }

  static Future<List<PendingNotificationRequest>> pending() =>
      _ready ? _plugin.pendingNotificationRequests() : Future.value(const []);

  // ── time helpers ────────────────────────────────────────────────

  /// Next occurrence of hour:minute (today if still ahead, else tomorrow).
  static tz.TZDateTime nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    return when;
  }

  /// Today at hour:minute (may be in the past — caller decides).
  static tz.TZDateTime todayAt(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    return tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
  }

  /// A specific calendar [date] at hour:minute in the local zone.
  static tz.TZDateTime onDate(DateTime date, int hour, int minute) =>
      tz.TZDateTime(tz.local, date.year, date.month, date.day, hour, minute);

  static tz.TZDateTime now() => tz.TZDateTime.now(tz.local);
}
