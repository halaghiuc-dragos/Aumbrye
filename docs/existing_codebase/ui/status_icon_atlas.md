# Status icon atlas

Despite the name, `StatusIconAtlas` is not an atlas: it is a procedural per-pixel image generator that builds one 22×22 `ImageTexture` per status id at runtime and caches it in a static dictionary. It is on the live play path — it is the sole source of status icon art in the combat HUD.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/ui/status_icon_atlas.gd` | `class_name StatusIconAtlas` — 93 lines, whole generator |
| `apps/game/client/scripts/ui/combat_hud.gd:195-198` | only caller of `get_icon` |
| `content/statuses/{burn,poison,stun,bleed,freeze}.json` | the five authored status definitions, each supplying `iconColor` |

## How it works

### Cache and entry point
`get_icon(status_id, fallback_color = Color.WHITE)` (`status_icon_atlas.gd:11`) returns `_cache[status_id]` when present. Otherwise it creates a transparent `Image` of `ICON_SIZE = 22` square in `FORMAT_RGBA8`, computes `center = (11, 11)` and `radius = 22 * 0.42 = 9.24`, calls `_draw_glyph`, wraps the result with `ImageTexture.create_from_image`, and stores it.

`_cache` is `static var` (`:8`), so it persists for the process lifetime across scene changes and is never invalidated — including when the pixel-diorama resolution preset changes.

### Glyph table
`_draw_glyph` (`:24`) is a `match` on the raw status id string:

| `status_id` | Drawing | Colors (hardcoded, `iconColor` ignored) |
|---|---|---|
| `burn` | filled circle r `9.24` + inner circle r `3.23` | `(1.0, 0.45, 0.1)` / `(1.0, 0.9, 0.3)` |
| `poison`, `venom` | filled circle r `9.24` + ring `5.08`→`6.93` | `(0.35, 0.9, 0.25)` / `(0.1, 0.35, 0.1)` |
| `frost`, `chill` | filled diamond r `9.24` | `(0.55, 0.85, 1.0)` |
| `stun`, `shock` | 6-point bolt polygon | `(1.0, 0.92, 0.2)` |
| `bleed` | filled circle r `9.24` | `(0.85, 0.12, 0.12)` |
| anything else | filled circle r `9.24` in `fallback_color` + ring `5.54`→`7.85` in `fallback_color.darkened(0.35)` | caller's `fallback_color` |

Only the default branch (`:44-46`) uses the `fallback_color` argument. Every named branch hardcodes its colors, so the `iconColor` values in `content/statuses/*.json` are read by `combat_hud.gd:196-197` and then discarded for `burn`, `poison`, `stun`, and `bleed`.

### Which status ids actually reach a named branch
`content/statuses/` contains exactly five definitions: `burn`, `poison`, `stun`, `bleed`, `freeze` (each verified by its `"id"` field, e.g. `content/statuses/freeze.json:2`). Mapping them against the `match`:

| Authored status id | Branch hit | Result |
|---|---|---|
| `burn` | `"burn"` | authored two-tone flame blob |
| `poison` | `"poison", "venom"` | authored green ringed blob |
| `stun` | `"stun", "shock"` | authored bolt |
| `bleed` | `"bleed"` | authored red circle |
| `freeze` | none — the frost branch matches `"frost"` and `"chill"`, not `"freeze"` | generic circle + ring in `#88ccff` |

The `venom`, `chill`, `frost`, and `shock` cases have no corresponding file under `content/statuses/`, so they are unreachable.

### Rasterizers
Four helpers write pixels one at a time over the full 22×22 grid, with no anti-aliasing and no dithering:
- `_fill_circle` (`:49`) — squared-distance test against `radius`.
- `_fill_ring` (`:59`) — squared-distance band between `inner` and `outer`.
- `_fill_diamond` (`:71`) — `abs(dx)/r + abs(dy)/r <= 1.0`.
- `_fill_bolt` (`:80`) — `Geometry2D.is_point_in_polygon` against a fixed 6-vertex `PackedVector2Array` derived from `center` and `radius`.

All four use pixel-center sampling (`float(x) + 0.5`).

## Contracts
- Public API: `static func get_icon(status_id: String, fallback_color: Color = Color.WHITE) -> Texture2D`. Never returns `null`.
- `ICON_SIZE = 22` must match the `custom_minimum_size` the HUD gives each icon `TextureRect` (`combat_hud.gd:194`); the two constants are independent and unenforced.
- Consumers are responsible for nearest filtering: `combat_hud.gd:199` sets `TEXTURE_FILTER_NEAREST` on each `TextureRect`; the generator does not set an import or filter hint.
- Status ids come from `content/statuses/*.json` via `StatusCatalog`; `iconColor` is read by the caller, not by this file.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Authored icon art | ABSENT — every glyph is generated per pixel at runtime; the repo contains zero `.png` (`apps/game/client/**/*.png` returns 0 files) | `status_icon_atlas.gd:14-21` |
| Texture atlas | ABSENT despite the class name — one standalone `ImageTexture` per status, no `AtlasTexture`, no grid | `status_icon_atlas.gd:8-21` |
| `freeze` icon | BROKEN — falls to the default branch because the match arm spells `frost`/`chill`; the only authored frost status renders as the generic circle-and-ring | `status_icon_atlas.gd:38` vs `content/statuses/freeze.json:2` |
| `iconColor` honored | PARTIAL — read at `combat_hud.gd:196-197` but discarded by every named branch | `status_icon_atlas.gd:32-43` |
| Dead match arms | STUB — `venom`, `chill`, `frost`, `shock` have no definition under `content/statuses/` | `status_icon_atlas.gd:35,38,41`; `content/statuses/` holds 5 files |
| Cache invalidation | ABSENT — `static var _cache` is never cleared, so icons survive resolution-preset changes and scene reloads | `status_icon_atlas.gd:8` |
| Stack / duration presentation | ABSENT — the texture is a flat glyph; the HUD carries stacks only in `tooltip_text` | `status_icon_atlas.gd:11-21`; `combat_hud.gd:202` |
| Buff versus debuff distinction | ABSENT — no border, frame, or tint conveys polarity | `status_icon_atlas.gd:24-46` |
| Icon size consistency check | ABSENT — `ICON_SIZE` and the HUD's `Vector2(22, 22)` are duplicated literals | `status_icon_atlas.gd:6`; `combat_hud.gd:194` |
| Colorblind support | ABSENT — colors are hardcoded and `AccessibilitySettings.colorblind_mode` is never consulted | `status_icon_atlas.gd:32-46`; grep `colorblind` finds no hit in this file |

## Related
- Improvement plan: [`../actual_improvements/ui/status_icon_atlas.md`](../actual_improvements/ui/status_icon_atlas.md)
- Coordination with input glyphs: [`../actual_improvements/ui/status_icons_glyphs.md`](../actual_improvements/ui/status_icons_glyphs.md)
- [`combat_hud.md`](combat_hud.md) · [`input_glyphs.md`](input_glyphs.md) · [`game_ui_skin.md`](game_ui_skin.md)
- [`../statuses-and-buffs.md`](../statuses-and-buffs.md) · [`../content-data.md`](../content-data.md)
