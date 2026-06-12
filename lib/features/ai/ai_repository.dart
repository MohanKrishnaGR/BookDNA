import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../../core/supabase/client.dart';
import 'ai_models.dart';

final aiRepositoryProvider = Provider<AiRepository?>((ref) {
  if (!supabaseConfigured) return null;
  return AiRepository(ref);
});

class AiRepository {
  AiRepository(this._ref);

  final Ref _ref;

  static const _prefKey = 'lastAnalysis';

  bool get signedIn => supabase.auth.currentSession != null;

  /// Streams assistant text chunks for a chat turn against `ai-chat`.
  Stream<String> chat(List<({String role, String text})> turns) async* {
    final session = supabase.auth.currentSession;
    if (session == null) {
      throw AiException('Sign in to chat with your library.');
    }

    final request = http.Request(
      'POST',
      Uri.parse('$kSupabaseUrl/functions/v1/ai-chat'),
    )
      ..headers.addAll({
        'Authorization': 'Bearer ${session.accessToken}',
        'apikey': kSupabaseAnonKey,
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode({
        'messages': [
          for (final t in turns) {'role': t.role, 'content': t.text},
        ],
      });

    final client = http.Client();
    try {
      final response = await client.send(request);
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw _errorFrom(response.statusCode, body);
      }

      // Parse the Anthropic SSE stream: emit text_delta chunks.
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        Map<String, dynamic> event;
        try {
          event = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        if (event['type'] == 'content_block_delta') {
          final delta = event['delta'] as Map<String, dynamic>?;
          final text = delta?['text'] as String?;
          if (text != null) yield text;
        } else if (event['type'] == 'error') {
          throw AiException('The assistant hit a snag — try again.');
        }
      }
    } finally {
      client.close();
    }
  }

  /// Runs a full shelf analysis via `ai-analyze` and caches the result
  /// locally so the screen renders offline afterwards.
  Future<ShelfAnalysis> analyze() async {
    if (!signedIn) {
      throw AiException('Sign in to run the AI analysis.');
    }
    try {
      final response = await supabase.functions.invoke('ai-analyze');
      final analysis = ShelfAnalysis.fromJson(
          Map<String, dynamic>.from(response.data as Map));
      await _ref
          .read(databaseProvider)
          .setPref(_prefKey, jsonEncode(analysis.toJson()));
      return analysis;
    } on FunctionException catch (e) {
      throw _errorFrom(
          e.status, e.details is String ? e.details : jsonEncode(e.details));
    }
  }

  Future<ShelfAnalysis?> cachedAnalysis() async {
    final raw = await _ref.read(databaseProvider).getPref(_prefKey);
    if (raw == null) return null;
    try {
      return ShelfAnalysis.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  AiException _errorFrom(int status, String? body) {
    String? message;
    bool quota = false;
    if (body != null && body.isNotEmpty) {
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        message = json['message'] as String?;
        quota = json['error'] == 'quota_exceeded';
      } catch (_) {}
    }
    return AiException(
      message ??
          switch (status) {
            401 => 'Sign in to use the AI features.',
            429 => 'You\'ve hit the usage limit — try again later.',
            _ => 'The assistant is unavailable right now — try again.',
          },
      isQuota: quota || status == 429,
    );
  }
}
