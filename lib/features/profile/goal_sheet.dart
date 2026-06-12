import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../widgets/common.dart';

/// Yearly reading-goal editor (prototype `GoalSheet`).
void showGoalSheet(BuildContext context, WidgetRef ref) {
  final db = ref.read(databaseProvider);
  final year = DateTime.now().year;
  final initial = ref.read(goalProvider).value?.target ?? 12;

  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      var target = initial;
      return StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(context);
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('$year reading goal',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Books this year',
                        style: theme.textTheme.bodyLarge),
                    StepperRow(
                      value: target,
                      min: 1,
                      max: 120,
                      onChanged: (v) => setState(() => target = v),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'That\'s ${(target / 12).toStringAsFixed(1)} books a month. At your velocity, very doable.',
                  style: theme.textTheme.bodySmall!.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () async {
                    await db.setGoal(year, target);
                    if (sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                    }
                    if (context.mounted) {
                      showToast(
                          context, 'Goal set: $target books in $year');
                    }
                  },
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                  icon: const Icon(Icons.flag_rounded),
                  label: const Text('Set goal'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
