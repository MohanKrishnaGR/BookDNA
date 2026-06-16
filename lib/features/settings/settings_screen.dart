import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/haptics/haptics.dart';
import '../../core/messaging/push_messaging.dart';
import '../../core/notifications/notification_scheduler.dart';
import '../../core/providers.dart';
import '../../core/supabase/client.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/utils/format.dart';
import '../../widgets/common.dart';
import '../auth/auth_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    final books = ref.read(booksProvider).value ?? [];
    final rows = <List<dynamic>>[
      [
        'Title', 'Author', 'Genre', 'Pages', 'Year', 'Price', 'Status',
        'Progress', 'Rating', 'ISBN', 'Publisher', 'Language', 'Added',
      ],
      for (final b in books)
        [
          b.title, b.author, b.genre, b.pages, b.year ?? '', b.price ?? '',
          b.status.name, (b.progress * 100).round(), b.rating ?? '',
          b.isbn ?? '', b.publisher ?? '', b.language,
          b.addedAt.toIso8601String().substring(0, 10),
        ],
    ];
    String cell(dynamic v) {
      final s = '$v';
      return s.contains(RegExp(r'[",\n]'))
          ? '"${s.replaceAll('"', '""')}"'
          : s;
    }

    final csv = rows.map((r) => r.map(cell).join(',')).join('\r\n');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/bookdna-library.csv');
    await file.writeAsString(csv);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'BookDNA library export',
      ),
    );
    if (context.mounted) {
      showToast(context, 'Exported ${books.length} books as CSV');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mode = ref.watch(themeModeProvider);
    final hapticsOn = ref.watch(hapticsEnabledProvider);
    final notifOn = ref.watch(notificationsEnabledProvider);
    final dailyOn = ref.watch(dailyReminderEnabledProvider);
    final dailyTime = ref.watch(dailyReminderTimeProvider);
    final streakOn = ref.watch(streakRemindersProvider);
    final finishOn = ref.watch(finishRemindersProvider);
    final lendOn = ref.watch(lendRemindersProvider);
    final books = ref.watch(booksProvider).value ?? [];
    final sync = ref.watch(syncControllerProvider);
    final user = ref.watch(currentUserProvider).value;

    void reschedule() => ref.read(notificationSchedulerProvider).refresh();

    Widget header(String label) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
          child: Text(label,
              style: theme.textTheme.labelMedium!.copyWith(
                  color: scheme.primary, letterSpacing: 1)),
        );

    Widget row(IconData icon, String title, String sub,
        {Widget? trailing, VoidCallback? onTap}) {
      return ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: scheme.surfaceContainerHighest,
          child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        ),
        title: Text(title, style: theme.textTheme.titleSmall),
        subtitle: Text(sub),
        trailing: trailing ??
            (onTap != null
                ? const Icon(Icons.chevron_right_rounded)
                : null),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          header('APPEARANCE'),
          row(
            Icons.dark_mode_rounded,
            'Dark theme',
            'Tonal palettes adapt automatically',
            trailing: Switch(
              value: mode == ThemeMode.dark,
              onChanged: (v) {
                Haptics.selection();
                ref.read(themeModeProvider.notifier).toggle(v);
              },
            ),
          ),
          row(
            Icons.vibration_rounded,
            'Haptic feedback',
            'Subtle taps on scans, saves and milestones',
            trailing: Switch(
              value: hapticsOn,
              onChanged: (v) {
                ref.read(hapticsEnabledProvider.notifier).toggle(v);
                if (v) Haptics.selection(); // let them feel it turn on
              },
            ),
          ),
          header('NOTIFICATIONS'),
          row(
            Icons.notifications_active_rounded,
            'Notifications',
            'Reminders, streak saves and nudges',
            trailing: Switch(
              value: notifOn,
              onChanged: (v) {
                ref.read(notificationsEnabledProvider.notifier).set(v);
                reschedule();
                // Register or drop the FCM token to match the toggle.
                PushMessaging.instance.syncRegistration(v);
              },
            ),
          ),
          if (notifOn) ...[
            row(
              Icons.alarm_rounded,
              'Daily reading reminder',
              dailyOn ? 'Every day at ${dailyTime.format(context)}' : 'Off',
              trailing: Switch(
                value: dailyOn,
                onChanged: (v) {
                  ref.read(dailyReminderEnabledProvider.notifier).set(v);
                  reschedule();
                },
              ),
            ),
            if (dailyOn)
              row(
                Icons.schedule_rounded,
                'Reminder time',
                dailyTime.format(context),
                onTap: () async {
                  final picked = await showTimePicker(
                      context: context, initialTime: dailyTime);
                  if (picked != null) {
                    ref.read(dailyReminderTimeProvider.notifier).set(picked);
                    reschedule();
                  }
                },
              ),
            row(
              Icons.local_fire_department_rounded,
              'Streak saver',
              "Evening nudge if you haven't read",
              trailing: Switch(
                value: streakOn,
                onChanged: (v) {
                  ref.read(streakRemindersProvider.notifier).set(v);
                  reschedule();
                },
              ),
            ),
            row(
              Icons.flag_circle_rounded,
              'Finish-line nudges',
              "When you're close to finishing a book",
              trailing: Switch(
                value: finishOn,
                onChanged: (v) {
                  ref.read(finishRemindersProvider.notifier).set(v);
                  reschedule();
                },
              ),
            ),
            row(
              Icons.swap_horiz_rounded,
              'Lend reminders',
              'When a lent book is due back',
              trailing: Switch(
                value: lendOn,
                onChanged: (v) {
                  ref.read(lendRemindersProvider.notifier).set(v);
                  reschedule();
                },
              ),
            ),
          ],
          header('DATA'),
          row(
            Icons.download_rounded,
            'Export library',
            '${books.length} books as CSV',
            onTap: () => _exportCsv(context, ref),
          ),
          row(
            Icons.cloud_sync_rounded,
            'Backup & sync',
            switch (sync.phase) {
              SyncPhase.disabled =>
                'No backend configured for this build',
              SyncPhase.syncing => 'Syncing…',
              SyncPhase.error => 'Last attempt failed — tap to retry',
              SyncPhase.idle => sync.lastSync == null
                  ? user == null
                      ? 'Sign in to sync across devices'
                      : 'Tap to sync now'
                  : 'Last synced ${relativeTime(sync.lastSync!)}',
            },
            onTap: () {
              if (sync.phase == SyncPhase.disabled) {
                showToast(context,
                    'Run with --dart-define=SUPABASE_URL/SUPABASE_ANON_KEY to enable sync');
              } else if (user == null) {
                context.go('/auth');
              } else {
                if (sync.phase == SyncPhase.error && sync.message != null) {
                  showToast(context,
                      'Retrying — last error: ${sync.message!.substring(0, sync.message!.length.clamp(0, 120))}');
                } else {
                  showToast(context, 'Syncing your library…');
                }
                ref.read(syncControllerProvider.notifier).syncNow();
              }
            },
          ),
          row(
            Icons.extension_rounded,
            'Integrations',
            'Goodreads import — Phase 3',
            onTap: () =>
                showToast(context, 'Goodreads CSV import arrives in Phase 3'),
          ),
          header('PRIVACY & ACCOUNT'),
          row(
            Icons.visibility_rounded,
            'Public profile',
            'Friends can see your shelf & streaks — Phase 3',
            trailing: Switch(value: false, onChanged: (_) {}),
          ),
          if (user == null)
            row(
              Icons.account_circle_rounded,
              'Account',
              supabaseConfigured
                  ? 'Not signed in — sign in to keep your library safe'
                  : 'Local mode — no backend configured',
              onTap: () => context.go('/auth'),
            )
          else
            row(
              Icons.account_circle_rounded,
              'Account',
              user.isAnonymous
                  ? 'Guest — add an email to keep your library safe'
                  : user.email ?? 'Signed in',
              trailing: TextButton(
                onPressed: () async {
                  if (user.isAnonymous) {
                    context.go('/auth');
                    return;
                  }
                  await ref.read(authControllerProvider).signOut();
                  if (context.mounted) {
                    showToast(context,
                        'Signed out — local data cleared (safe in the cloud)');
                    context.go('/auth');
                  }
                },
                child: Text(user.isAnonymous ? 'Upgrade' : 'Sign out'),
              ),
            ),
        ],
      ),
    );
  }
}
