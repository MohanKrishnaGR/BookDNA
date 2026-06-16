import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/messaging/push_messaging.dart';
import '../core/notifications/local_notifications.dart';
import '../core/notifications/notification_scheduler.dart';
import '../core/providers.dart';
import '../core/sync/sync_providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class BookDnaApp extends ConsumerStatefulWidget {
  const BookDnaApp({super.key});

  @override
  ConsumerState<BookDnaApp> createState() => _BookDnaAppState();
}

class _BookDnaAppState extends ConsumerState<BookDnaApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Route a tapped notification (local or push) through the router.
    LocalNotifications.onNavigate = (route) => router.go(route);
    PushMessaging.instance.onNavigate = (route) => router.go(route);
    // Re-derive reminders whenever the app comes back to the foreground.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(notificationSchedulerProvider).refresh(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationSchedulerProvider).refresh();
      LocalNotifications.handleLaunchPayload();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    // Arm the sync orchestrator (auth/connectivity/mutation triggers).
    ref.watch(syncControllerProvider);
    // Load the persisted haptics preference into the Haptics facade.
    ref.watch(hapticsEnabledProvider);
    // Mirror the master notifications preference so push token registration
    // honours it (re-registers/drops the FCM token as the toggle changes).
    PushMessaging.instance.notificationsEnabled =
        ref.watch(notificationsEnabledProvider);
    // Keep the reactive notification scheduler alive.
    ref.watch(notificationSchedulerProvider);
    return MaterialApp.router(
      title: 'BookDNA',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      routerConfig: router,
    );
  }
}
