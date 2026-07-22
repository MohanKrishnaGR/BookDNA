import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme/book_accent.dart';
import '../../core/providers.dart';
import '../../widgets/common.dart';
import '../insights/logic/formulas.dart';
import '../wrapped/wrapped_stats.dart';

/// Notification center, generated from real local state:
/// streak risk, overdue lends, goal progress.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(allSessionsProvider).value ?? [];
    final lends = ref.watch(lendsProvider).value ?? [];
    final books = ref.watch(booksProvider).value ?? [];
    final goal = ref.watch(goalProvider).value;
    final theme = Theme.of(context);

    final streak = currentStreak(sessions);
    final today = DateTime.now();
    final readToday = sessions.any((s) =>
        s.sessionDate.year == today.year &&
        s.sessionDate.month == today.month &&
        s.sessionDate.day == today.day);
    // Only announce Wrapped when the month (or its fallback) has activity.
    final wrapped = WrappedStats.compute(books, sessions);

    final items = <({IconData icon, int hue, String title, String sub, String? action, VoidCallback? onAction})>[
      if (streak > 0 && !readToday)
        (
          icon: Icons.local_fire_department_rounded,
          hue: 30,
          title: 'Your $streak-day streak is at risk',
          sub: 'Read a few pages today to keep it going',
          action: null,
          onAction: null,
        ),
      for (final l in lends)
        if (l.dueOn != null && DateTime.now().isAfter(l.dueOn!))
          (
            icon: Icons.swap_horiz_rounded,
            hue: 60,
            title:
                '${l.bookTitle} is ${DateTime.now().difference(l.dueOn!).inDays} days overdue',
            sub: '${l.toName} borrowed it — send a reminder?',
            action: 'Remind',
            onAction: () => SharePlus.instance.share(ShareParams(
                text: 'Hey ${l.toName.split(' ').first}! Friendly nudge — '
                    'could I get "${l.bookTitle}" back when you\'re '
                    'done? 📚')),
          ),
      if (goal != null)
        (
          icon: Icons.flag_rounded,
          hue: 150,
          title:
              '${finishedInYear(books, today.year)} of ${goal.target} books read this year',
          sub: 'Tap the goal card on Home to adjust your target',
          action: null,
          onAction: null,
        ),
      if (!wrapped.isEmpty)
        (
          icon: Icons.auto_awesome_rounded,
          hue: 150,
          title: 'Your ${wrapped.monthLabel} Wrapped is ready',
          sub: 'Your month in books, as a story — see how it went',
          action: 'Watch',
          onAction: () => context.push('/wrapped'),
        ),
    ];

    return Scaffold(
      // No "Clear all": these cards are derived live from streak/lend/goal
      // state, so the only honest way to clear one is to act on it.
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
        children: [
          for (final n in items)
            Builder(builder: (context) {
              final accent = accentFor(n.hue, theme.brightness);
              return ListTile(
                leading: CircleAvatar(
                  radius: 22,
                  backgroundColor: accent.container,
                  child: Icon(n.icon, size: 20, color: accent.onContainer),
                ),
                title: Text(n.title,
                    style: theme.textTheme.bodyLarge!
                        .copyWith(fontWeight: FontWeight.w500)),
                subtitle: Text(n.sub),
                trailing: n.action != null
                    ? FilledButton.tonal(
                        onPressed: n.onAction, child: Text(n.action!))
                    : null,
              );
            }),
          if (items.isEmpty)
            const EmptyState(
                icon: Icons.notifications_none_rounded,
                message: 'All caught up.'),
        ],
      ),
    );
  }
}
