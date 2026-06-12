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
import 'metadata_repository.dart';

/// Review looked-up metadata, optionally edit, then add to library.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key, required this.metadata});

  final BookMetadata metadata;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  late final BookMetadata _meta = widget.metadata;
  bool _added = false;

  Future<void> _add() async {
    if (_added) return;
    setState(() => _added = true);
    final db = ref.read(databaseProvider);
    await db.upsertBook(BooksCompanion.insert(
      id: newId(),
      title: _meta.title,
      author: Value(_meta.author),
      genre: Value(_meta.genre),
      pages: Value(_meta.pages),
      year: Value(_meta.year),
      price: Value(_meta.listPriceInr),
      estValue: Value(_meta.estimatedValueInr),
      status: BookStatus.unread,
      hueShift: Value(hueShiftForImport(_meta.genre)),
      isbn: Value(_meta.isbn),
      publisher: Value(_meta.publisher),
      language: Value(_meta.language),
      description: Value(_meta.description),
      coverUrl: Value(_meta.coverUrl),
      addedAt: DateTime.now(),
      updatedAt: nowMs(),
    ));
    await db.logActivity(
        'barcode_scanner', 'Scanned ${_meta.title} into your library');
    if (!mounted) return;
    showToast(context, 'Added to your library');
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    context.pop();
    context.go('/library');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Book found'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                Center(
                  child: Column(children: [
                    BookCover(
                        title: _meta.title,
                        author: _meta.author,
                        hueShift: hueShiftForImport(_meta.genre),
                        width: 150),
                    const SizedBox(height: 16),
                    Text(_meta.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(_meta.author,
                        style: theme.textTheme.bodyMedium!
                            .copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.qr_code_rounded,
                          size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text('ISBN ${_meta.isbn}',
                          style: theme.textTheme.labelMedium!
                              .copyWith(color: scheme.onSurfaceVariant)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 3.4,
                      children: [
                        _field(context, 'Publisher', _meta.publisher ?? '—'),
                        _field(context, 'Year', '${_meta.year ?? '—'}'),
                        _field(context, 'Pages',
                            _meta.pages > 0 ? '${_meta.pages}' : '—'),
                        _field(context, 'Genre', _meta.genre),
                        _field(context, 'Language', _meta.language),
                        _field(context, 'Est. value',
                            formatInr(_meta.estimatedValueInr)),
                      ],
                    ),
                  ),
                ),
                if (_meta.description != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    color: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ABOUT',
                              style: theme.textTheme.labelMedium!.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  letterSpacing: 1)),
                          const SizedBox(height: 8),
                          Text(_meta.description!,
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ),
                ],
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
              child: Row(children: [
                FilledButton.tonalIcon(
                  onPressed: _openEdit,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Edit'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _add,
                    style:
                        FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    icon: Icon(_added
                        ? Icons.check_rounded
                        : Icons.library_add_rounded),
                    label:
                        Text(_added ? 'Added' : 'Add to library'),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label.toUpperCase(),
            style: theme.textTheme.labelSmall!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.8)),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium),
      ],
    );
  }

  void _openEdit() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        var title = _meta.title;
        var author = _meta.author;
        var pages = _meta.pages.clamp(1, 2000);
        var genre = _meta.genre;
        return StatefulBuilder(builder: (context, setSheet) {
          final theme = Theme.of(context);
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Edit details', style: theme.textTheme.titleMedium),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: title,
                  decoration: const InputDecoration(labelText: 'Title'),
                  onChanged: (v) => title = v,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: author,
                  decoration: const InputDecoration(labelText: 'Author'),
                  onChanged: (v) => author = v,
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Pages', style: theme.textTheme.bodyLarge),
                    StepperRow(
                        value: pages,
                        min: 1,
                        max: 2000,
                        step: 10,
                        onChanged: (v) => setSheet(() => pages = v)),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in kGenres.take(7))
                      FilterChip(
                        label: Text(g),
                        selected: genre == g,
                        onSelected: (_) => setSheet(() => genre = g),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _meta
                        ..title = title
                        ..author = author
                        ..pages = pages
                        ..genre = genre;
                    });
                    Navigator.pop(sheetContext);
                    showToast(context, 'Details updated');
                  },
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save'),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}
