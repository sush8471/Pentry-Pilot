/// Utility class for normalizing raw OCR token text before allergen lookup.
/// All normalization is pure string operations — no I/O, no async.
class TextNormalizer {
  /// PAL (Precautionary Allergen Labeling) phrases that signal cross-contamination warnings.
  static const List<String> _palPhrases = [
    'may contain',
    'may contain traces',
    'processed in a facility',
    'made on shared equipment',
    'made in a facility',
    'produced in a facility',
    'shared equipment with',
    'manufactured in a facility',
  ];

  /// Normalize a raw OCR token string into a clean, lookup-ready form.
  ///
  /// Pipeline steps:
  /// 1. Lowercase
  /// 2. Unicode normalization (remove diacritics, collapse whitespace)
  /// 3. Remove trailing punctuation (commas, colons, periods, parens content)
  /// 4. Rejoin hyphen-broken fragments ("so-di-um" → "sodium")
  /// 5. Strip quantity annotations ("water (50%)" → "water")
  static String normalize(String raw) {
    String s = raw.trim().toLowerCase();

    // Remove parenthesised quantity/unit annotations: "water (50%)" → "water", "salt (2.5g)" → "salt"
    s = s.replaceAll(RegExp(r'\s*\([^)]*(\d[\d\.,]*\s*(mg|g|ml|l|%|kcal|cal|kj)|%)[^)]*\)', caseSensitive: false), '').trim();

    // Strip remaining trailing punctuation that OCR tends to capture
    s = s.replaceAll(RegExp(r'[,\.:\(\)\[\]]+$'), '').trim();

    // Rejoin hyphen-broken OCR line-break fragments by iterating segments.
    // "so-di-um" → all segments ≤3 chars → fuse → "sodium"
    // "non-dairy" → "non" is 3 chars boundary but "dairy" is long → keep hyphen
    final parts = s.split('-');
    if (parts.length > 1) {
      final buf = StringBuffer();
      for (int i = 0; i < parts.length; i++) {
        final seg = parts[i];
        if (i < parts.length - 1 && seg.length <= 3) {
          buf.write(seg); // Fuse: drop hyphen
        } else {
          buf.write(seg);
          if (i < parts.length - 1) buf.write('-'); // Preserve meaningful hyphen
        }
      }
      s = buf.toString();
    }

    // Collapse multiple spaces
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    return s;
  }

  /// Normalize a list of raw tokens into deduped, ordered lookup candidates.
  static List<String> normalizeAll(List<String> rawTokens) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in rawTokens) {
      final normalized = normalize(raw);
      if (normalized.isNotEmpty && seen.add(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }

  /// Scan the full raw OCR text block for PAL (precautionary allergen labeling) phrases.
  /// Returns a list of all PAL phrases found — these trigger AMBIGUOUS for all active allergens.
  static List<String> detectPalPhrases(String rawText) {
    final lower = rawText.toLowerCase();
    return _palPhrases.where((phrase) => lower.contains(phrase)).toList();
  }

  /// True if the token looks like a measurement, quantity, or non-ingredient word to skip.
  static bool isNonIngredient(String token) {
    if (token.isEmpty) return true;
    // Pure numeric or numeric+unit ("500mg", "2%", "0.5g")
    if (RegExp(r'^\d+[\d\.\,]*\s*(mg|g|ml|%|kcal|cal|kj)?$').hasMatch(token)) return true;
    // Ingredient list header words
    if (const {'ingredients', 'contains', 'allergens', 'manufactured', 'by', 'serving', 'size'}.contains(token)) return true;
    return false;
  }
}
