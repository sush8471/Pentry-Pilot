# 03 — Cactus AI Integration

## What is Cactus Compute?

Cactus Compute is an on-device AI framework built from the ground up in C++ to run on mobile hardware — smartphones, wearables, and edge devices — without any cloud dependency. It has its own kernel implementations, its own quantization format (`.cact`), and its own inference graph engine specifically tuned for ARM NPUs.

Crucially, it has **no licensing cost and zero per-query fees** — once the model binary is on the device, every inference is free forever.

---

## Cactus Mirage — The OCR Engine

### What it is
Mirage is a 22MB Vision-Language Model (VLM). It is not a traditional OCR engine — it's a full multimodal model with:
- A 7.8M parameter image encoder (HConvGLU architecture — Hadamard transforms + small convolutions)
- A 40.8M parameter language decoder
- A 2.6M parameter dedicated OCR + spatial head

### What it does for Pantry Pilot
Given a camera frame (cropped to the ingredient label area), Mirage:
1. Encodes the image into visual feature tokens
2. Runs a single forward pass that simultaneously extracts text AND bounding boxes
3. Returns structured JSON: `{ tokens: ["maltodextrin", "casein", ...], bounding_boxes: [{text, rect: {x,y,w,h}}] }`

There is no separate detection → crop → OCR pipeline. It's one model, one forward pass. This is how it achieves ~74ms on NPU.

### Multilingual capability
Mirage handles EN, DE, FR, ES, IT, NL, PL natively. For v1 we scope to English only. The same model binary supports multilingual — it's purely a prompt/configuration choice.

### Integration via Dart FFI

```dart
// cactus_ffi.dart — Mirage OCR call
String mirageOcr(Uint8List yuvBytes, int width, int height) {
  // 1. Allocate native memory and copy YUV bytes
  final nativeBytes = calloc<Uint8>(yuvBytes.length);
  nativeBytes.asTypedList(yuvBytes.length).setAll(0, yuvBytes);

  // 2. Call into libcactus.so via FFI
  final resultPtr = _mirageOcr(_mirageHandle!, nativeBytes, width, height);

  // 3. Convert C string to Dart string and free native memory
  final result = resultPtr.toDartString();
  _freeString(resultPtr);
  calloc.free(nativeBytes);

  // 4. result = JSON: { "tokens": [...], "bounding_boxes": [...] }
  return result;
}
```

### Expected output format
```json
{
  "tokens": ["ingredients:", "water", "maltodextrin", "casein", "sunflower oil", "natural flavors"],
  "bounding_boxes": [
    { "text": "casein",        "rect": { "x": 142, "y": 318, "w": 86, "h": 24 } },
    { "text": "natural flavors","rect": { "x": 142, "y": 346, "w": 198, "h": 24 } }
  ],
  "confidence": 0.94,
  "inference_ms": 74
}
```

---

## Cactus Needle — The Allergen Agent

### What it is
Needle is a 8–29MB text model built on a *Simple Attention Network* architecture. Unlike general-purpose LLMs, Needle has no large feed-forward layers for storing world knowledge — 100% of its parameters are dedicated to **syntax mapping, span extraction, and schema alignment**.

### The critical feature: Constrained Decoding
When you pass a JSON schema (tool definition) to Needle, the engine:
1. Compiles the schema into a **byte-level LALR grammar** before the first token is generated
2. At every decode step, the grammar restricts the valid next-token set to only tokens that keep the output valid
3. The model **cannot produce** invalid JSON, out-of-enum values, or malformed structure

This means:
- Zero need for output validation or retry logic
- Deterministic structured output every time
- JSON parsing never fails in the application layer

### Why this matters for allergen safety
In a traditional LLM approach, the model might hallucinate `"status": "DANGR"` or fail to close a bracket. With Needle's grammar constraints, the output is guaranteed to be `"status": "DANGER" | "AMBIGUOUS" | "SAFE"` — the enum is enforced at the hardware level.

### The Tool Schema (defined once at app init)

```json
{
  "name": "evaluate_ingredients",
  "parameters": {
    "type": "object",
    "properties": {
      "findings": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "token":            { "type": "string" },
            "status":           { "type": "string", "enum": ["SAFE", "DANGER", "AMBIGUOUS"] },
            "matched_allergen": { "type": ["string", "null"] },
            "confidence":       { "type": "number", "minimum": 0.0, "maximum": 1.0 }
          },
          "required": ["token", "status", "confidence"]
        }
      },
      "overall_verdict": { "type": "string", "enum": ["SAFE", "DANGER", "AMBIGUOUS"] }
    },
    "required": ["findings", "overall_verdict"]
  }
}
```

### Grammar caching
The compiled grammar is cached in native memory after the first call. Subsequent calls reuse the compiled grammar — skipping grammar compilation reduces Needle latency from ~50ms to ~20ms on the second and all subsequent frames.

### Integration via Dart FFI

```dart
// cactus_ffi.dart — Needle evaluation call
String needleComplete(String messagesJson, String toolsJson) {
  final msgPtr  = messagesJson.toNativeUtf8();
  final toolPtr = toolsJson.toNativeUtf8();

  final resultPtr = _needleComplete(_needleHandle!, msgPtr, toolPtr);
  final result    = resultPtr.toDartString();

  _freeString(resultPtr);
  calloc.free(msgPtr);
  calloc.free(toolPtr);

  return result; // Guaranteed-valid JSON per schema
}
```

---

## Model Loading Strategy

### Android JNI Linking

```
android/app/src/main/jniLibs/
  arm64-v8a/    libcactus.so    ← Flagship (Snapdragon 8xx+)
  armeabi-v7a/  libcactus.so    ← Low-end fallback
  x86_64/       libcactus.so    ← Emulator
```

### Model asset bundling (chosen: bundled in APK)

```yaml
# pubspec.yaml — bundle models at build time
flutter:
  assets:
    - assets/models/mirage.cact   # 22MB
    - assets/models/needle.cact   # 15MB
```

> **Why bundled?** Guarantees true offline-first. App works from the first launch with no network. Trade-off: APK size ~37MB larger. For a food safety app, true offline-first is non-negotiable.

### Cold-start initialization sequence

```
App Launch
    │
    ├─ 1. Init Hive (user profiles) — ~10ms
    ├─ 2. Init SQLite + load synonym index into memory — ~50ms
    ├─ 3. Load Mirage model from assets → NPU — ~800ms (once only)
    ├─ 4. Load Needle model from assets → NPU — ~400ms (once only)  [async]
    ├─ 5. Pre-compile Needle JSON grammar — ~30ms (once only, then cached)
    └─ 6. Camera viewfinder ready — Total cold start: ~1.5s
```

Splash screen with animated Cactus logo covers the 1.5s cold start. Models remain in NPU memory until app is backgrounded (Android lifecycle-managed).

---

## C API Surface (libcactus.so interface)

The complete C API surface that Pantry Pilot uses:

```c
// Lifecycle
CactusHandle cactus_init(const char* model_path, bool use_npu);
void         cactus_destroy(CactusHandle handle);

// Mirage OCR
const char*  cactus_mirage_ocr(CactusHandle, const uint8_t* yuv, int32_t w, int32_t h);

// Needle text agent
const char*  cactus_needle_complete(CactusHandle, const char* messages, const char* tools);

// Memory
void         cactus_free_string(const char* str);
```

This is a minimal, stable API surface. The Cactus library handles all model loading, NPU scheduling, quantization, and kernel dispatch internally.

