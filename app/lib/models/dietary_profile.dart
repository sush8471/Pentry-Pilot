import 'package:pantry_pilot/services/allergen_db_service.dart';

/// Supported allergen codes — mirrors allergen_seed.json groups
const kSupportedAllergenCodes = [
  'MILK', 'EGG', 'PEANUT', 'TREENUT', 'WHEAT', 'GLUTEN', 'SOY', 'FISH', 'SHELLFISH', 'SESAME'
];

/// A single user dietary profile stored locally.
class DietaryProfile {
  final String id;
  final String name;
  final List<String> activeAllergenCodes;
  final bool strictMode; // true = treat AMBIGUOUS as DANGER
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DietaryProfile({
    required this.id,
    required this.name,
    required this.activeAllergenCodes,
    this.strictMode = false,
    this.isActive = false,
    required this.createdAt,
    required this.updatedAt,
  });

  DietaryProfile copyWith({
    String? name,
    List<String>? activeAllergenCodes,
    bool? strictMode,
    bool? isActive,
  }) {
    return DietaryProfile(
      id: id,
      name: name ?? this.name,
      activeAllergenCodes: activeAllergenCodes ?? this.activeAllergenCodes,
      strictMode: strictMode ?? this.strictMode,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'activeAllergenCodes': activeAllergenCodes,
    'strictMode': strictMode,
    'isActive': isActive,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory DietaryProfile.fromJson(Map<String, dynamic> json) => DietaryProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    activeAllergenCodes: (json['activeAllergenCodes'] as List<dynamic>).cast<String>(),
    strictMode: json['strictMode'] as bool? ?? false,
    isActive: json['isActive'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

/// In-memory profile store. On device this is backed by sqflite (profiles table).
/// Used directly in tests for fast, isolated verification.
class ProfileService {
  final Map<String, DietaryProfile> _profiles = {};
  String? _activeId;

  ProfileService();

  List<DietaryProfile> get allProfiles => _profiles.values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  DietaryProfile? get activeProfile =>
      _activeId != null ? _profiles[_activeId] : null;

  /// Create and persist a new profile. The first profile created is auto-activated.
  DietaryProfile create({
    required String name,
    required List<String> activeAllergenCodes,
    bool strictMode = false,
  }) {
    final profile = DietaryProfile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      activeAllergenCodes: List<String>.from(activeAllergenCodes),
      strictMode: strictMode,
      isActive: _profiles.isEmpty, // Auto-activate first profile
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _profiles[profile.id] = profile;
    if (profile.isActive) _activeId = profile.id;
    return profile;
  }

  /// Update a profile by ID.
  DietaryProfile update(String id, {
    String? name,
    List<String>? activeAllergenCodes,
    bool? strictMode,
  }) {
    final existing = _profiles[id];
    if (existing == null) throw ArgumentError('Profile $id not found');
    final updated = existing.copyWith(
      name: name,
      activeAllergenCodes: activeAllergenCodes,
      strictMode: strictMode,
    );
    _profiles[id] = updated;
    return updated;
  }

  /// Set a profile as the active scanning profile. Only one can be active at a time.
  void setActive(String id) {
    if (!_profiles.containsKey(id)) throw ArgumentError('Profile $id not found');
    // Deactivate current active
    if (_activeId != null && _profiles.containsKey(_activeId!)) {
      _profiles[_activeId!] = _profiles[_activeId!]!.copyWith(isActive: false);
    }
    _profiles[id] = _profiles[id]!.copyWith(isActive: true);
    _activeId = id;
  }

  /// Delete a profile by ID. If it was active, active is cleared.
  void delete(String id) {
    _profiles.remove(id);
    if (_activeId == id) {
      _activeId = _profiles.isNotEmpty ? _profiles.keys.first : null;
      if (_activeId != null) {
        _profiles[_activeId!] = _profiles[_activeId!]!.copyWith(isActive: true);
      }
    }
  }
}

/// Builds the Needle system prompt from an active [DietaryProfile].
String buildNeedleSystemPrompt(DietaryProfile profile, AllergenDbService db) {
  final names = profile.activeAllergenCodes
      .map((code) => db.groupDisplayName(code))
      .join(', ');

  final strictNote = profile.strictMode
      ? 'STRICT MODE: Treat every AMBIGUOUS ingredient as DANGER.'
      : 'STANDARD MODE: Flag unclear or unverifiable sources as AMBIGUOUS.';

  return 'You are an offline food allergen evaluator. '
      'User must strictly avoid: $names. '
      '$strictNote '
      'For every ingredient token call evaluate_ingredients. '
      'DANGER=confirmed allergen or known derivative. '
      'AMBIGUOUS=possible alias, hidden source, or unclear processing. '
      'SAFE=no allergen risk. '
      'When uncertain always prefer AMBIGUOUS over SAFE. '
      'Output only the tool call JSON.';
}

