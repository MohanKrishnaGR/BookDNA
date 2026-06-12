import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/book_accent.dart';
import '../../core/db/database.dart';
import '../../core/models/book_status.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/common.dart';
import '../../widgets/stars.dart';
import '../../widgets/status_badge.dart';
import 'sheets.dart';

class BookDetailsScreen extends ConsumerWidget {
  const BookDetailsScreen({super.key, required this.bookId});

  final String bookId;

  Future<void> _startReading(
      BuildContext context, WidgetRef ref, Book book) async {
    final db = ref.read(databaseProvider);
    if (book.status != BookStatus.reading) {
      await db.updateBook(
        book.id,
        BooksCompanion(
          status: const Value(BookStatus.reading),
          startedAt: Value(book.startedAt ?? DateTime.now()),
          progress: Value(book.status == BookStatus.read ? 0 : book.progress),
          currentPage:
              Value(book.status == BookStatus.read ? 0 : book.currentPage),
        ),
      );
      await db.logActivity('auto_stories', 'Started reading ${book.title}');
    }
    if (context.mounted) context.push('/tracker/${book.id}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookAsync = ref.watch(bookProvider(bookId));
    final book = bookAsync.value;
    if (book == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = accentFor(book.hueShift, theme.brightness);
    final notes = ref.watch(bookNotesProvider(bookId)).value ?? [];
    final related = (ref.watch(booksProvider).value ?? [])
        .where((b) => b.genre == book.genre && b.id != book.id)
        .take(5)
        .toList();

    final primaryLabel = switch (book.status) {
      BookStatus.unread => 'Start reading',
      BookStatus.reading => 'Continue reading',
      BookStatus.read => 'Read again',
    };

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [accent.container, scheme.surface],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        children: [
                          Row(children: [
                            IconButton(
                              onPressed: () => context.pop(),
                              icon: Icon(Icons.arrow_back_rounded,
                                  color: accent.onContainer),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: () => showShareSheet(context, book),
                              icon: Icon(Icons.share_rounded,
                                  color: accent.onContainer),
                            ),
                            IconButton(
                              onPressed: () =>
                                  showMoreSheet(context, ref, book),
                              icon: Icon(Icons.more_vert_rounded,
                                  color: accent.onContainer),
                            ),
                          ]),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                BookCover(
                                    title: book.title,
                                    author: book.author,
                                    hueShift: book.hueShift,
                                    width: 118),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(book.title,
                                          style: theme.textTheme.titleLarge!
                                              .copyWith(
                                                  color: accent.onContainer)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${book.author}${book.year != null ? ' · ${book.year}' : ''}',
                                        style: theme.textTheme.bodyMedium!
                                            .copyWith(
                                                color: accent.onContainer
                                                    .withValues(alpha: 0.75)),
                                      ),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          StatusBadge(status: book.status),
                                          Stars(
                                            rating: book.rating ?? 0,
                                            size: 20,
                                            onRate: (r) async {
                                              await ref
                                                  .read(databaseProvider)
                                                  .updateBook(
                                                      book.id,
                                                      BooksCompanion(
                                                          rating: Value(r)));
                                              if (context.mounted) {
                                                showToast(context,
                                                    'Rated $r star${r == 1 ? '' : 's'}');
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Metadata pills.
                      SizedBox(
                        height: 32,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _pill(context, Icons.menu_book_rounded,
                                '${book.pages} pages'),
                            _pill(context, Icons.category_outlined,
                                book.genre),
                            _pill(context, Icons.language_rounded,
                                book.language),
                            if (book.price != null)
                              _pill(context, Icons.payments_outlined,
                                  formatInr(book.price!)),
                            if (book.publisher != null)
                              _pill(context, Icons.apartment_rounded,
                                  book.publisher!),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      if (book.status == BookStatus.reading) ...[
                        _ProgressCard(book: book),
                        const SizedBox(height: 12),
                      ],

                      if (book.description != null)
                        Card(
                          color: scheme.secondaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.auto_awesome_rounded,
                                    size: 20,
                                    color: scheme.onSecondaryContainer),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    book.description!,
                                    style: theme.textTheme.bodyMedium!
                                        .copyWith(
                                            color:
                                                scheme.onSecondaryContainer),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      SectionTitle(
                          title: 'Notes & highlights',
                          action: 'Add',
                          onAction: () => showNoteSheet(context, ref, book)),
                      if (notes.isEmpty)
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: scheme.outlineVariant),
                          ),
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => showNoteSheet(context, ref, book),
                            child: const Padding(
                              padding: EdgeInsets.all(18),
                              child: Text(
                                  'No notes yet — capture a thought or quote'),
                            ),
                          ),
                        )
                      else
                        for (final n in notes)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('“${n.body}”',
                                      style: theme.textTheme.bodyMedium!
                                          .copyWith(
                                              fontStyle: FontStyle.italic)),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${n.page != null ? 'p. ${n.page} · ' : ''}${relativeTime(n.createdAt)}',
                                    style: theme.textTheme.labelMedium!
                                        .copyWith(
                                            color: scheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ),

                      if (related.isNotEmpty) ...[
                        SectionTitle(title: 'More ${book.genre} on your shelf'),
                        SizedBox(
                          height: 84 * 1.5,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final b in related)
                                Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: InkWell(
                                    onTap: () => context
                                        .pushReplacement('/book/${b.id}'),
                                    child: BookCover(
                                        title: b.title,
                                        author: b.author,
                                        hueShift: b.hueShift,
                                        width: 84),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
          ),
          // Bottom action bar.
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
              color: scheme.surface,
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: SafeArea(
              top: false,
              child: Row(children: [
                FilledButton.tonalIcon(
                  onPressed: () => showNoteSheet(context, ref, book),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Note'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _startReading(context, ref, book),
                    style:
                        FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(primaryLabel),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(children: [
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelMedium!
                .copyWith(color: scheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _ProgressCard extends ConsumerWidget {
  const _ProgressCard({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Reading progress',
                    style: theme.textTheme.titleSmall!
                        .copyWith(color: scheme.onPrimaryContainer)),
                Text('${(book.progress * 100).round()}%',
                    style: theme.textTheme.titleSmall!
                        .copyWith(color: scheme.onPrimaryContainer)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: book.progress,
                minHeight: 8,
                backgroundColor:
                    scheme.onPrimaryContainer.withValues(alpha: 0.16),
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Page ${book.currentPage} of ${book.pages}',
              style: theme.textTheme.bodySmall!.copyWith(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }
}
