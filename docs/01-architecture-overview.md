# 01 — Architecture Overview

## Problem Statement

Reading food ingredient labels manually is error-prone, slow, and cognitively demanding — especially for people managing multiple allergies. Hidden allergen aliases (e.g., "casein" = dairy, "tahini" = sesame) are routinely missed. Pantry Pilot eliminates this risk by embedding a real-time AI scanner directly in the camera viewfinder.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Android Device                               │
│                                                                     │
│  ┌──────────┐    ┌────────────┐    ┌──────────────┐               │
│  │  Camera   │───▶│  Frame     │───▶│  Cactus       │               │
│  │  Sensor   │    │  Throttler │    │  Mirage OCR   │               │
│  │  30fps    │    │  ~8-10fps  │    │  (NPU 74ms)   │               │
│  └──────────┘    └────────────┘    └──────┬───────┘               │
│                                           │ JSON tokens + bboxes   │
│  ┌──────────┐    ┌────────────┐    ┌──────▼───────┐               │
│  │  AR HUD  │◀───│  Allergen  │◀───│  Cactus       │               │
│  │  Painter │    │  Resolver  │    │  Needle Agent │               │
│  │  60fps   │    │  SQLite    │    │  (<30ms)      │               │
│  └──────────┘    └────────────┘    └──────────────┘               │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────┐       │
│  │  Dietary Profile (Hive)   │   Allergen DB (SQLite)       │       │
│  └─────────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────┘
```

## End-to-End Data Flow

```
Live Camera Stream (YUV_420_888, 30fps)
        │
        ▼
Frame Throttler — Drop-Latest Backpressure
  ● Samples at 8fps (flagship) / 4fps (low-end)
  ● "Busy" flag: drops frame if previous pipeline not done
        │
        ▼
ROI Sampler + Sharpness Gate
  ● Center-crops 70% of frame (where label typically appears)
  ● Laplacian variance check — rejects blurry frames (<120 score)
  ● If rejected → "Hold steady" nudge on HUD
        │ (cropped, sharp frame)
        ▼
Cactus Mirage OCR  [22MB VLM — runs on NPU]
  ● Single-pass: extracts ingredient text tokens + bounding boxes
  ● Returns structured JSON: { tokens: [...], bounding_boxes: [...] }
  ● Latency: ~74ms NPU | ~107ms CPU fallback
        │
        ▼
Text Normalizer
  ● Lowercase, strip Unicode noise, deduplicate
  ● Hyphen-fragment joiner ("so-di-um" → "sodium")
  ● PAL (precautionary allergen labeling) regex pass
        │
        ▼
Cactus Needle Agent  [~15MB — runs on NPU/CPU]
  ● Receives ingredient token list + user's active allergen profile
  ● Constrained-decoding JSON output (schema-locked, zero hallucination)
  ● Returns: { findings: [{token, status, matched_allergen, confidence}], overall_verdict }
  ● Latency: ~20-30ms (grammar pre-compiled at init)
        │
        ▼
Allergen DB Resolver (SQLite — in-memory index)
  ● Cross-references findings against synonym table
  ● In-memory LRU cache for top-200 tokens
  ● Latency: <2ms
        │
        ▼
AR HUD CustomPainter
  ● Paints coloured bounding boxes over CameraPreview at 60fps
  ● RED = DANGER | AMBER = AMBIGUOUS | GREEN = SAFE
  ● shouldRepaint() guard prevents unnecessary redraws
        │
        ▼
User sees real-time coloured highlights + verdict badge
```

## Latency Budget

| Stage | Budget | Actual (Flagship) | Actual (Low-End) |
|---|---|---|---|
| Frame throttle + ROI | 2ms | ~1ms | ~2ms |
| Mirage OCR (NPU) | 80ms | ~74ms | ~140ms |
| Text Normalize | 1ms | <1ms | <1ms |
| Needle Evaluation | 30ms | ~20ms | ~45ms |
| Allergen DB lookup | 2ms | <2ms | <2ms |
| HUD repaint | 1ms | <1ms | <1ms |
| **Total** | **<116ms** | **~98ms** | **~191ms** |

> **Low-end strategy:** On devices where Mirage+Needle total >150ms, we pre-filter tokens through the SQLite synonym table first. Only matched candidates go to Needle, reducing context by ~80% and cutting Needle latency to ~15ms. Combined total stays under 200ms, which remains perceptually fast for a camera scanner.

## Architectural Principles

1. **Offline-first, always.** No feature may require a network call. The app must function identically in airplane mode.
2. **Drop, never queue.** Frames are dropped when the pipeline is busy. Queueing causes latency buildup and eventual OOM.
3. **Isolate inference.** Mirage and Needle run in a background Dart isolate. The UI isolate only handles rendering.
4. **Conservative on ambiguity.** When uncertain, the system flags AMBIGUOUS rather than SAFE. User safety > false negative prevention.
5. **Device-adaptive.** Frame rate, resolution, and inference strategy adapt to device tier at runtime.

