# Game UI skin — improvement plan

## Status: FINISHED

## Current state
`GameUISkin` (`apps/game/client/scripts/ui/game_ui_skin.gd`) is the single source of truth for UI design tokens, theme construction, and runtime helpers. The generated theme `apps/game/client/assets/ui/aumbrye_ui.tres` is registered in `project.godot` under `gui/theme/custom`, and seven `theme_type_variation` names style every shipping label in `scenes/ui/*.tscn`. See [`../existing_codebase/ui/game_ui_skin.md`](../existing_codebase/ui/game_ui_skin.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| SKN-01 | P0 | ~~No `Theme` resource~~ | **CLOSED** — `aumbrye_ui.tres` + `gui/theme/custom`; `quest_board_ui.gd` and `achievement_toast.gd` call `apply_modal_menu` |
| SKN-02 | P0 | ~~Label styling by node-name substring~~ | **CLOSED** — `theme_type_variation` on every `scenes/ui/*.tscn` label; `apply_modal_menu` no longer walks labels |
| SKN-03 | P1 | ~~No UI font asset~~ | **CLOSED** — `assets/ui/fonts/aumbrye_pixel.ttf` |
| SKN-04 | P1 | ~~`build_human_silhouette` blockout~~ | **CLOSED** — `paperdoll_silhouette.png` + `build_paperdoll_backdrop` |
| SKN-05 | P1 | ~~Panel styling ignores pixel mode~~ | **CLOSED** — `make_panel_style()` branches on `is_pixel_ui()`; `restyle_tree` wired from `PixelDioramaSettings.apply_all()` |
| SKN-06 | P1 | ~~Font sizes not tokenized~~ | **CLOSED** — `FONT_SIZE_*` constants; dialogue/inventory/quest-tracker use them |
| SKN-07 | P1 | ~~`wire_button_sfx` opt-in~~ | **CLOSED** — `make_button()` factory; `apply_modal_menu` wires scene buttons |
| SKN-08 | P2 | ~~Dead `CELL_SIZE` / `EQUIP_CELL_SIZE`~~ | **CLOSED** — removed from `game_ui_skin.gd` |
| SKN-09 | P2 | ~~`clamped_panel_half_size` null crash~~ | **CLOSED** — null viewport guard at `game_ui_skin.gd:clamped_panel_half_size` |
| SKN-10 | P2 | ~~No focus visual~~ | **CLOSED** — `FOCUS_RING_COLOR` focus styleboxes on Button, ItemList, OptionButton, CheckBox, LineEdit |

## Target design
Implemented as specified: generated `aumbrye_ui.tres` from `GameUISkin.build_theme()`, `tools/build_ui_theme.gd` headless exporter, seven label variations, pixel-aware panels, `restyle_tree`, `make_button`, authored paper-doll texture, and focus rings.

## Work plan
All steps landed in Batch 8 substitute topic `ui/game_ui_skin`.

## Data and schema changes
No JSON schema or save-format changes.

Committed resources:
- `apps/game/client/assets/ui/aumbrye_ui.tres`
- `apps/game/client/assets/ui/fonts/aumbrye_pixel.ttf` + `.import`
- `apps/game/client/assets/ui/paperdoll_silhouette.png` + `.import`
- `apps/game/client/scripts/tools/build_ui_theme.gd`

## Acceptance criteria
- [x] `aumbrye_ui.tres` exists and `project.godot` sets `gui/theme/custom`.
- [x] `tools/build_ui_theme.gd` regenerates the `.tres` from `GameUISkin` constants.
- [x] Every `Label` in `scenes/ui/*.tscn` has a non-empty `theme_type_variation`.
- [x] `apply_modal_menu` contains no label-name walk.
- [x] Pixel mode zeroes panel corner radius and shadow.
- [x] `PixelDioramaSettings.apply_all()` restyles open panels via `restyle_tree`.
- [x] Exactly one `.ttf` under `apps/game/client` and theme default font points at it.
- [x] Hub/pause/inventory/settings/vendor/portal menu buttons play UI SFX.
- [x] Focus ring styleboxes on five interactive control types.
- [x] No dead constants in `game_ui_skin.gd`.
- [x] No `build_human_silhouette` call sites under `scripts/ui/`.

## Validation
`m6_suite.gd` — tests `ui.skin.theme_resource` through `ui.skin.paperdoll_texture` (see suite for assertions).

## Related
- Existing behavior: [`../existing_codebase/ui/game_ui_skin.md`](../existing_codebase/ui/game_ui_skin.md)
- [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`status_icons_glyphs.md`](status_icons_glyphs.md)
- [`../00-QUALITY-BAR.md`](../00-QUALITY-BAR.md) · [`../../existing_codebase/pixel-style.md`](../../existing_codebase/pixel-style.md)
