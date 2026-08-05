# Dialogue, quests, and talents — coordination improvement plan

## Current state
The three panels that carry the game's non-combat progression share nothing: three navigation models, three skinning approaches (one of them none), three direct `Input.mouse_mode` writes, and no common notification path. A quest can complete mid-run and grant gold and items without a single pixel of feedback. Talent points accumulate with nothing but the talent panel ever mentioning them. Dialogue exists only in the hub scene while dungeon rooms depend on it. See [`../existing_codebase/ui/dialogue_quests_talents.md`](../existing_codebase/ui/dialogue_quests_talents.md), and the per-surface plans in [`dialogue_quests.md`](dialogue_quests.md) and [`talents.md`](talents.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| DQT-01 | P0 | Quest completion is invisible: rewards are granted silently and `quest_updated` has one listener, the board itself. A player can finish a quest, receive gold and an item, and never be told. | `quest_service.gd:32-41`, `:125-133`; `quest_board_ui.gd:23` |
| DQT-02 | P0 | Unspent talent points are never surfaced outside the talent panel; the getter has exactly one call site, so leveling up produces no visible prompt to spend. | `talents_ui.gd:112`; 1 match for `get_available_talent_points` in `apps/game/client/scripts/` |
| DQT-03 | P0 | Dialogue and the quest board exist only in the hub scene while dungeon lore and NPC quest rooms look the dialogue panel up by group, so those room types are inert during runs. | `hub.tscn:9`, `:13`; `room_lore_content.gd:41-47`; `room_npc_quest_content.gd:45-47` |
| DQT-04 | P0 | Three sibling panels use three navigation models, two without any focus owner, so no consistent controller contract exists for progression UI. | `dialogue_ui.gd:96-119`; `quest_board_ui.gd:35`; `talents_ui.gd:76-85` |
| DQT-05 | P1 | Skinning is inconsistent across the three: `apply_modal_menu`, `MenuShell.build_modal`, and nothing at all. | `dialogue_ui.gd:24`; `talents_ui.gd:28`; `quest_board_ui.gd:16-23` |
| DQT-06 | P1 | No icon art anywhere in the three surfaces; every list, choice, and node is text. | `dialogue_ui.tscn:39-53`; `quest_board_ui.gd:56-67`; `talents_ui.gd:108-110` |
| DQT-07 | P1 | Content is inconsistently localized: talent names use `tr()` — the only `tr(` call in the client — while dialogue, quests, and all surrounding chrome are literal English, and `strings.csv` carries two unused UI keys. | `talents_ui.gd:165`; `content/dialogue/aldric_greeting.json:6-11`; `content/quests/kill_grunts.json:3`; `strings.csv:2-3` |
| DQT-08 | P1 | No quest tracking: `QuestService` has no HUD consumer, so an accepted quest gives no in-run guidance. | `quest_service.gd:1-133` |
| DQT-09 | P1 | All three write `Input.mouse_mode` directly and capture on close, and none pauses, so any of them can float over live gameplay with contradictory cursor state. | `dialogue_ui.gd:40`, `:49`; `quest_board_ui.gd:34`, `:41`; `talents_ui.gd:53`, `:60` |
| DQT-10 | P2 | Dialogue actions are dispatched through `get_parent().call(...)`, coupling the panel to being a hub child, and unknown types vanish. | `dialogue_ui.gd:126-136` |
| DQT-11 | P2 | Respec spans two systems with one entry point: a code-added blacksmith button, never mentioned in the talent panel. | `blacksmith_ui.gd:27-30`; `talents_ui.gd:27-41` |
| DQT-12 | P2 | Content declares rewards and costs that no surface displays. | `content/quests/kill_grunts.json:8`; `content/talents/tree.json:13` |

## Target design

### One notification channel
`scripts/ui/notification_center.gd`, autoloaded as `NotificationCenter`, owns a bottom-right toast queue on the `PlayerControls` layer and is the single place any system announces progression:

| Kind | Trigger | Content |
|---|---|---|
| `quest_accepted` | `QuestService.quest_updated(_, "active")` | quest icon, title, first objective |
| `quest_progress` | new `QuestService.objective_progressed` | quest icon, `n/m` |
| `quest_completed` | `quest_updated(_, "completed")` | quest icon, title, reward row with gold and item icons |
| `talent_point` | `ProgressionService.progression_changed` when available points increase | star icon, count, and the `talents` glyph |
| `level_up` | `CharacterService.level_changed` | level number and the points granted |
| `achievement` | existing achievement path | reuses the same toast (see [`run_outcome.md`](run_outcome.md)) |

Toasts are `scenes/ui/toast_card.tscn`, queued at most three at a time, `4` s each with a `0.25` s slide, suppressed while a modal is open and replayed when it closes. This replaces the current per-system silence and gives `achievement_toast.gd` a home rather than a parallel implementation (DQT-01, DQT-02).

