import 'package:bookdna/core/db/database.dart';
import 'package:bookdna/core/providers.dart';
import 'package:bookdna/features/import/import_screen.dart';
import 'package:bookdna/features/import/metadata_repository.dart';
import 'package:bookdna/widgets/common.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Regression tests for the add-a-book flow.
///
/// Bug (reproduced before the fix): using the edit sheet — always for MANUAL
/// entry (no catalogue match), and when editing a found book — then tapping
/// "Add to library" landed the tap on the sheet's dismiss-animation barrier, so
/// _add() never ran and no book was saved ("it keeps asking for the details").
///
/// Fix: manual entry adds the book directly from the edit sheet (no second tap),
/// and _add() is hardened (try/catch, saving/added state, single go()).
void main() {
  GoRouter buildRouter() => GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
              path: '/home',
              builder: (_, _) =>
                  const Scaffold(body: Center(child: Text('HOME')))),
          GoRoute(
              path: '/import',
              builder: (_, s) =>
                  ImportScreen(metadata: s.extra as BookMetadata)),
          GoRoute(
              path: '/library',
              builder: (_, _) =>
                  const Scaffold(body: Center(child: Text('LIBRARY')))),
        ],
      );

  Widget appWith(GoRouter router, AppDatabase db) => ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: router),
      );

  // Bounded pumping — a real pumpAndSettle can hang on the bottom sheet's
  // animation. `frames` of 100ms also fires _add's 700ms delay and the 2600ms
  // SnackBar timer so nothing is left pending at teardown.
  Future<void> pumpFrames(WidgetTester tester, int frames) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // The Drift stream only emits a populated list under real async.
  Future<List<Book>> readBooks(WidgetTester tester, AppDatabase db) async {
    final books = await tester.runAsync(() => db.watchBooks().first);
    return books ?? const [];
  }

  testWidgets('manual entry: filling the edit sheet adds the book',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final router = buildRouter();

    await tester.pumpWidget(appWith(router, db));
    await pumpFrames(tester, 6);

    // Empty title => manual-entry mode; initState auto-opens the edit sheet.
    router.push('/import', extra: BookMetadata(isbn: '9790000000000', title: ''));
    await pumpFrames(tester, 10);

    expect(find.byType(TextFormField), findsWidgets,
        reason: 'edit sheet should be open');
    await tester.enterText(find.byType(TextFormField).first, 'My Manual Book');
    await tester.pump();

    // For manual entry the sheet's primary button is "Add to library" (saves +
    // adds). The main action bar behind the sheet shares that label, so tap the
    // last match — the sheet is on top of the tree.
    expect(find.text('Add to library'), findsWidgets);
    await tester.tap(find.text('Add to library').last);
    await pumpFrames(tester, 45); // upsert + 700ms delay + nav + SnackBar timer

    final books = await readBooks(tester, db);
    expect(books, hasLength(1), reason: 'the manual book must be saved');
    expect(books.single.title, 'My Manual Book');
    expect(books.single.isbn, '9790000000000');
    expect(find.text('LIBRARY'), findsOneWidget,
        reason: 'should land on the library after adding');
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('found book (no edit): Add to library saves and navigates',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final router = buildRouter();

    await tester.pumpWidget(appWith(router, db));
    await pumpFrames(tester, 6);

    router.push('/import',
        extra: BookMetadata(isbn: '9780000000001', title: 'Found Book'));
    await pumpFrames(tester, 6);

    await tester.tap(find.text('Add to library'));
    await pumpFrames(tester, 45);

    final books = await readBooks(tester, db);
    expect(books, hasLength(1));
    expect(books.single.title, 'Found Book');
    expect(find.text('LIBRARY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('found book + edit: editing then adding saves the edited title',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final router = buildRouter();

    await tester.pumpWidget(appWith(router, db));
    await pumpFrames(tester, 6);

    router.push('/import',
        extra: BookMetadata(isbn: '9780000000002', title: 'Found Book'));
    await pumpFrames(tester, 6);

    // Open the editor, change the title, Save (found-book sheet button).
    await tester.tap(find.text('Edit'));
    await pumpFrames(tester, 10);
    await tester.enterText(find.byType(TextFormField).first, 'Edited Title');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await pumpFrames(tester, 20); // let the sheet fully dismiss before adding

    await tester.tap(find.text('Add to library'));
    await pumpFrames(tester, 45);

    final books = await readBooks(tester, db);
    expect(books, hasLength(1));
    expect(books.single.title, 'Edited Title',
        reason: 'the edited title must persist into the saved book');
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets(
      'manual entry: dismissing the sheet keeps the draft, bottom Add saves',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final router = buildRouter();

    await tester.pumpWidget(appWith(router, db));
    await pumpFrames(tester, 6);

    router.push('/import',
        extra: BookMetadata(isbn: '9790000000001', title: ''));
    await pumpFrames(tester, 10);

    // Type a title, then dismiss the auto-opened sheet WITHOUT tapping its
    // button (tap the scrim above the sheet) — the previous bug lost the draft
    // and left the screen's Add button disabled forever.
    await tester.enterText(
        find.byType(TextFormField).first, 'Dismissed Draft Book');
    await tester.pump();
    await tester.tapAt(const Offset(10, 10)); // modal barrier / scrim
    await pumpFrames(tester, 10);

    // The screen's own "Add to library" must now be enabled and save the book.
    expect(find.text('Add to library'), findsOneWidget);
    await tester.tap(find.text('Add to library'));
    await pumpFrames(tester, 45);

    final books = await readBooks(tester, db);
    expect(books, hasLength(1),
        reason: 'draft kept after dismissal must still be addable');
    expect(books.single.title, 'Dismissed Draft Book');
    expect(find.text('LIBRARY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('StepperRow: tapping the number edits the value, clamped to max',
      (tester) async {
    var captured = 5;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) => StepperRow(
              value: captured,
              min: 0,
              max: 100,
              step: 10,
              onChanged: (v) => setState(() => captured = v),
            ),
          ),
        ),
      ),
    ));

    // Tap the number → inline field; type above max → clamps to 100.
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '250');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(captured, 100, reason: 'typed value should clamp to max');

    // Non-numeric input reverts to the current value (no change).
    await tester.tap(find.text('100'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(captured, 100, reason: 'invalid input must not change the value');
    expect(tester.takeException(), isNull);
  });
}
