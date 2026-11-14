# 04 — Allergen Taxonomy

## Regulatory Scope (v1)

**Primary:** FDA Big 9 (United States FALCPA + FASTER Act)  
**Secondary:** EU Big 14 flags available as opt-in extension (v2)

The 9 major allergens mandated by US law:
1. Milk (Dairy)
2. Egg
3. Peanut
4. Tree Nuts
5. Wheat
6. Soy
7. Fish
8. Crustacean Shellfish
9. Sesame *(added 2023 under FASTER Act)*

Additionally, Pantry Pilot exposes a **custom "GLUTEN" group** covering Wheat + Barley + Rye + all derivatives — this is the Celiac-Safe profile, broader than the FDA's Wheat-only requirement.

---

## Database Schema

```sql
-- allergen_groups: One row per top-level allergen category
CREATE TABLE allergen_groups (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    code         TEXT NOT NULL UNIQUE,   -- 'MILK', 'GLUTEN', 'SESAME', etc.
    display_name TEXT NOT NULL,
    regulation   TEXT NOT NULL,          -- 'FDA', 'EU', 'CUSTOM'
    severity     INTEGER DEFAULT 2       -- 1=advisory, 2=major, 3=anaphylaxis-risk
);

-- allergen_synonyms: Every known alias/derivative mapped to a parent group
CREATE TABLE allergen_synonyms (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    allergen_id  INTEGER NOT NULL REFERENCES allergen_groups(id),
    synonym      TEXT NOT NULL,          -- lowercase normalised
    match_type   TEXT NOT NULL,          -- 'exact' | 'prefix' | 'contains' | 'regex'
    confidence   REAL DEFAULT 1.0,       -- 1.0=definite, 0.5=ambiguous context-dependent
    source_note  TEXT                    -- e.g., 'refined oil exempt under FDA'
);

-- ambiguous_entries: Terms that MIGHT indicate an allergen depending on source
CREATE TABLE ambiguous_entries (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    term            TEXT NOT NULL,       -- e.g., 'natural flavors', 'starch'
    ambiguity_note  TEXT NOT NULL,
    allergen_ids    TEXT                 -- comma-separated group codes to flag
);

-- Performance indexes
CREATE UNIQUE INDEX idx_synonym_unique ON allergen_synonyms(allergen_id, synonym);
CREATE INDEX        idx_synonym_text   ON allergen_synonyms(synonym);
CREATE INDEX        idx_ambiguous_term ON ambiguous_entries(term);
```

---

## Full Synonym Dictionary (Seed Data — FDA Big 9)

### MILK / DAIRY
| Synonym | Match Type | Confidence | Note |
|---|---|---|---|
| casein | exact | 1.0 | — |
| caseinate | prefix | 1.0 | Covers sodium/calcium/potassium caseinate |
| whey | exact | 1.0 | — |
| whey protein | exact | 1.0 | — |
| whey protein isolate | exact | 1.0 | — |
| whey protein concentrate | exact | 1.0 | — |
| lactalbumin | exact | 1.0 | — |
| lactoglobulin | exact | 1.0 | — |
| lactose | exact | 1.0 | — |
| butter | exact | 1.0 | — |
| butterfat | exact | 1.0 | — |
| buttermilk | exact | 1.0 | — |
| butter oil | exact | 1.0 | — |
| ghee | exact | 1.0 | — |
| milk powder | exact | 1.0 | — |
| milk solids | exact | 1.0 | — |
| milk protein | exact | 1.0 | — |
| cream | exact | 1.0 | — |
| half and half | exact | 1.0 | — |
| sour cream | exact | 1.0 | — |
| cheese | exact | 1.0 | — |
| nougat | exact | 0.9 | May be dairy-free in some formulations |
| tagatose | exact | 0.8 | Lactose-derived; some processes remove allergen |
| recaldent | exact | 1.0 | — |
| custard | exact | 1.0 | — |
| pudding | exact | 0.9 | Usually dairy; check formulation |

