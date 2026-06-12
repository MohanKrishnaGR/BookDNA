import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/book_accent.dart';
import '../../core/db/database.dart';
import '../../core/models/book_status.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/common.dart';
import '../../widgets/status_badge.dart';

enum LibraryView { grid, shelf, list, timeline }

enum LibrarySort { title, author, newest, value }

final libraryViewProvider = StateProvider((_) => LibraryView.grid);
final librarySortProvider = StateProvider((_) => LibrarySort.title);
final libraryQueryProvider = StateProvider((_) => '');
final libraryGenreProvider = StateProvider<String?>((_) => null);
final libraryStatusProvider = StateProvider<BookStatus?>((_) => null);

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  List<Book> _filtered(WidgetRef ref, List<Book> books) {
    final q = ref.watch(libraryQueryProvider).toLowerCase();
    final genre = ref.watch(libraryGenreProvider);
    final status = ref.watch(libraryStatusProvider);
    final sort = ref.watch(librarySortProvider);

    var list = books.where((b) {
      if (q.isNotEmpty &&
          !('${b.title} ${b.author}'.toLowerCase().contains(q))) {
        return false;
      }
      if (genre != null && b.genre != genre) return false;
      if (status != null && b.status != status) return false;
      return true;
    }).toList();

    list.sort(switch (sort) {
      LibrarySort.title => (a, b) => a.title.compareTo(b.title),
      LibrarySort.author => (a, b) => a.author.compareTo(b.author),
      LibrarySort.newest => (a, b) => b.addedAt.compareTo(a.addedAt),
      LibrarySort.value => (a, b) => (b.estValue ?? b.price ?? 0)
          .compareTo(a.estValue ?? a.price ?? 0),
    });
    return list;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider);
    final books = booksAsync.value ?? [];
    final filtered = _filtered(ref, books);
    final view = ref.watch(libraryViewProvider);
    final sort = ref.watch(librarySortProvider);
    final genre = ref.watch(libraryGenreProvider);
    final status = ref.watch(libraryStatusProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search + view switcher.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: TextField(
                      onChanged: (v) =>
                          ref.read(libraryQueryProvider.notifier).state = v,
                      decoration: InputDecoration(
                        hintText: 'Search ${books.length} books…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(99),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _ViewSwitcher(view: view),
              ]),
            ),
            // Filter chips.
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _chip(
                    context,
                    label: 'Sort: ${sort.name[0].toUpperCase()}${sort.name.substring(1)}',
                    icon: Icons.swap_vert_rounded,
                    selected: true,
                    onTap: () {
                      final next = LibrarySort.values[
                          (sort.index + 1) % LibrarySort.values.length];
                      ref.read(librarySortProvider.notifier).state = next;
                    },
                  ),
                  const VerticalDivider(indent: 12, endIndent: 12),
                  _chip(context,
                      label: 'All',
                      selected: genre == null,
                      onTap: () => ref
                          .read(libraryGenreProvider.notifier)
                          .state = null),
                  for (final g in kGenres.take(7))
                    _chip(context,
                        label: g,
                        selected: genre == g,
                        onTap: () => ref
                            .read(libraryGenreProvider.notifier)
                            .state = genre == g ? null : g),
                  const VerticalDivider(indent: 12, endIndent: 12),
                  for (final s in BookStatus.values)
                    _chip(context,
                        label: s.label,
                        selected: status == s,
                        onTap: () => ref
                            .read(libraryStatusProvider.notifier)
                            .state = status == s ? null : s),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const EmptyState(
                      icon: Icons.menu_book_rounded,
                      message: 'No books match — try clearing filters.')
                  : switch (view) {
                      LibraryView.grid => _GridView(books: filtered),
                      LibraryView.shelf => _ShelfView(books: filtered),
                      LibraryView.list => _ListView(books: filtered),
                      LibraryView.timeline => _TimelineView(books: filtered),
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context,
      {required String label,
      IconData? icon,
      required bool selected,
      VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
      child: FilterChip(
        label: Text(label),
        avatar: icon != null ? Icon(icon, size: 16) : null,
        selected: selected,
        showCheckmark: icon == null,
        onSelected: (_) => onTap?.call(),
      ),
    );
  }
}

