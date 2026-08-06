# Game UI skin

`GameUISkin` is the shared styling layer for every menu, HUD, and overlay in the client. It exposes design tokens as `const` values, builds the global Godot `Theme` resource, and provides runtime helpers for modals, progress bars, and pixel-mode passes. It is on the live play path: every UI script under `apps/game/client/scripts/ui/` preloads it, including `quest_board_ui.gd` and `achievement_toast.gd`.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/ui/game_ui_skin.gd` | `class_name GameUISkin` â€” tokens, `build_theme()`, panel/backdrop factories, label variation helpers, `make_button`, `restyle_tree` |
| `apps/game/client/assets/ui/aumbrye_ui.tres` | Generated `Theme` registered as `gui/theme/custom` in `project.godot` |
| `apps/game/client/assets/ui/fonts/aumbrye_pixel.ttf` | Default UI font (Press Start 2P derivative, OFL) |
| `apps/game/client/assets/ui/paperdoll_silhouette.png` | 96Ã—160 px inventory paper-doll backdrop |
| `apps/game/client/scripts/tools/build_ui_theme.gd` | Headless exporter â€” regenerates `aumbrye_ui.tres` from `GameUISkin.build_theme()` |
| `apps/game/client/scripts/ui/menu_shell.gd` | Modal scaffold; `make_menu_button` delegates to `GameUISkin.make_button` |
| `apps/game/client/scripts/ui/inventory_ui_layout.gd` | Re-exports `INVENTORY_CELL_SIZE` / `INVENTORY_EQUIP_CELL_SIZE` / `GRID_GAP` |

## How it works

### Design tokens
Font-size ladder at `game_ui_skin.gd`:
`FONT_SIZE_TITLE` 22, `FONT_SIZE_HEADER` 16, `FONT_SIZE_BODY` 14, `FONT_SIZE_SMALL` 12, `FONT_SIZE_MICRO` 10.

Panel tokens: `PANEL_CORNER_RADIUS_HD` 8, `PANEL_CORNER_RADIUS_PIXEL` 0, `PANEL_SHADOW_SIZE_HD` 8, `PANEL_SHADOW_SIZE_PIXEL` 0, `PANEL_BORDER_WIDTH` 2, `FOCUS_RING_COLOR` `Color(0.95, 0.82, 0.40)`.

Color tokens unchanged: `TITLE_COLOR`, `BODY_COLOR`, `HINT_COLOR`, `FRAME_BG`, `FRAME_BORDER`, `DANGER_COLOR`, `STAT_DELTA_POSITIVE`, `STAT_DELTA_NEGATIVE`.

### Global theme
`build_theme()` assembles `aumbrye_ui.tres`: default font, panel styleboxes, button states (including `focus`), `ItemList`/`OptionButton`/`CheckBox`/`HSlider`/`LineEdit`/`ProgressBar`/`ScrollContainer` entries, and seven label `theme_type_variation` types:

| Variation | Font size | Color | Alignment |
|-----------|-----------|-------|-----------|
| `MenuTitle` | 22 | `TITLE_COLOR` | center |
| `SectionTitle` | 16 | `TITLE_COLOR` | center |
| `BodyText` | 14 | `BODY_COLOR` | left |
| `HintText` | 12 | `HINT_COLOR` | center |
| `StatValue` | 14 | `TITLE_COLOR` | left |
| `StatDelta` | 12 | green/red override | left |
| `DangerText` | 12 | `DANGER_COLOR` | left |

Every `Label` in `scenes/ui/*.tscn` sets `theme_type_variation` in the editor.

### Panel construction
- `make_panel_style()` branches on `is_pixel_ui()` â€” zero corner radius and shadow in pixel mode, HD radius 8 otherwise.
- `clamped_panel_half_size()` returns the requested half-size when `parent.get_viewport()` is null (pre-tree guard).
- `make_center_panel`, `make_section_frame`, `make_backdrop`, `ensure_backdrop` unchanged in role.

### `apply_modal_menu`
`apply_modal_menu(root, panel_path, dimmer_path, fallback_panel_path)` ensures backdrop, calls `apply_pixel_theme`, styles the panel `PanelContainer`, and calls `wire_button_sfx` on every descendant `BaseButton`. It does **not** walk `Label` nodes.

### Runtime helpers
- `make_button(text, variation)` â€” creates a `Button`, optional `theme_type_variation`, always wires UI SFX.
- `style_*_label` helpers set `theme_type_variation` instead of imperative font overrides (accessibility subtitle scaling in `dialogue_ui.gd` still overrides size at runtime).
- `build_paperdoll_backdrop(parent, cell_size, gap)` â€” `TextureRect` with nearest filtering; falls back to deprecated `build_human_silhouette` with `push_warning` if the PNG is missing.
- `restyle_tree(root)` â€” re-applies `apply_pixel_theme` and `style_panel` on all `PanelContainer` descendants. Called from `PixelDioramaSettings.apply_all()` via `_restyle_ui_trees`.

### Pixel-mode handling
- `is_pixel_ui()` â€” `false` on native-HD preset, else `PixelDioramaSettings.low_res_viewport_enabled`.
- `apply_pixel_theme(root)` â€” sets `texture_filter` on root and descendant `Label`/`Button`/`ProgressBar` nodes.

## Contracts
- `section_content(frame)` requires the `content_vbox` meta from `make_section_frame`.
- `make_item_cell_style` depends on `RarityRegistry` color helpers.
- `wire_button_sfx` / `make_button` depend on `AudioDirector.play_ui_sfx()`.
- `is_pixel_ui` / `restyle_tree` depend on `PixelDioramaSettings` static state.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Design tokens as `const` | IMPLEMENTED | `game_ui_skin.gd` |
| Godot `Theme` resource | IMPLEMENTED | `assets/ui/aumbrye_ui.tres`, `project.godot` `[gui] theme/custom` |
| Authored UI font | IMPLEMENTED | `assets/ui/fonts/aumbrye_pixel.ttf` |
| Label `theme_type_variation` in scenes | IMPLEMENTED | every `Label` in `scenes/ui/*.tscn` |
| Paper-doll backdrop | IMPLEMENTED | `paperdoll_silhouette.png`, `build_paperdoll_backdrop` at `inventory_ui.gd:208` |
| Pixel-aware panel corners | IMPLEMENTED | `make_panel_style()` + `restyle_tree` |
| Tokenized font sizes | IMPLEMENTED | `FONT_SIZE_*`; dialogue/inventory/quest-tracker use constants |
| Button SFX coverage | IMPLEMENTED | `make_button`, `apply_modal_menu` BaseButton walk, `MenuShell.make_menu_button` |
| Focus ring styleboxes | IMPLEMENTED | `make_focus_style()` in theme for five control types |

## Related
- Improvement plan: [`../actual_improvements/ui/game_ui_skin.md`](../actual_improvements/ui/game_ui_skin.md) - **FINISHED**
- [`menu_shell.md`](menu_shell.md) Â· [`status_icon_atlas.md`](status_icon_atlas.md) Â· [`inventory_ui.md`](inventory_ui.md)
- [`../pixel-style.md`](../pixel-style.md) Â· [`../pixel-diorama-settings.md`](../pixel-diorama-settings.md)
