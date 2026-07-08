import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Brand seed — matches the design prototype (#0b57d0).
const int kSeedColorValue = 0xFF0B57D0;
const Color kSeedColor = Color(kSeedColorValue);

/// Per-book accent palette derived from the brand seed plus a hue shift,
/// mirroring the prototype's `M3.accent(seed, hueShift, isDark)`.
///
/// Tone roles (prototype parity):
///   main         P(40) light / P(80) dark
///   container    P(90) light / P(30) dark
///   onContainer  P(30) light / P(90) dark
///   dim          P(70) light / P(60) dark
class BookAccent {
  const BookAccent({
    required this.main,
    required this.container,
    required this.onContainer,
    required this.dim,
  });

  final Color main;
  final Color container;
  final Color onContainer;
  final Color dim;
}

/// Hue shift per BookDNA genre, from the prototype data set.
const Map<String, int> kGenreHueShift = {
  'Technology': 0,
  'AI & Science': 150,
  'Business': 60,
  'Psychology': 210,
  'Biography': 30,
  'Self Help': 320,
  'History': 270,
  'Fiction': 180,
  'Other': 100,
};

/// The canonical genre list used for filters, import mapping and accents.
const List<String> kGenres = [
  'Technology',
  'AI & Science',
  'Business',
  'Psychology',
  'Biography',
  'Self Help',
  'History',
  'Fiction',
  'Other',
];

int hueShiftForGenre(String genre) =>
    // Every kGenres value is mapped above; an unknown genre falls back to the
    // curated 'Other' hue so the accent is always deterministic (a previous
    // String.hashCode fallback shifted between Dart versions/platforms).
    kGenreHueShift[genre] ?? kGenreHueShift['Other']!;

final double _seedHue = Hct.fromInt(kSeedColorValue).hue;
final Map<int, TonalPalette> _paletteCache = {};

TonalPalette _paletteFor(int hueShift) => _paletteCache.putIfAbsent(
      hueShift % 360,
      // Chroma 48 in HCT ≈ the prototype's OKLab chroma 0.10–0.11.
      () => TonalPalette.of((_seedHue + hueShift) % 360, 48),
    );

BookAccent accentFor(int hueShift, Brightness brightness) {
  final p = _paletteFor(hueShift);
  final dark = brightness == Brightness.dark;
  return BookAccent(
    main: Color(p.get(dark ? 80 : 40)),
    container: Color(p.get(dark ? 30 : 90)),
    onContainer: Color(p.get(dark ? 90 : 30)),
    dim: Color(p.get(dark ? 60 : 70)),
  );
}
