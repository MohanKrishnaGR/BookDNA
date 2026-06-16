import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../notifications/local_notifications.dart';
import '../supabase/client.dart';

/// Background/terminated-state message handler. Must be a top-level function.
/// Android renders `notification` messages in the tray automatically while the
/// app is backgrounded, so there's nothing to do here — but the handler has to
/// exist and be registered.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// FCM push: registers this device's token (server-side reassignment keeps it
/// tied to the current account), renders foreground messages via the local
/// notifications channel, and deep-links taps. Activates only when Firebase is
/// configured; otherwise every method no-ops.
class PushMessaging {
  PushMessaging._();
  static final PushMessaging instance = PushMessaging._();

  bool _ready = false;
  String? _token;

  /// Mirrors the master notifications preference (set from the app layer).
  bool notificationsEnabled = true;

  /// Routes a tapped push's `data.route` deep-link (wired to router.go).
  void Function(String route)? onNavigate;

  /// Call after a successful Firebase.initializeApp().
  Future<void> init() async {
    if (_ready) return;
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      final messaging = FirebaseMessaging.instance;

      // Foreground messages aren't shown by the OS — render them ourselves.
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null) return;
        LocalNotifications.showNow(
          9000 + ((m.messageId?.hashCode ?? 0) % 1000),
          n.title ?? 'BookDNA',
          n.body ?? '',
          payload: m.data['route'] as String?,
        );
      });

      // Tap from background, and cold-start from a tapped push.
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _handleOpen(initial);

      messaging.onTokenRefresh.listen((t) {
        _token = t;
        _registerIfEligible();
      });

      // Re-register when the signed-in identity changes (account switch).
      supabase.auth.onAuthStateChange.listen((change) {
        if (change.event == AuthChangeEvent.signedIn ||
            change.event == AuthChangeEvent.tokenRefreshed) {
          _registerIfEligible();
        }
      });

      _token = await messaging.getToken();
      _ready = true;
      await _registerIfEligible();
    } catch (e) {
      debugPrint('PushMessaging init skipped: $e');
    }
  }

  void _handleOpen(RemoteMessage m) {
    final route = m.data['route'] as String?;
    if (route != null && route.isNotEmpty) onNavigate?.call(route);
  }

  /// Follow the master notifications preference: register or drop the token.
  Future<void> syncRegistration(bool enabled) async {
    notificationsEnabled = enabled;
    if (enabled) {
      await _registerIfEligible();
    } else {
      await _unregister();
    }
  }

  /// Drop this device's token at sign-out. Must run *before* `auth.signOut()`
  /// so RLS still has the user context to delete the row. Leaves the master
  /// preference untouched (unlike [syncRegistration]).
  Future<void> unregister() => _unregister();

  Future<void> _registerIfEligible() async {
    if (!_ready || !notificationsEnabled) return;
    final token = _token;
    if (token == null) return;
    if (!supabaseConfigured || supabase.auth.currentUser == null) return;
    try {
      await supabase.rpc('register_device_token',
          params: {'p_token': token, 'p_platform': 'fcm'});
    } catch (e) {
      debugPrint('register_device_token failed: $e');
    }
  }

  Future<void> _unregister() async {
    final token = _token;
    if (token == null || !supabaseConfigured) return;
    if (supabase.auth.currentUser == null) return;
    try {
      await supabase.from('device_tokens').delete().eq('token', token);
    } catch (e) {
      debugPrint('device_token delete failed: $e');
    }
  }
}