class _ViewSwitcher extends ConsumerWidget {
  const _ViewSwitcher({required this.view});
  final LibraryView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    const icons = {
      LibraryView.grid: Icons.grid_view_rounded,
      LibraryView.shelf: Icons.shelves,
      LibraryView.list: Icons.view_list_rounded,
      LibraryView.timeline: Icons.timeline_rounded,
    };
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        children: [
          for (final v in LibraryView.values)
            InkWell(
              onTap: () => ref.read(libraryViewProvider.notifier).state = v,
              borderRadius: BorderRadius.circular(99),
              child: Container(
                width: 38,
                decoration: BoxDecoration(
                  color: v == view ? scheme.secondaryContainer : null,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Icon(icons[v],
                    size: 18,
                    color: v == view
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _GridView extends StatelessWidget {
  const _GridView({required this.books});
  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.52,
      ),
      itemCount: books.length,
      itemBuilder: (context, i) {
        final b = books[i];
        return InkWell(
          onTap: () => context.push('/book/${b.id}'),
          borderRadius: BorderRadius.circular(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => BookCover(
                    title: b.title,
                    author: b.author,
                    hueShift: b.hueShift,
                    width: c.maxWidth,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(b.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium!
                      .copyWith(fontWeight: FontWeight.w500)),
              if (b.status == BookStatus.reading) ...[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                      value: b.progress, minHeight: 4),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Spine-based bookshelf view — rows of vertical spines on shelf boards.
class _ShelfView extends StatelessWidget {
  const _ShelfView({required this.books});
  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <List<Book>>[];
    for (var i = 0; i < books.length; i += 7) {
      rows.add(books.sublist(i, (i + 7).clamp(0, books.length)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: rows.length,
      itemBuilder: (context, r) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final b in rows[r]) _Spine(book: b),
              ],
            ),
            Container(
              height: 10,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(3),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 4,
                      offset: Offset(0, 3)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Spine extends StatelessWidget {
  const _Spine({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    final hash = book.id.hashCode.abs();
    final height = 108.0 + (hash * 13) % 34;
    final width = 26.0 + (book.pages > 500 ? 10 : book.pages > 350 ? 5 : 0);
    final accent = accentFor(book.hueShift, Brightness.light);
    final invert = hash % 4 == 0;
    final bg = invert ? accent.onContainer : accent.container;
    final fg = invert ? accent.container : accent.onContainer;

    return InkWell(
      onTap: () => context.push('/book/${book.id}'),
      child: Container(
        width: width,
        height: height,
        margin: const EdgeInsets.only(right: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(3),
            topRight: Radius.circular(3),
            bottomLeft: Radius.circular(1),
            bottomRight: Radius.circular(1),
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 2,
                offset: Offset(1, 0)),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: RotatedBox(
          quarterTurns: 1,
          child: Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _ListView extends StatelessWidget {
  const _ListView({required this.books});
  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
      itemCount: books.length,
      itemBuilder: (context, i) {
        final b = books[i];
        return ListTile(
          onTap: () => context.push('/book/${b.id}'),
          leading: BookCover(
              title: b.title,
              author: b.author,
              hueShift: b.hueShift,
              width: 40,
              radius: 4,
              shadow: false),
          title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${b.author} · ${b.pages} pages'),
          trailing: StatusBadge(status: b.status),
        );
      },
    );
  }
}

/// Acquisition timeline — books grouped by the year they joined the shelf.
class _TimelineView extends StatelessWidget {
  const _TimelineView({required this.books});
  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byYear = <int, List<Book>>{};
    for (final b in books) {
      byYear.putIfAbsent(b.addedAt.year, () => []).add(b);
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: years.length,
      itemBuilder: (context, i) {
        final year = years[i];
        final list = byYear[year]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('$year', style: theme.textTheme.titleMedium),
              const SizedBox(width: 12),
              const Expanded(child: Divider()),
              const SizedBox(width: 12),
              Text('${list.length} book${list.length == 1 ? '' : 's'}',
                  style: theme.textTheme.labelMedium!
                      .copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              height: 74 * 1.5,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final b in list)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: InkWell(
                        onTap: () => context.push('/book/${b.id}'),
                        child: BookCover(
                            title: b.title,
                            author: b.author,
                            hueShift: b.hueShift,
                            width: 74),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
        );
      },
    );
  }
}

/// Read-formatted value used by the sort chip & worth lists.
String bookValue(Book b) => formatInr(b.estValue ?? b.price ?? 0);
