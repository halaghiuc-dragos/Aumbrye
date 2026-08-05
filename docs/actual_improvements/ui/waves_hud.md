# Waves HUD — improvement plan

## Current state
The whole Umbral Waves run interface is one autowrapped `Label`, one Ready `Button`, and a `VBoxContainer` of reward buttons in a full-width top panel (`waves_run_ui.gd:14-36`). Every state is a text swap. The prep countdown is printed once from a literal `5.0` and never refreshed (`waves_run.gd:168-170` vs `:236-238`). Reward buttons show raw item ids (`:80`), track selection by id so duplicate stacks desynchronize, and leave a fourth button visually pressed when the cap is hit (`:97-103`). Nothing calls `grab_focus`. `waves_inventory_ui.gd` is a 7-line self-deleting stub with zero references. See [`../existing_codebase/ui/waves_hud.md`](../existing_codebase/ui/waves_hud.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| WHD-01 | P0 | The reward pick is mouse-only. No `grab_focus`, no `focus_neighbor_*`, so a gamepad player cannot claim rewards at the end of a completed waves run and the run is unfinishable on pad. | 0 `grab_focus` matches in `waves_run_ui.gd`; `:79-86` builds bare `Button`s |
| WHD-02 | P0 | Selecting a fourth reward leaves the button latched on while the id is not recorded, so the player confirms a selection different from what the UI shows. | `:97-103` — with `_selected_rewards.size() >= 3` and the id absent, neither branch runs and `toggle_mode` (`:81`) has already set `button_pressed = true` |
| WHD-03 | P0 | Reward selection is keyed on `item_id`, but the list is built per inventory *slot*, so two stacks of the same item produce two buttons sharing one entry: clicking the second de-selects the first. | `:75-84` iterates `slots`; `:97-103` keys on `item_id` |
| WHD-04 | P0 | Rewards are labeled with raw content ids: the victory screen of a full waves run reads `Take castle_sword`, `Take skip_10_floors`. | `:80` `"Take %s" % item_id` with no `ItemCatalog.get_definition` lookup |
| WHD-05 | P1 | The prep countdown is a frozen number. `show_prep` receives the literal `5.0` once and the label is never updated while `_prep_countdown` ticks down. | `waves_run.gd:168-170`, `:222-224`; decrement at `:236-238` with no UI call |
| WHD-06 | P1 | No enemies-remaining or wave-progress readout: the only combat information is the wave index, printed once per wave. | `waves_run_ui.gd:57-60` |
| WHD-07 | P1 | The panel is `PRESET_TOP_WIDE` to `offset_bottom = 120` and overlaps the waves `CombatHUD` health/stamina block at top-left `20,20`-`300,84`. | `waves_run_ui.gd:19-20` vs `waves_run.gd:283-289` |
| WHD-08 | P1 | Zero localization — six hardcoded English format strings, one of which hardcodes the keyboard key name `E` instead of resolving the `interact` glyph. | `:51`, `:54`, `:60`, `:65`, `:74`, `:80` |
| WHD-09 | P1 | Reward buttons are text-only with no item icon, rarity color, or stat preview, so the player picks blind. | `:79-84`; no `TextureRect` in the file |
| WHD-10 | P2 | The `MarginContainer` gets no margin overrides and the `VBoxContainer` no separation, so the panel ignores the skin's spacing tokens. | `:23-26` |
| WHD-11 | P2 | Reward buttons bypass `MenuShell.make_menu_button` and are raw `Button.new()` with only `wire_button_sfx`, so they are styled differently from the Ready and Confirm buttons in the same box. | `:79-83` vs `:31`, `:85` |
| WHD-12 | P2 | The run node is reached by group lookup plus `has_method` string checks rather than a typed reference or a signal, so a renamed method fails silently. | `:89-94`, `:106-109` |
| WHD-13 | P2 | `waves_inventory_ui.gd` is unreachable dead code — 7 lines that free themselves, referenced nowhere in `apps/`, `content/`, or `tools/`. | `waves_inventory_ui.gd:5-7`; repo grep matches only `docs/` files |

## Target design

### Structured HUD instead of one label
Replace the single `Label` with a purpose-built control tree so each piece of information has a stable home:

```
WavesUI (Control, MOUSE_FILTER_IGNORE, anchored FULL_RECT)
├── TopBanner (PanelContainer, PRESET_CENTER_TOP, width 420, height 56)
│   └── HBoxContainer
│       ├── Label "WaveLabel"        # "Wave 7 / 20"
│       ├── VSeparator
│       ├── Label "EnemiesLabel"     # "Enemies 4"
│       └── Label "PrepLabel"        # "Prep 3.2s", visible only in prep
├── LobbyPanel (PanelContainer, PRESET_CENTER_BOTTOM, offset_top -140)
│   └── VBoxContainer
│       ├── Label "LobbyHint"        # localized, with the interact glyph
│       ├── HBoxContainer "ChestPips"  # one 16px atlas cell per chest, open/closed
│       └── Button "ReadyButton"
└── RewardPanel (PanelContainer, centered modal via MenuShell.build_modal)
    └── VBoxContainer
        ├── Label "RewardTitle"
        ├── Label "RewardCounter"    # "2 / 3 chosen"
        ├── GridContainer "RewardGrid" (columns 4)   # ItemCell instances
        └── Button "ConfirmButton"
```

`TopBanner` moves to `PRESET_CENTER_TOP` at 420 px wide, clearing the `CombatHUD` block that occupies the top-left 300 px (WHD-07). `LobbyPanel` only exists during the lobby, so it cannot overlap the combat banner.

### Reward pick by instance, with icons
`show_reward_pick` builds one `ItemCell` per slot using the shared cell from [`inventory_ui.md`](inventory_ui.md), so each reward shows its atlas icon, rarity frame, stack count, and localized name, with the full tooltip on focus.

Selection is tracked as `Array[String]` of `instanceId`, not `itemId`:

```gdscript
var _selected_instances: Array[String] = []
func _on_pick_reward(instance_id: String, cell: Control) -> void
```

This fixes duplicate-stack desynchronization (WHD-03). The cap is enforced *before* the toggle by intercepting `gui_input` / `toggled` and calling `set_pressed_no_signal(false)` when the cap is reached, plus a one-shot shake on `RewardCounter` and the `ui_denied` sound, so the visual state can never disagree with `_selected_instances` (WHD-02). `complete_waves_with_rewards` takes instance ids; `waves_run.gd:252` resolves them against `WavesRunService.waves_inventory`.

Rejected alternative: keeping `itemId` and de-duplicating the button list. That silently drops the second copy of a duplicate reward, which is worse than showing it.

### Live values
`waves_run_ui.gd` stops being push-only. It connects to new `WavesRunService` signals and updates itself:

```gdscript
signal wave_started(wave: int, total: int)
signal wave_enemies_changed(remaining: int)
signal prep_started(wave: int, duration: float)
signal prep_tick(remaining: float)
signal lobby_chests_changed(opened: int, total: int)
```

`prep_tick` is emitted from `waves_run.gd`'s existing `_process` decrement at `:236-238` at 10 Hz, which is what makes the countdown move (WHD-05). `wave_enemies_changed` is emitted from the existing `enemy_died` handling, giving a live enemies-remaining count (WHD-06). The group-lookup calls at `:89-94` and `:106-109` are replaced by two signals the run node connects to — `ready_requested` and `rewards_confirmed(Array[String])` — so a rename becomes a compile error (WHD-12).

### Chest pips
`ChestPips` draws one 16 px atlas cell per chest from the shared symbol atlas, keyed `ui/chest_closed` and `ui/chest_open` (see [`status_icons_glyphs.md`](status_icons_glyphs.md)), replacing the `(2/5)` fraction in the middle of a sentence with a glanceable row.

### Focus rules
- Entering the lobby: `ReadyButton.grab_focus()`.
- `ReadyButton.disabled` while chests remain; the focus stays on it and the hint label states what is missing, so a pad player is never focus-less.
- Opening the reward panel: first `ItemCell` grabs focus; `focus_neighbor_*` wires the 4-column grid; `ui_down` from the last row reaches `ConfirmButton`.
- `RewardPanel` registers with the `MenuStack` from [`menu_shell_a11y.md`](menu_shell_a11y.md) so it owns mouse mode and cannot be closed with `ui_cancel` while rewards are unconfirmed (WHD-01).

### Localization and glyphs
Keys added to `apps/game/client/translations/strings.csv`: `WAVES_LOBBY_HINT` (with a `{glyph}` placeholder filled from `InputGlyphService.get_action_glyph("interact")`), `WAVES_LOBBY_READY_PROMPT`, `WAVES_READY_BUTTON`, `WAVES_WAVE_LABEL`, `WAVES_ENEMIES_LABEL`, `WAVES_PREP_LABEL`, `WAVES_REWARD_TITLE`, `WAVES_REWARD_COUNTER`, `WAVES_REWARD_CONFIRM`, `WAVES_REWARD_TAKE` (WHD-04, WHD-08).

### Styling
Every button goes through `MenuShell.make_menu_button` (WHD-11); every panel gets `GameUISkin.PANEL_MARGIN` and `SECTION_SEPARATION` via a new `GameUISkin.apply_panel_spacing(margin, vbox)` helper so the values are not retyped (WHD-10).

### Dead file
Delete `apps/game/client/scripts/ui/waves_inventory_ui.gd`. Its documented replacement — the global `InventoryUI` switching to `WavesRunService.waves_inventory` — is already live at `inventory_ui.gd:76-88` (WHD-13).

## Work plan
1. **Selection integrity** — key `_selected_instances` on `instanceId`, enforce the cap before the toggle with `set_pressed_no_signal`, add the counter label (WHD-02, WHD-03).
2. **Display names** — resolve `ItemCatalog.get_definition(...).name` through `tr()` for every reward button (WHD-04).
3. **Focus** — `grab_focus` on lobby entry and reward-panel open, `focus_neighbor_*` on the reward grid, `MenuStack` registration (WHD-01).
4. **Service signals** — add the five signals to `WavesRunService`, emit them from `waves_run.gd`, and convert `waves_run_ui.gd` from push-only to connected; add `ready_requested` / `rewards_confirmed` in the other direction (WHD-05, WHD-06, WHD-12).
5. **Control tree** — split the single label into `TopBanner` / `LobbyPanel` / `RewardPanel`, move the banner to `PRESET_CENTER_TOP` (WHD-07).
6. **Reward cells** — reuse the inventory `ItemCell` with icon, rarity frame, and tooltip (WHD-09).
7. **Chest pips** — atlas-cell row replacing the fraction (WHD-06 support).
8. **Localization** — move all strings to `strings.csv`, insert the interact glyph (WHD-08).
9. **Styling and cleanup** — `make_menu_button` everywhere, `apply_panel_spacing`, delete `waves_inventory_ui.gd` (WHD-10, WHD-11, WHD-13).

Steps 1-3 are the unfinishable-run fixes and should ship together.

## Data and schema changes
- `apps/game/client/scripts/dungeon/waves_run_service.gd`: five outbound signals listed above. No change to `to_save_dict` keys (`lobbyReady`, `chests_opened`, `seed` stay as-is), so no `save_migrator.gd` bump.
- `content/ui/status_icon_atlas.json` (or a `ui/` namespace within it): `ui/chest_open`, `ui/chest_closed` cells.
- `apps/game/client/translations/strings.csv`: the `WAVES_*` keys above.
- Deleted: `apps/game/client/scripts/ui/waves_inventory_ui.gd`.

## Acceptance criteria
- [ ] Entering the waves lobby leaves `ReadyButton` focused; a gamepad can ready up without touching the mouse.
- [ ] Opening the reward panel focuses the first reward cell; the whole pick and confirm flow is completable on gamepad only.
- [ ] With three rewards chosen, clicking or accepting a fourth leaves that cell unselected and plays the denied sound; `_selected_instances.size() == 3`.
- [ ] Two stacks of the same item id produce two independently selectable cells.
- [ ] Confirming a selection passes exactly the instance ids of the visually selected cells.
- [ ] Reward cells show the localized item name and its atlas icon; no cell text equals a raw content id.
- [ ] The prep label counts down visibly from `5.0` to `0.0` and updates at least 10 times per second's worth of ticks.
- [ ] Killing an enemy mid-wave decrements the enemies-remaining readout within one frame.
- [ ] The waves banner rect does not intersect the `CombatHUD` `Margin` rect at any window size from `1280×720` to `2560×1440`.
- [ ] The lobby hint shows the current `interact` binding's glyph, not the literal `E`.
- [ ] Switching the locale to a stub translation changes every visible waves string.
- [ ] `waves_run_ui.gd` contains no `get_first_node_in_group("waves_run")` and no `has_method(` call.
- [ ] `apps/game/client/scripts/ui/waves_inventory_ui.gd` does not exist and no file references it.

## Validation
Extend `apps/game/client/scripts/validation/suites/m7_suite.gd` and add `waves_ui` cases:

| Test id | Assertion |
|---|---|
| `waves_ui.lobby_focus` | after `show_lobby()`, `gui_get_focus_owner() == ReadyButton` |
| `waves_ui.reward_focus` | after `show_reward_pick()`, focus is the first `RewardGrid` child |
| `waves_ui.reward_cap_visual` | select 3, attempt a 4th: the 4th cell reports `button_pressed == false` and `_selected_instances.size() == 3` |
| `waves_ui.duplicate_instances` | two slots with the same `itemId` yield two cells whose selection states toggle independently |
| `waves_ui.confirm_payload` | `rewards_confirmed` carries exactly the selected `instanceId` values in selection order |
| `waves_ui.reward_names_localized` | no reward cell's text equals its `itemId`; every name resolves through `strings.csv` |
| `waves_ui.reward_icons` | every reward cell contains a `TextureRect` with a non-null texture |
| `waves_ui.prep_ticks` | emitting `prep_tick` from `5.0` down to `0.0` produces at least 40 distinct label values |
| `waves_ui.enemies_remaining` | emitting `wave_enemies_changed(3)` updates `EnemiesLabel` in the same frame |
| `waves_ui.no_hud_overlap` | `TopBanner.get_global_rect()` does not intersect `CombatHUD/Margin.get_global_rect()` at 1280×720 and 2560×1440 |
| `waves_ui.interact_glyph` | `LobbyHint` contains `InputGlyphService.get_action_glyph("interact")` and not the literal `" + E"` |
| `waves_ui.localized` | every `Label`/`Button` text in the built tree is a `strings.csv` key |
| `waves_ui.no_group_lookup` | `waves_run_ui.gd` contains no `get_first_node_in_group` and no `has_method(` |
| `waves_ui.buttons_skinned` | every `Button` under `WavesUI` was produced by `MenuShell.make_menu_button` (checked via a `menu_button` meta flag) |
| `waves_ui.stub_removed` | `FileAccess.file_exists("res://scripts/ui/waves_inventory_ui.gd") == false` |

## Related
- Existing behavior: [`../existing_codebase/ui/waves_hud.md`](../existing_codebase/ui/waves_hud.md)
- [`combat_hud.md`](combat_hud.md) · [`inventory_ui.md`](inventory_ui.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`status_icons_glyphs.md`](status_icons_glyphs.md) · [`run_flow_ui.md`](run_flow_ui.md)
- [`../waves-run.md`](../waves-run.md) · [`../run-flow.md`](../run-flow.md) · [`../loot-and-equipment.md`](../loot-and-equipment.md)
