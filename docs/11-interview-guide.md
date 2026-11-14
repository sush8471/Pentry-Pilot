# 11 — Interview Guide

> This document prepares you to explain the Pantry Pilot project confidently in a technical interview, portfolio review, or demo setting.

---

## The 30-Second Pitch

> *"I built Pantry Pilot — an Android app that acts as a real-time allergen scanner for food labels. You point the camera at any ingredient list, and the app instantly highlights every dangerous ingredient with a colour-coded AR overlay. The entire AI pipeline runs on-device using Cactus Compute: a 22MB vision model reads the label text via the camera's NPU chip, and a 15MB AI agent cross-references every ingredient against the user's dietary profile. No internet required, no cloud costs, and sub-100ms end-to-end latency."*

---

## Key Talking Points

### 1. Why offline-first?
*"Food safety decisions happen in environments with poor connectivity — supermarket basements, international travel, rural stores. If the app requires internet, it fails exactly when users need it most. All models are bundled in the APK. The app works in airplane mode from the first launch."*

### 2. How did you achieve sub-100ms latency?
*"Three things: First, Cactus Mirage runs in a single forward pass on the device's NPU — there's no pipeline of separate detection, cropping, and OCR models. Second, Cactus Needle uses constrained-decoding: the JSON schema is compiled into a byte-level grammar before inference starts, so the model only generates tokens that match the output format — no post-processing, no retry loops. Third, I pre-filter ingredient tokens through a local SQLite synonym database before they reach the AI — 60-80% of tokens never need to go to the AI at all."*

### 3. How does the allergen matching work?
*"Two-stage: Stage one is deterministic — a SQLite database of 400+ allergen synonyms (casein = dairy, tahini = sesame, etc.). Any token that exactly matches a synonym is immediately flagged as DANGER without touching AI. Stage two handles the unknowns — the remaining tokens go to Cactus Needle with the user's active dietary profile injected as context. Needle returns a JSON object with a verdict for each token: SAFE, DANGER, or AMBIGUOUS. The key innovation is that Needle's output is grammar-locked — it cannot hallucinate or return invalid JSON."*

### 4. What's the camera pipeline doing?
*"The camera runs at 30fps. The AI pipeline can process about 8-10fps on a flagship device, 4fps on low-end. So I use a drop-latest pattern — whenever a new frame arrives and the pipeline is busy, the frame is silently discarded. This prevents memory buildup and ensures every processed frame is the most recent one. Before the frame even reaches the AI, it passes through a Laplacian sharpness gate — if the variance score is below threshold, it's a blurry frame and I skip it entirely and show a 'Hold steady' nudge instead."*

### 5. How did you handle the Flutter/C++ FFI bridge?
*"Cactus Compute provides `libcactus.so` for Android — a C library with a minimal API: init a model handle, run OCR, run text completion, free memory. I wrote Dart FFI bindings using `dart:ffi` to call directly into this shared library. The tricky part is memory management: C returns a `const char*` pointer to the JSON result, and I need to copy it to Dart's heap and then call `cactus_free_string()` to avoid leaks. I also use `TransferableTypedData` to pass camera frame buffers between Dart isolates without copying the raw bytes — a 1.4MB zero-copy transfer per frame."*

### 6. What's the most interesting technical challenge you solved?
*"The coordinate transformation for the AR overlay. Mirage reports bounding boxes in camera preview space (1280×720 landscape), but Flutter renders in screen space (portrait, variable density). The camera sensor is physically landscape, so the preview is rotated 90 degrees in portrait mode. I had to map `cameraPreviewSize.height → screenSize.width` and `cameraPreviewSize.width → screenSize.height` to get the highlight boxes to align with the actual text on screen. Getting this wrong means the red boxes float in the wrong position — which is worse than no overlay at all."*

### 7. What would you do differently?
*"On low-end devices, Mirage's CPU inference at ~140ms is at the edge of the latency budget. In v2, I'd explore using Mirage only for text localization (finding where text is) and a faster classical OCR model (like Tesseract with a custom trained model for ingredient lists) for the actual text extraction. This would give a hybrid pipeline: fast classical OCR for extraction, Needle AI for semantic evaluation."*

---

## Architecture Diagram (for whiteboard)

```
Camera (30fps)
     │
     ▼
Frame Throttler (Drop-Latest, 8fps)
     │
     ▼
ROI Crop + Sharpness Gate
     │ [sharp frame]
     ▼
Cactus Mirage OCR   ← 22MB model on NPU (74ms)
     │ [JSON: tokens + bboxes]
     ▼
Text Normalizer (lowercase, dehyphenate, PAL scan)
     │
     ▼
SQLite Synonym Pre-filter   ← DANGER shortcut for known aliases
     │ [unknown tokens only]
     ▼
Cactus Needle Agent   ← 15MB model, grammar-locked JSON output (20ms)
     │ [AllergenFindings: SAFE/DANGER/AMBIGUOUS per token]
     ▼
AR HUD CustomPainter   ← Overlay on CameraPreview at 60fps
```

---

## Common Interview Questions & Answers

**Q: Couldn't you just use a regex/dictionary without AI?**
> "A pure dictionary works for exact matches, but allergen aliases are vast and context-dependent. 'Modified starch' might be wheat-derived or corn-derived depending on the product — a dictionary can't distinguish. 'Natural flavors' is legally allowed to hide dairy, wheat, or soy. Needle handles the semantic ambiguity that rules can't. The SQLite dictionary handles the clear-cut cases fast; Needle handles everything else."

**Q: What if Cactus Compute disappears or breaks?**
> "The models are bundled in the APK — existing installs keep working indefinitely. The fallback is SQLite-only mode, which still catches all 400+ known synonyms. The core functionality degrades gracefully, not catastrophically."

**Q: How do you test allergen accuracy?**
> "I maintain a test suite of 50 labeled food products with known allergen profiles. The test asserts that for each product, every known allergen is correctly flagged. I track accuracy by allergen category — a false negative on peanuts is more catastrophic than on sesame. The Phase 5 gate requires ≥90% accuracy across the full test set before v1 ships."

**Q: What's the app footprint?**
> "APK size: ~37MB for models + ~8MB Flutter engine + ~5MB app code = ~50MB total. Runtime memory: ~200MB when scanning actively (models resident in NPU memory). Both are within normal ranges for a modern Android app."

**Q: Why Riverpod over Provider or BLoC?**
> "Riverpod 2 with code generation gives compile-time safety — if a provider dependency is wrong, it fails at build time, not at runtime. For a camera app where providers span background isolates and native code, that compile-time guarantee catches a whole class of bugs before they reach users."

---

## Portfolio Checklist

- [ ] Demo video: 60-second screen recording scanning 3 real labels (safe, danger, ambiguous)
- [ ] GitHub repo with README explaining Cactus integration
- [ ] This `/docs` folder committed to repo
- [ ] Architecture diagram in README
- [ ] Phase gate log showing testing methodology
- [ ] APK downloadable from releases page (airplane-mode tested)

