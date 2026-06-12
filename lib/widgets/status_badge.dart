import 'package:flutter/material.dart';

import '../core/models/book_status.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final BookStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, icon) = switch (status) {
      BookStatus.reading => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Icons.auto_stories_rounded
        ),
      BookStatus.read => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
          Icons.check_circle_rounded
        ),
      BookStatus.unread => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          Icons.schedule_rounded
        ),
    };
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: Theme.of(context)
                .textTheme
                .labelMedium!
                .copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}
