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

/// Display identity derived from the signed-in Supabase user — used for the
/// home greeting and profile header. Falls back gracefully for guests and
/// local (no-backend) mode, so nothing is ever hard-coded to one person.
class UserProfile {
  const UserProfile({
    required this.name,
    required this.initials,
    required this.isGuest,
    this.email,
    this.photoUrl,
  });

  final String name;
  final String initials;
  final bool isGuest;
  final String? email;
  final String? photoUrl;

  /// First name only, for greetings.
  String get firstName =>
      name.split(RegExp(r'\s+')).firstWhere((p) => p.isNotEmpty,
          orElse: () => name);
}

String _initialsFrom(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 'R';
  if (parts.length == 1) {
    final p = parts.first;
    return (p.length >= 2 ? p.substring(0, 2) : p).toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

UserProfile profileFromUser(User? user) {
  if (user == null) {
    return const UserProfile(name: 'Reader', initials: 'R', isGuest: false);
  }
  if (user.isAnonymous) {
    return const UserProfile(name: 'Guest', initials: 'G', isGuest: true);
  }
  final meta = user.userMetadata ?? const <String, dynamic>{};
  String? metaStr(String key) {
    final v = meta[key];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  final email = user.email;
  final name = metaStr('full_name') ??
      metaStr('name') ??
      metaStr('user_name') ??
      ((email != null && email.contains('@')) ? email.split('@').first : null) ??
      'Reader';
  return UserProfile(
    name: name,
    initials: _initialsFrom(name),
    isGuest: false,
    email: email,
    photoUrl: metaStr('avatar_url') ?? metaStr('picture'),
  );
}

/// The signed-in user's display identity (reactive to auth changes).
final userProfileProvider = Provider<UserProfile>((ref) {
  final user = ref.watch(currentUserProvider).value;
  return profileFromUser(user);
});

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
