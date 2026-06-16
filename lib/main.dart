import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/analytics/analytics.dart';
import 'core/messaging/push_messaging.dart';
import 'core/notifications/local_notifications.dart';
import 'core/supabase/client.dart';

Future<void> main() async {
  // runZonedGuarded captures async errors that escape the framework so
  // Crashlytics can record them. All app startup happens inside the zone.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Firebase powers Crashlytics + Analytics. It only activates once
    // android/app/google-services.json (and the Gradle plugins) are present;
    // until then init throws and we run gracefully with telemetry disabled.
    try {
      await Firebase.initializeApp();
      Analytics.instance.enable();

      // Route Flutter framework + platform errors to Crashlytics.
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      // FCM push (token registration, foreground display, deep-link).
      await PushMessaging.instance.init();
    } catch (e) {
      // Firebase not configured for this build — keep the app fully usable.
      debugPrint('Firebase not initialized (telemetry off): $e');
    }

    await initSupabase();
    await LocalNotifications.init();
    runApp(const ProviderScope(child: BookDnaApp()));
  }, (error, stack) {
    if (Analytics.instance.ready) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } else {
      debugPrint('Uncaught zone error: $error\n$stack');
    }
  });
}
