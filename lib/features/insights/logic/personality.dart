import '../../../core/db/database.dart';
import '../../../core/models/book_status.dart';
import 'formulas.dart';

/// Deterministic reading-personality archetypes (first matching rule wins).
/// Only finished books count toward genre shares.
class Personality {
  const Personality({
    required this.archetype,
    required this.description,
    required this.traits,
  });

  final String archetype;
  final String description;
  final List<String> traits;
}

Personality computePersonality(
  List<Book> books,
  List<ReadingSession> sessions,
) {
  final read = books.where((b) => b.status == BookStatus.read).toList();
  if (read.isEmpty) {
    return const Personality(
      archetype: 'The Newcomer',
      description:
          'Your reading story is just beginning — finish your first book and BookDNA starts decoding you.',
      traits: ['Fresh shelf', 'Open horizon', 'First chapter'],
    );
  }

  double genreShare(Set<String> genres) {
    final pages = read.fold(0, (s, b) => s + b.pages);
    if (pages == 0) return 0;
    final matched = read
        .where((b) => genres.contains(b.genre))
        .fold(0, (s, b) => s + b.pages);
    return matched / pages;
  }

  final counts = <String, int>{};
  for (final b in read) {
    counts[b.genre] = (counts[b.genre] ?? 0) + 1;
  }
  final topShare = counts.values.isEmpty
      ? 0.0
      : counts.values.reduce((a, b) => a > b ? a : b) / read.length;
  final diversity = computeDiversity(books);
  final pagesList = read.map((b) => b.pages).toList()..sort();
  final medianPages = pagesList[pagesList.length ~/ 2];
  final unreadRatio =
      books.isEmpty ? 0.0 : books.where((b) => b.status == BookStatus.unread).length / books.length;

  final applied =
      genreShare({'Technology', 'Business', 'AI & Science'});
  if (applied >= 0.45) {
    return Personality(
      archetype: 'The Builder',
      description:
          'You read to make things. Systems over stories, depth over breadth — ${(applied * 100).round()}% of your finished pages are applied, and you finish what you start.',
      traits: const ['Deep-diver', 'Serial finisher', 'Future-focused'],
    );
  }
  if (diversity.breadth >= 0.8 && topShare < 0.3) {
    return const Personality(
      archetype: 'The Explorer',
      description:
          'No genre holds you for long. Your shelf wanders wide — every section of the bookstore is home.',
      traits: ['Wide-ranger', 'Curious', 'Genre-hopper'],
    );
  }
  if (topShare >= 0.5) {
    return Personality(
      archetype: 'The Specialist',
      description:
          'You go deep. ${(topShare * 100).round()}% of your finished books live in one genre — mastery is the goal.',
      traits: const ['Focused', 'Expert-track', 'Completist'],
    );
  }
  if (genreShare({'History', 'Psychology'}) >= 0.4) {
    return const Personality(
      archetype: 'The Philosopher',
      description:
          'You read to understand people and time. Minds and histories fill your shelf.',
      traits: ['Reflective', 'Big-picture', 'Human-centered'],
    );
  }
  final monthly = finishedPerMonth(books);
  if (monthly >= 1.5 && medianPages < 300) {
    return const Personality(
      archetype: 'The Sprinter',
      description:
          'Fast and frequent. You devour books in quick succession — momentum is your method.',
      traits: ['High-velocity', 'Snackable reads', 'Always mid-book'],
    );
  }
  if (unreadRatio >= 0.6) {
    return const Personality(
      archetype: 'The Collector',
      description:
          'You buy ahead of your interests. Your unread pile predicts your next obsession.',
      traits: ['Anti-library', 'Future reader', 'Shelf-curator'],
    );
  }
  if (medianPages >= 450) {
    return const Personality(
      archetype: 'The Scholar',
      description:
          'You favor the heavy volumes. Depth, rigor and long-form thinking define your shelf.',
      traits: ['Tome-tamer', 'Patient', 'Thorough'],
    );
  }
  return const Personality(
    archetype: 'The Wanderer',
    description:
        'Your shelf resists a single label — it follows your curiosity wherever it leads.',
    traits: ['Eclectic', 'Open-minded', 'Mood-reader'],
  );
}

/// Books finished per month over the trailing 90 days.
double finishedPerMonth(List<Book> books) {
  final cutoff = DateTime.now().subtract(const Duration(days: 90));
  final n = books
      .where((b) =>
          b.status == BookStatus.read &&
          b.finishedAt != null &&
          b.finishedAt!.isAfter(cutoff))
      .length;
  return n / 3;
}