### EGG
| Synonym | Match Type | Confidence | Note |
|---|---|---|---|
| albumin | exact | 1.0 | — |
| albumen | exact | 1.0 | — |
| ovalbumin | exact | 1.0 | — |
| ovomucoid | exact | 1.0 | — |
| ovomucin | exact | 1.0 | — |
| ovovitellin | exact | 1.0 | — |
| egg white | exact | 1.0 | — |
| egg yolk | exact | 1.0 | — |
| egg solids | exact | 1.0 | — |
| dried egg | exact | 1.0 | — |
| meringue | exact | 1.0 | — |
| mayonnaise | exact | 1.0 | — |
| lysozyme | exact | 0.9 | Used in some cheeses/wines; egg-derived |
| surimi | exact | 0.8 | Often contains egg whites |

### PEANUT
| Synonym | Match Type | Confidence | Note |
|---|---|---|---|
| peanut | exact | 1.0 | — |
| peanut butter | exact | 1.0 | — |
| peanut flour | exact | 1.0 | — |
| peanut oil | exact | 0.7 | Refined oil may be exempt; flag as AMBIGUOUS |
| arachis oil | exact | 0.8 | Cold-pressed = allergenic; refined = may be exempt |
| groundnut | exact | 1.0 | — |
| ground nut | exact | 1.0 | — |
| beer nuts | exact | 1.0 | — |
| goobers | exact | 1.0 | — |
| mandelona | exact | 1.0 | Almond soaked in peanut flavor |
| mixed nuts | contains | 0.6 | May contain peanuts; flag AMBIGUOUS |
| artificial nuts | exact | 0.8 | — |

### TREE NUTS
| Synonym | Match Type | Confidence | Note |
|---|---|---|---|
| almond | exact | 1.0 | — |
| almond paste | exact | 1.0 | — |
| marzipan | exact | 1.0 | — |
| walnut | exact | 1.0 | — |
| pecan | exact | 1.0 | — |
| cashew | exact | 1.0 | — |
| pistachio | exact | 1.0 | — |
| macadamia | exact | 1.0 | — |
| brazil nut | exact | 1.0 | — |
| hazelnut | exact | 1.0 | — |
| filbert | exact | 1.0 | Hazelnut synonym |
| pine nut | exact | 1.0 | — |
| pesto | exact | 0.9 | Traditionally contains pine nuts/cashews |
| praline | exact | 0.9 | Usually nut-based |
| gianduja | exact | 1.0 | Chocolate-hazelnut spread |
| nut butter | contains | 0.9 | — |
| nut milk | contains | 0.9 | — |

### WHEAT (FDA) / GLUTEN (Celiac-Safe — includes Barley + Rye)
| Synonym | Group | Match Type | Confidence |
|---|---|---|---|
| wheat | WHEAT+GLUTEN | exact | 1.0 |
| wheat flour | WHEAT+GLUTEN | exact | 1.0 |
| wheat starch | WHEAT+GLUTEN | exact | 1.0 |
| wheat germ | WHEAT+GLUTEN | exact | 1.0 |
| wheat bran | WHEAT+GLUTEN | exact | 1.0 |
| spelt | WHEAT+GLUTEN | exact | 1.0 |
| kamut | WHEAT+GLUTEN | exact | 1.0 |
| farro | WHEAT+GLUTEN | exact | 1.0 |
| durum | WHEAT+GLUTEN | exact | 1.0 |
| einkorn | WHEAT+GLUTEN | exact | 1.0 |
| emmer | WHEAT+GLUTEN | exact | 1.0 |
| triticale | WHEAT+GLUTEN | exact | 1.0 |
| seitan | WHEAT+GLUTEN | exact | 1.0 |
| vital wheat gluten | WHEAT+GLUTEN | exact | 1.0 |
| semolina | WHEAT+GLUTEN | exact | 1.0 |
| bulgur | WHEAT+GLUTEN | exact | 1.0 |
| farina | WHEAT+GLUTEN | exact | 1.0 |
| freekeh | WHEAT+GLUTEN | exact | 1.0 |
| couscous | WHEAT+GLUTEN | exact | 1.0 |
| barley | GLUTEN | exact | 1.0 |
| barley malt | GLUTEN | exact | 1.0 |
| malt | GLUTEN | exact | 0.9 |
| malt extract | GLUTEN | exact | 1.0 |
| malt syrup | GLUTEN | exact | 1.0 |
| malt flavoring | GLUTEN | exact | 1.0 |
| rye | GLUTEN | exact | 1.0 |
| modified food starch | GLUTEN | exact | 0.6 |
| cereal extract | GLUTEN | exact | 0.8 |

