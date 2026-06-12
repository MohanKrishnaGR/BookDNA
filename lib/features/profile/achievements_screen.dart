import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import 'badges.dart';

final allNotesProvider = StreamProvider(
    (ref) => ref.watch(databaseProvider).watchAllNotes());

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider).value ?? [];
    final sessions = ref.watch(allSessionsProvider).value ?? [];
    final notes = ref.watch(allNotesProvider).value ?? [];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final badges =
        evaluateBadges(books: books, sessions: sessions, notes: notes);
    final earnedCount = badges.where((b) => b.earned).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Achievements'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 14),
            child: Text(
              '$earnedCount of ${badges.length} earned',
              style: theme.textTheme.bodyMedium!
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.82,
            children: [
              for (final b in badges)
                Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 6),
                  decoration: BoxDecoration(
                    color: b.earned ? scheme.surfaceContainer : null,
                    borderRadius: BorderRadius.circular(16),
                    border: b.earned
                        ? null
                        : Border.all(color: scheme.outlineVariant),
                  ),
                  child: Opacity(
                    opacity: b.earned ? 1 : 0.55,
                    child: Column(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: b.earned
                                ? scheme.tertiaryContainer
                                : scheme.surfaceContainerHigh,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            b.earned ? b.spec.icon : Icons.lock_rounded,
                            size: 24,
                            color: b.earned
                                ? scheme.onTertiaryContainer
                                : scheme.outline,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(b.spec.name,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelMedium),
                        const SizedBox(height: 2),
                        Expanded(
                          child: Text(
                            b.earned ? 'Earned' : b.spec.hint,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall!.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w400),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
