# Main menu — improvement plan

## Current state
`main_menu.tscn` is an empty script host; `main_menu.gd:38-80` builds a flat `ColorRect` backdrop and a centered panel with two labels, four buttons, and a hint. Nothing is focused on open, so the front end cannot be operated with a gamepad. It builds its own panel instead of using `MenuShell.build_modal`, uses `_input` rather than `_unhandled_input` for `ui_cancel`, and stacks a second confirmation if Esc is pressed inside the New Warden prompt. Seven strings are hardcoded English. See [`../existing_codebase/ui/main_menu.md`](../existing_codebase/ui/main_menu.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| MMN-01 | P0 | The front end is mouse-only. Four buttons, no `grab_focus`, no `focus_neighbor_*`, so a controller player cannot reach New Game at all. | `main_menu.gd:69-74`; 0 `grab_focus` matches in the file |
| MMN-02 | P0 | Esc inside the New Warden confirmation stacks a quit confirmation on top of it, because the overlay returned by `show_confirmation` at `:117` is discarded while `_input` only knows about `_quit_overlay`. | `:117-128` vs `:203-207` |
| MMN-03 | P1 | The scene has no authored content, so the front end cannot be art-directed in the editor. | `main_menu.tscn:5-13` |
| MMN-04 | P1 | No art at all: a flat `Color(0.02, 0.02, 0.06)` fill, text buttons, no logo, no background, no ornament. | `:40-43`; 0 `.png` files under `apps/game/client` |
| MMN-05 | P1 | Zero localization across seven strings, including two full confirmation bodies. | `:60`, `:65`, `:69-76`, `:119-127`, `:159-167` |
| MMN-06 | P1 | It duplicates the modal scaffold instead of using `MenuShell.build_modal`, with its own 24 px margins against `PANEL_MARGIN = 18`, so the front end is spaced differently from every other menu. | `:44-58` vs `menu_shell.gd:26-36`, `game_ui_skin.gd:15` |
| MMN-07 | P1 | It is the only menu that uses `_input` instead of `_unhandled_input`, so it consumes `ui_cancel` ahead of focused controls and ahead of every other menu. | `:200` against eight `_unhandled_input` handlers elsewhere |
| MMN-08 | P2 | `"Esc: quit"` hardcodes a key name instead of resolving the `ui_cancel` glyph, so it is wrong on a gamepad. | `:76` |
| MMN-09 | P2 | `_show_main_panel(false)` hides only the panel, leaving the flat backdrop visible while each submenu draws its own backdrop over it — two stacked dimmers. | `:101-102`; `menu_shell.gd:23` inside the submenus |
| MMN-10 | P2 | No credits, achievements, or leaderboard entry, though achievements and leaderboards both exist as systems. | `:69-74`; `LeaderboardSettings` is configured at `settings_ui.gd:126-133` |
| MMN-11 | P2 | The Continue button's disabled state is the only save feedback; the menu never shows which warden Continue would resume. | `:95-98` |

## Target design

### Authored scene with art
`main_menu.tscn` becomes a real scene reusing the title screen's background so the two front-end screens share an identity:

```
MainMenu (Control, FULL_RECT)
├── TextureRect "Background"     # assets/ui/title_bg.png, STRETCH_KEEP_ASPECT_COVERED, NEAREST
├── ColorRect   "Scrim"          # Color(0.01, 0.01, 0.04, 0.55), MOUSE_FILTER_IGNORE
├── TextureRect "Logo"           # assets/ui/title_logo.png, PRESET_CENTER_TOP, offset_top 40
├── MenuModal   "MenuPanel"      # from menu_shell.md; half size 300 × 250
│   └── ContentVBox
│       ├── Label  "Subtitle"        theme_type_variation = BodyText
│       ├── Button "NewGameButton"   MenuButton
│       ├── Button "ContinueButton"  MenuButton
│       ├── Label  "ContinueDetail"  HintText — "Warden {name} · floor {n}"
│       ├── Button "SettingsButton"  MenuButton
│       ├── Button "ExtrasButton"    MenuButton
│       └── Button "QuitButton"      MenuButton
│   └── HintLabel                    # glyph + "quit", pinned outside the scroll
├── CharacterCreateUI
├── ContinueMenu
└── ExtrasMenu                    # new: credits, achievements, leaderboard
```

Adopting `MenuModal` removes the duplicated backdrop/margin/vbox code and the 24 px margin override, and gives the front end the same panel spacing as every other menu (MMN-03, MMN-04, MMN-06).

`Scrim` replaces the opaque `ColorRect` at `:40-43`; because it is semi-transparent over the shared background, hiding `MenuPanel` for a submenu no longer produces two stacked dimmers — the submenu's own backdrop is the only dimmer (MMN-09).

### Focus and navigation
- `initial_focus` is `ContinueButton` when `LocalSave.has_playable_character()`, otherwise `NewGameButton`.
- Vertical order is implicit from the `VBoxContainer`; `ContinueDetail` is a `Label` and therefore skipped.
- A disabled `ContinueButton` is skipped by pointing `NewGameButton.focus_neighbor_bottom` at `SettingsButton`, so focus never lands on a dead control.
- `MenuStack` owns `ui_cancel`; `main_menu.gd`'s `_input` override is deleted, which also removes the special-casing that caused the double prompt (MMN-01, MMN-02, MMN-07).

### Confirmations through the stack
Both confirmations become `MenuStack.confirm(ConfirmSpec)` calls with `destructive = true` for Quit. Because a confirmation is always the top of the stack, Esc can only ever dismiss the confirmation (MMN-02).

### Continue detail line
`ContinueDetail` reads the most recent entry from `LocalSave.list_character_slots()` and shows `tr("MENU_CONTINUE_DETAIL").format({"name": ..., "floor": ...})`, hidden when no save exists. It refreshes on the same three triggers that already call `_refresh_continue_button` (MMN-11).

### Extras submenu
`ExtrasMenu` is a `MenuModal` with three entries — Credits, Achievements, Leaderboard — where Leaderboard is disabled unless `LeaderboardSettings.opt_in` is true, with the reason in its hint. Credits content lives in `content/ui/credits.json` so it is data, not a string wall (MMN-10).

### Localization and glyphs
Keys: `MENU_SUBTITLE`, `MENU_NEW_GAME`, `MENU_CONTINUE`, `MENU_CONTINUE_DETAIL`, `MENU_SETTINGS`, `MENU_EXTRAS`, `MENU_QUIT`, `MENU_HINT_QUIT`, `MENU_CONFIRM_NEW_TITLE`, `MENU_CONFIRM_NEW_BODY`, `MENU_CONFIRM_NEW_OK`, `MENU_CONFIRM_QUIT_TITLE`, `MENU_CONFIRM_QUIT_BODY`, `MENU_CONFIRM_QUIT_OK`, `MENU_CONFIRM_QUIT_CANCEL`. The hint row is a `make_symbol_caption_row` pairing the `ui_cancel` glyph with `MENU_HINT_QUIT` (MMN-05, MMN-08).

Rejected alternative: keeping the English literals and adding `tr()` calls with the English text as the key. That works until a string changes and silently breaks every translation; explicit keys fail loudly instead.

## Work plan
1. **Focus** — add `initial_focus`, disabled-control skipping, and delete the `_input` override in favor of `MenuStack` (MMN-01, MMN-07).
2. **Confirmations via the stack** — both `show_confirmation` calls become `MenuStack.confirm`, Quit marked destructive (MMN-02).
3. **Scene and `MenuModal` adoption** — author `main_menu.tscn`, drop the hand-built panel, add `Background`/`Scrim`/`Logo` (MMN-03, MMN-04, MMN-06, MMN-09).
4. **Localization and glyph hint** (MMN-05, MMN-08).
5. **Continue detail line** (MMN-11).
6. **Extras submenu** with credits from `content/ui/credits.json` (MMN-10).

## Data and schema changes
- `apps/game/client/scenes/ui/main_menu.tscn`: full authored tree.
- Reuses `assets/ui/title_bg.png` and `assets/ui/title_logo.png` from [`title_screen.md`](title_screen.md); no new art beyond those.
- New: `content/ui/credits.json` plus `content/schemas/credits.v1.json` (`sections[] { titleKey, entries[] }`).
- `apps/game/client/translations/strings.csv`: the `MENU_*` keys above plus `EXTRAS_*` for the new submenu.
- No save-format change.

## Acceptance criteria
- [ ] Opening the main menu leaves a focused button; the whole front end including character creation is completable on a gamepad with no mouse.
- [ ] With no save present, focus starts on New Game and `ui_down` from it reaches Settings, skipping the disabled Continue button.
- [ ] Pressing Esc inside the New Warden confirmation dismisses only that confirmation and creates no quit prompt.
- [ ] At most one confirmation overlay exists at any time.
- [ ] `main_menu.gd` contains no `_input` override and no `Input.mouse_mode` assignment.
- [ ] `main_menu.tscn` declares `Background`, `Scrim`, `Logo`, and `MenuPanel` nodes.
- [ ] `main_menu.gd` contains no `make_center_panel` call and no `MarginContainer.new()`.
- [ ] Opening the continue menu shows exactly one dimming layer over the background.
- [ ] Every visible string changes when the locale is switched to a stub translation.
- [ ] The quit hint shows the current `ui_cancel` glyph, not the literal `Esc`.
- [ ] With a save present, the continue detail line names the warden and floor; with none, it is hidden.
- [ ] The Extras submenu lists credits from `content/ui/credits.json` and disables Leaderboard when `LeaderboardSettings.opt_in` is false.

## Validation
Extend `apps/game/client/scripts/validation/suites/ui_suite.gd`, category `main_menu`:

| Test id | Assertion |
|---|---|
| `main_menu.focus_on_open` | `gui_get_focus_owner()` is a `Button` inside `MenuPanel` after open |
| `main_menu.focus_skips_disabled` | with no save, `ui_down` from New Game focuses Settings |
| `main_menu.no_double_confirm` | Esc inside the New Warden confirmation leaves zero overlays |
| `main_menu.single_overlay` | opening a second confirmation while one is open is refused or replaces it; count stays `<= 1` |
| `main_menu.no_input_override` | `main_menu.gd` contains no `func _input(` and no `Input.mouse_mode` |
| `main_menu.scene_authored` | `main_menu.tscn` declares `Background`, `Scrim`, `Logo`, `MenuPanel` |
| `main_menu.no_handbuilt_panel` | `main_menu.gd` contains no `make_center_panel` and no `MarginContainer.new()` |
| `main_menu.single_dimmer` | with the continue menu open, exactly one full-rect `ColorRect` with alpha `> 0.4` is visible |
| `main_menu.localized` | every `Label` and `Button` text resolves from a `strings.csv` key |
| `main_menu.hint_glyph` | the hint contains `InputGlyphService.get_action_glyph("ui_cancel")` and not the literal `Esc` |
| `main_menu.continue_detail` | with a seeded save, the detail line contains the character name and floor; with none it is `visible == false` |
| `main_menu.extras_credits` | the Extras submenu renders one section per entry in `content/ui/credits.json` |
| `main_menu.extras_leaderboard_gate` | with `LeaderboardSettings.opt_in == false`, the Leaderboard entry is `disabled` and its hint is non-empty |

## Related
- Existing behavior: [`../existing_codebase/ui/main_menu.md`](../existing_codebase/ui/main_menu.md)
- Entry-flow coordination: [`title_main_continue.md`](title_main_continue.md)
- [`title_screen.md`](title_screen.md) · [`continue_menu.md`](continue_menu.md) · [`character_create.md`](character_create.md) · [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`settings.md`](settings.md)
- [`../local-save.md`](../local-save.md) · [`../achievements-meta.md`](../achievements-meta.md) · [`../platform-and-net.md`](../platform-and-net.md)
