import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/analytics/analytics.dart';
import '../../core/db/database.dart';
import '../../core/haptics/haptics.dart';
import '../../core/models/book_status.dart';
import '../../core/providers.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/common.dart';
import '../../widgets/ring.dart';
import '../insights/logic/formulas.dart';
import 'heatmap.dart';

class TrackerScreen extends ConsumerWidget {
  const TrackerScreen({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(bookProvider(bookId)).value;
    final sessions = ref.watch(bookSessionsProvider(bookId)).value ?? [];
    final allSessions = ref.watch(allSessionsProvider).value ?? [];
    if (book == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pagesLeft = (book.pages - book.currentPage).clamp(0, book.pages);
    final speed = readingSpeed(sessions.isEmpty ? allSessions : sessions);
    final days = daysToFinish(book, sessions);
    final heat = readingHeatmap(allSessions, weeks: 9);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reading tracker'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              children: [
                // Book + progress ring.
                Card(
                  color: scheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      BookCover(
                          title: book.title,
                          author: book.author,
                          hueShift: book.hueShift,
                          width: 64),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(book.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall!.copyWith(
                                    color: scheme.onPrimaryContainer)),
                            Text(book.author,
                                style: theme.textTheme.bodySmall!.copyWith(
                                    color: scheme.onPrimaryContainer
                                        .withValues(alpha: 0.75))),
                          ],
                        ),
                      ),
                      Ring(
                        value: book.progress,
                        size: 66,
                        stroke: 7,
                        color: scheme.primary,
                        track:
                            scheme.onPrimaryContainer.withValues(alpha: 0.14),
                        child: Text('${(book.progress * 100).round()}%',
                            style: theme.textTheme.labelLarge!.copyWith(
                                color: scheme.onPrimaryContainer)),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),

                // Stat tiles.
                Row(children: [
                  _tile(context, Icons.menu_book_rounded,
                      '${book.currentPage}', 'current page'),
                  const SizedBox(width: 10),
                  _tile(context, Icons.auto_stories_rounded, '$pagesLeft',
                      'pages left'),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  _tile(context, Icons.speed_rounded,
                      '${speed.round()}/hr', 'reading speed'),
                  const SizedBox(width: 10),
                  _tile(context, Icons.event_available_rounded,
                      pagesLeft == 0 ? 'Done' : '$days days', 'to finish'),
                ]),

                const SectionTitle(title: 'Recent sessions'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _SessionBars(sessions: sessions.take(7).toList()),
                        if (sessions.isNotEmpty) const Divider(height: 26),
                        for (final s in sessions.take(4))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: Icon(Icons.auto_stories_rounded,
                                size: 20, color: scheme.primary),
                            title: Text(
                                '${s.pages} pages · ${s.minutes} min',
                                style: theme.textTheme.bodyMedium),
                            subtitle: Text(
                                DateFormat('EEE, d MMM').format(s.sessionDate)),
                            trailing: Text(
                                '${(s.pages / s.minutes * 60).round()} pp/hr',
                                style: theme.textTheme.labelMedium!.copyWith(
                                    color: scheme.onSurfaceVariant)),
                          ),
                        if (sessions.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                                'No sessions yet — log your first below.'),
                          ),
                      ],
                    ),
                  ),
                ),

                const SectionTitle(title: 'Reading calendar'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HeatmapGrid(data: heat, cell: 26, gap: 5),
                        const SizedBox(height: 10),
                        Text('Last 9 weeks · darker = more pages',
                            style: theme.textTheme.bodySmall!.copyWith(
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: SafeArea(
              top: false,
              child: FilledButton.icon(
                onPressed: () => _showLogSheet(context, ref, book),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52)),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Log a session'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
      BuildContext context, IconData icon, String value, String label) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(value, style: theme.textTheme.titleMedium),
              Text(label,
                  style: theme.textTheme.labelMedium!
                      .copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogSheet(BuildContext context, WidgetRef ref, Book book) {
    final db = ref.read(databaseProvider);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        var pages = 20;
        var minutes = 30;
        return StatefulBuilder(builder: (context, setState) {
          final theme = Theme.of(context);
          final newPage = (book.currentPage + pages).clamp(0, book.pages);
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Log a reading session',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Pages read', style: theme.textTheme.bodyLarge),
                    StepperRow(
                        value: pages,
                        min: 1,
                        max: 200,
                        step: 5,
                        onChanged: (v) => setState(() => pages = v)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Minutes', style: theme.textTheme.bodyLarge),
                    StepperRow(
                        value: minutes,
                        min: 5,
                        max: 300,
                        step: 5,
                        onChanged: (v) => setState(() => minutes = v)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'You\'ll be on page $newPage of ${book.pages}.',
                  style: theme.textTheme.bodySmall!.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    final finished = newPage >= book.pages;
                    await db.addSession(
                        bookId: book.id, pages: pages, minutes: minutes);
                    await db.updateBook(
                      book.id,
                      BooksCompanion(
                        currentPage: Value(newPage),
                        progress: Value(book.pages == 0
                            ? 0
                            : newPage / book.pages),
                        status: Value(finished
                            ? BookStatus.read
                            : BookStatus.reading),
                        finishedAt:
                            Value(finished ? DateTime.now() : null),
                      ),
                    );
                    await db.logActivity('auto_stories',
                        'Read $pages pages of ${book.title}');
                    Analytics.instance.log('reading_session_logged', {
                      'pages': pages,
                      'minutes': minutes,
                    });
                    if (finished) {
                      Analytics.instance
                          .log('book_finished', {'genre': book.genre});
                      Haptics.celebrate();
                    } else {
                      Haptics.success();
                    }
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    if (context.mounted) {
                      showToast(
                          context,
                          finished
                              ? 'You finished ${book.title}! 🎉'
                              : 'Logged $pages pages — streak alive');
                    }
                  },
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save session'),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}

class _SessionBars extends StatelessWidget {
  const _SessionBars({required this.sessions});

  final List<ReadingSession> sessions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (sessions.isEmpty) return const SizedBox.shrink();
    final ordered = sessions.reversed.toList();
    final max = ordered.fold(1, (m, s) => s.pages > m ? s.pages : m);
    return SizedBox(
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < ordered.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${ordered[i].pages}',
                        style: theme.textTheme.labelMedium),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      height: 70 * ordered[i].pages / max,
                      decoration: BoxDecoration(
                        color: i == ordered.length - 1
                            ? scheme.primary
                            : scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(DateFormat('E').format(ordered[i].sessionDate),
                        style: theme.textTheme.labelSmall!
                            .copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
