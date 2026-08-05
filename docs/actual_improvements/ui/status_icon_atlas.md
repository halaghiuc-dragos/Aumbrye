# Status icon atlas — improvement plan

## Current state
`status_icon_atlas.gd` is a runtime pixel plotter, not an atlas: `get_icon` builds a 22×22 `Image` and fills circles, rings, diamonds, or a bolt polygon one pixel at a time, caching the result in a never-invalidated `static var _cache` (`status_icon_atlas.gd:8-21`, `:49-92`). Four of the five authored statuses hit a named branch with hardcoded colors that override the `iconColor` the caller already looked up; the fifth, `freeze`, misses entirely because the match arm spells `frost` / `chill` (`status_icon_atlas.gd:38` vs `content/statuses/freeze.json:2`). The repo contains no `.png` at all, so there is no authored icon art to fall back on. See [`../existing_codebase/ui/status_icon_atlas.md`](../existing_codebase/ui/status_icon_atlas.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| SIA-01 | P0 | Status icons are procedural blobs, not authored art. The class name promises an atlas and delivers per-pixel `set_pixel` loops. | `status_icon_atlas.gd:14-21`, `:49-92`; `apps/game/client/**/*.png` returns 0 files |
| SIA-02 | P0 | `freeze` — the only frost status in the game — renders as the generic fallback circle because the branch matches `"frost", "chill"`. A player cannot distinguish being frozen from an unknown effect. | `status_icon_atlas.gd:38`; `content/statuses/freeze.json:2` sets `"id": "freeze"` |
| SIA-03 | P1 | `iconColor` from `content/statuses/*.json` is read by `combat_hud.gd:196-197` and then thrown away by every named branch, so authoring a new color has no visible effect for `burn`, `poison`, `stun`, or `bleed`. | `status_icon_atlas.gd:32-43` |
| SIA-04 | P1 | Icons carry no stack count, no remaining duration, and no buff/debuff polarity. | `status_icon_atlas.gd:11-21` returns a flat glyph |
| SIA-05 | P1 | Colors are hardcoded and `AccessibilitySettings.colorblind_mode` is never consulted, so the colorblind option in settings cannot help status readability. | grep `colorblind` returns no hit in `status_icon_atlas.gd`; `accessibility_settings.gd:10` |
| SIA-06 | P2 | Four dead match arms (`venom`, `chill`, `frost`, `shock`) have no definition under `content/statuses/`. | `status_icon_atlas.gd:35,38,41`; `content/statuses/` contains 5 files |
| SIA-07 | P2 | `static var _cache` is never invalidated, so textures survive a resolution-preset change and a scene reload with no way to regenerate. | `status_icon_atlas.gd:8` |
| SIA-08 | P2 | `ICON_SIZE = 22` is duplicated as the literal `Vector2(22, 22)` in the HUD; the two can drift silently. | `status_icon_atlas.gd:6`; `combat_hud.gd:194` |
| SIA-09 | P2 | A missing status icon fails silently into an anonymous circle, so an unauthored status id is indistinguishable from an authored one at a glance. | `status_icon_atlas.gd:44-46` |

## Target design

### One authored atlas texture
Ship `apps/game/client/assets/ui/status_icons.png`: **128 × 96 px**, an **8 × 6 grid of 16 × 16 px cells**, 48 cells. 16 px is chosen so the icon is an integer 1:1 match at the `320×180` preset and scales by whole factors upward; the HUD renders it at 16 px logical with `TEXTURE_FILTER_NEAREST`. Import settings: `filter=false`, `mipmaps=false`, `compress/mode=0` (lossless).

Cell assignment is data-driven, not positional-by-convention. Add a manifest at `content/ui/status_icon_atlas.json`:

```json
{
  "schemaVersion": 1,
  "texture": "res://assets/ui/status_icons.png",
  "cellSize": 16,
  "columns": 8,
  "rows": 6,
  "cells": {
    "burn":    { "col": 0, "row": 0 },
    "poison":  { "col": 1, "row": 0 },
    "freeze":  { "col": 2, "row": 0 },
    "stun":    { "col": 3, "row": 0 },
    "bleed":   { "col": 4, "row": 0 },
    "unknown": { "col": 7, "row": 5 }
  }
}
```

Reserved rows: row `0` elemental debuffs, row `1` control debuffs, row `2` damage-over-time, row `3` buffs, row `4` auras and stances, row `5` utility, with `(7,5)` permanently the `unknown` marker. Naming convention for source art layers and any exported single files: `status_<id>_16.png`.

Every id in `cells` must have a matching `content/statuses/<id>.json`, and every authored status must have a cell — both enforced by validation, so SIA-02 and SIA-06 become impossible to reintroduce.

### New API
```gdscript
class_name StatusIconAtlas

static func get_icon(status_id: String) -> AtlasTexture   # cached AtlasTexture into the shared source
static func has_icon(status_id: String) -> bool
static func icon_size() -> int                            # from the manifest, single source of truth
static func reload() -> void                              # clears the cache; called on manifest reload
```

`get_icon` returns an `AtlasTexture` whose `atlas` is the one shared `CompressedTexture2D` and whose `region` is `Rect2(col * 16, row * 16, 16, 16)`, so all statuses share a single GPU texture. The `fallback_color` parameter is removed: color lives in the authored pixels, which resolves SIA-03 by deleting the ambiguity rather than by threading the value through.

`icon_size()` replaces the duplicated literal in `combat_hud.gd:194` (SIA-08).

An id with no cell returns the `unknown` cell **and** calls `push_warning("status icon missing for id '%s'" % status_id)`, so an unauthored status is loud in the log and visually distinct on screen (SIA-09).

### Stacks, duration, polarity
The atlas stays a flat glyph; presentation composition moves to the `StatusPip` scene specified in [`combat_hud.md`](combat_hud.md): `Icon` (this atlas cell) + `DurationArc` (radial `TextureProgressBar`) + `StackLabel`. Polarity comes from the pip frame, driven by a new `"polarity"` key on the status definition (`"debuff"` or `"buff"`), which selects one of two 20×20 frame cells at `(6,5)` and `(7,4)` — a warm frame for buffs, a cold frame for debuffs (SIA-04).

### Colorblind variants
Add a second texture `apps/game/client/assets/ui/status_icons_cb.png` with the same grid and cell mapping, authored with distinct **shapes and values** rather than only distinct hues (solid vs. hollow vs. hatched fill), for the `protanopia` / `deuteranopia` / `tritanopia` modes. `get_icon` picks the source texture from `AccessibilitySettings.colorblind_mode`, and `reload()` is called when the mode changes so the cache does not serve stale variants (SIA-05, SIA-07).

Rejected alternative: recoloring the default texture per mode with a shader. Recoloring alone does not help protanopes distinguish the red `bleed` glyph from the orange `burn` glyph, because both collapse to similar values; different shapes do.

### Removal of the plotter
`_draw_glyph`, `_fill_circle`, `_fill_ring`, `_fill_diamond`, and `_fill_bolt` are deleted. Nothing outside this file calls them (grep for each name matches only `status_icon_atlas.gd`).

## Work plan
1. **Manifest and loader** — add `content/ui/status_icon_atlas.json` and `content/schemas/status-icon-atlas.v1.json`; add a manifest parser plus `icon_size()`, `has_icon()`, `reload()` to `status_icon_atlas.gd`, still falling back to the existing plotter when the texture is missing. Fix the `freeze` id at the same time by giving it a manifest cell (SIA-02, SIA-08).
2. **Authored art** — commit `assets/ui/status_icons.png` (128×96, 8×6 of 16×16) with the five authored statuses plus the `unknown` cell; switch `get_icon` to return `AtlasTexture` and delete the five plotter functions and the `fallback_color` parameter; update `combat_hud.gd:195-198` accordingly (SIA-01, SIA-03, SIA-06).
3. **Missing-icon diagnostics** — `push_warning` plus the `unknown` cell (SIA-09).
4. **Polarity** — add `"polarity"` to `content/schemas/status-definition.v1.json` and each status file; author the two frame cells; consume them in the `StatusPip` scene (SIA-04).
5. **Colorblind variants** — commit `status_icons_cb.png`; select the source texture from `AccessibilitySettings.colorblind_mode`; call `reload()` from the settings mode handler (SIA-05, SIA-07).

Step 1 lands with the old renderer intact, so the game stays runnable; step 2 flips the source of truth once the art exists.

## Data and schema changes
- New: `content/schemas/status-icon-atlas.v1.json` — requires `schemaVersion`, `texture`, `cellSize`, `columns`, `rows`, `cells`; each cell requires integer `col` and `row` within bounds; `additionalProperties: false`.
- New: `content/ui/status_icon_atlas.json` — the manifest above.
- `content/schemas/status-definition.v1.json`: add `"polarity": {"type": "string", "enum": ["buff", "debuff"]}`. `iconColor` (`status-definition.v1.json:18`) stays for damage-number tinting but is no longer read by the icon path; note that in the schema description.
- Each of `content/statuses/{burn,poison,stun,bleed,freeze}.json` gains `"polarity": "debuff"`.
- New assets: `assets/ui/status_icons.png`, `assets/ui/status_icons_cb.png`, both 128×96 with `.import` `filter=false`, `mipmaps=false`.
- No save-format change, so no `save_migrator.gd` bump.

## Acceptance criteria
- [ ] `content/ui/status_icon_atlas.json` validates against `content/schemas/status-icon-atlas.v1.json`.
- [ ] Every `content/statuses/*.json` id has a cell in the manifest, and every manifest cell id except `unknown` has a status file.
- [ ] `StatusIconAtlas.get_icon("freeze")` returns a distinct region from `get_icon("burn")` and from the `unknown` cell.
- [ ] `get_icon` returns an `AtlasTexture` and all five statuses share one `atlas` object.
- [ ] `status_icon_atlas.gd` contains no `set_pixel` call and no `_fill_` function.
- [ ] `get_icon` has no `fallback_color` parameter, and `combat_hud.gd` passes no color.
- [ ] `get_icon("not_a_status")` returns the `unknown` cell and emits a warning containing the id.
- [ ] `combat_hud.gd` sizes status icons from `StatusIconAtlas.icon_size()`, not from a literal.
- [ ] Setting `AccessibilitySettings.colorblind_mode = "deuteranopia"` and calling `reload()` makes `get_icon("burn").atlas.resource_path` end in `status_icons_cb.png`.
- [ ] Each status file declares `polarity`, and buff and debuff pips draw different frames.

## Validation
Extend `apps/game/client/scripts/validation/suites/content_suite.gd` (data integrity) and `m5_suite.gd` (HUD wiring):

| Test id | Suite | Assertion |
|---|---|---|
| `content.status_atlas_schema` | content | the manifest validates against `status-icon-atlas.v1.json` |
| `content.status_atlas_covers_all` | content | for every file in `content/statuses/`, `StatusIconAtlas.has_icon(id)` is `true` |
| `content.status_atlas_no_orphan_cells` | content | every manifest cell id except `unknown` has a `content/statuses/<id>.json` |
| `content.status_atlas_cells_in_bounds` | content | every `col < columns` and `row < rows`, and `columns * cellSize == texture.get_width()` |
| `content.status_polarity_present` | content | every status file declares `polarity` in `["buff", "debuff"]` |
| `ui.status_atlas_is_atlas` | m5 | `get_icon("burn") is AtlasTexture` and `get_icon("burn").atlas == get_icon("poison").atlas` |
| `ui.status_atlas_freeze_distinct` | m5 | `get_icon("freeze").region != get_icon("burn").region` and `!= unknown` region |
| `ui.status_atlas_no_plotter` | m5 | `ctx.file_contains("res://scripts/ui/status_icon_atlas.gd", "set_pixel") == false` |
| `ui.status_atlas_unknown_warns` | m5 | `has_icon("zzz") == false` and `get_icon("zzz").region` equals the `unknown` region |
| `ui.status_atlas_size_shared` | m5 | `combat_hud.gd` contains `StatusIconAtlas.icon_size()` and no `Vector2(22, 22)` |
| `ui.status_atlas_cb_variant` | m5 | with `colorblind_mode = "protanopia"` and after `reload()`, the atlas source path ends in `status_icons_cb.png` |

## Related
- Existing behavior: [`../existing_codebase/ui/status_icon_atlas.md`](../existing_codebase/ui/status_icon_atlas.md)
- Cross-system coordination: [`status_icons_glyphs.md`](status_icons_glyphs.md)
- [`combat_hud.md`](combat_hud.md) · [`input_glyphs.md`](input_glyphs.md) · [`game_ui_skin.md`](game_ui_skin.md)
- [`../../existing_codebase/statuses-and-buffs.md`](../../existing_codebase/statuses-and-buffs.md) · [`../accessibility.md`](../accessibility.md)
