import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/book_accent.dart';
import '../../core/models/book_status.dart';
import '../../core/providers.dart';
import '../../widgets/ring.dart';
import '../auth/auth_controller.dart';
import '../insights/logic/formulas.dart';
import '../insights/logic/personality.dart';
import '../premium/entitlement.dart';
import 'achievements_screen.dart';
import 'badges.dart';
import 'goal_sheet.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider).value ?? [];
    final sessions = ref.watch(allSessionsProvider).value ?? [];
    final lends = ref.watch(lendsProvider).value ?? [];
    final goal = ref.watch(goalProvider).value;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final stats = computeLibraryStats(books, sessions);
    final streak = currentStreak(sessions);
    final best = bestStreak(sessions);
    final diversity = computeDiversity(books);
    final personality = computePersonality(books, sessions);
    final genresRead = books
        .where((b) => b.status == BookStatus.read)
        .map((b) => b.genre)
        .toSet()
        .length;

    // Level system: books read + streaks + diversity feed XP.
    final xp = 100 * stats.read +
        10 * best +
        2 * diversity.score +
        25 * genresRead +
        stats.pagesRead ~/ 100;
    final level = math.sqrt(xp / 150).floor() + 1;
    final nextLevelXp = 150 * (level * level);
    final levelProgress =
        nextLevelXp == 0 ? 0.0 : (xp / nextLevelXp).clamp(0.0, 1.0);
    final accent = accentFor(0, theme.brightness);
    final done = finishedInYear(books, DateTime.now().year);
    final notes = ref.watch(allNotesProvider).value ?? [];
    final badgesEarned =
        evaluateBadges(books: books, sessions: sessions, notes: notes)
            .where((b) => b.earned)
            .length;
    final premium =
        ref.watch(premiumProvider).value ?? const PremiumState();
    final profile = ref.watch(userProfileProvider);
    final hasPhoto = profile.photoUrl != null && profile.photoUrl!.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
          children: [
            Center(
              child: Column(children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: accent.container,
                  foregroundImage:
                      hasPhoto ? NetworkImage(profile.photoUrl!) : null,
                  child: Text(profile.initials,
                      style: theme.textTheme.headlineSmall!
                          .copyWith(color: accent.onContainer)),
                ),
                const SizedBox(height: 12),
                Text(profile.name, style: theme.textTheme.headlineSmall),
                if (profile.email != null)
                  Text(profile.email!,
                      style: theme.textTheme.bodySmall!
                          .copyWith(color: scheme.onSurfaceVariant)),
                Text('Level $level · ${personality.archetype}',
                    style: theme.textTheme.bodyMedium!
                        .copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _pill(context, Icons.local_fire_department_rounded,
                        '$streak', scheme.tertiaryContainer,
                        scheme.onTertiaryContainer),
                    const SizedBox(width: 8),
                    _pill(context, Icons.shelves, '${stats.owned}',
                        scheme.secondaryContainer,
                        scheme.onSecondaryContainer),
                    const SizedBox(width: 8),
                    _pill(context, Icons.check_circle_rounded,
                        '${stats.read}', scheme.secondaryContainer,
                        scheme.onSecondaryContainer),
                  ],
                ),
              ]),
            ),
            const SizedBox(height: 20),

            Card(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Ring(
                    value: levelProgress,
                    size: 58,
                    stroke: 6,
                    color: scheme.primary,
                    track: scheme.onPrimaryContainer.withValues(alpha: 0.14),
                    child: Text('L$level',
                        style: theme.textTheme.labelLarge!
                            .copyWith(color: scheme.onPrimaryContainer)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${formatXpToNext(xp, level)} XP to Level ${level + 1}',
                            style: theme.textTheme.titleSmall!.copyWith(
                                color: scheme.onPrimaryContainer)),
                        const SizedBox(height: 2),
                        Text(
                            'Levels grow with books read, streaks and diversity',
                            style: theme.textTheme.bodySmall!.copyWith(
                                color: scheme.onPrimaryContainer
                                    .withValues(alpha: 0.8))),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),

            Card(
              child: Column(children: [
                _row(
                  context,
                  Icons.flag_rounded,
                  'Reading goals',
                  '${goal?.target ?? 12} books in ${DateTime.now().year} · $done done',
                  () => showGoalSheet(context, ref),
                ),
                _row(
                  context,
                  Icons.military_tech_rounded,
                  'Achievements',
                  '$badgesEarned of ${kBadges.length} badges earned',
                  () => context.push('/achievements'),
                ),
                _row(
                  context,
                  Icons.swap_horiz_rounded,
                  'Borrow & lend',
                  '${lends.length} book${lends.length == 1 ? '' : 's'} out',
                  () => context.go('/community'),
                ),
                _row(
                  context,
                  Icons.workspace_premium_rounded,
                  'BookDNA Premium',
                  premium.active
                      ? 'Active — ${premium.daysLeft} day${premium.daysLeft == 1 ? '' : 's'} left'
                      : 'Knowledge graph, unlimited GPT & more',
                  () => context.push('/premium'),
                ),
                _row(
                  context,
                  Icons.settings_rounded,
                  'Settings',
                  'Theme, data, account',
                  () => context.push('/settings'),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                'BookDNA 1.0 · Understand your reading life',
                style: theme.textTheme.labelMedium!
                    .copyWith(color: scheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String formatXpToNext(int xp, int level) {
    final next = 150 * ((level + 1) * (level + 1)) - xp;
    return '$next';
  }

  Widget _pill(BuildContext context, IconData icon, String label, Color bg,
      Color fg) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(children: [
        Icon(icon, size: 16, color: fg),
        const SizedBox(width: 5),
        Text(label,
            style:
                Theme.of(context).textTheme.labelLarge!.copyWith(color: fg)),
      ]),
    );
  }

  Widget _row(BuildContext context, IconData icon, String title, String sub,
      VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: scheme.surfaceContainerHighest,
        child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(sub),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}
