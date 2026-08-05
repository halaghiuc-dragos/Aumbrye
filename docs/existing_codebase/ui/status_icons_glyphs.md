# Status icons and input glyphs (coordination)

This topic covers what `status_icon_atlas.gd` and `input_glyph_service.gd` share, and what they do not. Both answer the question "what small symbol goes here?", both feed the combat HUD, and neither uses authored art. They are otherwise entirely uncoordinated: no common manifest, no common size, no common cache, no common fallback, and no shared consumer helper.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/ui/status_icon_atlas.gd` | procedurally draws a 22×22 `ImageTexture` per status id |
| `apps/game/client/scripts/ui/input_glyph_service.gd` | returns a short `String` per input action per device family |
| `apps/game/client/scripts/ui/combat_hud.gd:183-241` | the only file that consumes both — status row plus controls hint |
| `apps/game/client/scripts/ui/inventory_ui.gd:795-842` | consumes `input_glyph_service.gd`, and separately hardcodes its own Unicode item glyphs |
| `content/statuses/*.json` | supplies `iconColor` (5 files) |
| `apps/game/client/project.godot:81-299` | supplies the input action names the glyph service is asked about |

## How the two compare

| Dimension | `StatusIconAtlas` | `InputGlyphService` |
|---|---|---|
| Return type | `Texture2D` (`ImageTexture`) | `String` |
| Art source | per-pixel `Image.set_pixel` loops (`status_icon_atlas.gd:49-92`) | hardcoded string literals (`input_glyph_service.gd:67-114`) |
| Size | `ICON_SIZE = 22` (`:6`) | none — sized by the consuming `Label`'s font |
| Data-driven | partially: reads status id, ignores `iconColor` for named branches (`:32-43`) | not at all: never queries `InputMap` |
| Cache | `static var _cache: Dictionary`, never invalidated (`:8`) | none; `detect_family()` re-polls on every call (`:27`) |
| Variant axis | none | device family (`:6`) |
| Fallback | generic circle + ring in the caller's color (`:44-46`) | first character of the action name, or `A` / `Cross` / `Btn` (`:78,92,106,114`) |
| Fallback is distinguishable from a real value | no | no |
| Localization | not applicable (no text) | hardcoded English (`:39-60`) |
| Colorblind awareness | none | not applicable |
| Signal on change | none | none |

## Shared consumer: the combat HUD

`combat_hud.gd` uses both within 60 lines of each other, in two incompatible presentation modes:

- `_refresh_status_icons()` (`:183-203`) creates a `TextureRect` per status at `Vector2(22, 22)` with `texture_filter = TEXTURE_FILTER_NEAREST`, `EXPAND_IGNORE_SIZE`, `STRETCH_KEEP_ASPECT_CENTERED`, and puts the human-readable name and stack count into `tooltip_text` only.
- `_ensure_controls_hint()` (`:222-241`) creates a single `Label` whose text is four `format_action_hint` results joined by `"  |  "`, with a manual font-shadow override at `:232-234`.

So one symbol family renders as nearest-filtered textures and the other as antialiased default-font text on the same screen. There is no shared helper that produces "a symbol plus a caption" for either.

`inventory_ui.gd` compounds the split: it calls `InputGlyphService.get_action_glyph` for its footer (`:835-842`) while hardcoding a third symbol vocabulary — Unicode characters in `Label`s — for item types and equipment slots (`:795-831`).

## Contracts
- Both are `RefCounted` classes with only static members, consumed without instantiation.
- Neither declares a signal, so a consumer cannot be notified when the underlying symbol changes (status color edit, device change, rebind).
- `combat_hud.gd:194` duplicates `StatusIconAtlas.ICON_SIZE` as the literal `Vector2(22, 22)`.
- `combat_hud.gd:196-197` reads `iconColor` from the status definition and passes it as `fallback_color`; `status_icon_atlas.gd` uses it only in the default branch.
- No file in the repo defines a shared symbol-manifest schema. `ABSENT` — searched `content/schemas/` (24 files, none icon- or glyph-related) and `content/ui/` (does not exist).

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Shared symbol manifest or schema | ABSENT | `content/schemas/` has no icon/glyph schema; no `content/ui/` directory |
| Shared cell size or grid convention | ABSENT — `22` px textures versus font-sized text | `status_icon_atlas.gd:6`; `input_glyph_service.gd:26` |
| Shared cache and invalidation policy | ABSENT — one never-cleared dictionary versus no cache | `status_icon_atlas.gd:8`; `input_glyph_service.gd:27` |
| Shared "missing symbol" fallback that is visibly distinct | ABSENT — both silently substitute a plausible-looking value | `status_icon_atlas.gd:44-46`; `input_glyph_service.gd:78` |
| Shared consumer helper (symbol + caption row) | ABSENT — each consumer builds its own container | `combat_hud.gd:193-203` vs `:225-241` |
| Consistent filtering across symbol families | BROKEN — status textures are `TEXTURE_FILTER_NEAREST`, glyph text inherits the default font antialiasing | `combat_hud.gd:199`; `input_glyph_service.gd` returns text |
| Authored art in either family | ABSENT — `apps/game/client/**/*.png` returns 0 files | verified by glob |
| Third competing symbol vocabulary in the inventory | PARTIAL — Unicode `Label`s coexist with both services | `inventory_ui.gd:795-831` |
| Change notification | ABSENT in both | neither file declares a `signal` |

## Related
- Improvement plan: [`../actual_improvements/ui/status_icons_glyphs.md`](../actual_improvements/ui/status_icons_glyphs.md)
- Per-system docs: [`status_icon_atlas.md`](status_icon_atlas.md) · [`input_glyphs.md`](input_glyphs.md)
- Consumers: [`combat_hud.md`](combat_hud.md) · [`inventory_ui.md`](inventory_ui.md)
- [`game_ui_skin.md`](game_ui_skin.md) · [`../accessibility.md`](../accessibility.md) · [`../content-data.md`](../content-data.md)
