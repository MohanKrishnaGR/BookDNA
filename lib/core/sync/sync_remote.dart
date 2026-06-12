import 'package:supabase_flutter/supabase_flutter.dart';

/// Transport abstraction for the sync engine — Supabase in production,
/// an in-memory fake in tests.
abstract class SyncRemote {
  /// Signed-in user id, or null when sync is unavailable.
  String? get userId;

  /// Batched upsert; rows already carry `user_id`.
  Future<void> upsert(String table, List<Map<String, dynamic>> rows);

  /// Rows with `server_updated_at` strictly after [watermark],
  /// ordered ascending by `server_updated_at`, at most [limit].
  Future<List<Map<String, dynamic>>> pullSince(
    String table,
    String? watermark, {
    int limit = 500,
  });
}

class SupabaseRemote implements SyncRemote {
  SupabaseRemote(this._client);

  final SupabaseClient _client;

  @override
  String? get userId => _client.auth.currentUser?.id;

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from(table).upsert(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> pullSince(
    String table,
    String? watermark, {
    int limit = 500,
  }) async {
    var query = _client.from(table).select();
    if (watermark != null) {
      query = query.gt('server_updated_at', watermark);
    }
    final rows =
        await query.order('server_updated_at', ascending: true).limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }
}
