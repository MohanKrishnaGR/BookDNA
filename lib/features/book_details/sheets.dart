import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/db/database.dart';
import '../../core/models/book_status.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/stars.dart';

// ───────────────────────── Note sheet ─────────────────────────

void showNoteSheet(BuildContext context, WidgetRef ref, Book book) {
  final db = ref.read(databaseProvider);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      var text = '';
      var page = book.currentPage;
      return StatefulBuilder(builder: (context, setState) {
        final theme = Theme.of(context);
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add a note', style: theme.textTheme.titleMedium),
              const SizedBox(height: 14),
              TextField(
                autofocus: true,
                maxLines: 4,
                onChanged: (v) => setState(() => text = v),
                decoration: const InputDecoration(
                    hintText: 'A thought, a quote, a highlight…'),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Page', style: theme.textTheme.bodyLarge),
                  StepperRow(
                    value: page,
                    min: 0,
                    max: book.pages,
                    step: 1,
                    onChanged: (v) => setState(() => page = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: text.trim().isEmpty
                    ? null
                    : () async {
                        await db.addNote(book.id, text.trim(), page);
                        await db.logActivity(
                            'edit_note', 'Added a note to ${book.title}');
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        if (context.mounted) showToast(context, 'Note added');
                      },
                style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Save note'),
              ),
            ],
          ),
        );
      });
    },
  );
}

// ───────────────────────── Share sheet ─────────────────────────

void showShareSheet(BuildContext context, Book book) {
  final slug = (book.isbn != null && book.isbn!.isNotEmpty)
      ? book.isbn!
      : book.id;
  final link = 'https://bookdna.app/b/$slug';
  final rating = book.rating;
  final shareText = [
    '📚 ${book.title}${book.author.isEmpty ? '' : ' — ${book.author}'}',
    if (rating != null && rating > 0)
      'My rating: ${'★' * rating}${'☆' * (5 - rating)}',
    'From my BookDNA shelf: $link',
  ].join('\n');

  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      Widget item(IconData icon, String title, String sub,
          Future<void> Function() action, String? toast) {
        return ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Icon(icon, size: 20, color: scheme.onSecondaryContainer),
          ),
          title: Text(title),
          subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () async {
            Navigator.pop(sheetContext);
            await action();
            if (toast != null && context.mounted) {
              showToast(context, toast);
            }
          },
        );
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Share “${book.title}”',
                  style: theme.textTheme.titleMedium),
            ),
            item(
                Icons.link_rounded,
                'Copy link',
                'bookdna.app/b/$slug',
                () => Clipboard.setData(ClipboardData(text: link)),
                'Link copied'),
            item(
                Icons.ios_share_rounded,
                'Share…',
                'Title, your rating and a link — via any app',
                () => SharePlus.instance
                    .share(ShareParams(text: shareText)),
                null),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

// ───────────────────────── More sheet ─────────────────────────

void showMoreSheet(BuildContext context, WidgetRef ref, Book book) {
  final db = ref.read(databaseProvider);
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true, // keyboard-aware for the lend name field
    builder: (sheetContext) {
      var lending = false;
      var borrower = '';
      return StatefulBuilder(builder: (context, setState) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                SegmentedButton<BookStatus>(
                  segments: [
                    for (final s in BookStatus.values)
                      ButtonSegment(value: s, label: Text(s.label)),
                  ],
                  selected: {book.status},
                  onSelectionChanged: (sel) async {
                    final s = sel.first;
                    await db.updateBook(
                      book.id,
                      BooksCompanion(
                        status: Value(s),
                        progress: Value(s == BookStatus.read
                            ? 1.0
                            : s == BookStatus.unread
                                ? 0.0
                                : book.progress),
                        currentPage: Value(s == BookStatus.read
                            ? book.pages
                            : s == BookStatus.unread
                                ? 0
                                : book.currentPage),
                        // Keep the start/finish dates consistent with the
                        // status: unread resets both, reading/read record a
                        // start if one was never set.
                        startedAt: Value(s == BookStatus.unread
                            ? null
                            : (book.startedAt ?? DateTime.now())),
                        finishedAt: Value(
                            s == BookStatus.read ? DateTime.now() : null),
                      ),
                    );
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    if (context.mounted) {
                      showToast(context, 'Marked as ${s.label}');
                    }
                  },
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Your rating', style: theme.textTheme.bodyLarge),
                    Stars(
                      rating: book.rating ?? 0,
                      size: 28,
                      onRate: (r) async {
                        await db.updateBook(
                            book.id, BooksCompanion(rating: Value(r)));
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        if (context.mounted) {
                          showToast(context,
                              'Rated $r star${r == 1 ? '' : 's'}');
                        }
                      },
                    ),
                  ],
                ),
                const Divider(height: 28),
                if (!lending) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.payments_outlined),
                    title: const Text('Edit price'),
                    subtitle: Text(book.price != null && book.price! > 0
                        ? formatInr(book.price!)
                        : 'Not set'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      showPriceSheet(context, ref, book);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.swap_horiz_rounded),
                    title: const Text('Lend this book'),
                    onTap: () => setState(() => lending = true),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline_rounded,
                        color: scheme.error),
                    title: Text('Remove from library',
                        style: TextStyle(color: scheme.error)),
                    onTap: () async {
                      await db.softDeleteBook(book.id);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      if (context.mounted) {
                        showToast(context, 'Removed from library');
                        context.pop();
                      }
                    },
                  ),
                ] else ...[
                  Text('Lend to',
                      style: theme.textTheme.labelLarge!
                          .copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: "Borrower's name",
                        hintText: 'Who has it?'),
                    onChanged: (v) => setState(() => borrower = v),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: borrower.trim().isEmpty
                        ? null
                        : () async {
                            final name = borrower.trim();
                            await db.addLend(
                                bookTitle: book.title,
                                bookId: book.id,
                                toName: name);
                            await db.logActivity('swap_horiz',
                                'Lent ${book.title} to $name');
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                            if (context.mounted) {
                              showToast(context,
                                  'Lent to ${name.split(' ').first} — due back in 3 weeks');
                            }
                          },
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 50)),
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Lend for 3 weeks'),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        );
      });
    },
  );
}

// ───────────────────────── Price sheet ─────────────────────────

/// Correct the price/worth recorded for a book — the amount actually paid
/// often differs from the catalogue list price.
void showPriceSheet(BuildContext context, WidgetRef ref, Book book) {
  final db = ref.read(databaseProvider);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      var text = (book.price != null && book.price! > 0)
          ? book.price!.toStringAsFixed(0)
          : '';
      final theme = Theme.of(sheetContext);
      return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Price you paid', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('Corrects the catalogue list price for this book.',
                style: theme.textTheme.bodySmall!
                    .copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: text,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Price (₹)',
                prefixText: '₹ ',
              ),
              onChanged: (v) => text = v,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                final price =
                    double.tryParse(text.trim().replaceAll(',', ''));
                final value = (price != null && price > 0) ? price : null;
                await db.updateBook(
                  book.id,
                  BooksCompanion(
                    price: Value(value),
                    // Keep the book's recorded worth in step with the price,
                    // including when it's cleared.
                    estValue: Value(value),
                  ),
                );
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                if (context.mounted) showToast(context, 'Price updated');
              },
              style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Save price'),
            ),
          ],
        ),
      );
    },
  );
}
