# Menu shell — improvement plan

## Current state
`menu_shell.gd` builds the standard modal scaffold in `build_modal` and returns an untyped `Dictionary` of four nodes (`:12-43`). It focuses nothing, handles no `ui_cancel`, applies no pixel theme, and wraps nothing in a `ScrollContainer`. `show_confirmation` is the only shared code in the project that sets `focus_neighbor_*` and calls `grab_focus` (`:121-123`), but it parents the overlay to the calling menu, so hiding that menu orphans a live confirmation. Nine scripts use it and nine other menus ignore it entirely in favor of `GameUISkin.apply_modal_menu` on an authored scene. See [`../existing_codebase/ui/menu_shell.md`](../existing_codebase/ui/menu_shell.md).

Focus and keyboard rules for the menus built on this scaffold are owned by [`menu_shell_a11y.md`](menu_shell_a11y.md); this plan covers the scaffold's structure, styling, and lifetime.

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| MSH-01 | P0 | A confirmation is parented to the menu that opened it and is only hidden, never freed, when that menu closes. Pressing Esc while the pause menu's Abandon confirmation is open closes the pause menu and leaves the overlay alive; reopening the pause menu shows the stale confirmation. | `menu_shell.gd:101`; `pause_menu.gd:41-49` sets `visible = false` only; `pause_menu.gd:68-73` fires while the overlay is up |
| MSH-02 | P0 | `main_menu.gd` only special-cases `_quit_overlay` for Esc, so pressing Esc inside the "New Warden" confirmation falls through to `_prompt_quit()` and stacks a second confirmation over the first. | `main_menu.gd:117-128` creates an overlay it never stores; `:200-219` handles only `_quit_overlay` |
| MSH-03 | P0 | `build_modal` never applies the pixel theme. `GameUISkin.apply_pixel_theme` is reached only through `apply_modal_menu`, which is used by scene-based menus, so every code-built modal (pause, settings, talents, continue, character create) renders with default filtering while every scene-based menu renders nearest-filtered. | `menu_shell.gd:12-43` has no `apply_pixel_theme`; `game_ui_skin.gd:186` is inside `apply_modal_menu` |
| MSH-04 | P1 | No `ScrollContainer`: content taller than the panel — which is clamped to 48 % of the viewport height — silently overflows. The settings panel and character creator are the realistic victims. | `menu_shell.gd:33-36`; `game_ui_skin.gd:74-79` |
| MSH-05 | P1 | `build_modal` returns an untyped `Dictionary` indexed by string keys, so a typo is a runtime `null` and no consumer gets autocompletion or type checks. | `:43`; `pause_menu.gd:59`, `talents_ui.gd:28`, `continue_menu.gd:26` |
| MSH-06 | P1 | No Godot `Theme` resource anywhere: every label, panel, and bar is styled with per-node `add_theme_*_override` and a freshly allocated `StyleBoxFlat` per call. Nine scene-based menus bypass `MenuShell` entirely and are styled by a name-sniffing loop instead. | `game_ui_skin.gd:54-63`, `:135-163`, `:195-204`; 0 theme resources under `apps/game/client` |
| MSH-07 | P1 | Every string reaching the shell is a hardcoded English literal, including the `"Confirm"` / `"Cancel"` defaults. | `menu_shell.gd:95-96`; `pause_menu.gd:94-95`, `main_menu.gd:166-167`, `continue_menu.gd:38-40` |
| MSH-08 | P1 | No modal stack. Each menu sets `Input.mouse_mode` on its own open and close, which is why closing the inventory over an open vendor panel captures the mouse. | `pause_menu.gd:38`, `:48`; `inventory_ui.gd:289`, `:302`; `loadout_ui.gd:36`, `:45` |
| MSH-09 | P2 | `show_confirmation` frees the overlay without restoring focus to whatever was focused before it opened. | `:111-119` |
| MSH-10 | P2 | No open/close transition; panels pop in instantly, which reads as a glitch at 60 fps. | `:12-43` |
| MSH-11 | P2 | `clear_children = true` uses `queue_free()`, so the old children are still in the tree for one frame while the new backdrop and panel are added. A `build_modal` called twice on the same parent in one frame produces two overlapping panels. | `:20-32` |

## Target design

### `MenuShell` becomes a node, not a static bag
Add `apps/game/client/scripts/ui/menu_modal.gd`:

