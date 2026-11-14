# 02 — Tech Stack & Decisions

## Decision Log

Every technology choice in this project was evaluated against three criteria:
1. Does it support 100% offline operation?
2. Does it meet the <100ms latency target?
3. Does it minimise implementation complexity for a single developer?

---

## Framework: Flutter (Dart FFI)

### Why not React Native?
React Native's JavaScript bridge introduces 2–8ms of serialization overhead per native call. For a pipeline where every millisecond counts and we're calling into `libcactus` on every frame, this overhead compounds. Additionally, the `cactus-react-native` package is less mature than the official Flutter/pub.dev package.

### Why not Native Kotlin?
Native Kotlin would yield the best raw latency (~10ms advantage over Flutter), but doubles the codebase when iOS is added in v2. Flutter's `dart:ffi` has near-zero overhead when calling into C libraries — the `cactus_dart` package already provides typed FFI bindings.

### Flutter advantages for this project:
- Official `cactus` pub.dev package with `CactusMirage` and `CactusLM` classes
- `CustomPainter` renders HUD overlay at 60fps without custom OpenGL code
- `camera` plugin provides `startImageStream()` for raw YUV frame access
- Single codebase → easy iOS port in v2 (just swap `.so` for `.xcframework`)
- Dart Isolates provide clean background inference without JNI thread management

---

## AI Runtime: Cactus Compute

| Component | Model | Size | Purpose | Latency (NPU) |
|---|---|---|---|---|
| **Cactus Mirage** | `mirage.cact` | 22MB | OCR + bounding box extraction | ~74ms |
| **Cactus Needle** | `needle.cact` | ~15MB | Allergen evaluation + JSON tool calling | ~20ms |

### Why Cactus over TensorFlow Lite / ML Kit?

| Criterion | Cactus Compute | TFLite | ML Kit |
|---|---|---|---|
| Offline OCR | ✅ Full VLM | ⚠️ Needs custom model | ⚠️ Requires network for some features |
| Allergen reasoning | ✅ Needle agent | ❌ Rule engine only | ❌ Rule engine only |
| JSON constrained output | ✅ Grammar-locked | ❌ Post-process only | ❌ Post-process only |
| Model size | ✅ 37MB total | Variable | Variable |
| NPU support (Android) | ✅ Native | ✅ NNAPI delegate | ✅ NNAPI delegate |
| Allergen aliasing | ✅ Needle reasoning | ❌ Manual synonym table | ❌ Manual synonym table |

The killer feature is Needle's **constrained-decoding**: the JSON output schema is compiled to a byte-level grammar before inference starts. The model literally cannot produce invalid JSON or hallucinate outside the schema. This is non-negotiable for a safety-critical food allergen app.

---

## Local Persistence: SQLite + Hive (dual-store)

### Why two databases?

Different data has different shapes:

| Store | Technology | Data Type | Why |
|---|---|---|---|
| **Allergen taxonomy** | SQLite (`sqflite`) | Relational (groups → synonyms JOIN) | Needs JOIN queries, full-text prefix search, WAL mode for <2ms reads |
| **User profiles** | Hive | Simple key-value blob | Profiles are flat objects, no joins needed; Hive's Isolate-safe box is perfect |

### Why not just SQLite for everything?
Hive's `Box` is Isolate-safe out of the box and faster for simple object reads. Reading a user profile from SQLite requires parsing rows into Dart objects on every frame — Hive caches the deserialized object in memory automatically.

### Why not Realm / ObjectBox?
Both are excellent but add binary size and licensing complexity. SQLite + Hive is the Flutter community standard, battle-tested, and adds ~200KB combined.

---

## State Management: Riverpod 2

Chosen over Provider, BLoC, and GetX because:
- **Compile-time safety**: `riverpod_generator` + `@riverpod` annotation catches provider errors at compile time
- **Isolate-aware**: Providers can safely expose `AsyncValue` from background isolates
- **No BuildContext dependency**: Service providers can be accessed outside widget tree (needed for camera isolate callbacks)
- **Testable**: Providers can be overridden per-test without boilerplate

---

## Optional Cloud Sync: Firebase Firestore

User dietary profiles can optionally sync to Firebase Firestore. This is:
- **Opt-in only** — toggled in settings
- **Offline-first** — Firestore's local persistence means profiles work without connectivity
- **Anonymous auth** — No email/password required; device-linked anonymous UID

The sync layer is completely decoupled from the allergen pipeline. Removing it has zero impact on the core scanning functionality.

---

## Dependency Manifest

```yaml
# Core
flutter_riverpod: ^2.6.0      # State management
go_router: ^14.0.0             # Navigation
freezed: ^2.5.0                # Immutable models
json_serializable: ^6.9.0      # JSON codegen

# AI
cactus: ^1.14.0                # High-level Cactus wrapper
cactus_dart: ^1.14.0           # Low-level FFI bindings
ffi: ^2.1.0                    # dart:ffi support

# Camera
camera: ^0.11.0                # Camera2 API access
permission_handler: ^11.3.1    # Runtime permission

# Storage
sqflite: ^2.4.0                # Allergen taxonomy DB
hive_flutter: ^1.1.0           # User profile storage
path_provider: ^2.1.5          # App data directories

# Cloud sync (optional)
firebase_core: ^3.0.0          # Firebase init
cloud_firestore: ^5.0.0        # Profile sync
firebase_auth: ^5.0.0          # Anonymous auth

# Testing
mocktail: ^1.0.0               # Mocking
flutter_test: (SDK)
```

