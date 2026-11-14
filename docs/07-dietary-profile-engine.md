# 07 — Dietary Profile Engine

## Overview

The Dietary Profile Engine stores and manages a user's dietary restrictions. It bridges the gap between "user says I'm Dairy-Free" and "Needle knows to flag casein, whey, and lactalbumin."

---

## Profile Data Model

```dart
// Stored in Hive (fast key-value, Isolate-safe)
@HiveType(typeId: 0)
class DietaryProfile extends HiveObject {
  @HiveField(0) String id;           // UUID
  @HiveField(1) String name;         // "My Dairy & Nut Free Profile"
  @HiveField(2) List<String> activeAllergenCodes; // ['MILK', 'TREENUT', 'SESAME']
  @HiveField(3) bool strictMode;     // true = AMBIGUOUS treated as DANGER
  @HiveField(4) bool isActive;       // Only one profile active at a time
  @HiveField(5) DateTime createdAt;
  @HiveField(6) DateTime updatedAt;
  @HiveField(7) String? cloudId;     // Firebase document ID (null = not synced)
}
```

**Multiple profiles:** A user can create multiple profiles (e.g., "For Me", "For Child", "Guest"). Only one is active at a time. Switching profiles updates the Needle system prompt in memory immediately — no restart needed.

---

## Supported Allergen Groups (UI toggle chips)

```dart
const List<AllergenGroup> kAllergenGroups = [
  AllergenGroup(code: 'MILK',      label: 'Dairy / Milk',         emoji: '🥛'),
  AllergenGroup(code: 'EGG',       label: 'Egg',                  emoji: '🥚'),
  AllergenGroup(code: 'PEANUT',    label: 'Peanut',               emoji: '🥜'),
  AllergenGroup(code: 'TREENUT',   label: 'Tree Nuts',             emoji: '🌰'),
  AllergenGroup(code: 'WHEAT',     label: 'Wheat',                emoji: '🌾'),
  AllergenGroup(code: 'GLUTEN',    label: 'Gluten-Free (Celiac)', emoji: '⚠️'),
  AllergenGroup(code: 'SOY',       label: 'Soy',                  emoji: '🫘'),
  AllergenGroup(code: 'FISH',      label: 'Fish',                 emoji: '🐟'),
  AllergenGroup(code: 'SHELLFISH', label: 'Shellfish',            emoji: '🦐'),
  AllergenGroup(code: 'SESAME',    label: 'Sesame',               emoji: '🌱'),
];
```

> Note: `GLUTEN` is a superset of `WHEAT` — selecting GLUTEN automatically deselects WHEAT and covers it. The UI enforces this logic.

---

## Profile → Needle Context Mapping

When a profile becomes active, the system builds a Needle system prompt and caches it:

```dart
String buildNeedleSystemPrompt(DietaryProfile profile) {
  final allergenNames = profile.activeAllergenCodes
      .map((code) => kAllergenGroups.firstWhere((g) => g.code == code).label)
      .join(', ');

  final strictNote = profile.strictMode
      ? 'In strict mode: treat all AMBIGUOUS tokens as DANGER.'
      : 'In standard mode: flag unclear terms as AMBIGUOUS.';

  return '''You are a food allergen evaluation engine.
The user must avoid: $allergenNames.
$strictNote
For each ingredient token, call evaluate_ingredients with:
- DANGER if it is a known or likely allergen for the user's restrictions
- AMBIGUOUS if it might be allergenic or the source is unclear
- SAFE if it has no connection to the restricted allergens
Be conservative: when in doubt, choose AMBIGUOUS over SAFE.
Never emit text outside the tool call JSON.''';
}
```

This prompt is built once when the profile changes and cached in `CactusService`. Needle's context window is tiny (by design), so the prompt + ingredient list stays well within token limits.

---

## SQLite Pre-Filter Integration

Before Needle runs, the `AllergenDbService` checks each token against the synonym table:

```dart
Future<SynonymMatch?> lookupToken(String token, List<String> activeCodes) async {
  // 1. Try exact match first (fastest — O(1) with index)
  var row = await _db.query(
    'allergen_synonyms',
    where: 'synonym = ? AND allergen_id IN (SELECT id FROM allergen_groups WHERE code IN (${activeCodes.map((_) => '?').join(',')}))',
    whereArgs: [token, ...activeCodes],
    limit: 1,
  );

  if (row.isNotEmpty) {
    return SynonymMatch(
      allergenCode: row.first['code'] as String,
      confidence: row.first['confidence'] as double,
      matchType: 'exact',
    );
  }

  // 2. Check ambiguous entries
  row = await _db.query(
    'ambiguous_entries',
    where: 'term = ?',
    whereArgs: [token],
    limit: 1,
  );

  if (row.isNotEmpty) {
    return SynonymMatch.ambiguous(note: row.first['ambiguity_note'] as String);
  }

  return null; // Send to Needle
}
```

**In-memory LRU cache:** The top 200 most recently looked-up tokens are cached in memory using an `LinkedHashMap`-based LRU. For typical shopping sessions, the cache hit rate exceeds 90% (most products reuse common ingredients like "water", "salt", "sugar").

---

## Optional Cloud Sync (Firebase)

Cloud sync is **opt-in**, toggled in Settings. When enabled:

```
Local Change (profile create/update)
        │
        ▼
Hive Box.save()  ← Always happens first (local-first)
        │
        ▼
FirestoreSync.pushProfile(profile)
        │
        ├── If online: Firestore.set(docId, profileJson)
        └── If offline: Enqueued in Firestore's local pending writes
                        (auto-syncs when connectivity restored)
```

**Firestore document structure:**

```json
// Collection: users/{anonymousUID}/profiles/{profileId}
{
  "id": "uuid-v4",
  "name": "My Dairy-Free Profile",
  "activeAllergenCodes": ["MILK", "SESAME"],
  "strictMode": false,
  "isActive": true,
  "createdAt": "2026-11-14T10:00:00Z",
  "updatedAt": "2026-11-14T10:00:00Z"
}
```

**Security rules:**

```javascript
// Firestore security rules — users can only read/write their own profiles
match /users/{userId}/profiles/{profileId} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}
```

**Anonymous auth:** No email or password. Firebase issues an anonymous UID tied to the device. If the user reinstalls the app, they can re-link via a restore code (v2 feature).

---

## Profile Engine Riverpod Providers

```dart
// Active profile — drives the entire Needle system prompt
@riverpod
Future<DietaryProfile?> activeProfile(ActiveProfileRef ref) async {
  final box = Hive.box<DietaryProfile>('profiles');
  return box.values.firstWhereOrNull((p) => p.isActive);
}

// All profiles — used in the profile switcher UI
@riverpod
List<DietaryProfile> allProfiles(AllProfilesRef ref) {
  final box = Hive.box<DietaryProfile>('profiles');
  return box.values.toList();
}

// Needle system prompt — derived from active profile
@riverpod
String needleSystemPrompt(NeedleSystemPromptRef ref) {
  final profile = ref.watch(activeProfileProvider).value;
  if (profile == null) return kDefaultSystemPrompt;
  return buildNeedleSystemPrompt(profile);
}
```

When the user switches profiles, `activeProfileProvider` invalidates → `needleSystemPromptProvider` rebuilds → `CactusService` picks up the new prompt on the next frame.