```gdscript
class_name MenuModal
extends Control

signal opened
signal closed
signal cancel_requested

@export var title_key: StringName
@export var half_size: Vector2 = Vector2(GameUISkin.MENU_HALF_W, GameUISkin.MENU_HALF_H)

var panel: PanelContainer
var margin: MarginContainer
var scroll: ScrollContainer
var content: VBoxContainer
var backdrop: ColorRect
var initial_focus: Control

func open() -> void
func close() -> void
func is_open() -> bool
```

`build_modal` stays as a thin compatibility shim returning the same `Dictionary` for one release, but it delegates to `MenuModal` so behavior converges immediately (MSH-05). Typed fields replace string-key lookups.

`MenuModal.open()` does, in order: `visible = true`, register with `MenuStack`, `apply_pixel_theme`, `initial_focus.grab_focus()`, play the open transition, emit `opened`. `close()` unregisters, restores the previous focus owner, and emits `closed`.

### Structure with scroll
```
MenuModal (Control, FULL_RECT)
├── ColorRect "Backdrop"       (BACKDROP_COLOR, MOUSE_FILTER_STOP)
└── PanelContainer "Panel"     (PRESET_CENTER, clamped half size)
    └── MarginContainer "Margin"   (PANEL_MARGIN)
        └── VBoxContainer "Frame"
            ├── Label "TitleLabel"           (style_menu_title, tr(title_key))
            ├── ScrollContainer "Scroll"     (SIZE_EXPAND_FILL, follow_focus = true)
            │   └── VBoxContainer "ContentVBox"  (separation DEFAULT_SEPARATION)
            └── Label "HintLabel"            (pinned below the scroll, never scrolls away)
```

`Scroll.follow_focus = true` is what makes gamepad navigation of a long settings list work at all; the hint row sits outside the scroll so the "Esc: back" affordance is always visible (MSH-04).

### Modal stack autoload
`apps/game/client/scripts/ui/menu_stack.gd`, registered as the `MenuStack` autoload:

```gdscript
signal stack_changed(depth: int)

func push(modal: Control) -> void
func pop(modal: Control) -> void
func top() -> Control
func depth() -> int
func handles_cancel(modal: Control) -> bool     # true only for the top modal
```

`MenuStack` owns `Input.mouse_mode`: visible while `depth() > 0`, restored to the gameplay mode when the stack empties. Every `Input.mouse_mode` assignment in `pause_menu.gd`, `inventory_ui.gd`, `loadout_ui.gd`, `settings_ui.gd`, and the vendor scripts is removed (MSH-08).

`ui_cancel` is routed once: `MenuStack` handles the action in `_unhandled_input` and calls `cancel_requested` on `top()` only. That deletes the per-menu Esc handlers and structurally prevents the `main_menu` double-confirmation, because a `ConfirmOverlay` is always the top of the stack (MSH-02).

### Confirmation ownership
`show_confirmation` becomes `MenuStack.confirm(spec: ConfirmSpec) -> void`, where the overlay is parented to a dedicated `MenuStack` `CanvasLayer` at layer `40` — above every menu — instead of to the calling menu. Consequences: hiding the caller cannot orphan it, and it always draws on top without `move_to_front()` (MSH-01).

```gdscript
class_name ConfirmSpec
extends RefCounted
var title_key: StringName
var message_key: StringName
var message_args: Array = []
var confirm_key: StringName = &"UI_CONFIRM"
var cancel_key: StringName = &"UI_CANCEL"
var destructive: bool = false     # confirm button uses the danger token, focus starts on cancel
var on_confirm: Callable
var on_cancel: Callable
```

`destructive` is set for Abandon run, Quit to menu, Delete warden, and Reset save; focus starts on Cancel for those and on Confirm otherwise (MSH-09 pairs with the focus-restore below).

### A real `Theme`
Author `apps/game/client/themes/aumbrye_ui.theme` with type variations, and set it once on the root `CanvasLayer` of `PlayerControls` plus each menu scene root, so styling inherits instead of being reapplied per node:

| Variation | Applies to | Replaces |
|---|---|---|
| `MenuTitle` | `Label` | `style_menu_title` (`game_ui_skin.gd:143-148`) |
| `SectionTitle` | `Label` | `style_section_title` (`:135-141`) |
| `BodyText` | `Label` | `style_body_label` (`:151-156`) |
| `HintText` | `Label` | `style_hint_label` (`:158-163`) |
| `MenuButton` | `Button` | `make_menu_button` sizing |
| `DangerButton` | `Button` | new, for `destructive` confirmations |
| `ModalPanel` | `PanelContainer` | `make_panel_style` (`:54-63`) |
| `SectionFrame` | `PanelContainer` | `make_section_frame` (`:103-128`) |
| `ItemCell` | `PanelContainer` | `make_item_cell_style` base, rarity still applied per cell |
| `ResourceBar` | `ProgressBar` | `style_progress_bar` (`:276-296`) |

