# Status icon atlas

## Status: FINISHED

`StatusIconAtlas` loads authored 16×16 cells from `content/ui/status_icon_atlas.json` and `assets/ui/status_icons.png` through `UISymbolAtlas`. Colorblind mode selects `status_icons_cb.png`; polarity frames drive `StatusPip` borders. Procedural plotter removed.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/ui/status_icon_atlas.gd` | Thin wrapper over `UISymbolAtlas`; `get_icon`, `reload`, `get_polarity_frame` |
| `apps/game/client/scripts/ui/ui_symbol_atlas.gd` | Shared manifest loader and per-key `AtlasTexture` cache |
| `content/ui/status_icon_atlas.json` | Cell map (`burn`, `poison`, `freeze`, `stun`, `bleed`, `unknown`, polarity frames) |
| `content/schemas/status-icon-atlas.v1.json` | Schema for the manifest |
| `assets/ui/status_icons.png` | 128×96, 8×6 grid of 16 px cells |
| `assets/ui/status_icons_cb.png` | Colorblind variant (same grid) |
| `apps/game/client/scripts/ui/combat_hud.gd` | Status row via `StatusIconAtlas.icon_size()` and `StatusPip` |
| `apps/game/client/scripts/validation/suites/status_icon_atlas_suite.gd` | Atlas schema, coverage, CB variant, polarity |

## How it works

`get_icon(status_id)` (`status_icon_atlas.gd:15`) ensures the manifest is loaded, warns and returns the `unknown` cell when `status_id` is absent (`:19-21`). `_colorblind_texture_path()` reads `AccessibilitySettings.colorblind_mode` and swaps to `status_icons_cb.png` for protanopia/deuteranopia/tritanopia (`:53-57`). `reload()` clears the loader cache when `UISymbolBus` emits `colorblind` or `preset` (`ui_symbol_bus.gd:24-33`).

`get_polarity_frame(polarity)` maps `buff` / `debuff` to manifest keys `frame_buff` / `frame_debuff` (`status_icon_atlas.gd:25-27`). `combat_hud.gd` passes `def.polarity` into `StatusPip.setup`.

`icon_size()` returns manifest `cellSize` (16); combat HUD sizes icons from this constant — no `Vector2(22, 22)` literal.

## Contracts

- Public API: `get_icon(String) -> AtlasTexture`, `has_icon`, `icon_size()`, `reload()`, `get_polarity_frame`.
- Every `content/statuses/*.json` id must have a manifest cell; `iconColor` is for damage tinting only, not icon drawing.
- Missing ids: `push_warning` + `unknown` cell region.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Authored atlas art (SIA-01) | IMPLEMENTED | `status_icons.png`, `UISymbolAtlas` |
| `freeze` distinct cell (SIA-02) | IMPLEMENTED | manifest `freeze` col 2 |
| `iconColor` in icon path (SIA-03) | IMPLEMENTED — removed; colors are in pixels | no `fallback_color` param |
| Polarity frames (SIA-04) | IMPLEMENTED | `get_polarity_frame`, `status_pip.gd` |
| Colorblind variant (SIA-05) | IMPLEMENTED | `status_icons_cb.png`, `reload()` on mode change |
| Dead match arms (SIA-06) | IMPLEMENTED — plotter deleted | no `_fill_` functions |
| Cache invalidation (SIA-07) | IMPLEMENTED | `reload()` + `UISymbolBus` |
| Shared icon size (SIA-08) | IMPLEMENTED | `icon_size()`, `combat_hud.gd` |
| Missing-icon diagnostics (SIA-09) | IMPLEMENTED | `push_warning`, `unknown` cell |

## Related

- Improvement plan: [`../actual_improvements/ui/status_icon_atlas.md`](../actual_improvements/ui/status_icon_atlas.md) - **FINISHED**
- [`status_icons_glyphs.md`](status_icons_glyphs.md), [`combat_hud.md`](combat_hud.md), [`../statuses-and-buffs.md`](../statuses-and-buffs.md)
