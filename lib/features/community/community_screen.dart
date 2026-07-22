import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme/book_accent.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../../widgets/common.dart';
import 'challenge_card.dart';
import 'challenges_providers.dart';

/// Community tab: challenges (live), weekly leaderboard (live, scoped to
/// your circle), friend feed (honest empty state until follows exist),
/// and borrow & lend tracking.
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lends = ref.watch(lendsProvider).value ?? [];
    final books = ref.watch(booksProvider).value ?? [];
    final sessions = ref.watch(allSessionsProvider).value ?? [];
    final challenges =
        ref.watch(challengesProvider).value ?? kDefaultChallenges;
    final joined = ref.watch(joinedChallengesProvider).value ?? {};
    final leaderboard = ref.watch(leaderboardProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final db = ref.read(databaseProvider);

    final active =
        challenges.where((c) => joined.contains(c.id)).toList();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Community', style: theme.textTheme.headlineSmall),
                    Text('Read with your people',
                        style: theme.textTheme.bodySmall!
                            .copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
                IconButton.filledTonal(
                  onPressed: () => SharePlus.instance.share(ShareParams(
                      text:
                          'I track my bookshelf, streaks and reading DNA '
                          'with BookDNA — join me! '
                          'https://bookdna.app')),
                  icon: const Icon(Icons.person_add_rounded),
                ),
              ],
            ),

            SectionTitle(
                title: 'Active challenges',
                action: 'See all',
                onAction: () => context.push('/challenges')),
            SizedBox(
              height: 158,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final c in active)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ChallengeCard(
                        challenge: c,
                        progress: challengeProgress(c, books, sessions),
                        compact: true,
                      ),
                    ),
                  InkWell(
                    onTap: () => context.push('/challenges'),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 130,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline_rounded,
                              color: scheme.primary),
                          const SizedBox(height: 8),
                          Text(active.isEmpty ? 'Join one' : 'Join more',
                              style: theme.textTheme.labelLarge!
                                  .copyWith(color: scheme.primary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SectionTitle(title: "This week's leaderboard"),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: switch (leaderboard) {
                  AsyncData(:final value) when value.isNotEmpty =>
                    Column(children: [
                      for (var i = 0; i < value.length; i++)
                        _leaderboardRow(context, i + 1, value[i]),
                      if (value.length == 1)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                          child: Text(
                            'Just you so far — invite friends to compete '
                            'on weekly pages.',
                            style: theme.textTheme.bodySmall!.copyWith(
                                color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ]),
                  AsyncLoading() => const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))),
                    ),
                  _ => const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                          'Sign in to compete with friends on weekly pages.'),
                    ),
                },
              ),
            ),

            const SectionTitle(title: 'Friend activity'),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: scheme.outlineVariant),
              ),
              color: Colors.transparent,
              child: const Padding(
                padding: EdgeInsets.all(18),
                child: EmptyState(
                  icon: Icons.groups_outlined,
                  message:
                      'No friends yet. When friends join BookDNA, their '
                      'finishes, streaks and reviews show up here.',
                ),
              ),
            ),

            const SectionTitle(title: 'Borrowed & lent'),
            if (lends.isEmpty)
              const EmptyState(
                icon: Icons.swap_horiz_rounded,
                message:
                    'Nothing lent out. Lend a book from its details page (⋮ menu).',
              )
            else
              for (final l in lends)
                Builder(builder: (context) {
                  final overdueDays = l.dueOn == null
                      ? 0
                      : DateTime.now().difference(l.dueOn!).inDays;
                  final overdue = overdueDays > 0;
                  final accent = accentFor(
                      l.toName.hashCode.abs() % 360, theme.brightness);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: overdue
                        ? RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: scheme.error),
                          )
                        : null,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: accent.container,
                        child: Text(
                            l.toName.split(' ').map((w) => w[0]).join(),
                            style: TextStyle(
                                color: accent.onContainer,
                                fontWeight: FontWeight.w700)),
                      ),
                      title: Text(l.bookTitle),
                      subtitle: Text(
                        '${l.toName} · since ${relativeTime(l.lentOn)}'
                        '${overdue ? ' · $overdueDays days overdue' : ''}',
                        style: overdue
                            ? TextStyle(color: scheme.error)
                            : null,
                      ),
                      trailing: Wrap(spacing: 2, children: [
                        IconButton(
                          tooltip: 'Remind',
                          // Opens the system share sheet with a ready-made
                          // nudge — send it over any messaging app.
                          onPressed: () => SharePlus.instance.share(
                              ShareParams(
                                  text:
                                      'Hey ${l.toName.split(' ').first}! '
                                      'Friendly nudge — could I get '
                                      '"${l.bookTitle}" back when you\'re '
                                      'done? 📚')),
                          icon:
                              const Icon(Icons.notifications_none_rounded),
                        ),
                        IconButton(
                          tooltip: 'Mark returned',
                          onPressed: () async {
                            await db.returnLend(l.id);
                            if (context.mounted) {
                              showToast(context,
                                  '${l.bookTitle} is back on your shelf');
                            }
                          },
                          icon: const Icon(Icons.check_rounded),
                        ),
                      ]),
                    ),
                  );
                }),
          ],
        ),
      ),
    );
  }

  Widget _leaderboardRow(
      BuildContext context, int rank, LeaderboardEntry entry) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent =
        accentFor(entry.name.hashCode.abs() % 360, theme.brightness);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: entry.isMe
          ? BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            )
          : null,
      child: ListTile(
        dense: true,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              child: Text('$rank',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall!.copyWith(
                      color: rank <= 3
                          ? scheme.primary
                          : scheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 19,
              backgroundColor: accent.container,
              child: Text(
                entry.name
                    .split(' ')
                    .where((w) => w.isNotEmpty)
                    .take(2)
                    .map((w) => w[0].toUpperCase())
                    .join(),
                style: TextStyle(
                    color: accent.onContainer, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        title: Text(
          entry.isMe ? '${entry.name} (you)' : entry.name,
          style: theme.textTheme.bodyLarge!.copyWith(
              fontWeight: entry.isMe ? FontWeight.w700 : FontWeight.w400),
        ),
        subtitle: Text('${formatNumber(entry.pages)} pages'),
        trailing: rank == 1
            ? Icon(Icons.emoji_events_rounded,
                color: accentFor(60, theme.brightness).main)
            : null,
      ),
    );
  }
}
