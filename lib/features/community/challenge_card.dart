import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/book_accent.dart';
import '../../widgets/common.dart';
import 'challenges_providers.dart';

IconData challengeIcon(String name) => switch (name) {
      'local_fire_department' => Icons.local_fire_department_rounded,
      'menu_book' => Icons.menu_book_rounded,
      'explore' => Icons.explore_rounded,
      'groups' => Icons.groups_rounded,
      _ => Icons.flag_rounded,
    };

class ChallengeCard extends ConsumerWidget {
  const ChallengeCard({
    super.key,
    required this.challenge,
    required this.progress,
    this.compact = false,
  });

  final Challenge challenge;
  final int progress;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accent = accentFor(challenge.hueShift, theme.brightness);
    final joined = (ref.watch(joinedChallengesProvider).value ?? {})
        .contains(challenge.id);

    return Container(
      width: compact ? 190 : null,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.container,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(challengeIcon(challenge.icon),
                  size: 24, color: accent.onContainer),
              if (!compact)
                FilledButton.tonal(
                  onPressed: () async {
                    await ref
                        .read(joinedChallengesProvider.notifier)
                        .toggle(challenge.id);
                    if (context.mounted) {
                      showToast(
                          context,
                          joined
                              ? 'Left ${challenge.title}'
                              : 'Joined ${challenge.title} — go!');
                    }
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    backgroundColor: joined
                        ? Colors.white.withValues(alpha: 0.45)
                        : accent.onContainer.withValues(alpha: 0.12),
                    foregroundColor: accent.onContainer,
                  ),
                  child: Text(joined ? 'Joined ✓' : 'Join'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(challenge.title,
              style: theme.textTheme.titleSmall!
                  .copyWith(color: accent.onContainer)),
          Text(challenge.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall!.copyWith(
                  color: accent.onContainer.withValues(alpha: 0.75))),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: challenge.target == 0
                  ? 0
                  : progress / challenge.target,
              minHeight: 7,
              color: accent.onContainer,
              backgroundColor:
                  accent.onContainer.withValues(alpha: 0.18),
            ),
          ),
          const SizedBox(height: 5),
          Align(
            alignment: Alignment.centerRight,
            child: Text('$progress/${challenge.target}',
                style: theme.textTheme.labelMedium!
                    .copyWith(color: accent.onContainer)),
          ),
        ],
      ),
    );
  }
}
