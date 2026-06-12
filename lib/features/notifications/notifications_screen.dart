import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/book_accent.dart';
import '../../core/providers.dart';
import '../../widgets/common.dart';
import '../insights/logic/formulas.dart';

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
            onAction: () => showToast(
                context, 'Reminder sent to ${l.toName.split(' ').first}'),
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
      (
        icon: Icons.auto_awesome_rounded,
        hue: 150,
        title: 'Your Wrapped is ready',
        sub: 'Your month in books, as a story — see how it went',
        action: 'Watch',
        onAction: () => context.push('/wrapped'),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          TextButton(
            onPressed: () {
              showToast(context, 'All caught up');
              context.pop();
            },
            child: const Text('Clear all'),
          ),
        ],
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
