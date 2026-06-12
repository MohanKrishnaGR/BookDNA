/// Structured result of a shelf analysis (mirrors the Edge Function schema).
class ShelfAnalysis {
  const ShelfAnalysis({
    required this.readingProfile,
    required this.archetype,
    required this.traits,
    required this.blindSpots,
    required this.readNext,
    required this.themeEdges,
    required this.isDemo,
    required this.model,
  });

  final String readingProfile;
  final String archetype;
  final List<String> traits;
  final List<({String area, String why})> blindSpots;
  final List<({String bookId, String reason})> readNext;

  /// Pairs of short (8-char) book id prefixes sharing a theme.
  final List<(String, String)> themeEdges;
  final bool isDemo;
  final String model;

  factory ShelfAnalysis.fromJson(Map<String, dynamic> json, {String? model}) {
    final result = (json['result'] ?? json) as Map<String, dynamic>;
    final personality =
        (result['personality'] as Map<String, dynamic>? ?? {});
    return ShelfAnalysis(
      readingProfile: result['reading_profile'] as String? ?? '',
      archetype: personality['archetype'] as String? ?? 'The Reader',
      traits: ((personality['traits'] as List?) ?? [])
          .map((t) => '$t')
          .toList(),
      blindSpots: ((result['blind_spots'] as List?) ?? [])
          .map((b) => (
                area: (b as Map)['area'] as String? ?? '',
                why: b['why'] as String? ?? '',
              ))
          .toList(),
      readNext: ((result['read_next'] as List?) ?? [])
          .map((r) => (
                bookId: (r as Map)['book_id'] as String? ?? '',
                reason: r['reason'] as String? ?? '',
              ))
          .toList(),
      themeEdges: ((result['theme_edges'] as List?) ?? [])
          .where((e) => e is List && e.length >= 2)
          .map((e) => ('${(e as List)[0]}', '${e[1]}'))
          .toList(),
      isDemo: result['demo'] == true,
      model: model ?? json['model'] as String? ?? 'unknown',
    );
  }

  Map<String, dynamic> toJson() => {
        'model': model,
        'result': {
          'reading_profile': readingProfile,
          'personality': {'archetype': archetype, 'traits': traits},
          'blind_spots': [
            for (final b in blindSpots) {'area': b.area, 'why': b.why},
          ],
          'read_next': [
            for (final r in readNext)
              {'book_id': r.bookId, 'reason': r.reason},
          ],
          'theme_edges': [
            for (final e in themeEdges) [e.$1, e.$2],
          ],
          if (isDemo) 'demo': true,
        },
      };
}

class AiException implements Exception {
  AiException(this.message, {this.isQuota = false});

  final String message;
  final bool isQuota;

  @override
  String toString() => message;
}