Rejected alternative: adding a HUD badge only. A badge answers "do I have points" but not "what did I just earn"; the toast queue covers both and is reused by three systems.

### Persistent unspent-points affordance
Beyond the toast, an unspent-points pip appears on:
- the HUD XP row (`combat_hud.gd` level cluster),
- the pause menu row that leads to talents,
- the talent panel's own header.

All three read `ProgressionService.get_available_talent_points()` through a shared `ProgressionBadge` control so the number cannot drift (DQT-02).

### Global panels and a modal stack
Dialogue, the quest board, and talents all move onto the `PlayerControls` layer and register with `MenuStack` (specified in [`menu_shell.md`](menu_shell.md)), which owns pausing, mouse mode, `ui_cancel`, focus restoration, and suppression of gameplay input. No panel writes `Input.mouse_mode` again (DQT-03, DQT-09).

Room content keeps calling `get_first_node_in_group("dialogue_ui")`, which now always resolves; `PlayerControls.open_dialogue(id)` is the preferred call and returns `false` when a modal is already open.

### One navigation contract
Every progression panel follows the same rules, enforced by tests in [`menu_shell_a11y.md`](menu_shell_a11y.md):
1. a focus owner exists at all times while open;
2. `initial_focus` is declared in the scene;
3. selection is derived from focus — no parallel index variables;
4. `ui_accept` commits, `ui_cancel` backs out one level;
5. bumpers switch tabs or branches;
6. every actionable row is a `Button` with a visible focus style from the shared theme.

The `_cursor` in `talents_ui.gd` and the `_selected_index` in `dialogue_ui.gd` are both deleted (DQT-04).

### Shared visual language
All three adopt the shared theme and the same atlases (DQT-05, DQT-06):

| Atlas | Grid | Cell | Used by |
|---|---|---|---|
| `assets/ui/atlas/quest_icons.png` | `4 × 2` | `24 × 24` | quest cards, toasts, HUD tracker |
| `assets/ui/atlas/talent_icons.png` | `8 × 4` | `32 × 32` | talent nodes, toasts |
| `assets/ui/atlas/item_icons.png` | `16 × 16` | `32 × 32` | quest rewards, vendors, inventory |
| `assets/ui/atlas/ui_symbols.png` | `8 × 8` | `16 × 16` | currency, star, check mark, glyph captions |
| `assets/ui/atlas/ui_frames.png` | 9-slice | — | panels, cards, node state frames |

Theme variations shared by the three: `MenuTitle`, `MenuSection`, `CardTitle`, `CardBody`, `CardValue`, `RowFocus`, `HintCaption`, `ToastTitle`, `ToastBody`.

### Content and text unification
- Dialogue nodes use `speakerId` + `textKey`; choices use `textKey`.
- Quests use `titleKey`, `descKey`, and an `objectives[]` array.
- Talents gain `descKey` and `flavorKey`.
- All player-visible enums (quest type, stat id) resolve through `StatDisplay` / `QuestTypeDisplay` maps to `strings.csv` keys.
- `UI_PAUSE` and `UI_RESUME` are adopted by the pause menu, so no key in `strings.csv` is dead (DQT-07, DQT-12).

A content validation pass fails the build when any player-visible string in `content/dialogue`, `content/quests`, or `content/talents` is a literal instead of a key.

### Quest tracking into the run
`QuestService` gains `set_tracked_quest(id)` / `get_tracked_objective()`, stored in `WorldState`. The HUD objective banner shows the tracked objective and its `n/m`, and the minimap marks the target room type when the objective is location-bound (see [`minimap.md`](minimap.md) and [`combat_hud.md`](combat_hud.md)) (DQT-08).

### Action registry and respec
`DialogueActions` replaces `get_parent().call(...)` with an explicit registry that resolves services directly, logs unknown types, and gains `give_item`, `set_flag`, and `start_run`. Respec becomes `ProgressionService.respec()` with two entry points — the blacksmith and the talent panel header — sharing one confirmation spec (DQT-10, DQT-11).

## Work plan
1. **`NotificationCenter` + `toast_card.tscn`**, and route quest, talent, level, and achievement events into it (DQT-01, DQT-02).
2. **`ProgressionBadge`** on the HUD, pause menu, and talent header (DQT-02).
3. **Move dialogue, quest board, and talents onto the `PlayerControls` layer and `MenuStack`** (DQT-03, DQT-09).
4. **Delete the parallel selection indices** and adopt the navigation contract in all three (DQT-04).
5. **Adopt the shared theme and atlases**, removing `apply_modal_menu` from dialogue and adding real skinning to the board (DQT-05, DQT-06).
6. **Content key migration** for dialogue, quests, talents, plus display maps for enums and stats, and the content validation pass (DQT-07, DQT-12).
7. **Objectives schema, tracking, and HUD/minimap consumers** (DQT-08).
8. **`DialogueActions` registry** (DQT-10).
9. **Shared respec path with two entry points** (DQT-11).

