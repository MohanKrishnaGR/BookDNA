import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/book_accent.dart';
import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/common.dart';
import '../../widgets/ring.dart';
import '../auth/auth_controller.dart';
import '../insights/logic/formulas.dart';
import '../profile/goal_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider).value ?? [];
    final sessions = ref.watch(allSessionsProvider).value ?? [];
    final reading = ref.watch(currentlyReadingProvider).value ?? [];
    final goal = ref.watch(goalProvider).value;
    final activities = ref.watch(activitiesProvider).value ?? [];

    final stats = computeLibraryStats(books, sessions);
    final streak = currentStreak(sessions);
    final diversity = computeDiversity(books);
    final velocity = velocityPagesPerDay(sessions);
    final continueBook = reading.isEmpty ? null : reading.first;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final profile = ref.watch(userProfileProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            // Header.
            Row(children: [
              _Avatar(
                onTap: () => context.go('/profile'),
                initials: profile.initials,
                photoUrl: profile.photoUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${greetingForHour(now.hour)}, ${profile.firstName}',
                        style: theme.textTheme.titleMedium),
                    Text(fullDate(now),
                        style: theme.textTheme.bodySmall!
                            .copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              _StreakPill(streak: streak),
              IconButton(
                onPressed: () => context.push('/notifications'),
                icon: const Icon(Icons.notifications_outlined),
              ),
            ]),
            const SizedBox(height: 16),

            // Continue reading.
            if (continueBook != null) _ContinueCard(book: continueBook),
            const SizedBox(height: 12),

            // Stat triplet.
            Row(children: [
              _StatCard(
                  icon: Icons.shelves, value: stats.owned, label: 'Owned'),
              const SizedBox(width: 10),
              _StatCard(
                  icon: Icons.check_circle_outline_rounded,
                  value: stats.read,
                  label: 'Read'),
              const SizedBox(width: 10),
              _StatCard(
                  icon: Icons.schedule_rounded,
                  value: stats.unread,
                  label: 'Unread'),
            ]),

            SectionTitle(
                title: 'Your Reading DNA',
                action: 'All insights',
                onAction: () => context.go('/insights')),
            SizedBox(
              height: 124,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _TeaserCard(
                    icon: Icons.payments_outlined,
                    hue: 60,
                    value: formatInr(stats.libraryValue),
                    label: 'Library value',
                    sub: 'estimated worth',
                  ),
                  _TeaserCard(
                    icon: Icons.category_outlined,
                    hue: 0,
                    value: genreBreakdown(books).isEmpty
                        ? '—'
                        : genreBreakdown(books).first.name,
                    label: 'Top genre',
                    sub: genreBreakdown(books).isEmpty
                        ? ''
                        : '${genreBreakdown(books).first.pct.round()}% of your shelf',
                  ),
                  _TeaserCard(
                    icon: Icons.speed_rounded,
                    hue: 150,
                    value: '${velocity.round()} pp/day',
                    label: 'Velocity',
                    sub: 'trailing 30 days',
                  ),
                  _TeaserCard(
                    icon: Icons.history_edu_rounded,
                    hue: 210,
                    value: '${stats.knowledgeAge}',
                    label: 'Knowledge age',
                    sub: 'median publish year',
                  ),
                  _TeaserCard(
                    icon: Icons.diversity_2_rounded,
                    hue: 320,
                    value: '${diversity.score}/100',
                    label: 'Diversity',
                    sub: 'genre & author spread',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Unread knowledge card.
            _UnreadCard(stats: stats),

            const SectionTitle(title: 'Quick actions'),
            _QuickActions(),

            const SizedBox(height: 12),
            _GoalCard(goal: goal, books: books),

            const SectionTitle(title: 'Recent activity'),
            Card(
              child: Column(
                children: [
                  for (final a in activities)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: scheme.surfaceContainerHighest,
                        child: Icon(iconFromName(a.icon),
                            size: 20, color: scheme.onSurfaceVariant),
                      ),
                      title: Text(a.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium),
                      trailing: Text(relativeTime(a.createdAt),
                          style: theme.textTheme.labelMedium!
                              .copyWith(color: scheme.onSurfaceVariant)),
                    ),
                  if (activities.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Your reading activity will appear here.'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.onTap, required this.initials, this.photoUrl});
  final VoidCallback? onTap;
  final String initials;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final accent = accentFor(0, Theme.of(context).brightness);
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: CircleAvatar(
        radius: 22,
        backgroundColor: accent.container,
        // Network photo (Google) when available; initials are the fallback
        // shown underneath if the image is missing or fails to load.
        foregroundImage: hasPhoto ? NetworkImage(photoUrl!) : null,
        child: Text(initials,
            style: TextStyle(
                color: accent.onContainer, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.streak});
  final int streak;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(children: [
        Icon(Icons.local_fire_department_rounded,
            size: 16, color: scheme.onTertiaryContainer),
        const SizedBox(width: 4),
        Text('$streak',
            style: Theme.of(context)
                .textTheme
                .labelLarge!
                .copyWith(color: scheme.onTertiaryContainer)),
      ]),
    );
  }
}

class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/book/${book.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(
                  title: book.title,
                  author: book.author,
                  hueShift: book.hueShift,
                  width: 86),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CONTINUE READING',
                        style: theme.textTheme.labelMedium!.copyWith(
                            color: scheme.onPrimaryContainer
                                .withValues(alpha: 0.7),
                            letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium!
                            .copyWith(color: scheme.onPrimaryContainer)),
                    Text(book.author,
                        style: theme.textTheme.bodySmall!.copyWith(
                            color: scheme.onPrimaryContainer
                                .withValues(alpha: 0.75))),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: book.progress,
                        minHeight: 8,
                        backgroundColor:
                            scheme.onPrimaryContainer.withValues(alpha: 0.18),
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('p. ${book.currentPage} of ${book.pages}',
                            style: theme.textTheme.labelMedium!.copyWith(
                                color: scheme.onPrimaryContainer
                                    .withValues(alpha: 0.8))),
                        FilledButton.icon(
                          onPressed: () =>
                              context.push('/tracker/${book.id}'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 34),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text('Resume'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.icon, required this.value, required this.label});
  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 6),
            AnimatedCounter(
                value: value,
                format: (v) => formatNumber(v),
                style: theme.textTheme.titleMedium),
            Text(label,
                style: theme.textTheme.labelMedium!
                    .copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

class _TeaserCard extends StatelessWidget {
  const _TeaserCard({
    required this.icon,
    required this.hue,
    required this.value,
    required this.label,
    required this.sub,
  });

  final IconData icon;
  final int hue;
  final String value;
  final String label;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentFor(hue, theme.brightness);
    return GestureDetector(
      onTap: () => context.go('/insights'),
      child: Container(
        width: 142,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accent.container,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: accent.onContainer),
            const Spacer(),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium!
                    .copyWith(color: accent.onContainer)),
            Text(label,
                style: theme.textTheme.labelMedium!
                    .copyWith(color: accent.onContainer)),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall!.copyWith(
                    color: accent.onContainer.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}

class _UnreadCard extends StatelessWidget {
  const _UnreadCard({required this.stats});
  final LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ratio = stats.owned == 0 ? 0.0 : stats.unread / stats.owned;
    return Card(
      color: scheme.tertiaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/insights'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Ring(
              value: ratio,
              size: 56,
              stroke: 6,
              color: scheme.tertiary,
              track: scheme.onTertiaryContainer.withValues(alpha: 0.15),
              child: Icon(Icons.hourglass_bottom_rounded,
                  size: 20, color: scheme.onTertiaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${formatNumber(stats.unreadHours)} hours of knowledge waiting',
                    style: theme.textTheme.titleSmall!
                        .copyWith(color: scheme.onTertiaryContainer),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${stats.unread} unread books · ${formatNumber(stats.unreadPages)} pages on your shelf',
                    style: theme.textTheme.bodySmall!.copyWith(
                        color: scheme.onTertiaryContainer
                            .withValues(alpha: 0.75)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: scheme.onTertiaryContainer),
          ]),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final actions = [
      (Icons.qr_code_scanner_rounded, 'Scan book', '/scanner'),
      (Icons.edit_note_rounded, 'Add manually', '/scanner?manual=1'),
      (Icons.auto_awesome_rounded, 'AI analysis', '/ai'),
      (Icons.flag_rounded, 'Challenges', '/community'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final (icon, label, route) in actions)
            Expanded(
              child: InkWell(
                onTap: () => route.startsWith('/scanner') ||
                        route.startsWith('/ai')
                    ? context.push(route)
                    : context.go(route),
                borderRadius: BorderRadius.circular(12),
                child: Column(children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon,
                        size: 22, color: scheme.onSecondaryContainer),
                  ),
                  const SizedBox(height: 6),
                  Text(label,
                      style: theme.textTheme.labelMedium,
                      textAlign: TextAlign.center),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal, required this.books});
  final Goal? goal;
  final List<Book> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final year = DateTime.now().year;
    final done = finishedInYear(books, year);
    final target = goal?.target ?? 12;
    final remaining = target - done;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showGoalSheet(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Ring(
              value: target == 0 ? 0 : done / target,
              size: 70,
              stroke: 7,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$done/$target', style: theme.textTheme.titleSmall),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$year reading goal',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    remaining > 0
                        ? '$remaining books to go'
                        : 'Goal reached — tap to raise it',
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.trending_up_rounded, color: scheme.secondary),
          ]),
        ),
      ),
    );
  }
}
