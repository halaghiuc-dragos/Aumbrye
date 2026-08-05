# Talents UI — improvement plan

## Current state
The talent tree is presented as a flat 18-row `ItemList` with the branch name in brackets; the `requires` graph in content is never drawn. Clicking a row does not move the internal cursor, so `Enter` can unlock a different talent than the one highlighted. The panel self-opens on the `talents` action in every scene, including the main menu, and that action shares gamepad button `7` with `heal`. The only localized text in the whole client lives here — talent names — while the surrounding labels are hardcoded English. See [`../existing_codebase/ui/talents.md`](../existing_codebase/ui/talents.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| TAL-01 | P0 | Clicking a row and pressing accept can unlock the wrong talent: `item_selected` is never connected, so the visible selection and `_cursor` diverge. | `:34-36`, `:73-74`, `:145-151` |
| TAL-02 | P0 | There is no tree. Eighteen nodes in one flat list, with `requires` prerequisites present in content and never shown, so the player cannot see paths, tiers, or branch identity. | `:88-99`, `:108-110`; `content/talents/tree.json:22`, `:30`, `:38` |
| TAL-03 | P0 | The panel opens over the title screen and main menu, because it self-opens on the `talents` action while living on the always-present `PlayerControls` layer. | `:63-67`; `player_controls.gd:27`; `project.godot:49` |
| TAL-04 | P0 | `talents` and `heal` share gamepad button `7`, so healing on a pad also opens the talent panel. | `project.godot:271-276`, `:283-288` |
| TAL-05 | P1 | No focus owner: navigation depends on the panel intercepting `ui_up`/`ui_down` globally rather than on a focused control. | `:48-53`, `:76-85` |
| TAL-06 | P1 | Raw content identifiers are shown as effect text, e.g. `physicalDamage +3%`. | `:128-135` |
| TAL-07 | P1 | No talent descriptions, no cost, no prerequisite text, no rank preview — only effect math and the word `Locked`. | `content/talents/tree.json:9-16`; `:119-142` |
| TAL-08 | P1 | Opening does not pause, so the panel floats over live combat with the cursor released. | `:48-53` |
| TAL-09 | P1 | Every string except talent names is hardcoded English, in the one file that already uses `tr()`. Meanwhile `UI_PAUSE` and `UI_RESUME` sit unused in `strings.csv`. | `:28`, `:41`, `:112`, `:141`; `strings.csv:2-3`; `pause_menu.gd:55`, `:60` |
| TAL-10 | P2 | No talent or branch icons. | `:108-110` |
| TAL-11 | P2 | Respec is discoverable only as a blacksmith button and is never referenced here. | `blacksmith_ui.gd:27-30` |
| TAL-12 | P2 | Unlock is instant with no confirmation and no undo window. | `:145-151` |
| TAL-13 | P2 | Unlocking calls `InventoryService.apply_equipment_to_player_node` on a possibly absent player node as its stat-refresh mechanism. | `:150` |
| TAL-14 | P2 | A `560 × 260` minimum list inside a `680 × 520` panel prevents the panel from clamping to small windows. | `:35`, `:28` |

## Target design

### An actual tree
`scenes/ui/talents.tscn` renders three branch columns with tiered rows and drawn dependency lines:

```
TalentsUI (MenuModal)
└── PanelContainer "Panel"                  TalentPanel variation, clamped
    └── MarginContainer → VBoxContainer
        ├── HBoxContainer "HeaderRow"
        │   ├── Label "TitleLabel"           MenuTitle
        │   ├── HBoxContainer "PointsBox"    star icon + "PointsValue" + "SpentValue"
        │   └── Button "RespecButton"        opens the respec confirmation, cost from BlacksmithService
        ├── HBoxContainer "BranchTabs"       Arms │ Guard │ Aptitude (also selectable with bumpers)
        ├── HBoxContainer "Body"
        │   ├── Control "TreeCanvas"          custom _draw of dependency links
        │   │   └── GridContainer "Nodes"     3 columns × 6 tiers of TalentNode
        │   └── PanelContainer "TalentDetail"
        │       ├── Label "NameLabel" + Label "RankLabel"     "Rank 1 / 3"
        │       ├── Label "DescLabel"                          from descKey
        │       ├── GridContainer "EffectRows"                 stat display name │ current │ next
        │       ├── Label "RequirementLabel"                   names the missing prerequisite
        │       └── HBoxContainer "CostRow"                    star icon + cost
        └── HBoxContainer "FooterRow"        Unlock │ Close + glyph hint captions
```

`TalentNode` (`scenes/ui/talent_node.tscn`):
```
TalentNode (Button, FOCUS_ALL, toggle_mode)
├── TextureRect "Frame"       48 × 48 state frame: locked / available / partial / maxed
├── TextureRect "Icon"        32 × 32 from talent_icons atlas
└── Label "RankLabel"         "2/3" bottom-right
```

`TreeCanvas._draw` connects each node to its `requires` nodes with a 2-px line, drawn in `TALENT_LINK_LOCKED` or `TALENT_LINK_UNLOCKED` theme colors, so the path is visible at a glance (TAL-02, TAL-10).

Talent icon atlas: `assets/ui/atlas/talent_icons.png`, `8 × 4` grid of `32 × 32` cells (`256 × 128`), cell ids `talent_<node_id>` plus `branch_arms`, `branch_guard`, `branch_aptitude`, and four state frames in `assets/ui/atlas/ui_frames.png` under `talent_frame_<state>`.

Rejected alternative: keeping the list and adding an indent per tier. It communicates depth but not branching, and the content already models a DAG through `requires`.

### Selection with one source of truth
Nodes are focusable buttons; the focused node is the selection, and `TalentDetail` updates on `focus_entered`. The `_cursor` field and the `ItemList` are deleted, which removes the click/keyboard divergence entirely (TAL-01, TAL-05).

Focus rules:
- `initial_focus` is the first available node of the currently selected branch, else that branch's first node.
- `ui_left`/`ui_right` move across branch columns at the same tier; `ui_up`/`ui_down` move tiers.
- Bumpers switch branch tabs; `ui_accept` unlocks; `RespecButton` is reachable from the top row.

### Readable effects and content additions
Stat identifiers map through `StatDisplay.name_for(stat)` to localized names and formats (`percent`, `flat`, `seconds`), so the detail row reads `Physical damage  +3%  →  +8%`. Content gains per-node `descKey` and an optional `flavorKey`, and the detail pane shows `costPerRank`, the current rank, the next rank, and the specific missing prerequisite by name (TAL-06, TAL-07).

### Gating, pausing, and input
- `TalentsUI` no longer handles the `talents` action itself. `PlayerControls` owns the binding, refuses to open while `allows_player_ui()` is false (front end, cutscene, dialogue), and pushes the panel onto `MenuStack`, which pauses the tree and owns mouse mode and `ui_cancel` (TAL-03, TAL-05, TAL-08).
- `heal` is rebound to gamepad button `3`, and a validation test forbids two rebindable actions sharing a joypad event (TAL-04).

### Respec and confirmation
`RespecButton` opens the same `MenuStack.confirm` the blacksmith uses, sharing one `ProgressionService.respec()` path and stating the cost and the number of points that will be refunded. Unlocking a talent asks for confirmation only when it spends the last available point, so ordinary progress stays fast (TAL-11, TAL-12).

### Stat refresh
Unlocking calls `ProgressionService.notify_talents_changed()`, which emits `progression_changed`; the player node listens and re-applies its derived stats. The direct `InventoryService.apply_equipment_to_player_node` call from the UI is removed (TAL-13).

### Localization
Keys: `TALENT_TITLE`, `TALENT_POINTS`, `TALENT_SPENT`, `TALENT_UNLOCK`, `TALENT_RESPEC`, `TALENT_RESPEC_CONFIRM`, `TALENT_RANK`, `TALENT_REQUIRES`, `TALENT_MAXED`, `TALENT_HINT_*`, `STAT_<STAT_ID>` for every stat in the effect table, plus `descKey` rows for all 18 nodes. `UI_PAUSE` and `UI_RESUME` are adopted by the pause menu so `strings.csv` has no dead keys (TAL-09).

## Work plan
1. **Author `talents.tscn` and `talent_node.tscn`**, with branch tabs and the tiered grid (TAL-02).
2. **`TreeCanvas._draw` dependency links** with locked/unlocked colors (TAL-02).
3. **Delete `_cursor` and the `ItemList`**; drive selection from focus (TAL-01, TAL-05).
4. **Author `talent_icons.png` and the four state frames** (TAL-10).
5. **`StatDisplay` mapping and content `descKey`/`flavorKey`**; detail pane with rank, next rank, cost, missing prerequisite (TAL-06, TAL-07).
6. **Move the `talents` action to `PlayerControls`**, gate on `allows_player_ui()`, register with `MenuStack` (TAL-03, TAL-08).
7. **Rebind `heal` to pad button 3** and add the collision test (TAL-04).
8. **Respec button and shared confirm path**; last-point confirmation (TAL-11, TAL-12).
9. **`notify_talents_changed` refresh path** (TAL-13).
10. **Localization sweep, including adopting `UI_PAUSE`/`UI_RESUME`** (TAL-09).

## Data and schema changes
- `content/talents/tree.json`: per-node `descKey`, optional `flavorKey`, optional `iconId`; branch `iconId`.
- New `assets/ui/atlas/talent_icons.png` (`8 × 4` grid, `32 × 32` cells); four `talent_frame_<state>` cells in `ui_frames.png`.
- New `scenes/ui/talents.tscn`, `scenes/ui/talent_node.tscn`, `scripts/ui/tree_canvas.gd`, `scripts/ui/stat_display.gd`.
- `ProgressionService`: `notify_talents_changed()`, `respec()` shared with the blacksmith, `get_spent_talent_points()`.
- `project.godot`: `heal` joypad event changed from `7` to `3`.
- `strings.csv`: the `TALENT_*`, `STAT_*`, and 18 `descKey` rows.

## Acceptance criteria
- [ ] The panel shows three branch columns with six tiers and drawn dependency lines.
- [ ] Clicking a node and pressing accept always affects that node; `_cursor` no longer exists.
- [ ] Every node shows an icon and a state frame, and maxed nodes are visually distinct.
- [ ] The detail pane shows a localized name, description, current and next rank values with localized stat names, cost, and the specific missing prerequisite.
- [ ] No raw stat identifier appears anywhere in the panel.
- [ ] The panel cannot be opened on the title screen or main menu.
- [ ] Pressing heal on a gamepad does not open the talent panel.
- [ ] Opening the panel pauses the game and releases the cursor; closing restores both.
- [ ] Respec is reachable from the panel and uses the same service path as the blacksmith.
- [ ] Spending the last available point asks for confirmation.
- [ ] `talents_ui.gd` contains no `InventoryService` call and no `Input.mouse_mode` write.
- [ ] The panel fits a `1280 × 720` window at UI scale `1.5`.
- [ ] Every visible string resolves from `strings.csv`, and no key in `strings.csv` is unused.

## Validation
Extend `apps/game/client/scripts/validation/suites/m5_suite.gd` (progression) and add `talents` cases:

| Test id | Assertion |
|---|---|
| `talents.tree_layout` | node count per branch is `6`, and each node's grid position matches its tier from `requires` depth |
| `talents.links_drawn` | `TreeCanvas` draws one link per `requires` entry |
| `talents.selection_single_source` | `talents_ui.gd` contains no `_cursor`; focusing a node updates the detail pane; accept unlocks the focused node |
| `talents.click_then_accept` | clicking node `guard_3` then pressing accept attempts `guard_3`, not another id |
| `talents.icons_present` | every node has a non-null icon and a state frame matching its state |
| `talents.detail_fields` | the detail pane exposes name, description, current rank, next-rank value, cost, and requirement text |
| `talents.no_raw_stats` | no visible label contains a raw stat id from the effect table |
| `talents.front_end_blocked` | with the current scene in the `front_end` group, the `talents` action leaves `is_open() == false` |
| `talents.heal_no_collision` | no two rebindable actions share a joypad event; `heal` uses button `3` |
| `talents.pauses` | opening sets `get_tree().paused == true`; closing restores the previous value |
| `talents.respec_shared_path` | the panel's respec and the blacksmith's respec both call `ProgressionService.respec()` |
| `talents.last_point_confirm` | unlocking with exactly one point left opens a confirmation |
| `talents.no_inventory_call` | the script contains no `InventoryService` reference |
| `talents.no_mouse_mode` | the script contains no `Input.mouse_mode` |
| `talents.panel_clamped` | at a `1280 × 720` viewport the panel fits inside the window |
| `talents.localized` | every visible string resolves from a `strings.csv` key |
| `talents.no_dead_keys` | every key in `strings.csv` is referenced by at least one script or content file |

## Related
- Existing behavior: [`../existing_codebase/ui/talents.md`](../existing_codebase/ui/talents.md)
- Coordination: [`dialogue_quests_talents.md`](dialogue_quests_talents.md)
- [`dialogue_quests.md`](dialogue_quests.md) · [`hub_vendors.md`](hub_vendors.md) · [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`pause_menu.md`](pause_menu.md) · [`settings.md`](settings.md)
- [`../progression-service.md`](../progression-service.md) · [`../content-data.md`](../content-data.md) · [`../player-controls.md`](../player-controls.md) · [`../combat-core.md`](../combat-core.md)
