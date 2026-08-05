# Talents UI

The talent panel: a flat `ItemList` of every node in the tree, a points counter, a detail line, and a hint. Owned by the `PlayerControls` autoload, so it exists in every scene.

## File
`apps/game/client/scripts/ui/talents_ui.gd` — 172 lines, `extends Control`. No scene; created at `player_controls.gd:27`.

## Control tree (`_build_ui`, `:27-41`)
```
Control (TalentsUI, PROCESS_MODE_ALWAYS)
├── ColorRect "Backdrop"
└── PanelContainer "Panel"        (half 340 × 260 from MenuShell.build_modal)
    └── MarginContainer "Margin"
        └── VBoxContainer "ContentVBox"
            ├── Label "TitleLabel"    "Talents"
            ├── Label "PointsLabel"   "Points: %d"
            ├── ItemList              custom_minimum_size 560 × 260
            ├── Label (detail, autowrap)
            └── Label "HintLabel"     "Enter: unlock | Esc: close"
```

## Data
| Concern | Source |
|---|---|
| Tree | `ProgressionService.get_talent_tree()`, flattened branch-by-branch into `_nodes` with `branchName`/`branchNameKey` copied onto each node (`:88-99`) |
| Rows | `"[%s] %s (%d/%d)"` — branch display name, talent display name, current rank, `maxRank` (`:108-110`) |
| Points | `ProgressionService.get_available_talent_points()` (`:112`) |
| Detail | effect list built from `effects[].stat` and `valuePerRank`, then `"Can unlock"` or `"Locked"` from `can_unlock_talent` (`:119-142`) |
| Unlock | `ProgressionService.unlock_talent(id)`, then `InventoryService.apply_equipment_to_player_node(player)` (`:145-151`) |
| Refresh | `ProgressionService.progression_changed` (`:23-24`) |

Content: `content/talents/tree.json` — three branches (`arms`, `guard`, `aptitude`) of six nodes each, every node with `nameKey`, `maxRank`, `costPerRank`, `requires`, and `effects` (`:4-45`).

## Localization
`_localized_label` (`:162-171`) calls `tr(key)` and falls back to `name`, then `id`. This is the only `tr(` call in the entire client: 1 match across `apps/game/client/scripts/`. `translations/strings.csv` has 26 lines — `keys,en` plus `UI_PAUSE`, `UI_RESUME`, `STORY_PREMISE`, and the 21 talent branch and node keys — and `project.godot:303` registers a single `en` translation.

`UI_PAUSE` and `UI_RESUME` exist in `strings.csv:2-3` and are used nowhere; `pause_menu.gd:55` and `:60` hardcode `"Paused"` and `"Resume"`.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Spending points and refreshing | IMPLEMENTED | `:145-151`, `:102-116` |
| Talent name localization | IMPLEMENTED — the only localized surface in the client | `:162-171`; `strings.csv:5-25` |
| Tree structure | PLACEHOLDER — the "tree" is a flat 18-row `ItemList` with the branch name in brackets. `requires` prerequisites exist in content and are never drawn, so no dependency, tier, or branch layout is visible | `:88-99`, `:108-110`; `content/talents/tree.json:22`, `:30`, `:38` |
| Mouse selection vs. keyboard cursor | BROKEN — `item_selected` is never connected, so clicking a row moves the `ItemList`'s visible selection while `_cursor` stays where it was; `ui_accept` then unlocks the talent at `_cursor`, not the one the player clicked | `:34-36` (no `item_selected` connect), `:73-74`, `:145-151` |
| Focus | ABSENT — `open_talents` never calls `grab_focus`; navigation works only because the panel intercepts `ui_up`/`ui_down` in `_unhandled_input` | `:48-53`, `:76-85` |
| Availability outside gameplay | BROKEN — the panel self-opens on the `talents` action from its own `_unhandled_input`, and as a `PlayerControls` child it exists on the title screen and main menu too, so the talent list can be opened over the front end | `:63-67`; `player_controls.gd:27`; `project.godot:49` |
| Input collision | BROKEN — `talents` is bound to gamepad button `7` and `heal` is bound to the same button, so a heal press on a pad also opens the talent panel | `project.godot:271-276` and `:283-288` |
| Pause behavior | PARTIAL — opening does not pause the tree, so the panel appears over live combat with the cursor released | `:48-53` (no `get_tree().paused`) |
| Stat names | PARTIAL — the detail line prints raw content identifiers such as `physicalDamage +3%` and `staminaCostReduction +5%` | `:128-135` |
| Talent descriptions | ABSENT — content has no `descKey`, and the UI shows only effect math | `content/talents/tree.json:9-16`; `:119-142` |
| Cost display | ABSENT — `costPerRank` exists in content and is never shown | `content/talents/tree.json:13`; `:102-142` |
| Prerequisite explanation | PARTIAL — locked nodes show the word `"Locked"` with no statement of what is required | `:136-142` |
| Rank preview | ABSENT — no current-versus-next-rank comparison | `:119-142` |
| Icons | ABSENT — rows and branches are text only | `:108-110` |
| Respec discoverability | ABSENT — respec exists only as a blacksmith button and is not mentioned here | `blacksmith_ui.gd:27-30` |
| Other strings | PARTIAL — `"Talents"`, `"Points: %d"`, `"Can unlock"`, `"Locked"`, and the hint are hardcoded English despite the file being the one place that uses `tr()` | `:28`, `:41`, `:112`, `:141` |
| Mouse mode | PARTIAL — releases the cursor on open and captures it on close unconditionally | `:53`, `:60` |
| Player-node coupling | PARTIAL — unlocking calls `InventoryService.apply_equipment_to_player_node` on the `player` group, which is null when the panel is used outside gameplay | `:150` |
| Panel sizing | PARTIAL — a `560 × 260` minimum list inside a `680 × 520` panel, so the panel cannot clamp below the list | `:35`; `:28` |

## Related
- Improvement plan: [`../actual_improvements/ui/talents.md`](../actual_improvements/ui/talents.md)
- Coordination: [`dialogue_quests_talents.md`](dialogue_quests_talents.md)
- [`dialogue_quests.md`](dialogue_quests.md) · [`hub_vendors.md`](hub_vendors.md) · [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`combat_hud.md`](combat_hud.md)
- [`../progression-service.md`](../progression-service.md) · [`../content-data.md`](../content-data.md) · [`../player-controls.md`](../player-controls.md) · [`../accessibility.md`](../accessibility.md)
