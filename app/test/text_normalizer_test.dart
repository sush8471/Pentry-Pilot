import 'package:test/test.dart';
import 'package:pantry_pilot/services/text_normalizer.dart';

void main() {
  group('Phase 3: Text Normalizer', () {
    test('Lowercases and trims whitespace', () {
      expect(TextNormalizer.normalize('  CASEIN  '), equals('casein'));
      expect(TextNormalizer.normalize('Whey Protein'), equals('whey protein'));
    });

    test('Strips trailing punctuation from OCR artefacts', () {
      expect(TextNormalizer.normalize('casein,'), equals('casein'));
      expect(TextNormalizer.normalize('maltodextrin.'), equals('maltodextrin'));
      expect(TextNormalizer.normalize('whey:'), equals('whey'));
    });

    test('Strips quantity annotations', () {
      expect(TextNormalizer.normalize('water (50%)'), equals('water'));
      expect(TextNormalizer.normalize('salt (2.5g)'), equals('salt'));
    });

    test('Fuses short hyphen-broken OCR fragments', () {
      // "so-di" — both sides ≤3 chars → fuse
      expect(TextNormalizer.normalize('so-di-um'), equals('sodium'));
    });

    test('Preserves meaningful compound hyphens', () {
      // "non-dairy" — "non" is 3 chars (boundary) — keep hyphen
      expect(TextNormalizer.normalize('non-dairy'), contains('dairy'));
    });

    test('Deduplicates token list', () {
      final tokens = ['casein', 'water', 'CASEIN', 'salt', 'Water'];
      final result = TextNormalizer.normalizeAll(tokens);
      expect(result.length, equals(3));
      expect(result, containsAll(['casein', 'water', 'salt']));
    });

    test('Filters non-ingredient tokens', () {
      expect(TextNormalizer.isNonIngredient('500mg'), isTrue);
      expect(TextNormalizer.isNonIngredient('2%'), isTrue);
      expect(TextNormalizer.isNonIngredient('ingredients'), isTrue);
      expect(TextNormalizer.isNonIngredient('casein'), isFalse);
    });

    test('Detects PAL cross-contamination phrases', () {
      const text = 'Ingredients: water, salt. May contain traces of peanuts and tree nuts.';
      final pal = TextNormalizer.detectPalPhrases(text);
      expect(pal, isNotEmpty);
      expect(pal.any((p) => p.contains('may contain')), isTrue);
    });

    test('Returns empty list for clean label text with no PAL', () {
      const text = 'Ingredients: water, sugar, salt, citric acid.';
      expect(TextNormalizer.detectPalPhrases(text), isEmpty);
    });
  });
}

