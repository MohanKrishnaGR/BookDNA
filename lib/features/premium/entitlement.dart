import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../../core/supabase/client.dart';

class PremiumState {
  const PremiumState({this.until, this.trialUsed = false});

  final DateTime? until;
  final bool trialUsed;

  bool get active => until != null && until!.isAfter(DateTime.now());

  int get daysLeft =>
      active ? until!.difference(DateTime.now()).inDays + 1 : 0;
}

class PremiumException implements Exception {
  PremiumException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Premium entitlement, sourced from profiles.premium_until (server-set
/// only) and cached in local prefs so gating works offline.
final premiumProvider =
    AsyncNotifierProvider<PremiumNotifier, PremiumState>(PremiumNotifier.new);

class PremiumNotifier extends AsyncNotifier<PremiumState> {
  @override
  Future<PremiumState> build() async {
    final cached = await _readCache();
    if (supabaseConfigured && supabase.auth.currentSession != null) {
      // Refresh from the server in the background; serve cache first.
      unawaited(refresh());
    }
    return cached;
  }

  Future<PremiumState> _readCache() async {
    final raw = await ref.read(databaseProvider).getPref('premiumState');
    if (raw == null) return const PremiumState();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return PremiumState(
        until: json['until'] != null
            ? DateTime.parse(json['until'] as String)
            : null,
        trialUsed: json['trialUsed'] == true,
      );
    } catch (_) {
      return const PremiumState();
    }
  }

  Future<void> _store(PremiumState s) =>
      ref.read(databaseProvider).setPref(
            'premiumState',
            jsonEncode({
              'until': s.until?.toIso8601String(),
              'trialUsed': s.trialUsed,
            }),
          );

  Future<void> refresh() async {
    if (!supabaseConfigured || supabase.auth.currentSession == null) return;
    try {
      final res = await supabase.functions
          .invoke('verify-purchase', body: {'action': 'status'});
      final data = Map<String, dynamic>.from(res.data as Map);
      final next = PremiumState(
        until: data['premium_until'] != null
            ? DateTime.parse(data['premium_until'] as String).toLocal()
            : null,
        trialUsed: data['trial_used'] == true,
      );
      await _store(next);
      state = AsyncData(next);
    } catch (_) {
      // Keep the cached state on network failure.
    }
  }

  /// One-time 7-day free trial, granted server-side.
  Future<PremiumState> startTrial() async {
    if (!supabaseConfigured || supabase.auth.currentSession == null) {
      throw PremiumException('Sign in first to start your free trial.');
    }
    try {
      final res = await supabase.functions
          .invoke('verify-purchase', body: {'action': 'trial'});
      final data = Map<String, dynamic>.from(res.data as Map);
      final next = PremiumState(
        until: DateTime.parse(data['premium_until'] as String).toLocal(),
        trialUsed: true,
      );
      await _store(next);
      state = AsyncData(next);
      return next;
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['message'] as String? : null;
      throw PremiumException(message ??
          (e.status == 409
              ? 'Your free trial has already been used.'
              : 'Could not start the trial — try again.'));
    }
  }
}

/// Convenience: is premium currently active (offline-safe).
final isPremiumProvider = Provider<bool>(
    (ref) => ref.watch(premiumProvider).value?.active ?? false);
