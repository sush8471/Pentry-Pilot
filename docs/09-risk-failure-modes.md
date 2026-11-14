# 09 — Risk & Failure Modes

## Failure Mode Registry

Every identified failure mode is documented here with its likelihood, impact on users, detection method, and mitigation strategy.

---

## OCR Quality Failures

### F-01: Blurry / Out-of-Focus Label
- **Cause:** User moves phone too quickly, shaky hands, poor stabilization
- **Detection:** Laplacian variance score < 120 (sharpness gate)
- **Impact:** Mirage returns empty or garbage tokens → no HUD overlay
- **Mitigation:** Sharpness gate rejects frame immediately (saves NPU). HUD shows "Hold steady" nudge. Persistent blur (>2 seconds) triggers "Tap to pause" and shows torch-on suggestion.

### F-02: Poor / Uneven Lighting
- **Cause:** Supermarket shelf shadow, back-lighting, dim conditions
- **Detection:** Mean pixel brightness of Y-plane < 40 or > 220 (clamped)
- **Impact:** OCR confidence drops; tokens missed or garbled
- **Mitigation:**
  - Auto-torch: If average brightness < 40 for 3 consecutive rejected frames, suggest enabling torch via platform channel
  - Mirage handles moderate under/overexposure better than classical OCR due to its learned image encoder

### F-03: Curved / Cylindrical Container (Cans, Bottles)
- **Cause:** Ingredients wrap around a curved surface; perspective distortion
- **Detection:** OCR confidence score < 0.65 from Mirage
- **Impact:** Some tokens fragmented or duplicated
- **Mitigation:**
  - Multi-frame token merging: Collect OCR output across 5 consecutive frames and take the **union** of tokens weighted by frequency. A token appearing in 3/5 frames is promoted to CONFIRMED; 1–2/5 stays tentative.
  - Prompt user: "Rotate can slowly" nudge when curved label detected

### F-04: Very Small Font (Microprint, Sub-Labels)
- **Cause:** May-contain warnings in 4pt type; trace allergen disclosures
- **Detection:** Mirage bounding box height < 12px for a detected token
- **Impact:** Token missed entirely
- **Mitigation:**
  - "Zoom in" nudge when very small text detected
  - On-demand: User can tap "Zoom" button to switch to `ResolutionPreset.high` temporarily

### F-05: Crumpled / Damaged Packaging
- **Cause:** Dented cans, torn labels, condensation
- **Detection:** High sharpness variance but low OCR confidence
- **Impact:** Partial token extraction
- **Mitigation:** Multi-frame merging (see F-03). Prompt user to flatten/photograph label separately if persistent.

### F-06: Non-English Labels (v1 scope)
- **Cause:** Imported product with foreign-language ingredients
- **Detection:** Character distribution outside ASCII 32–126
- **Impact:** Token extraction fails; Needle cannot evaluate
- **Mitigation:** "Unsupported language detected" banner. Mirage actually supports 7 languages — this is a UI/UX limitation in v1, not a model limitation. Can be unlocked in v2 without model changes.

---

## Allergen Evaluation Failures

### F-07: Novel Allergen Alias Not in Taxonomy
- **Cause:** Manufacturer uses non-standard or regional name for an allergen derivative
- **Detection:** Token not in SQLite synonym table → goes to Needle → Needle returns SAFE with low confidence
- **Impact:** False negative — allergen missed
- **Mitigation:**
  - Needle is prompted to prefer AMBIGUOUS over SAFE when uncertain
  - Confidence threshold: if Needle returns SAFE with confidence < 0.7, downgrade to AMBIGUOUS
  - Community reporting: In-app "Flag as allergen" button sends the token to a backend for taxonomy review (network call, non-critical, fails gracefully)

### F-08: PAL (Precautionary Allergen Labeling) Missed
- **Cause:** "May contain traces of peanuts" in separate paragraph below ingredients
- **Detection:** Text normalizer PAL regex pass may miss it if the HUD only covers the main ingredient block
- **Impact:** Cross-contamination risk not flagged
- **Mitigation:**
  - PAL regex applied to ALL extracted text, not just the ingredient list
  - PAL tokens ("may contain", "processed in a facility") are always flagged AMBIGUOUS for all active allergens
  - HUD shows separate "⚠️ Cross-contamination warning" indicator at bottom

