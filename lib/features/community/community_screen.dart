import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/book_accent.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../../widgets/common.dart';

/// Community tab. Borrow & lend is live (local). Challenges, leaderboard
/// and the friend feed ship with Phase 3 (Supabase social graph).
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lends = ref.watch(lendsProvider).value ?? [];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final db = ref.read(databaseProvider);

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
                  onPressed: () => showToast(
                      context, 'Invite link copied — share it anywhere'),
                  icon: const Icon(Icons.person_add_rounded),
                ),
              ],
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
                          onPressed: () => showToast(context,
                              'Reminder sent to ${l.toName.split(' ').first}'),
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

            const SectionTitle(title: 'Coming in Phase 3'),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: scheme.outlineVariant),
              ),
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (icon, title, sub) in [
                      (
                        Icons.local_fire_department_rounded,
                        'Challenges',
                        '100-day streaks, monthly book sprints, genre explorer'
                      ),
                      (
                        Icons.leaderboard_rounded,
                        'Leaderboard',
                        'Weekly pages, ranked with friends'
                      ),
                      (
                        Icons.groups_rounded,
                        'Friend activity',
                        'See what your circle is reading and finishing'
                      ),
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icon,
                                size: 20,
                                color: scheme.onSecondaryContainer),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title,
                                    style: theme.textTheme.titleSmall),
                                Text(sub,
                                    style: theme.textTheme.bodySmall!
                                        .copyWith(
                                            color:
                                                scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ]),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
