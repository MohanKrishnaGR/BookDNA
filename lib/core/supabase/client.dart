import 'package:supabase_flutter/supabase_flutter.dart';

/// Injected at build time:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// Android emulator + local stack: http://10.0.2.2:54321
const String kSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String kSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Whether this build was configured with a Supabase backend.
/// When false the app runs fully local (guest mode, no sync).
bool get supabaseConfigured =>
    kSupabaseUrl.isNotEmpty && kSupabaseAnonKey.isNotEmpty;

Future<void> initSupabase() async {
  if (!supabaseConfigured) return;
  await Supabase.initialize(
      url: kSupabaseUrl, publishableKey: kSupabaseAnonKey);
}

SupabaseClient get supabase => Supabase.instance.client;
