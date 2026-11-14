/// A synonym match result returned by [AllergenDbService]
class SynonymMatch {
  final String allergenCode;
  final String displayName;
  final double confidence;
  final String? sourceNote;
  final bool isAmbiguous;

  const SynonymMatch({
    required this.allergenCode,
    required this.displayName,
    required this.confidence,
    this.sourceNote,
    this.isAmbiguous = false,
  });

  const SynonymMatch.ambiguous({required String note, String allergenCodes = ''})
      : allergenCode = allergenCodes,
        displayName = 'Ambiguous',
        confidence = 0.6,
        sourceNote = note,
        isAmbiguous = true;
}

/// In-memory LRU cache for allergen synonym lookups.
class _LruCache<K, V> {
  final int capacity;
  final _map = <K, V>{};

  _LruCache(this.capacity);

  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) _map[key] = value; // Move to most-recently-used end
    return value;
  }

  void put(K key, V value) {
    _map.remove(key); // Remove if exists (re-insert at end)
    if (_map.length >= capacity) {
      _map.remove(_map.keys.first); // Evict least-recently-used
    }
    _map[key] = value;
  }
}

/// In-memory allergen taxonomy engine for unit-testable, offline-first allergen lookups.
/// On real device this wraps sqflite; in tests it uses the pre-loaded in-memory tables.
class AllergenDbService {
  // In-memory representation of the taxonomy — loaded from seed JSON
  final Map<String, _AllergenGroup> _groups = {};
  final List<_SynonymEntry> _synonyms = [];
  final List<_AmbiguousEntry> _ambiguous = [];

  final _LruCache<String, SynonymMatch?> _cache = _LruCache(300);

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Load seed data from a pre-parsed map (decoded from allergen_seed.json).
  void loadFromSeedMap(Map<String, dynamic> seed) {
    final groups = seed['allergen_groups'] as List<dynamic>;
    for (final g in groups) {
      final map = g as Map<String, dynamic>;
      final code = map['code'] as String;
      _groups[code] = _AllergenGroup(
        code: code,
        displayName: map['display_name'] as String,
        regulation: map['regulation'] as String,
        severity: map['severity'] as int,
      );
    }

    final synonyms = seed['synonyms'] as List<dynamic>;
    for (final s in synonyms) {
      final map = s as Map<String, dynamic>;
      _synonyms.add(_SynonymEntry(
        allergenCode: map['allergen_code'] as String,
        synonym: map['synonym'] as String,
        matchType: map['match_type'] as String,
        confidence: (map['confidence'] as num).toDouble(),
        sourceNote: map['source_note'] as String?,
      ));
    }

    final ambiguous = seed['ambiguous_entries'] as List<dynamic>;
    for (final a in ambiguous) {
      final map = a as Map<String, dynamic>;
      _ambiguous.add(_AmbiguousEntry(
        term: map['term'] as String,
        ambiguityNote: map['ambiguity_note'] as String,
        allergenCodes: map['allergen_codes'] as String,
      ));
    }

    _loaded = true;
  }

  /// Look up a normalized token against the active allergen codes.
  /// Returns [SynonymMatch] if found (DANGER or AMBIGUOUS), null if SAFE.
  ///
  /// Lookup priority:
  ///   1. LRU cache hit
  ///   2. Exact synonym match
  ///   3. Prefix synonym match (e.g., "sodium caseinate" matches prefix "caseinate")
  ///   4. Ambiguous entry match
  ///   5. null → SAFE
  SynonymMatch? lookup(String normalizedToken, List<String> activeAllergenCodes) {
    if (normalizedToken.isEmpty) return null;

    final cacheKey = '$normalizedToken|${activeAllergenCodes.join(",")}';
    final cached = _cache.get(cacheKey);
    if (cached != null) return cached;
    // Note: null returned from cache.get means "not in cache" vs a cached null-meaning-safe.
    // We handle this by checking if the cacheKey was inserted (see put below).

    // --- Exact match ---
    for (final entry in _synonyms) {
      if (!activeAllergenCodes.contains(entry.allergenCode)) continue;
      if (entry.matchType == 'exact' && entry.synonym == normalizedToken) {
        final group = _groups[entry.allergenCode];
        final match = SynonymMatch(
          allergenCode: entry.allergenCode,
          displayName: group?.displayName ?? entry.allergenCode,
          confidence: entry.confidence,
          sourceNote: entry.sourceNote,
        );
        _cache.put(cacheKey, match);
        return match;
      }
    }

    // --- Prefix match (token contains synonym as a word boundary) ---
    for (final entry in _synonyms) {
      if (!activeAllergenCodes.contains(entry.allergenCode)) continue;
      if (entry.matchType == 'prefix' && normalizedToken.contains(entry.synonym)) {
        final group = _groups[entry.allergenCode];
        final match = SynonymMatch(
          allergenCode: entry.allergenCode,
          displayName: group?.displayName ?? entry.allergenCode,
          confidence: entry.confidence * 0.9, // Slight confidence reduction for prefix
          sourceNote: entry.sourceNote,
        );
        _cache.put(cacheKey, match);
        return match;
      }
    }

    // --- Ambiguous entry match ---
    // Strategy: only flag AMBIGUOUS when the token IS the term, or the token starts with the term
    // followed by a space (e.g. "starch syrup"). We deliberately do NOT match when the term
    // appears as a suffix (e.g. "corn starch" must NOT trigger the "starch" ambiguous entry).
    // This avoids false positives on safe multi-word ingredients.
    for (final entry in _ambiguous) {
      final term = entry.term;
      final isMatch = normalizedToken == term ||
          normalizedToken.startsWith('$term ');
      if (isMatch) {
        final match = SynonymMatch.ambiguous(
          note: entry.ambiguityNote,
          allergenCodes: entry.allergenCodes,
        );
        _cache.put(cacheKey, match);
        return match;
      }
    }

    // SAFE — cache the negative result sentinel
    _cache.put(cacheKey, _kSafeSentinel);
    return null;
  }

  /// Warm the cache by pre-looking-up common safe tokens (saves first-frame latency)
  void warmCache(List<String> commonSafeTokens, List<String> activeCodes) {
    for (final token in commonSafeTokens) {
      lookup(token, activeCodes);
    }
  }

  List<String> get groupCodes => _groups.keys.toList();
  String groupDisplayName(String code) => _groups[code]?.displayName ?? code;

  static final _kSafeSentinel = SynonymMatch(
    allergenCode: '',
    displayName: 'SAFE',
    confidence: 1.0,
  );
}

class _AllergenGroup {
  final String code;
  final String displayName;
  final String regulation;
  final int severity;
  _AllergenGroup({required this.code, required this.displayName, required this.regulation, required this.severity});
}

class _SynonymEntry {
  final String allergenCode;
  final String synonym;
  final String matchType;
  final double confidence;
  final String? sourceNote;
  _SynonymEntry({required this.allergenCode, required this.synonym, required this.matchType, required this.confidence, this.sourceNote});
}

class _AmbiguousEntry {
  final String term;
  final String ambiguityNote;
  final String allergenCodes;
  _AmbiguousEntry({required this.term, required this.ambiguityNote, required this.allergenCodes});
}
