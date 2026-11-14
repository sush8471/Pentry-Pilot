# Pantry Pilot — Project Documentation Index

> **"Real-Time Offline Dietary & Allergen HUD"**  
> An offline-first Android app that scans food ingredient labels live via camera and highlights allergen risks with sub-100ms latency, powered entirely by on-device AI (Cactus Compute).

---

## Document Index

| # | Document | Description |
|---|---|---|
| 1 | [Architecture Overview](./01-architecture-overview.md) | System design, data flow pipeline, component diagram |
| 2 | [Tech Stack & Decisions](./02-tech-stack-decisions.md) | Framework comparison, library choices, rationale |
| 3 | [Cactus AI Integration](./03-cactus-ai-integration.md) | Mirage OCR + Needle FFI bridge — how it works |
| 4 | [Allergen Taxonomy](./04-allergen-taxonomy.md) | Data schema, Big 9 synonyms, hidden derivatives |
| 5 | [Camera Pipeline](./05-camera-pipeline.md) | Frame throttling, ROI sampling, sharpness gating |
| 6 | [AR HUD Rendering](./06-ar-hud-rendering.md) | CustomPainter overlay, coordinate mapping, colour coding |
| 7 | [Dietary Profile Engine](./07-dietary-profile-engine.md) | SQLite + Hive schema, Needle evaluation, cloud sync |
| 8 | [Performance & Battery](./08-performance-battery.md) | Latency budget, thermal strategy, benchmark results |
| 9 | [Risk & Failure Modes](./09-risk-failure-modes.md) | OCR edge cases, fallback architecture, mitigations |
| 10 | [Phase Gate Log](./10-phase-gate-log.md) | Running record of phase reviews, decisions, test results |
| 11 | [Interview Guide](./11-interview-guide.md) | How to explain this project — talking points, diagrams, questions |

---

## Development Status (All Phases 100% Completed)

| Phase | Focus | Status | Tests |
|---|---|---|---|
| Phase 1 | Cactus Compute FFI & Engine Integration | ✅ Complete | 4/4 passing |
| Phase 2 | Camera Pipeline & Frame Processing | ✅ Complete | 4/4 passing |
| Phase 3 | Text Normalizer & Dietary Engine | ✅ Complete | 87/87 passing |
| Phase 4 | AR HUD Viewfinder UI & Riverpod State | ✅ Complete | 10/10 passing |
| Phase 5 | Battery Profiling, P95 Latency & Offline Verification | ✅ Complete | 10/10 passing |
| **Total** | **Full End-to-End Suite** | **✅ 100% PASS** | **115/115 passing** |

---

## Project At a Glance

```
Platform:     Android (API 29+)
Language:     Dart / Flutter 3.27+
AI Runtime:   Cactus Compute (Mirage OCR + Needle Agent)
AI Execution: 100% on-device — no cloud, no API keys
Model Size:   ~22MB (Mirage) + ~15MB (Needle) = ~37MB total
Latency:      <100ms end-to-end (P95 target)
Persistence:  SQLite (allergen taxonomy) + Hive (user profiles)
Sync:         Optional Firebase cloud sync for profiles
```

---

## Quick-Reference: The Three-Second Pitch

> *"Pantry Pilot is an Android app that acts like an allergen X-ray for food packaging. You point your phone camera at any ingredient label and the app instantly highlights every dangerous ingredient in red — no internet required, running entirely on the phone's AI chip. It uses Cactus Compute's 22MB vision model to read the label and a 15MB agent model to match ingredients against your dietary profile, all within 100 milliseconds."*

