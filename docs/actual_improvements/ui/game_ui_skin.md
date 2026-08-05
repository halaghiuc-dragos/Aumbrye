# Game UI skin — improvement plan

## Current state
`game_ui_skin.gd` holds every UI design token as a `const` and applies them through static helpers that call `add_theme_*_override` on individual controls (`game_ui_skin.gd:135-176`, `:276-307`). There is no Godot `Theme` resource anywhere in `apps/game/client`, no UI font, and no `.png` in the entire client, so all UI art is either a `ColorRect` blockout or a Unicode character in a `Label`. `apply_modal_menu` retrofits scene-authored menus by substring-matching `Label` node names against `title` / `hint` / `status` (`game_ui_skin.gd:195-204`), which silently leaves most content labels on the Godot default theme. See [`../existing_codebase/ui/game_ui_skin.md`](../existing_codebase/ui/game_ui_skin.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| SKN-01 | P0 | No `Theme` resource: every control is styled by an imperative call, so any control created without a skin call renders in Godot's default gray. `quest_board_ui.gd` and `achievement_toast.gd` never call the skin at all. | `quest_board_ui.gd:1-23` has no `GameUISkinScript` const; `achievement_toast.gd:1-21`; no `Theme` `.tres` under `apps/game/client` |
| SKN-02 | P0 | Label styling is decided by node-name substring, so `SpeakerLabel`, `TextLabel`, `DetailLabel`, `GoldLabel`, `TimeLabel`, `KillsLabel`, `LootLabel`, `XpLabel`, `RulesLabel` are unstyled in shipping menus. | `game_ui_skin.gd:195-204`; `scenes/ui/dialogue_ui.tscn:39-46`; `scenes/ui/results_screen.tscn:45-64`; `scenes/ui/merchant_ui.tscn:44-58` |
| SKN-03 | P1 | No UI font asset: the pixel-diorama art direction is undercut by Godot's default sans-serif at every size. | `apps/game/client/**/*.{ttf,otf,fnt}` returns 0 files |
| SKN-04 | P1 | `build_human_silhouette` ships six `ColorRect` rectangles as the paper doll and the character-creation preview. | `game_ui_skin.gd:218-231`; consumed at `inventory_ui.gd:210`, `character_create_ui.gd:63` |
| SKN-05 | P1 | Panel styling ignores pixel mode: `make_panel_style` always sets corner radius `8` and an 8 px soft shadow, while `style_progress_bar` correctly zeroes radius when `is_pixel_ui()`. Rounded, blurred panels over a nearest-filtered viewport read as two different games. | `game_ui_skin.gd:59-62` vs `:279-286` |
| SKN-06 | P1 | Font sizes are not tokenized: `style_body_label` hardcodes `14`, and callers set their own sizes (`18`, `11`, `10`, `int(16 * subtitle_scale)`), so `AccessibilitySettings.subtitle_scale` affects dialogue only. | `game_ui_skin.gd:153`; `inventory_ui.gd:348,356,362`; `dialogue_ui.gd:80-81` |
| SKN-07 | P1 | `wire_button_sfx` is opt-in, so bare `Button.new()` call sites are silent while `MenuShell` buttons click. | silent: `stair_menu.gd:81-85`, `umbral_endless_menu.gd:97`, `blacksmith_ui.gd:27`, all `scenes/ui/*.tscn` buttons; wired: `menu_shell.gd:75` |
| SKN-08 | P2 | `CELL_SIZE` (`56`) and `EQUIP_CELL_SIZE` (`64`) are dead constants shadowed by `INVENTORY_CELL_SIZE` (`64`) and `INVENTORY_EQUIP_CELL_SIZE` (`82`). | `game_ui_skin.gd:30-35`; `inventory_ui_layout.gd:8-9` |
| SKN-09 | P2 | `clamped_panel_half_size` calls `parent.get_viewport()` with no null guard, so it hard-crashes if a modal is built before the control enters the tree. | `game_ui_skin.gd:74-79` |
| SKN-10 | P2 | No focus visual: no helper sets `theme_override_styles/focus`, so the focused control in any menu is indistinguishable from its neighbors. | grep `focus` in `apps/game/client/scripts/ui` returns only `grab_focus` / `focus_neighbor` / `focus_mode` |

## Target design

### A real `Theme` resource, tokens still in code
Ship `apps/game/client/assets/ui/aumbrye_ui.tres` (`type="Theme"`) and set `gui/theme/custom="res://assets/ui/aumbrye_ui.tres"` in `project.godot`. Every control then inherits correct styling on `add_child`, and skin helpers become *variant* selectors rather than the only source of style.

The `.tres` is generated, not hand-edited, so the constants in `game_ui_skin.gd` stay the single source of truth. Add `tools/build_ui_theme.gd` (a `SceneTree` script run headless) that reads the `GameUISkin` constants and writes the resource. Rejected alternative: authoring the `.tres` by hand in the editor — it would immediately drift from the constants that 20+ scripts already read.

Theme entries to emit:

| Theme item | Type | Value source |
|---|---|---|
| `Panel/styles/panel` | `StyleBoxFlat` | `make_panel_style()` |
| `PanelContainer/styles/panel` | `StyleBoxFlat` | `make_panel_style()` |
| `Label/colors/font_color` | `Color` | `BODY_COLOR` |
| `Label/font_sizes/font_size` | `int` | `FONT_SIZE_BODY` (new, `14`) |
| `Button/styles/{normal,hover,pressed,disabled,focus}` | `StyleBoxFlat` | new `make_button_style(state)` |
| `Button/colors/{font_color,font_hover_color,font_disabled_color}` | `Color` | `BODY_COLOR`, `TITLE_COLOR`, `BODY_COLOR.darkened(0.45)` |
| `ItemList/styles/{panel,focus,selected,cursor}` | `StyleBoxFlat` | new `make_list_style(state)` |
| `OptionButton`, `CheckBox`, `HSlider`, `LineEdit`, `ScrollContainer` | mixed | derived from the same tokens |
| `ProgressBar/styles/{background,fill}` | `StyleBoxFlat` | `style_progress_bar` bodies |
| default font | `FontFile` | `assets/ui/fonts/aumbrye_pixel.ttf` |

### Named theme variations instead of name-substring matching
Replace the `apply_modal_menu` label walk with explicit `theme_type_variation` names, registered in the same `.tres`:

| Variation | Replaces | Tokens |
|---|---|---|
| `MenuTitle` | `style_menu_title` | `TITLE_FONT_SIZE` 22, `TITLE_COLOR`, centered |
| `SectionTitle` | `style_section_title` | `HEADER_FONT_SIZE` 16, `TITLE_COLOR`, centered |
| `BodyText` | `style_body_label` | `FONT_SIZE_BODY` 14, `BODY_COLOR` |
| `HintText` | `style_hint_label` | `HINT_FONT_SIZE` 12, `HINT_COLOR`, centered |
| `StatValue` | new | `FONT_SIZE_BODY`, `TITLE_COLOR`, tabular alignment |
| `StatDelta` | `_compare_label` inline color at `inventory_ui.gd:191` | `FONT_SIZE_SMALL` 12, green/red by sign |
| `DangerText` | `_name_error` inline color at `character_create_ui.gd:57` | `FONT_SIZE_SMALL`, `Color(0.95,0.45,0.35)` |

Set `theme_type_variation` in the `.tscn` files, so a designer opening `scenes/ui/results_screen.tscn` sees the shipped look in the editor. `apply_modal_menu` keeps only its scrim + panel + pixel-filter duties and stops walking labels.

### Pixel-aware styleboxes
Add `PANEL_CORNER_RADIUS_HD := 8`, `PANEL_CORNER_RADIUS_PIXEL := 0`, `PANEL_SHADOW_SIZE_HD := 8`, `PANEL_SHADOW_SIZE_PIXEL := 0`, `PANEL_BORDER_WIDTH := 2`. `make_panel_style()` branches on `is_pixel_ui()` exactly as `style_progress_bar` already does. Because the preset can change at runtime (`settings_ui.gd:226-243`), add:

```gdscript
static func restyle_tree(root: Control) -> void  # re-applies panel + bar styles and texture_filter
```

and call it from `PixelDioramaSettings.save_and_apply()`'s existing notification path for every `Control` in `get_tree().root`.

### Font
Add one bitmap-friendly pixel font at `apps/game/client/assets/ui/fonts/aumbrye_pixel.ttf` with `.import` settings `antialiasing=0`, `hinting=0`, `subpixel_positioning=0`, `multichannel_signed_distance_field=false`. Declare the design size ladder as constants and use only these five sizes so glyphs land on whole pixels:

`FONT_SIZE_TITLE := 22`, `FONT_SIZE_HEADER := 16`, `FONT_SIZE_BODY := 14`, `FONT_SIZE_SMALL := 12`, `FONT_SIZE_MICRO := 10`.

### Authored paper-doll art
Replace `build_human_silhouette` with a single authored texture `apps/game/client/assets/ui/paperdoll_silhouette.png`, 96×160 px, drawn in the `PaletteTheme.HUB` ramp (`pixel_diorama_style.gd:25-37`), `SILHOUETTE_COLOR` as the darkest value. New API:

```gdscript
static func build_paperdoll_backdrop(parent: Control, cell_size: int, gap: int) -> TextureRect
```

`TextureRect` with `texture_filter = TEXTURE_FILTER_NEAREST`, `stretch_mode = STRETCH_KEEP_ASPECT_CENTERED`, `MOUSE_FILTER_IGNORE`, `show_behind_parent = true`. Keep the old function as a fallback for one release, logging `push_warning` when the texture is missing.

### Focus visual
Add `FOCUS_RING_COLOR := Color(0.95, 0.82, 0.40)` and emit `Button/styles/focus`, `ItemList/styles/focus`, `OptionButton/styles/focus`, `CheckBox/styles/focus`, `LineEdit/styles/focus` as a `StyleBoxFlat` with a 2 px `FOCUS_RING_COLOR` border, transparent fill, and zero corner radius in pixel mode. This is the prerequisite for the focus work in [`menu_shell_a11y.md`](menu_shell_a11y.md).

### Unconditional button audio
Add:

```gdscript
static func make_button(text: String, variation: StringName = &"") -> Button
```

which creates the button, sets `theme_type_variation`, and calls `wire_button_sfx`. Convert every bare `Button.new()` in `apps/game/client/scripts/ui/` to it, and have `apply_modal_menu` call `wire_button_sfx` on every descendant `BaseButton` so scene-authored buttons are covered too.

## Work plan
1. **Tokenize** — add `FONT_SIZE_*`, `PANEL_CORNER_RADIUS_*`, `PANEL_SHADOW_SIZE_*`, `PANEL_BORDER_WIDTH`, `FOCUS_RING_COLOR` to `game_ui_skin.gd`; delete dead `CELL_SIZE` / `EQUIP_CELL_SIZE` (SKN-08); replace hardcoded `14` in `style_body_label` (SKN-06). Add the null guard in `clamped_panel_half_size` (SKN-09).
2. **Pixel-aware panels** — branch `make_panel_style()` on `is_pixel_ui()`; add `restyle_tree` and wire it to the settings apply path (SKN-05).
3. **Font** — import `aumbrye_pixel.ttf`, set it as the theme default font (SKN-03).
4. **Theme generator** — add `tools/build_ui_theme.gd`, generate `assets/ui/aumbrye_ui.tres`, set `gui/theme/custom` in `project.godot` (SKN-01).
5. **Variations** — add the seven `theme_type_variation` entries; convert `style_*_label` helpers into thin wrappers that set `theme_type_variation`; set the variation in each `scenes/ui/*.tscn`; remove the label walk from `apply_modal_menu` (SKN-02).
6. **Focus ring** — emit focus styleboxes for all five control classes (SKN-10).
7. **Audio + factory** — add `make_button`, convert bare `Button.new()` sites, extend `apply_modal_menu` to wire scene buttons (SKN-07).
8. **Paper doll** — author `paperdoll_silhouette.png`, add `build_paperdoll_backdrop`, repoint `inventory_ui.gd:210` and `character_create_ui.gd:63` (SKN-04).

Each step leaves the game runnable: steps 1-3 are additive, step 4 only adds a default that step 5 then relies on, and steps 6-8 are independent.

## Data and schema changes
No JSON schema under `content/schemas/` changes. No save-format change, so no `save_migrator.gd` version bump.

New resources committed:
- `apps/game/client/assets/ui/aumbrye_ui.tres` (generated `Theme`)
- `apps/game/client/assets/ui/fonts/aumbrye_pixel.ttf` + `.import`
- `apps/game/client/assets/ui/paperdoll_silhouette.png` + `.import` (`filter=false`, `mipmaps=false`)

`project.godot` gains `gui/theme/custom` under `[gui]`.

## Acceptance criteria
- [ ] `apps/game/client/assets/ui/aumbrye_ui.tres` exists and `project.godot` sets `gui/theme/custom` to it.
- [ ] `tools/build_ui_theme.gd` regenerates the `.tres` byte-identically from the `GameUISkin` constants.
- [ ] Every `Label` in `scenes/ui/*.tscn` has a non-empty `theme_type_variation`.
- [ ] `apply_modal_menu` contains no `find_children("*", "Label", ...)` call.
- [ ] With `low_res_viewport_enabled = true`, every `StyleBoxFlat` returned by `make_panel_style()` reports `corner_radius_top_left == 0` and `shadow_size == 0`.
- [ ] Toggling the render-resolution preset in the settings overlay restyles open panels without reopening them.
- [ ] `apps/game/client/**/*.{ttf,otf}` returns exactly one file and the theme's default font points at it.
- [ ] Every `BaseButton` reachable in the hub, pause, inventory, settings, vendor, and portal menus plays `AudioDirector.play_ui_sfx()` on press.
- [ ] The focused control in every menu draws a 2 px `FOCUS_RING_COLOR` border.
- [ ] `game_ui_skin.gd` declares no constant with zero readers.
- [ ] `build_human_silhouette` has no remaining call sites.

## Validation
Extend `apps/game/client/scripts/validation/suites/m6_suite.gd` (accessibility/UI category) with:

| Test id | Assertion |
|---|---|
| `ui.skin.theme_resource` | `ResourceLoader.exists("res://assets/ui/aumbrye_ui.tres")` and `load(...)` is a `Theme` |
| `ui.skin.theme_registered` | `ProjectSettings.get_setting("gui/theme/custom") == "res://assets/ui/aumbrye_ui.tres"` |
| `ui.skin.theme_regenerates` | running `tools/build_ui_theme.gd` produces a resource whose `get_color("font_color","Label")` equals `GameUISkin.BODY_COLOR` |
| `ui.skin.variations_present` | the theme has all seven variation types (`MenuTitle`, `SectionTitle`, `BodyText`, `HintText`, `StatValue`, `StatDelta`, `DangerText`) |
| `ui.skin.font_default` | the theme's `default_font` resource path ends in `aumbrye_pixel.ttf` |
| `ui.skin.pixel_panel_square` | with `PixelDioramaSettings.low_res_viewport_enabled = true`, `GameUISkin.make_panel_style().corner_radius_top_left == 0` and `.shadow_size == 0` |
| `ui.skin.hd_panel_rounded` | with the native-HD preset, the same call returns radius `8` |
| `ui.skin.focus_styleboxes` | the theme defines a `focus` stylebox for `Button`, `ItemList`, `OptionButton`, `CheckBox`, `LineEdit` |
| `ui.skin.no_label_walk` | `ctx.file_contains("res://scripts/ui/game_ui_skin.gd", "\"Label\", true") == false` |
| `ui.skin.no_dead_constants` | `game_ui_skin.gd` does not contain `const CELL_SIZE` or `const EQUIP_CELL_SIZE` |
| `ui.skin.button_sfx_coverage` | for each of `stair_menu.gd`, `umbral_endless_menu.gd`, `blacksmith_ui.gd`, the file contains no bare `Button.new()` |
| `ui.skin.paperdoll_texture` | `ResourceLoader.exists("res://assets/ui/paperdoll_silhouette.png")` and no `.gd` under `scripts/ui` contains `build_human_silhouette` |

Manual checklist (genuinely not automatable — needs a rendered frame):
- Screenshot the inventory, settings, pause, merchant, and results screens at the `320×180` and native-HD presets and confirm no control renders in Godot's default gray.

## Related
- Existing behavior: [`../existing_codebase/ui/game_ui_skin.md`](../existing_codebase/ui/game_ui_skin.md)
- [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`status_icons_glyphs.md`](status_icons_glyphs.md)
- [`../00-QUALITY-BAR.md`](../00-QUALITY-BAR.md) · [`../../existing_codebase/pixel-style.md`](../../existing_codebase/pixel-style.md)
