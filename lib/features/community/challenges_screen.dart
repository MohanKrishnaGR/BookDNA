import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/ring.dart';
import '../insights/logic/formulas.dart';
import '../profile/achievements_screen.dart';
import '../profile/badges.dart';
import 'challenge_card.dart';
import 'challenges_providers.dart';

class ChallengesScreen extends ConsumerWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final books = ref.watch(booksProvider).value ?? [];
    final sessions = ref.watch(allSessionsProvider).value ?? [];
    final notes = ref.watch(allNotesProvider).value ?? [];
    final challenges =
        ref.watch(challengesProvider).value ?? kDefaultChallenges;

    final streak = currentStreak(sessions);
    final best = bestStreak(sessions);
    final badges =
        evaluateBadges(books: books, sessions: sessions, notes: notes)
            .where((b) => b.earned)
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Challenges'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // Current streak card.
          Card(
            color: scheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Ring(
                  value: (streak / 100).clamp(0.0, 1.0),
                  size: 64,
                  stroke: 7,
                  color: scheme.primary,
                  track: scheme.onPrimaryContainer.withValues(alpha: 0.14),
                  child: Icon(Icons.local_fire_department_rounded,
                      size: 24, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$streak-day streak',
                          style: theme.textTheme.titleMedium!
                              .copyWith(color: scheme.onPrimaryContainer)),
                      const SizedBox(height: 2),
                      Text(
                        'Read a few pages today to keep it alive. '
                        'Your best is $best.',
                        style: theme.textTheme.bodySmall!.copyWith(
                            color: scheme.onPrimaryContainer
                                .withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),

          const SectionTitle(title: 'All challenges'),
          for (final c in challenges)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ChallengeCard(
                challenge: c,
                progress: challengeProgress(c, books, sessions),
              ),
            ),

          SectionTitle(
              title: 'Recent badges',
              action: 'All badges',
              onAction: () => context.push('/achievements')),
          if (badges.isEmpty)
            const EmptyState(
                icon: Icons.military_tech_rounded,
                message: 'Finish your first book to earn a badge.')
          else
            Row(children: [
              for (final b in badges.take(3))
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: scheme.tertiaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(b.spec.icon,
                            size: 24, color: scheme.onTertiaryContainer),
                      ),
                      const SizedBox(height: 8),
                      Text(b.spec.name,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelMedium),
                    ]),
                  ),
                ),
            ]),
        ],
      ),
    );
  }
}