## Data and schema changes
- New `scripts/ui/notification_center.gd` (autoload), `scenes/ui/toast_card.tscn`, `scripts/ui/progression_badge.gd`, `scripts/dialogue/dialogue_actions.gd`, `scripts/ui/quest_type_display.gd`, `scripts/ui/stat_display.gd`.
- `QuestService`: `objective_progressed` signal, `get_objective_progress`, `set_tracked_quest`, `abandon_quest`.
- `ProgressionService`: `respec()`, `notify_talents_changed()`, `get_spent_talent_points()`.
- `WorldState`: tracked quest id.
- Content: dialogue `speakerId`/`textKey`, quest `titleKey`/`descKey`/`objectives`, talent `descKey`/`flavorKey`.
- Atlases as tabled above.
- `strings.csv`: `TOAST_*`, `QUEST_*`, `TALENT_*`, `STAT_*`, `DLG_*` keys, and adoption of `UI_PAUSE`/`UI_RESUME`.

## Acceptance criteria
- [ ] Completing a quest during a run shows a toast naming the quest and its rewards with icons.
- [ ] Accepting a quest and progressing an objective each produce a toast.
- [ ] Leveling up shows a toast, and an unspent-points pip appears on the HUD, the pause menu, and the talent header until points are spent.
- [ ] Dialogue opens from a dungeon lore room and from a dungeon NPC quest room.
- [ ] All three panels have a focus owner at all times, declare `initial_focus`, and contain no parallel selection index.
- [ ] All three use the shared theme; the quest board is visually indistinguishable in chrome from the vendor panels.
- [ ] No raw enum or stat identifier is visible in any of the three panels.
- [ ] Every player-visible string in dialogue, quest, and talent content is a key, and the content validation pass fails when a literal is introduced.
- [ ] A tracked quest's objective appears on the HUD with `n/m`.
- [ ] None of the three scripts writes `Input.mouse_mode`; opening any of them pauses the tree.
- [ ] Respec is reachable from both the blacksmith and the talent panel and runs one service path.
- [ ] `strings.csv` has no unused key.

## Validation
Add a `progression_ui` group to `apps/game/client/scripts/validation/suites/m5_suite.gd`:

| Test id | Assertion |
|---|---|
| `progression_ui.quest_complete_toast` | completing `kill_grunts` enqueues a `quest_completed` toast containing `30` gold and `health_potion` |
| `progression_ui.quest_accept_toast` | accepting a quest enqueues a `quest_accepted` toast |
| `progression_ui.talent_point_toast` | gaining a level enqueues a `talent_point` toast |
| `progression_ui.badge_consistency` | HUD, pause menu, and talent header all report the same unspent-point count |
| `progression_ui.badge_clears` | spending the last point removes all three pips |
| `progression_ui.dialogue_in_dungeon` | on a generated floor, a lore room's interact opens the dialogue bar |
| `progression_ui.focus_contract` | for each of the three panels: a focus owner exists on open, and BFS from it reaches every actionable control |
| `progression_ui.no_parallel_index` | neither `talents_ui.gd` nor `dialogue_ui.gd` declares a selection index field |
| `progression_ui.theme_shared` | all three panels' root panels use the shared panel style, and none calls `apply_modal_menu` |
| `progression_ui.icons_present` | quest cards, talent nodes, and reward rows all have non-null textures |
| `progression_ui.content_keys` | no `text`, `title`, or `description` literal remains in `content/dialogue`, `content/quests`, `content/talents` |
| `progression_ui.no_raw_enums` | no visible label equals a quest type or stat id |
| `progression_ui.tracking` | tracking a quest sets the HUD objective text and `n/m` |
| `progression_ui.no_mouse_mode` | none of the three scripts contains `Input.mouse_mode` |
| `progression_ui.pauses` | opening any of the three sets `get_tree().paused == true` |
| `progression_ui.respec_one_path` | both respec entry points call `ProgressionService.respec()` |
| `progression_ui.no_dead_keys` | every `strings.csv` key is referenced by a script or content file |
| `progression_ui.toast_suppression` | a toast raised while a modal is open is deferred and shown after the modal closes |

## Related
- Per-surface plans: [`dialogue_quests.md`](dialogue_quests.md) · [`talents.md`](talents.md)
- Existing behavior: [`../existing_codebase/ui/dialogue_quests_talents.md`](../existing_codebase/ui/dialogue_quests_talents.md)
- [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`combat_hud.md`](combat_hud.md) · [`minimap.md`](minimap.md) · [`hub_vendors.md`](hub_vendors.md) · [`run_outcome.md`](run_outcome.md) · [`status_icons_glyphs.md`](status_icons_glyphs.md)
- [`../dialogue-quests.md`](../dialogue-quests.md) · [`../progression-service.md`](../progression-service.md) · [`../achievements-meta.md`](../achievements-meta.md) · [`../world-state.md`](../world-state.md) · [`../content-data.md`](../content-data.md)
