# Status icons and input glyphs — coordination improvement plan

## Current state
The two symbol systems in the client are entirely uncoordinated. `status_icon_atlas.gd` returns per-pixel-generated 22×22 `ImageTexture`s from a never-invalidated static cache; `input_glyph_service.gd` returns hardcoded English strings with no cache at all. They have no shared manifest, no shared cell size, no shared fallback policy, and no shared consumer helper, so `combat_hud.gd` renders nearest-filtered status textures at `:194-201` and antialiased glyph text at `:225-241` on the same screen. `inventory_ui.gd` adds a third vocabulary — Unicode characters in `Label`s (`:795-831`). See [`../existing_codebase/ui/status_icons_glyphs.md`](../existing_codebase/ui/status_icons_glyphs.md).

This plan owns only what the two systems must agree on. Per-system work lives in [`status_icon_atlas.md`](status_icon_atlas.md) and [`input_glyphs.md`](input_glyphs.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| SIG-01 | P0 | Two symbol families render with different filtering on the same frame: status icons are `TEXTURE_FILTER_NEAREST` textures, input prompts are default-font text. Nothing in the codebase can make them consistent because one has no texture path. | `combat_hud.gd:199` vs `:235-240`; `input_glyph_service.gd:26` returns `String` |
| SIG-02 | P0 | No shared atlas manifest schema, so each family invents its own lookup and neither can be validated for completeness against its data source. | `content/schemas/` contains 24 files, none icon- or glyph-related; no `content/ui/` directory exists |
| SIG-03 | P0 | Both families fail silently into a plausible-looking wrong symbol: an unauthored status becomes an anonymous circle, an unmapped action becomes the first letter of its name. A content gap is invisible in play and in the log. | `status_icon_atlas.gd:44-46`; `input_glyph_service.gd:78` |
| SIG-04 | P1 | No shared cell size, so a status pip and a button prompt placed side by side cannot align. `22` px is also not a power-of-two-friendly size for the `320×180` preset. | `status_icon_atlas.gd:6`; `combat_hud.gd:194` |
| SIG-05 | P1 | No shared "symbol + caption" builder, so every prompt row is hand-assembled and inconsistently styled (the HUD hint adds its own font shadow at `combat_hud.gd:232-234`; the inventory footer does not). | `combat_hud.gd:225-241`; `inventory_ui.gd:834-842` |
| SIG-06 | P1 | Neither family emits a change signal, so consumers cannot refresh when a device changes, a binding changes, or the colorblind mode changes. | neither file declares a `signal` |
| SIG-07 | P1 | Cache policies are opposite extremes — one never invalidates, one never caches — so a colorblind-mode change serves stale status textures while the inventory footer re-polls the joypad six times per cursor move. | `status_icon_atlas.gd:8`; `input_glyph_service.gd:27`; `inventory_ui.gd:835-842` via `_update_detail` at `:506` |
| SIG-08 | P2 | A third symbol vocabulary (Unicode item glyphs) exists in the inventory, outside either service. | `inventory_ui.gd:795-831` |

## Target design

### One shared atlas contract
Both families ship an authored PNG plus a JSON manifest that conform to a single base schema, `content/schemas/ui-symbol-atlas.v1.json`:

```json
{
  "schemaVersion": 1,
  "texture": "res://assets/ui/<name>.png",
  "cellSize": 16,
  "columns": <int>,
  "rows": <int>,
  "unknown": { "col": <int>, "row": <int> },
  "cells": { "<key>": { "col": <int>, "row": <int> } }
}
```

`status-icon-atlas.v1.json`, `input-glyph-atlas.v1.json`, and `item-icon-atlas.v1.json` all `$ref` this base and add only their own key-naming rule. Three concrete manifests:

| Manifest | Texture | Grid | Key namespace | Owner plan |
|---|---|---|---|---|
| `content/ui/status_icon_atlas.json` | `assets/ui/status_icons.png` 128×96 | 8×6 of 16 px | status id from `content/statuses/*.json` | [`status_icon_atlas.md`](status_icon_atlas.md) |
| `content/ui/input_glyph_atlas.json` | `assets/ui/input_glyphs.png` 256×128 | 16×8 of 16 px | `<family>/<key-or-button-index>` | [`input_glyphs.md`](input_glyphs.md) |
| `content/ui/item_icon_atlas.json` | `assets/ui/item_icons.png` 256×256 | 16×16 of 16 px | item id from `content/items/**` | [`inventory_ui.md`](inventory_ui.md) |

**`cellSize` is 16 for all three.** 16 px is an exact 1:1 pixel match at the `320×180` render preset and scales by whole integers at every larger preset, which the current `22` px cannot do (SIG-04).

### Shared loader
New file `apps/game/client/scripts/ui/ui_symbol_atlas.gd`:

```gdscript
class_name UISymbolAtlas
extends RefCounted

static func load_manifest(manifest_path: String) -> UISymbolAtlas
func has_cell(key: String) -> bool
func cell(key: String) -> AtlasTexture          # unknown cell + push_warning when missing
func cell_size() -> int
func keys() -> PackedStringArray                # for validation coverage checks
func invalidate() -> void
```

One `AtlasTexture` instance is cached per key per atlas, and every atlas shares one `atlas` source texture, so the whole UI symbol set costs three GPU textures. `invalidate()` is the single hook the colorblind-mode handler and the rebind handler call, replacing "never invalidate" and "never cache" with one policy (SIG-02, SIG-07).

`cell()` on a missing key returns the manifest's `unknown` region and calls `push_warning("ui symbol atlas '%s' has no cell for key '%s'")`. The `unknown` cell is authored as a magenta-and-black checkerboard so a content gap is unmistakable on screen as well as in the log (SIG-03).

Rejected alternative: one giant combined atlas for all three families. Item icons will grow to hundreds of cells on their own schedule; splitting by family keeps each PNG reviewable and lets the three plans land independently.

### Shared presentation helpers
Add to `game_ui_skin.gd`:

```gdscript
static func make_symbol_rect(tex: AtlasTexture, size_px: int) -> TextureRect
static func make_symbol_caption_row(tex: AtlasTexture, caption: String, size_px: int) -> HBoxContainer
static func make_symbol_badge(tex: AtlasTexture, stacks: int, ratio: float) -> Control
```

- `make_symbol_rect` sets `texture_filter = TEXTURE_FILTER_NEAREST`, `expand_mode = EXPAND_IGNORE_SIZE`, `stretch_mode = STRETCH_KEEP_ASPECT_CENTERED`, `custom_minimum_size = Vector2i(size_px, size_px)`, and `MOUSE_FILTER_IGNORE`.
- `make_symbol_caption_row` pairs it with a `Label` at `theme_type_variation = "HintText"`, separation `4`, `ALIGNMENT_CENTER`.
- `make_symbol_badge` is the `StatusPip` composition (icon + radial duration + stack count) described in [`combat_hud.md`](combat_hud.md).

Every symbol on screen goes through one of these three, which is what makes SIG-01 and SIG-05 structurally impossible to reintroduce. `size_px` defaults to `UISymbolAtlas.cell_size()` so callers never hardcode `22` again.

### Shared change notification
A single autoload, `UISymbolBus` (`apps/game/client/scripts/ui/ui_symbol_bus.gd`), emits:

```gdscript
signal symbols_invalidated(reason: StringName)   # &"device", &"rebind", &"colorblind", &"preset"
```

`InputGlyphWatcher` emits `&"device"` and `&"rebind"`; the settings colorblind handler emits `&"colorblind"`; `PixelDioramaSettings.save_and_apply()` emits `&"preset"`. Consumers connect once and rebuild their symbol rows. `combat_hud.gd` connects it for both the status row and the controls hint; `inventory_ui.gd` connects it for the footer (SIG-06).

### Unicode retirement
The `_item_glyph` / `_slot_glyph_for_label` Unicode tables in `inventory_ui.gd:795-831` are replaced by `item_icon_atlas.json` lookups keyed on item id, with the equipment-slot empty-cell art keyed as `slot/<slot_name>`. Details and the `iconPath` data work are in [`inventory_ui.md`](inventory_ui.md); this plan only fixes the shared contract they must use (SIG-08).

## Work plan
1. **Base schema** — add `content/schemas/ui-symbol-atlas.v1.json` (SIG-02).
2. **Shared loader** — add `ui_symbol_atlas.gd` with the API above, the per-key `AtlasTexture` cache, the `unknown`-cell warning, and `invalidate()` (SIG-02, SIG-03, SIG-07).
3. **Shared bus** — add `ui_symbol_bus.gd`, register it in `project.godot` `[autoload]` (SIG-06).
4. **Skin helpers** — add `make_symbol_rect`, `make_symbol_caption_row`, `make_symbol_badge` to `game_ui_skin.gd` (SIG-01, SIG-04, SIG-05).
5. **Status atlas onto the shared path** — `status_icon_atlas.gd` becomes a thin wrapper over `UISymbolAtlas` (executed in [`status_icon_atlas.md`](status_icon_atlas.md) step 2).
6. **Glyph atlas onto the shared path** — `input_glyph_service.gd` resolves textures through `UISymbolAtlas` and emits `&"device"` / `&"rebind"` on the bus (executed in [`input_glyphs.md`](input_glyphs.md) step 4).
7. **Consumer conversion** — `combat_hud.gd` and `inventory_ui.gd` build every symbol through the three skin helpers and connect `symbols_invalidated` (SIG-01, SIG-05, SIG-06).
8. **Item atlas onto the shared path** — retire the Unicode tables (executed in [`inventory_ui.md`](inventory_ui.md)) (SIG-08).

Steps 1-4 are pure additions and leave the game byte-identical at runtime; steps 5-8 flip each consumer over one at a time.

## Data and schema changes
- New: `content/schemas/ui-symbol-atlas.v1.json` (base), plus `status-icon-atlas.v1.json`, `input-glyph-atlas.v1.json`, `item-icon-atlas.v1.json` that `$ref` it.
- New: `content/ui/` directory holding the three manifests.
- New assets: `assets/ui/status_icons.png` (128×96), `assets/ui/input_glyphs.png` (256×128), `assets/ui/item_icons.png` (256×256), all `cellSize` 16, `.import` with `filter=false`, `mipmaps=false`, lossless compression.
- `apps/game/client/project.godot`: add `UISymbolBus` and `InputGlyphWatcher` under `[autoload]`.
- No save-format change; no `save_migrator.gd` bump.

## Acceptance criteria
- [ ] All three manifests validate against `ui-symbol-atlas.v1.json` and report `cellSize == 16`.
- [ ] `UISymbolAtlas.cell()` returns an `AtlasTexture`, and all cells from one manifest share a single `atlas` object.
- [ ] A missing key returns the `unknown` cell and emits a warning naming both the atlas and the key.
- [ ] The `unknown` cell is visually distinct from every authored cell in all three atlases.
- [ ] No file under `apps/game/client/scripts/ui/` sets `texture_filter` on a symbol directly; all go through `make_symbol_rect`.
- [ ] No file under `apps/game/client/scripts/ui/` contains the literal `Vector2(22, 22)`.
- [ ] Every symbol-plus-caption row in the combat HUD and inventory footer is produced by `make_symbol_caption_row`.
- [ ] Changing `AccessibilitySettings.colorblind_mode` emits `symbols_invalidated(&"colorblind")` and the status row rebuilds within one frame.
- [ ] Rebinding an action emits `symbols_invalidated(&"rebind")` and the inventory footer rebuilds.
- [ ] `input_glyph_service.gd` no longer calls `Input.get_connected_joypads()` from `get_action_glyph*`.
- [ ] `inventory_ui.gd` contains no non-ASCII character in a `return` statement.

## Validation
New suite `apps/game/client/scripts/validation/suites/ui_symbol_suite.gd`, category `ui_symbols`:

| Test id | Assertion |
|---|---|
| `ui_symbols.manifests_validate` | each of the three manifests validates against its schema and against the base |
| `ui_symbols.uniform_cell_size` | all three manifests report `cellSize == 16` |
| `ui_symbols.grid_matches_texture` | for each manifest, `columns * cellSize == texture.get_width()` and `rows * cellSize == texture.get_height()` |
| `ui_symbols.cells_in_bounds` | every cell and the `unknown` cell satisfy `col < columns` and `row < rows` |
| `ui_symbols.status_coverage` | every id in `content/statuses/*.json` has a status-atlas cell |
| `ui_symbols.action_coverage` | every action in `InputMap.get_actions()` with a bound event resolves to a glyph cell on every `DeviceFamily` |
| `ui_symbols.item_coverage` | every id in `content/items/catalog.json` has an item-atlas cell |
| `ui_symbols.shared_atlas_object` | `UISymbolAtlas.cell("burn").atlas == UISymbolAtlas.cell("poison").atlas` for the status atlas |
| `ui_symbols.unknown_warns` | requesting an absent key returns the `unknown` region and produces a warning |
| `ui_symbols.unknown_is_distinct` | the `unknown` region differs from every authored region in the same atlas |
| `ui_symbols.helpers_used` | `combat_hud.gd` and `inventory_ui.gd` contain no `texture_filter =` assignment and no `Vector2(22, 22)` |
| `ui_symbols.bus_registered` | `Engine.has_singleton`-equivalent lookup finds `UISymbolBus`, and it declares `symbols_invalidated` |
| `ui_symbols.invalidate_on_colorblind` | setting the colorblind mode emits `symbols_invalidated` with `&"colorblind"` |
| `ui_symbols.invalidate_on_rebind` | rebinding an action emits `symbols_invalidated` with `&"rebind"` |
| `ui_symbols.no_unicode_glyphs` | `inventory_ui.gd` matches no non-ASCII code point on a `return` line |

## Related
- Per-system plans: [`status_icon_atlas.md`](status_icon_atlas.md) · [`input_glyphs.md`](input_glyphs.md) · [`inventory_ui.md`](inventory_ui.md)
- Existing behavior: [`../existing_codebase/ui/status_icons_glyphs.md`](../existing_codebase/ui/status_icons_glyphs.md)
- [`game_ui_skin.md`](game_ui_skin.md) · [`combat_hud.md`](combat_hud.md) · [`../accessibility.md`](../accessibility.md)
