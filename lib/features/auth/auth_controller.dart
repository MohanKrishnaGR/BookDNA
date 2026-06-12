import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/client.dart';

/// Current Supabase user (null when signed out or backend unconfigured).
final currentUserProvider = StreamProvider<User?>((ref) {
  if (!supabaseConfigured) return Stream.value(null);
  return supabase.auth.onAuthStateChange
      .map((change) => change.session?.user)
      .distinct((a, b) => a?.id == b?.id);
});

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthController {
  /// Guest path. With a backend this is a real anonymous Supabase user
  /// (so the library syncs and can later be upgraded); without one the app
  /// simply runs local-only.
  Future<void> continueAsGuest() async {
    if (!supabaseConfigured) return;
    if (supabase.auth.currentUser != null) return;
    try {
      await supabase.auth.signInAnonymously();
    } on AuthApiException {
      // Anonymous sign-ins disabled server-side → stay local-only.
    }
  }

  /// Email + password: signs in, transparently creating the account on
  /// first use. Anonymous users are upgraded in place (library kept).
  Future<void> signInWithEmail(String email, String password) async {
    if (!supabaseConfigured) {
      throw AuthException(
          'No backend configured — run with --dart-define=SUPABASE_URL/…');
    }
    final current = supabase.auth.currentUser;
    if (current != null && current.isAnonymous) {
      // Upgrade guest → permanent account, keeping the synced library.
      try {
        await supabase.auth
            .updateUser(UserAttributes(email: email, password: password));
        return;
      } on AuthApiException {
        // Email already registered → fall through to a normal sign-in.
      }
    }
    try {
      await supabase.auth
          .signInWithPassword(email: email, password: password);
    } on AuthApiException catch (e) {
      if (e.code == 'invalid_credentials') {
        final res = await supabase.auth
            .signUp(email: email, password: password);
        if (res.session == null) {
          throw AuthException(
              'Check your inbox to confirm $email, then sign in.');
        }
      } else {
        throw AuthException(e.message);
      }
    }
  }

  Future<void> signOut() async {
    if (!supabaseConfigured) return;
    await supabase.auth.signOut();
  }
}

final authControllerProvider = Provider((_) => AuthController());
