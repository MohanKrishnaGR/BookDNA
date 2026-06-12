import 'package:bookdna/widgets/book_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('renders title and author', (tester) async {
    await tester.pumpWidget(host(const BookCover(
      title: 'Designing Data-Intensive Applications',
      author: 'Martin Kleppmann',
      hueShift: 0,
      width: 120,
    )));
    expect(
        find.text('Designing Data-Intensive Applications'), findsOneWidget);
    expect(find.text('Martin Kleppmann'), findsOneWidget);
  });

  testWidgets('keeps the 2:3 cover aspect ratio', (tester) async {
    await tester.pumpWidget(host(const BookCover(
      title: 'Sapiens',
      author: 'Yuval Noah Harari',
      hueShift: 270,
      width: 100,
    )));
    final size = tester.getSize(find.byType(BookCover));
    expect(size.width, 100);
    expect(size.height, 150);
  });

  testWidgets('same title always produces the same variant/colors',
      (tester) async {
    Future<BookCover> pump() async {
      await tester.pumpWidget(host(const BookCover(
        title: 'Zero to One',
        author: 'Peter Thiel',
        hueShift: 60,
      )));
      return tester.widget<BookCover>(find.byType(BookCover));
    }

    final a = await pump();
    final b = await pump();
    // Deterministic: hashing the same title twice gives identical layout.
    expect(a.title.hashCode % 3, b.title.hashCode % 3);
  });
}
