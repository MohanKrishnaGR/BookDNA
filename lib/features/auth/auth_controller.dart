import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/analytics/analytics.dart';
import '../../core/supabase/client.dart';

/// The Google Cloud **Web** OAuth client id — Supabase verifies the ID token
/// against it. Injected at build time so nothing is hard-coded:
///   --dart-define=GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com
const String kGoogleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

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
  /// Record a successful sign-in for analytics, tagging the auth method and
  /// binding the Supabase user id so events can be attributed per user.
  void _trackSignIn(String method) {
    Analytics.instance.setUser(supabase.auth.currentUser?.id);
    Analytics.instance.log('login', {'method': method});
  }

  /// Guest path. With a backend this is a real anonymous Supabase user
  /// (so the library syncs and can later be upgraded); without one the app
  /// simply runs local-only.
  Future<void> continueAsGuest() async {
    if (!supabaseConfigured) return;
    if (supabase.auth.currentUser != null) return;
    try {
      await supabase.auth.signInAnonymously();
      _trackSignIn('guest');
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
        _trackSignIn('email');
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
    _trackSignIn('email');
  }

  /// Whether native Google sign-in is wired for this build.
  bool get googleConfigured =>
      supabaseConfigured && kGoogleWebClientId.isNotEmpty;

  /// Native Google sign-in: gets a Google ID token and exchanges it with
  /// Supabase. Returns false if the user cancels; throws [AuthException] on
  /// a real failure. Guest data is preserved — onAuthStateChange triggers
  /// the sync engine's adopt-and-push under the new Google user.
  Future<bool> signInWithGoogle() async {
    if (!googleConfigured) {
      throw AuthException(
          "Google sign-in isn't configured yet — use email for now.");
    }
    final googleSignIn = GoogleSignIn(serverClientId: kGoogleWebClientId);
    // Clear any cached Google session so the account picker always appears.
    await googleSignIn.signOut();
    final account = await googleSignIn.signIn();
    if (account == null) return false; // user dismissed the picker
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw AuthException('Google did not return an ID token — try again.');
    }
    await supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: auth.accessToken,
    );
    _trackSignIn('google');
    return true;
  }

  Future<void> signOut() async {
    if (!supabaseConfigured) return;
    await supabase.auth.signOut();
  }
}

final authControllerProvider = Provider((_) => AuthController());
