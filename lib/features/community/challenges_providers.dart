import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/models/book_status.dart';
import '../../core/providers.dart';
import '../../core/supabase/client.dart';
import '../insights/logic/formulas.dart';

class Challenge {
  const Challenge({
    required this.id,
    required this.icon,
    required this.title,
    required this.description,
    required this.kind,
    required this.target,
    required this.hueShift,
  });

  final String id;
  final String icon;
  final String title;
  final String description;
  final String kind;
  final int target;
  final int hueShift;
}

/// Built-in mirror of the server catalogue: used offline and when the
/// backend isn't configured, so the feature always renders.
const kDefaultChallenges = [
  Challenge(
      id: 'streak-100',
      icon: 'local_fire_department',
      title: '100-Day Streak',
      description: 'Read every day for 100 days',
      kind: 'streak',
      target: 100,
      hueShift: 30),
  Challenge(
      id: 'books-5-month',
      icon: 'menu_book',
      title: '5 Books This Month',
      description: 'Finish 5 books this month',
      kind: 'books_month',
      target: 5,
      hueShift: 0),
  Challenge(
      id: 'genre-explorer',
      icon: 'explore',
      title: 'Genre Explorer',
      description: 'Finish books in 3 different genres',
      kind: 'genres',
      target: 3,
      hueShift: 150),
  Challenge(
      id: 'club-sprint',
      icon: 'groups',
      title: 'Monthly Sprint',
      // Progress counts any finish this month; circle-scoped tracking
      // arrives with the social graph (Phase 3).
      description: 'Finish 1 book this month',
      kind: 'club',
      target: 1,
      hueShift: 210),
];

final challengesProvider = FutureProvider<List<Challenge>>((ref) async {
  if (!supabaseConfigured || supabase.auth.currentSession == null) {
    return kDefaultChallenges;
  }
  try {
    final rows = await supabase
        .from('challenges')
        .select('id,icon,title,description,kind,target,hue_shift,sort')
        .order('sort');
    return [
      for (final r in rows)
        Challenge(
          id: r['id'] as String,
          icon: r['icon'] as String,
          title: r['title'] as String,
          description: r['description'] as String,
          kind: r['kind'] as String,
          target: (r['target'] as num).toInt(),
          hueShift: (r['hue_shift'] as num).toInt(),
        ),
    ];
  } catch (_) {
    return kDefaultChallenges;
  }
});

/// Joined challenge ids — server membership when signed in, with a local
/// prefs cache so the rail renders instantly and offline.
final joinedChallengesProvider =
    AsyncNotifierProvider<JoinedChallengesNotifier, Set<String>>(
        JoinedChallengesNotifier.new);

class JoinedChallengesNotifier extends AsyncNotifier<Set<String>> {
  static const _prefKey = 'joinedChallenges';

  @override
  Future<Set<String>> build() async {
    final db = ref.read(databaseProvider);
    final cached = await db.getPref(_prefKey);
    var joined = <String>{};
    if (cached != null) {
      try {
        joined = (jsonDecode(cached) as List).map((e) => '$e').toSet();
      } catch (_) {}
    }

    if (supabaseConfigured && supabase.auth.currentSession != null) {
      try {
        final rows = await supabase
            .from('challenge_members')
            .select('challenge_id');
        joined = {for (final r in rows) r['challenge_id'] as String};
        await db.setPref(_prefKey, jsonEncode(joined.toList()));
      } catch (_) {
        // keep cache
      }
    }
    return joined;
  }

  Future<void> toggle(String challengeId) async {
    final current = state.value ?? {};
    final joining = !current.contains(challengeId);
    final next = {...current};
    joining ? next.add(challengeId) : next.remove(challengeId);
    state = AsyncData(next);
    await ref
        .read(databaseProvider)
        .setPref(_prefKey, jsonEncode(next.toList()));

    if (supabaseConfigured && supabase.auth.currentSession != null) {
      try {
        final uid = supabase.auth.currentUser!.id;
        if (joining) {
          await supabase.from('challenge_members').upsert(
              {'challenge_id': challengeId, 'user_id': uid});
        } else {
          await supabase
              .from('challenge_members')
              .delete()
              .eq('challenge_id', challengeId)
              .eq('user_id', uid);
        }
      } catch (_) {
        // Local state is the optimistic source; next build() reconciles.
      }
    }
  }
}

/// Progress toward a challenge, computed from the member's own local data.
int challengeProgress(
  Challenge c,
  List<Book> books,
  List<ReadingSession> sessions,
) {
  final now = DateTime.now();
  bool inMonth(DateTime? d) =>
      d != null && d.year == now.year && d.month == now.month;
  final finishedThisMonth = books
      .where((b) => b.status == BookStatus.read && inMonth(b.finishedAt))
      .toList();

  final value = switch (c.kind) {
    'streak' => currentStreak(sessions),
    'books_month' => finishedThisMonth.length,
    'genres' => finishedThisMonth.map((b) => b.genre).toSet().length,
    'club' => finishedThisMonth.isEmpty ? 0 : 1,
    _ => 0,
  };
  return value.clamp(0, c.target);
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.name,
    required this.pages,
    required this.isMe,
  });

  final String name;
  final int pages;
  final bool isMe;
}

final leaderboardProvider =
    FutureProvider<List<LeaderboardEntry>>((ref) async {
  if (!supabaseConfigured || supabase.auth.currentSession == null) {
    return const [];
  }
  try {
    final rows = await supabase.rpc('weekly_leaderboard');
    return [
      for (final r in rows as List)
        LeaderboardEntry(
          name: r['display_name'] as String? ?? 'Reader',
          pages: (r['pages'] as num).toInt(),
          isMe: r['is_me'] == true,
        ),
    ];
  } catch (_) {
    return const [];
  }
});
