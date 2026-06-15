import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../app/theme/book_accent.dart';

/// Normalized book metadata from an ISBN lookup.
class BookMetadata {
  BookMetadata({
    required this.isbn,
    required this.title,
    this.author = '',
    this.publisher,
    this.year,
    this.pages = 0,
    this.language = 'English',
    this.genre = 'Other',
    this.description,
    this.coverUrl,
    this.listPriceInr,
  });

  final String isbn;
  String title;
  String author;
  String? publisher;
  int? year;
  int pages;
  String language;
  String genre;
  String? description;
  String? coverUrl;
  double? listPriceInr;

  /// ₹ value: provider list price when available, else a genre × pages
  /// heuristic, clamped — always shown as "estimated" and user-editable.
  double get estimatedValueInr {
    if (listPriceInr != null && listPriceInr! > 0) return listPriceInr!;
    final perPage = switch (genre) {
      'Technology' || 'AI & Science' => 4.5,
      'Business' || 'Psychology' => 2.2,
      _ => 1.8,
    };
    return (pages * perPage).clamp(199, 6000).toDouble();
  }
}

/// Maps provider category strings onto BookDNA's genre set.
String mapGenre(Iterable<String> categories) {
  final joined = categories.join(' ').toLowerCase();
  if (joined.isEmpty) return 'Other';
  const rules = <String, List<String>>{
    'AI & Science': [
      'artificial intelligence', 'machine learning', 'science', 'physics',
      'mathematics', 'neural', 'data science',
    ],
    'Technology': [
      'computer', 'software', 'programming', 'engineering', 'technology',
      'internet',
    ],
    'Business': [
      'business', 'economics', 'entrepreneur', 'management', 'finance',
      'startup', 'marketing',
    ],
    'Psychology': ['psychology', 'cognitive', 'behavior', 'mind'],
    'Biography': ['biography', 'autobiography', 'memoir'],
    'Self Help': ['self-help', 'self help', 'personal growth', 'productivity', 'habits'],
    'History': ['history', 'historical', 'civilization'],
    'Fiction': ['fiction', 'novel', 'fantasy', 'thriller', 'mystery'],
  };
  for (final entry in rules.entries) {
    if (entry.value.any(joined.contains)) return entry.key;
  }
  return 'Other';
}

class MetadataLookupException implements Exception {
  MetadataLookupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// ISBN lookup: Google Books primary, Open Library fallback.
/// Phase 2 swaps the transport for the `isbn-lookup` Edge Function
/// (caching + server-side keys) behind this same interface.
class MetadataRepository {
  MetadataRepository({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  Future<BookMetadata> lookup(String rawIsbn) async {
    final isbn = rawIsbn.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
    if (isbn.length < 10) {
      throw MetadataLookupException('That doesn\'t look like an ISBN.');
    }
    try {
      final fromGoogle = await _googleBooks(isbn);
      if (fromGoogle != null) return fromGoogle;
    } catch (_) {
      // fall through to Open Library
    }
    final fromOpenLibrary = await _openLibrary(isbn);
    if (fromOpenLibrary != null) return fromOpenLibrary;
    throw MetadataLookupException(
        'No match for ISBN $isbn — add the details manually.');
  }

  Future<BookMetadata?> _googleBooks(String isbn) async {
    final uri = Uri.parse(
        'https://www.googleapis.com/books/v1/volumes?q=isbn:$isbn&country=IN');
    final res = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final items = json['items'] as List?;
    if (items == null || items.isEmpty) return null;

    final item = items.first as Map<String, dynamic>;
    final info = item['volumeInfo'] as Map<String, dynamic>? ?? {};
    final sale = item['saleInfo'] as Map<String, dynamic>? ?? {};

    double? priceInr;
    final list = sale['listPrice'] as Map<String, dynamic>?;
    if (list != null && list['currencyCode'] == 'INR') {
      priceInr = (list['amount'] as num?)?.toDouble();
    }

    final categories =
        (info['categories'] as List?)?.cast<String>() ?? const <String>[];
    final published = info['publishedDate'] as String? ?? '';
    final yearMatch = RegExp(r'\d{4}').firstMatch(published);

    return BookMetadata(
      isbn: isbn,
      title: info['title'] as String? ?? 'Unknown title',
      author: ((info['authors'] as List?)?.cast<String>() ?? []).join(', '),
      publisher: info['publisher'] as String?,
      year: yearMatch != null ? int.parse(yearMatch.group(0)!) : null,
      pages: (info['pageCount'] as num?)?.toInt() ?? 0,
      language: _languageName(info['language'] as String?),
      genre: mapGenre(categories),
      description: info['description'] as String?,
      coverUrl: ((info['imageLinks'] as Map<String, dynamic>?)?['thumbnail']
              as String?)
          ?.replaceFirst('http://', 'https://'),
      listPriceInr: priceInr,
    );
  }

  Future<BookMetadata?> _openLibrary(String isbn) async {
    final uri = Uri.parse('https://openlibrary.org/isbn/$isbn.json');
    final res = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body) as Map<String, dynamic>;

    var author = '';
    final authors = json['authors'] as List?;
    if (authors != null && authors.isNotEmpty) {
      final key = (authors.first as Map<String, dynamic>)['key'] as String?;
      if (key != null) {
        try {
          final ares = await _client
              .get(Uri.parse('https://openlibrary.org$key.json'))
              .timeout(const Duration(seconds: 8));
          if (ares.statusCode == 200) {
            author = (jsonDecode(ares.body)
                    as Map<String, dynamic>)['name'] as String? ??
                '';
          }
        } catch (_) {}
      }
    }

    final published = json['publish_date'] as String? ?? '';
    final yearMatch = RegExp(r'\d{4}').firstMatch(published);
    final subjects =
        (json['subjects'] as List?)?.cast<String>() ?? const <String>[];

    return BookMetadata(
      isbn: isbn,
      title: json['title'] as String? ?? 'Unknown title',
      author: author,
      publisher:
          ((json['publishers'] as List?)?.cast<String>() ?? []).firstOrNull,
      year: yearMatch != null ? int.parse(yearMatch.group(0)!) : null,
      pages: (json['number_of_pages'] as num?)?.toInt() ?? 0,
      genre: mapGenre(subjects),
      coverUrl: 'https://covers.openlibrary.org/b/isbn/$isbn-M.jpg',
    );
  }

  String _languageName(String? code) => switch (code) {
        'en' => 'English',
        'hi' => 'Hindi',
        'ta' => 'Tamil',
        'te' => 'Telugu',
        'kn' => 'Kannada',
        'ml' => 'Malayalam',
        'fr' => 'French',
        'de' => 'German',
        'es' => 'Spanish',
        null => 'English',
        _ => code,
      };
}

/// Hue shift for a newly imported book, from its mapped genre.
int hueShiftForImport(String genre) => hueShiftForGenre(genre);