### F-09: OCR Token Fragmentation
- **Cause:** Hyphen in ingredient name OCR-ed as separate tokens (e.g., "sodium" / "caseinate" vs "sodium caseinate")
- **Detection:** None (happens silently)
- **Impact:** Compound synonym like "sodium caseinate" not matched exactly
- **Mitigation:**
  - Text normalizer joins adjacent tokens within 2-word distance if the combined form matches a synonym
  - SQLite includes both "sodium caseinate" (exact) and "caseinate" (prefix) synonyms

### F-10: Legally Exempt Ingredients (Refined Oils)
- **Cause:** "Peanut oil" or "soybean oil" may be highly refined and legally exempt from allergen labeling
- **Detection:** Exact term matches but has `source_note` indicating possible exemption
- **Impact:** Could generate false positive (more tolerable than false negative)
- **Mitigation:** Flag as AMBIGUOUS (not DANGER) for refined oils specifically. HUD shows informational tooltip: "Refined oil may be allergen-free — verify with manufacturer."

### F-11: Needle JSON Schema Drift (Model Update)
- **Cause:** Cactus Compute publishes a new Needle model version that behaves differently
- **Detection:** Boot-time canary test: run Needle on a known input, assert expected JSON structure
- **Impact:** App crashes or returns malformed data after update
- **Mitigation:** Pin model to a specific version hash in `pubspec.yaml`. Validate schema at startup. Fail-safe: if canary fails, disable Needle and fall back to SQLite-only evaluation with "Limited analysis mode" banner.

---

## Performance Failures

### F-12: Thermal Throttling
- **Cause:** Sustained NPU usage over 20+ minutes in hot environment
- **Detection:** `PowerManager.ThermalStatus` API (Android 10+)
- **Impact:** Mirage latency spikes from 74ms to 300ms+; HUD lags visibly
- **Mitigation:** Tiered response:
  - `LIGHT` → Reduce to 6fps
  - `MODERATE` → Reduce to 4fps + show "Device warming up" toast
  - `SEVERE` → Pause scanning + "Let device cool" full overlay
  - `CRITICAL` → Emergency stop, show cool-down timer

### F-13: Memory Pressure on Low-End Devices
- **Cause:** <2GB RAM Android device; camera buffer + model memory exceed available heap
- **Detection:** `lowMemory()` callback from `ComponentCallbacks2`
- **Impact:** OOM kill
- **Mitigation:** On `TRIM_MEMORY_RUNNING_CRITICAL`, immediately switch to `ResolutionPreset.low` and reduce frame pool to 1 buffer.

### F-14: Model Load Failure (Corrupted Asset)
- **Cause:** App update corrupted the model binary during copy
- **Detection:** `cactus_init()` returns null handle
- **Impact:** Scanning completely non-functional
- **Mitigation:** Detect null handle at init → show "Scan engine error" screen → option to "Re-download models" (triggers asset extraction from APK)

---

## Fallback Architecture

```
Frame arrives
     │
     ▼
Sharpness Gate?
     ├─ FAIL → "Hold steady" nudge, skip frame
     └─ PASS ↓

Mirage OCR?
     ├─ LOW confidence (<0.65) → Multi-frame token merge, continue
     └─ TOKENS EXTRACTED ↓

SQLite Pre-filter
     ├─ EXACT MATCH → DANGER verdict (skip Needle)
     ├─ AMBIGUOUS TERM → AMBIGUOUS verdict (skip Needle)
     └─ UNKNOWN TOKEN → Send to Needle ↓

Needle Evaluation
     ├─ VALID JSON → Use findings
     ├─ TIMEOUT / ERROR → SQLite-only mode (all unknowns = AMBIGUOUS)
     └─ NULL HANDLE → "Limited analysis" mode (SQLite only, banner shown)

HUD Render
     └─ Always renders with whatever data is available
```

**Key principle:** The app never shows nothing. Even in degraded mode, it shows partial results with a clear indication of reduced confidence.