### SOY
| Synonym | Match Type | Confidence |
|---|---|---|
| soy | exact | 1.0 |
| soybean | exact | 1.0 |
| soy protein | exact | 1.0 |
| soy flour | exact | 1.0 |
| soy lecithin | exact | 0.8 |
| tofu | exact | 1.0 |
| tempeh | exact | 1.0 |
| miso | exact | 1.0 |
| edamame | exact | 1.0 |
| tamari | exact | 1.0 |
| textured vegetable protein | exact | 0.9 |
| hydrolyzed soy protein | exact | 1.0 |
| hydrolyzed vegetable protein | exact | 0.7 |

### SESAME
| Synonym | Match Type | Confidence |
|---|---|---|
| sesame | exact | 1.0 |
| sesame oil | exact | 1.0 |
| sesame seeds | exact | 1.0 |
| sesame flour | exact | 1.0 |
| sesame paste | exact | 1.0 |
| tahini | exact | 1.0 |
| tahina | exact | 1.0 |
| halvah | exact | 1.0 |
| halva | exact | 1.0 |
| hummus | exact | 1.0 |
| benne | exact | 1.0 |
| benniseed | exact | 1.0 |
| gingelly | exact | 1.0 |
| gingelly oil | exact | 1.0 |
| gomasio | exact | 1.0 |
| sim sim | exact | 1.0 |
| til | exact | 1.0 |

---

## Ambiguous Terms (Always AMBIGUOUS verdict)

| Term | Note | Allergens to Flag |
|---|---|---|
| natural flavors | May hide milk, wheat, soy, or nut derivatives | MILK, SOY, WHEAT, TREENUT |
| artificial flavors | Similar to natural flavors | MILK, SOY, WHEAT |
| natural color | May include carmine (not an allergen but a flag) | — |
| spices | Rarely hides allergens; flag for extra-strict profiles | — |
| modified starch | Source often unspecified; may be wheat | WHEAT, GLUTEN |
| starch | Same as modified starch | WHEAT, GLUTEN |
| vegetable oil blend | May include peanut or tree nut oils | PEANUT, TREENUT |
| dextrin | Usually corn; occasionally wheat | WHEAT, GLUTEN |
| glucose syrup | Usually corn; occasionally wheat | WHEAT, GLUTEN |
| caramel color | Usually corn; Class IV may be wheat-derived | WHEAT, GLUTEN |
| msg | Typically corn or sugarcane derived | — |

---

## Text Normalization Rules

Before synonym lookup, every token passes through the normalizer:

1. **Lowercase**: `"Sodium Caseinate"` → `"sodium caseinate"`
2. **Strip punctuation** (except hyphens): `"whey-protein,"` → `"whey-protein"`
3. **Hyphen joining** (fragmented OCR): `"so-di-um"` → `"sodium"`
4. **Unicode normalization** (NFKD): strips diacritics, converts special chars
5. **Deduplication**: remove repeated tokens in the same frame
6. **PAL phrase detection** (regex pass): detect "may contain", "processed in a facility", "made on equipment shared with" → flag as AMBIGUOUS for all active allergens
7. **Quantity stripping**: `"water (50%)"` → `"water"` (percentage confuses Needle)

---

## Lookup Strategy: SQLite-First, Needle-Second

For low-end devices where Needle latency may be too high:

```
Token arrives from OCR
        │
        ▼
SQLite synonym lookup (exact match first) — <1ms
        │
   ┌────┴────┐
   │ Found?  │
   └────┬────┘
       YES → DANGER verdict directly (skip Needle for this token)
        │
       NO → Send to Needle for fuzzy/contextual evaluation
```

This pre-filter means Needle only receives:
- Tokens not in the synonym table (novel/unknown ingredients)
- Tokens in the ambiguous_entries table (need context)

On typical labels, this reduces Needle's input by 60–80%, cutting its latency proportionally.