`GameUISkin`'s style helpers become one-line `theme_type_variation` assignments during the transition and are deleted afterwards. The name-sniffing loop in `apply_modal_menu` (`game_ui_skin.gd:195-204`) is deleted; scene-authored labels declare their own variation (MSH-06). Full detail in [`game_ui_skin.md`](game_ui_skin.md).

Rejected alternative: keeping the static helpers and adding `apply_pixel_theme` to `build_modal`. That fixes MSH-03 alone and leaves two divergent styling paths for code-built and scene-built menus.

### Pixel theme correctness
`MenuModal.open()` calls `GameUISkin.apply_pixel_theme(self)` and reconnects to `PixelDioramaSettings` changes, so switching preset mid-session refilters open menus. With the theme in place, filtering is a single theme constant instead of a tree walk (MSH-03).

### Transitions
`open()` tweens `Panel.scale` from `0.96` to `1.0` and `Backdrop.color.a` from `0.0` to `BACKDROP_COLOR.a` over `0.12` s with `TRANS_CUBIC`, `EASE_OUT`; `close()` reverses over `0.09` s. Both are skipped when `AccessibilitySettings.reduced_motion` is on — a new flag that this plan requires and [`settings.md`](settings.md) exposes (MSH-10).

### Localization
`MenuModal` takes `StringName` keys, not strings, and resolves them with `tr()` at open time so a locale change mid-session is picked up. New base keys: `UI_CONFIRM`, `UI_CANCEL`, `UI_BACK`, `UI_CLOSE`, `UI_HINT_ESC_BACK`, `UI_HINT_ESC_RESUME` (MSH-07).

### Deterministic rebuild
`clear_children` uses `remove_child` + `queue_free` so the old nodes leave the tree in the same frame, and `MenuModal` asserts it has not already been built (MSH-11).

## Work plan
1. **Modal stack autoload** — add `menu_stack.gd`, register it, move `ui_cancel` routing and `Input.mouse_mode` ownership into it; strip the per-menu Esc and mouse-mode code (MSH-02, MSH-08).
2. **Confirmation relocation** — `MenuStack.confirm(ConfirmSpec)` on a dedicated `CanvasLayer`, with `destructive` focus rules and focus restore (MSH-01, MSH-09).
3. **`MenuModal` node** — typed fields, `ScrollContainer` with `follow_focus`, pinned hint row, `apply_pixel_theme` on open, `build_modal` shim (MSH-03, MSH-04, MSH-05, MSH-11).
4. **Theme resource** — author `aumbrye_ui.theme`, add the ten variations, convert `GameUISkin` helpers to variation assignments, delete the name-sniffing loop (MSH-06).
5. **Localization** — convert every shell string and call site to `StringName` keys (MSH-07).
6. **Transitions** — open/close tween gated on `reduced_motion` (MSH-10).
7. **Consumer migration** — `pause_menu`, `settings_ui`, `talents_ui`, `continue_menu`, `character_create_ui` extend `MenuModal`; `main_menu` drops its bespoke panel at `main_menu.gd:44-58` in favor of the shell.

Steps 1-2 remove two reproducible stale-overlay bugs and should land before the theme work.

## Data and schema changes
- New: `apps/game/client/scripts/ui/menu_modal.gd`, `menu_stack.gd`, `confirm_spec.gd`.
- New: `apps/game/client/themes/aumbrye_ui.theme`.
- `apps/game/client/project.godot`: add `MenuStack` to `[autoload]`.
- `apps/game/client/translations/strings.csv`: `UI_CONFIRM`, `UI_CANCEL`, `UI_BACK`, `UI_CLOSE`, `UI_HINT_ESC_BACK`, `UI_HINT_ESC_RESUME`, plus per-menu keys owned by each menu's own plan.
- `AccessibilitySettings`: new `reduced_motion: bool`, persisted; requires a `save_migrator.gd` step adding the default.

