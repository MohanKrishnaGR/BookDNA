import 'package:firebase_analytics/firebase_analytics.dart';

/// Thin analytics facade over Firebase Analytics.
///
/// Safe to call before Firebase is configured (e.g. before
/// android/app/google-services.json exists) — every method no-ops until
/// [enable] is called from main() after a successful Firebase init. This
/// keeps call sites clean and the app fully functional with analytics off.
class Analytics {
  Analytics._();
  static final Analytics instance = Analytics._();

  FirebaseAnalytics? _fa;
  bool get ready => _fa != null;

  /// Called from main() once Firebase has initialized successfully.
  void enable() => _fa = FirebaseAnalytics.instance;

  /// The underlying instance, or null when analytics is disabled
  /// (used to gate the go_router screen-view observer).
  FirebaseAnalytics? get firebase => _fa;

  Future<void> log(String name, [Map<String, Object>? params]) async {
    final fa = _fa;
    if (fa == null) return;
    try {
      await fa.logEvent(name: name, parameters: params);
    } catch (_) {
      // never let telemetry break a user flow
    }
  }

  Future<void> setUser(String? id) async {
    final fa = _fa;
    if (fa == null) return;
    try {
      await fa.setUserId(id: id);
    } catch (_) {}
  }
}
