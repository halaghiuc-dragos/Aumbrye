# Game UI skin

`GameUISkin` is the only shared styling layer for every menu, HUD, and overlay in the client. It is a `RefCounted` class of static helpers, not a Godot `Theme` resource, so styling is applied imperatively per control at runtime. It is on the live play path: every UI script under `apps/game/client/scripts/ui/` except `quest_board_ui.gd`, `achievement_toast.gd`, and `waves_inventory_ui.gd` preloads it.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/ui/game_ui_skin.gd` | `class_name GameUISkin` — colors, sizes, panel/backdrop factories, label stylers, progress-bar styler, item-cell styler, pixel-filter pass |
| `apps/game/client/scripts/ui/menu_shell.gd` | `class_name MenuShell` — builds modals on top of the skin (see [`menu_shell.md`](menu_shell.md)) |
| `apps/game/client/scripts/ui/inventory_ui_layout.gd` | Re-exports `INVENTORY_CELL_SIZE` / `INVENTORY_EQUIP_CELL_SIZE` / `GRID_GAP` as `CELL_SIZE` / `EQUIP_CELL_SIZE` / `GRID_GAP` |

## How it works

### Design tokens
All tokens are `const` at `game_ui_skin.gd:6-40`:

| Token | Value | Used by |
|-------|-------|---------|
| `BACKDROP_COLOR` | `Color(0.01, 0.01, 0.04, 0.78)` | `make_backdrop`, `ensure_backdrop`, `apply_modal_menu` |
| `PANEL_HALF_W` / `PANEL_HALF_H` | `580.0` / `360.0` | default `make_center_panel` size |
| `SETTINGS_HALF_W` / `SETTINGS_HALF_H` | `340.0` / `300.0` | `settings_ui.gd:38-39` (each with a hardcoded `+80.0` / `+40.0`) |
| `MENU_HALF_W` / `MENU_HALF_H` | `260.0` / `150.0` | `menu_shell.gd:15-16`, `pause_menu.gd:56-57`, `stair_menu.gd:45` |
| `PANEL_MARGIN` | `18` | panel stylebox content margin, `MenuShell.build_modal` margins |
| `SECTION_SEPARATION` | `22` | `inventory_ui.gd:144` |
| `GRID_GAP` | `4` | inventory grid separation |
| `HEADER_FONT_SIZE` / `TITLE_FONT_SIZE` / `HINT_FONT_SIZE` | `16` / `22` / `12` | `style_section_title`, `style_menu_title`, `style_hint_label` |
| `TITLE_COLOR` / `BODY_COLOR` / `HINT_COLOR` | `(0.92,0.86,0.72)` / `(0.82,0.78,0.72)` / `(0.68,0.68,0.74)` | label stylers |
| `ACCENT_BAR` / `FRAME_BG` / `FRAME_BORDER` | `(0.72,0.58,0.32,0.9)` / `(0.06,0.06,0.09,0.97)` / `(0.42,0.36,0.28)` | `make_section_frame`, `make_panel_style` |
| `SILHOUETTE_COLOR` | `Color(0.14, 0.13, 0.17, 0.55)` | `build_human_silhouette` |
| `CELL_SIZE` / `EQUIP_CELL_SIZE` | `56` / `64` | declared but never read outside this file |
| `INVENTORY_CELL_SIZE` / `INVENTORY_EQUIP_CELL_SIZE` | `64` / `82` | `inventory_ui_layout.gd:8-9` |
| `PIXEL_BAR_STEPS` | `8` | `style_progress_bar` quantizes `bar.step` to `max_value / 8` in pixel mode |

There is no `Theme` resource, no `theme_override` defined in an editor `.tres`, and no `gui/theme/custom` entry in `apps/game/client/project.godot`. `ABSENT` — searched `apps/game/client/**/*.tres` (all 41 hits are `Material`/`AudioBusLayout`) and grepped `project.godot` for `gui/theme`.

### Panel construction
- `make_panel_style()` (`:54`) returns a `StyleBoxFlat`: `FRAME_BG` fill, `FRAME_BORDER` 2 px border, 8 px corner radius, `PANEL_MARGIN` content margin, 8 px black shadow at alpha `0.5`. The corner radius is not conditioned on pixel mode.
- `make_center_panel(parent, half_w, half_h, panel_name)` (`:82`) clamps the requested half-size through `clamped_panel_half_size` (`:74`), which caps each axis at `48 %` of `get_viewport().get_visible_rect().size`, then anchors `PRESET_CENTER` with symmetric offsets.
- `make_section_frame(title)` (`:103`) builds `PanelContainer > MarginContainer > VBoxContainer`, prepends a centered header row of `ColorRect(36×3, ACCENT_BAR) + Label(title.to_upper()) + ColorRect(36×3, ACCENT_BAR)`, and stores the content `VBoxContainer` in `frame.set_meta("content_vbox", vbox)`. Callers retrieve it with `section_content(frame)` (`:131`).
- `make_backdrop(parent, name)` (`:43`) adds a full-rect `ColorRect` with `MOUSE_FILTER_STOP` and `show_behind_parent = true`.
- `ensure_backdrop(root)` (`:165`) looks for a child named `Backdrop`, then `Dimmer`; if neither exists it creates one and calls `root.move_child(backdrop, 0)`.

### `apply_modal_menu`
`apply_modal_menu(root, panel_path = "MainPanel", dimmer_path = "Dimmer", fallback_panel_path = "Panel")` (`:179`) is the retrofit entry point for scene-authored menus. It calls `ensure_backdrop`, `apply_pixel_theme`, recolors any `dimmer_path` `ColorRect` to `BACKDROP_COLOR`, styles the panel, and then walks **every** descendant `Label` and picks a style by substring match on the node name (`:195-204`):

| `label.name.to_lower()` contains | Style applied |
|---|---|
| `title` | `style_menu_title` |
| `hint` | `style_hint_label` |
| `status` | `style_body_label` |

Labels whose names match none of the three keep the Godot default theme. Call sites: `loadout_ui.gd:26`, `merchant_ui.gd:26`, `blacksmith_ui.gd:24`, `storage_ui.gd:24`, `dialogue_ui.gd:24`, `results_screen.gd:18`, `castle_entry_menu.gd:32-33`, `umbral_waves_menu.gd:20`, `umbral_endless_menu.gd:30`.

### Label and bar stylers
- `style_section_title` (`:135`): centered, `HEADER_FONT_SIZE`, `TITLE_COLOR`.
- `style_menu_title` (`:143`): centered, `TITLE_FONT_SIZE`, `TITLE_COLOR`.
- `style_body_label` (`:151`): `BODY_COLOR`, hardcoded font size `14`, `AUTOWRAP_WORD_SMART`, and `clip_text = true`.
- `style_hint_label` (`:158`): `HINT_FONT_SIZE`, `HINT_COLOR`, centered, word-smart wrap.
- `style_progress_bar(bar, fill_color, bg_color)` (`:276`): hides the percentage, builds background and fill `StyleBoxFlat`s, and in pixel mode sets `texture_filter = TEXTURE_FILTER_NEAREST` and `bar.step = bar.max_value / 8`.
- `make_item_cell_style(rarity, filled)` (`:299`): background and border from `RarityRegistry.slot_background_color` / `display_color`, 2 px border, 5 px corner radius, 3 px rarity-tinted shadow when `filled`.

### Pixel-mode handling
- `is_pixel_ui()` (`:244`) returns `false` when `PixelDioramaSettings.is_native_hd_preset()`, otherwise `PixelDioramaSettings.low_res_viewport_enabled`.
- `apply_pixel_theme(root)` (`:250`) sets `texture_filter` on the root and on every descendant `Label`, `Button`, and `ProgressBar` — `TEXTURE_FILTER_NEAREST` in pixel mode, `TEXTURE_FILTER_LINEAR` on the native-HD preset. It returns early and touches nothing when neither condition holds.

### Procedural silhouette
`build_human_silhouette(parent, cell_size, gap, scale)` (`:207`) adds a `Control` named `Silhouette` with `MOUSE_FILTER_IGNORE` and `show_behind_parent = true`, then six flat `ColorRect` blocks (head, torso, two arms, two legs) sized and positioned from `cell_size * scale`. Used by `inventory_ui.gd:210` behind the paper doll and `character_create_ui.gd:63` as the creation preview. No sprite, mesh, or texture is involved.

### Audio hook
`wire_button_sfx(button)` (`:234`) guards on the `&"ui_sfx_wired"` meta flag and connects `button.pressed` to `AudioDirector.play_ui_sfx()`. Applied by `MenuShell.make_menu_button` (`menu_shell.gd:75`) and manually at `settings_ui.gd:412,461`, `waves_run_ui.gd:83`. Buttons created with bare `Button.new()` — `stair_menu.gd:81-85`, `umbral_endless_menu.gd:97`, `blacksmith_ui.gd:27`, and every scene-authored button in `scenes/ui/*.tscn` — get no click sound.

## Contracts
- `section_content(frame)` requires the `content_vbox` meta set by `make_section_frame`; calling it on any other `PanelContainer` returns `null`.
- `apply_modal_menu` depends on node-name conventions: `MainPanel` or `Panel` for the frame, `Dimmer` or `Backdrop` for the scrim, and `*title*` / `*hint*` / `*status*` substrings on `Label` names.
- `make_item_cell_style` depends on `apps/game/client/scripts/loot/rarity_registry.gd` accepting the rarity string; unknown strings fall through to that file's defaults.
- `is_pixel_ui` / `apply_pixel_theme` depend on the `PixelDioramaSettings` autoload.
- `wire_button_sfx` depends on the `AudioDirector` autoload exposing `play_ui_sfx()`.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Design tokens as `const` in one file | IMPLEMENTED | `game_ui_skin.gd:6-40` |
| Godot `Theme` resource shared by all controls | ABSENT | no `Theme` `.tres` in `apps/game/client`; no `gui/theme` key in `project.godot` |
| Authored UI font | ABSENT | `apps/game/client/**/*.{ttf,otf,fnt}` returns 0 files |
| Any authored raster art for UI | ABSENT | `apps/game/client/**/*.png` returns 0 files |
| `apply_modal_menu` label styling | PARTIAL — matches only `title`/`hint`/`status` substrings, so `SpeakerLabel`, `TextLabel`, `DetailLabel`, `GoldLabel`, `LootLabel`, `KillsLabel`, `TimeLabel`, `XpLabel`, `RulesLabel` stay unstyled | `game_ui_skin.gd:195-204` vs `scenes/ui/dialogue_ui.tscn:39-53`, `scenes/ui/results_screen.tscn:45-64` |
| `build_human_silhouette` paper-doll art | PLACEHOLDER — six `ColorRect` blocks | `game_ui_skin.gd:218-231` |
| `CELL_SIZE` / `EQUIP_CELL_SIZE` | STUB — declared, no reader outside this file | `game_ui_skin.gd:30-31` |
| Panel corner radius in pixel mode | PARTIAL — `make_panel_style` always uses radius `8`, unlike `style_progress_bar` which zeroes radius in pixel mode | `game_ui_skin.gd:59` vs `:279-280` |
| Font sizes routed through tokens | PARTIAL — `style_body_label` hardcodes `14`; `combat_hud.gd`, `dialogue_ui.gd`, `inventory_ui.gd` set their own sizes | `game_ui_skin.gd:153`, `dialogue_ui.gd:80-81`, `inventory_ui.gd:348,356,362` |
| Button SFX coverage | PARTIAL — bare `Button.new()` call sites are silent | `stair_menu.gd:81-85`, `umbral_endless_menu.gd:97`, `blacksmith_ui.gd:27` |

## Related
- Improvement plan: [`../actual_improvements/ui/game_ui_skin.md`](../actual_improvements/ui/game_ui_skin.md)
- [`menu_shell.md`](menu_shell.md) · [`status_icon_atlas.md`](status_icon_atlas.md) · [`inventory_ui.md`](inventory_ui.md)
- [`../pixel-style.md`](../pixel-style.md) · [`../pixel-diorama-settings.md`](../pixel-diorama-settings.md)