## Acceptance criteria
- [ ] Opening the pause menu, choosing Abandon run, pressing Esc once cancels only the confirmation and leaves the pause menu open.
- [ ] Pressing Esc twice from there closes the pause menu with no `ConfirmOverlay` left in the tree.
- [ ] Pressing Esc inside the main menu's "New Warden" confirmation dismisses it and does not open the quit prompt.
- [ ] At most one `ConfirmOverlay` exists in the tree at any time.
- [ ] A confirmation renders above every menu without any `move_to_front()` call.
- [ ] Cancelling a confirmation returns focus to the control that was focused when it opened.
- [ ] A destructive confirmation starts focused on Cancel and its confirm button uses the `DangerButton` variation.
- [ ] With the low-res viewport preset active, every code-built modal reports `texture_filter == TEXTURE_FILTER_NEAREST`, matching scene-built menus.
- [ ] The settings panel content taller than the panel scrolls, and moving focus to an off-screen row scrolls it into view.
- [ ] The hint row stays visible while the content scrolls.
- [ ] No file under `apps/game/client/scripts/ui/` assigns `Input.mouse_mode`; only `menu_stack.gd` does.
- [ ] Closing the inventory while a vendor panel is open leaves the mouse visible.
- [ ] `menu_shell.gd` exposes no untyped `Dictionary` return outside the compatibility shim.
- [ ] Every `Label`, `Button`, `PanelContainer`, and `ProgressBar` in a menu has a non-empty `theme_type_variation`.
- [ ] `game_ui_skin.gd` contains no `find_children("*", "Label"` name-sniffing loop.
- [ ] Switching the locale changes the confirm and cancel button text.
- [ ] With `reduced_motion` on, opening a modal produces no `Tween`.

## Validation
New suite `apps/game/client/scripts/validation/suites/menu_shell_suite.gd`, category `menu_shell`:

| Test id | Assertion |
|---|---|
| `menu_shell.confirm_single_instance` | opening two confirmations in sequence leaves exactly one `ConfirmOverlay` node |
| `menu_shell.confirm_layer` | the overlay's parent is the `MenuStack` `CanvasLayer` and not the calling menu |
| `menu_shell.confirm_survives_owner_hide` | hiding the calling menu frees the overlay; the tree contains no `ConfirmOverlay` |
| `menu_shell.cancel_routes_to_top` | with a modal and a confirmation open, `ui_cancel` reaches only the confirmation |
| `menu_shell.main_menu_no_double_prompt` | Esc inside the New Warden confirmation leaves exactly zero overlays and does not create a quit prompt |
| `menu_shell.focus_restore` | focus owner after cancelling equals the owner captured before opening |
| `menu_shell.destructive_focus` | a `destructive` spec starts focus on the cancel button |
| `menu_shell.pixel_filter_parity` | with the low-res preset, a `MenuModal` and an `apply_modal_menu` scene report the same `texture_filter` |
| `menu_shell.scroll_present` | `MenuModal` contains a `ScrollContainer` with `follow_focus == true` wrapping `ContentVBox` |
| `menu_shell.scroll_follows_focus` | focusing a control below the visible area changes `scroll_vertical` |
| `menu_shell.hint_outside_scroll` | `HintLabel` is not a descendant of `Scroll` |
| `menu_shell.mouse_mode_single_owner` | no file under `scripts/ui/` except `menu_stack.gd` contains `Input.mouse_mode` |
| `menu_shell.stack_depth` | opening two modals reports `MenuStack.depth() == 2`; closing both reports `0` and restores the gameplay mouse mode |
| `menu_shell.theme_variations` | every `Label`, `Button`, `PanelContainer`, `ProgressBar` in each built menu has a non-empty `theme_type_variation` present in `aumbrye_ui.theme` |
| `menu_shell.no_name_sniffing` | `game_ui_skin.gd` contains no `name.to_lower().contains(` |
| `menu_shell.localized_defaults` | `menu_shell.gd` contains no `"Confirm"` or `"Cancel"` literal |
| `menu_shell.reduced_motion` | with `reduced_motion` on, `open()` creates no `Tween` and the panel scale is `1.0` on the first frame |
| `menu_shell.rebuild_same_frame` | calling the build path twice in one frame yields exactly one `Panel` |

## Related
- Existing behavior: [`../existing_codebase/ui/menu_shell.md`](../existing_codebase/ui/menu_shell.md)
- Accessibility rules: [`menu_shell_a11y.md`](menu_shell_a11y.md)
- [`game_ui_skin.md`](game_ui_skin.md) · [`pause_menu.md`](pause_menu.md) · [`settings.md`](settings.md) · [`title_main_continue.md`](title_main_continue.md)
- [`../accessibility.md`](../accessibility.md) · [`../project-config-autoloads.md`](../project-config-autoloads.md) · [`../save-migrator.md`](../save-migrator.md)
