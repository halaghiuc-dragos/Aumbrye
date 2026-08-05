# Waves HUD

The entire Umbral Waves in-run interface is one `Label`, one `Button`, and a `VBoxContainer` of reward buttons inside a full-width top panel. The second file named in this topic, `waves_inventory_ui.gd`, is a 7-line deprecation stub that deletes itself.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/ui/waves_run_ui.gd` | 110 lines, `extends Control`; lobby, combat, prep, and reward-pick states |
| `apps/game/client/scripts/ui/waves_inventory_ui.gd` | 7 lines; `_ready` sets `visible = false` then `queue_free()` |
| `apps/game/client/scripts/dungeon/waves_run.gd` | the only caller; builds and drives the UI |

No `.tscn` for either. `waves_run.gd:90-97` creates a bare `Control` named `WavesUI`, assigns `waves_run_ui.gd`, and adds it as a child of the run node. `waves_run.gd:270-282` separately builds a `CombatHUD` with `combat_hud.gd`, so waves runs show both surfaces.

## Control tree (`_ready`, `waves_run_ui.gd:14-36`)
```
Control (WavesUI, mouse_filter IGNORE)
└── PanelContainer "Panel"   (PRESET_TOP_WIDE, offset_bottom = 120, GameUISkin.style_panel)
    └── MarginContainer      (no margin constants set)
        └── VBoxContainer    (no separation constant set)
            ├── Label            (word-smart autowrap, style_body_label)
            ├── Button           "Ready — start waves", visible = false
            └── VBoxContainer    reward box, visible = false
```

## States and text
| Method | Called from | Text produced |
|---|---|---|
| `show_lobby()` `:39` | `waves_run.gd:106` on entering the lobby | delegates to `refresh_lobby` |
| `refresh_lobby()` `:45` | `waves_run.gd:139`, `:148` | `"Open all %d chests (%d/%d). Walk to chest + E. Waves loadout only."`, plus `"\nAll chests open — press Ready."` when eligible |
| `show_combat(wave)` `:57` | `waves_run.gd:161`, `:174`, `:229`, `:244` | `"Wave %d — clear all enemies."` |
| `show_prep(wave, countdown)` `:63` | `waves_run.gd:170`, `:224` | `"Milestone wave %d cleared! Walls rebuild — prep %.0fs."` |
| `show_reward_pick()` `:68` | `waves_run.gd:249` | `"Victory! Choose up to 3 items to keep:"` plus one `Button` per non-empty inventory slot labeled `"Take %s" % item_id` |

## Services
- `WavesRunService.get_chest_count()`, `.chests_opened`, `.all_chests_opened()`, `.lobby_ready`, `.current_wave`, `.waves_inventory` — read directly, never through a signal. Every refresh is a push from `waves_run.gd`.
- Outbound calls go through `get_tree().get_first_node_in_group("waves_run")` and `has_method` checks rather than a typed reference: `try_ready`, `start_waves_from_lobby` (`:89-94`), `complete_waves_with_rewards` (`:106-109`, implemented at `waves_run.gd:252`).
- Buttons come from `MenuShell.make_menu_button` (`:31`, `:85`) except the reward buttons, which are raw `Button.new()` with `GameUISkin.wire_button_sfx` (`:79-83`).

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Lobby chest counter | IMPLEMENTED | `waves_run_ui.gd:45-54` |
| Ready gate | IMPLEMENTED — button `disabled` mirrors `all_chests_opened()` | `:52`; service gate at `waves_run_service.gd:203`, `:208` |
| Wave / prep / reward states | IMPLEMENTED as text swaps on one `Label` | `:57-86` |
| Prep countdown | BROKEN — `show_prep` is called once with a literal `5.0`; `_prep_countdown` decrements in `waves_run.gd:236-238` but the UI is never refreshed, so the label reads `prep 5s` for the whole five seconds | `waves_run.gd:168-170`, `:222-224`, `:236-244` |
| Reward item names | PLACEHOLDER — buttons read `"Take castle_sword"`, the raw item id, not `ItemCatalog` display names | `:80` |
| Reward selection cap | BROKEN — with three items already chosen, a fourth click leaves `button_pressed == true` while the id is not in `_selected_rewards`, because neither branch of `_on_pick_reward` runs | `:97-103`; `toggle_mode = true` at `:81` |
| Duplicate reward items | BROKEN — selection is tracked by `item_id`, so two stacks of the same item share one entry and their two buttons desynchronize | `:97-103` against `WavesRunService.waves_inventory.slots` at `:75` |
| Reward icons | ABSENT — text-only buttons; no `TextureRect` anywhere in the file | `:79-84` |
| Keyboard/gamepad focus | PARTIAL — no `grab_focus` in the file, so the Ready button and every reward button are mouse-only; nothing sets `focus_neighbor_*` | 0 `grab_focus` matches in `waves_run_ui.gd` |
| Enemies-remaining counter | ABSENT — `show_combat` prints the wave number once and is not called again until the wave changes | `:57-60`; no per-frame update path |
| Wave timer or wave-of-N progress | ABSENT | `:60` shows only `wave` |
| Layout collision | PARTIAL — the panel is `PRESET_TOP_WIDE` to `offset_bottom = 120`, and the waves `CombatHUD` places its health/stamina margin at top-left `20,20`-`300,84`, inside that band | `waves_run_ui.gd:19-20` vs `waves_run.gd:283-289` |
| Panel margins | PARTIAL — the `MarginContainer` is added with no margin overrides and the `VBoxContainer` with no separation, unlike every skinned panel | `:23-26` against `game_ui_skin.gd` `PANEL_MARGIN` usage elsewhere |
| Localization | ABSENT — five hardcoded English format strings, including the em dash and the literal `+ E` key name | `:51`, `:54`, `:60`, `:65`, `:74`, `:80` |
| Input prompt accuracy | PARTIAL — `"Walk to chest + E"` hardcodes the keyboard binding instead of using `InputGlyphService.get_action_glyph("interact")` | `:51` |
| `waves_inventory_ui.gd` | STUB — `visible = false` then `queue_free()`; zero references anywhere in `apps/`, `content/`, or `tools/`, so the file is unreachable dead code | `waves_inventory_ui.gd:5-7`; grep for `waves_inventory_ui` across the repo matches only two files under `docs/` |
| Waves inventory access | IMPLEMENTED elsewhere — the global `InventoryUI` on `PlayerControls` switches to `WavesRunService.waves_inventory` in waves mode | `inventory_ui.gd:76-88`; `player_controls.gd:25` |

## Related
- Improvement plan: [`../actual_improvements/ui/waves_hud.md`](../actual_improvements/ui/waves_hud.md)
- [`combat_hud.md`](combat_hud.md) · [`inventory_ui.md`](inventory_ui.md) · [`menu_shell.md`](menu_shell.md) · [`run_portals.md`](run_portals.md) · [`run_outcome.md`](run_outcome.md)
- [`../waves-run.md`](../waves-run.md) · [`../run-flow.md`](../run-flow.md) · [`../loot-and-equipment.md`](../loot-and-equipment.md)
