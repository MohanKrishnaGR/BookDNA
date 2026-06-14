import 'package:flutter/services.dart';

/// Semantic haptic feedback facade.
///
/// Call sites use meaning (`success`, `error`, `selection`) rather than raw
/// vibration, so the feel can be tuned in one place. Every call is gated by
/// [enabled] (backed by the `hapticsEnabled` pref via `hapticsEnabledProvider`)
/// and the OS-level haptic setting, which Flutter's `HapticFeedback` already
/// respects. Uses only the built-in engine API — no extra plugin or
/// `VIBRATE` permission required.
class Haptics {
  Haptics._();

  /// Master switch, synced from the user's pref at startup. Default on.
  static bool enabled = true;

  /// A value ticked through a series — steppers, toggles, tab/slide changes.
  static void selection() {
    if (enabled) HapticFeedback.selectionClick();
  }

  /// A light, frequent tap — minor confirmations, story tap-through.
  static void tap() {
    if (enabled) HapticFeedback.lightImpact();
  }

  /// Something snapping into place — barcode lock-on, long-press.
  static void impact() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  /// A task completed — book added, session saved, sign-in, purchase.
  static void success() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  /// A cautionary bump.
  static void warning() {
    if (enabled) HapticFeedback.heavyImpact();
  }

  /// A failure — a distinct double buzz (the built-in API has no native
  /// "error" notification, so we approximate it).
  static Future<void> error() async {
    if (!enabled) return;
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 130));
    await HapticFeedback.heavyImpact();
  }

  /// A celebratory flourish for milestones — finishing a book, Wrapped finale.
  static Future<void> celebrate() async {
    if (!enabled) return;
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.mediumImpact();
  }
}
