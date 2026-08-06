# Dialogue and quests — improvement plan

## Status: FINISHED

## Current state
Branching dialogue and three quests are wired through hub Mira, the quest board, and `RunFlow` kill forwarding. Escape quests complete only via `register_run_outcome(OUTCOME_ESCAPED)`; fetch completes via `InventoryService.add_item` → `register_fetch`. Choiceless dialogue holds until `DialogueRunner.advance()`; waves kills forward to `QuestService.register_kill`; Aldric/Elara greet via dialogue before shop; unknown condition keys fail closed; quest tracker HUD and completed list ship on hub and combat HUD. See [`../existing_codebase/dialogue-quests.md`](../existing_codebase/dialogue-quests.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| DLQ-01 | P0 | ~~Escape on death~~ **FINISHED** — `register_run_outcome`; `_on_run_ended` clears progress only | `quest_service.gd` |
| DLQ-02 | P0 | ~~`register_fetch` uncalled~~ **FINISHED** — `inventory_service.gd:add_item` | was zero callers |
| DLQ-03 | P0 | ~~Choiceless auto-advance~~ **FINISHED** — holds line until `advance()`; optional `"auto": true` | `dialogue_runner.gd:83-92` |
| DLQ-04 | P1 | ~~Waves kills not forwarded~~ **FINISHED** — `waves_run.gd:_on_enemy_died` calls `QuestService.register_kill` | `waves_run.gd:207-212` |
| DLQ-05 | P1 | ~~Aldric/Elara dialogue unreachable~~ **FINISHED** — `npc_base.gd` emits `dialogue_requested` when `dialogueId` set | `npc_base.gd:53-64` |
| DLQ-06 | P1 | ~~Unknown condition keys pass~~ **FINISHED** — `push_warning` + `return false` | `dialogue_conditions.gd:55-56` |
| DLQ-07 | P2 | ~~No quest tracker / completed list / dead helpers~~ **FINISHED** — `quest_tracker_ui`; `get_completed_quests`; removed stubs | `quest_service.gd`, `quest_board_ui.gd` |

## Target design

### Escape honesty (align with RFL-01)
Implement the run-flow plan's `QuestService.register_run_outcome(outcome, context)` and complete `escape` quests only when `outcome == OUTCOME_ESCAPED`. Reduce `_on_run_ended` to clearing per-run escape progress. Delete `check_escape_on_portal`. **Do not invent a second fix** — land the same API RFL-01 specifies so the two docs stay one change.

### Fetch wiring
`InventoryService.add_item` / `world_item_pickup._pickup` / chest open paths call `QuestService.register_fetch(item_id)` after a successful add. Keep auto-complete semantics already described in `fetch_scrap.json`.

### Dialogue advance contract
Choiceless nodes must **stop** after `line_changed` and wait for `DialogueRunner.advance()` (Enter / interact), matching choice nodes. Only auto-follow `next` when an explicit `"auto": true` is set (optional, default false). Single-node `"next": "end"` dialogues wait for one confirm before `dialogue_ended`.

Rejected: keep auto-advance and add artificial delays — that fights input and gamepad confirm patterns already in `dialogue_ui.gd`.

### Shop NPCs
On blacksmith/merchant interact: either (a) emit dialogue first when `dialogueId` set and only open shop via dialogue action, or (b) open shop then offer a "Talk" button that starts dialogue. Prefer (a) so authored greetings are reachable without UI sprawl.

### Conditions
Unknown keys → `push_warning` + `return false` in debug; ship build may keep fail-closed `false`.

## Work plan

1. **Fix dialogue auto-advance (DLQ-03)** — stop after emit; drive `advance()` from UI. Independently landable.
2. **Wire `register_fetch` on successful item add (DLQ-02)** — `inventory_service.gd` / pickup / chest.
3. **Land RFL-01 escape outcome gating (DLQ-01)** — shared with run-flow work plan step 5.
4. **Forward waves kills to `QuestService.register_kill` (DLQ-04)**.
5. **Route Aldric/Elara through dialogue before shop (DLQ-05)**.
6. **Fail-closed unknown conditions + delete dead escape helpers (DLQ-06, part of DLQ-07)**.
7. **Optional quest tracker HUD + completed list (DLQ-07)** — P2.

## Data and schema changes

- Optional dialogue node key `"auto": boolean` in `dialogue-definition.v1.json`.
- No quest schema change for fetch/escape fixes.
- Save: none beyond quest state already stored.

## Acceptance criteria
- [x] Dying with active `escape_castle` leaves state `active` and gold unchanged; escaping completes once and grants +50 gold. (DLQ-01 / RFL-01)
- [x] Picking up `iron_scrap` with active `fetch_scrap` completes the quest and grants +20 gold. (DLQ-02)
- [x] `mira_greeting` `castle_lore` stays on screen until Enter; `dungeon_lore_default` requires one confirm then closes cleanly. (DLQ-03)
- [x] Three `castle_grunt` kills in waves complete `kill_grunts` if accepted. (DLQ-04)
- [x] Interacting with Aldric shows `aldric_greeting` before or as gate to the forge. (DLQ-05)
- [x] Condition `{ "minLvl": 1 }` (typo) does not pass. (DLQ-06)

## Validation
Extend `hub_m4_suite.gd` (already has kill quest coverage):

| Assertion id | Checks |
|--------------|--------|
| `hub_m4.quest.escape_not_completed_on_death` | Same as RFL plan — death leaves quest active |
| `hub_m4.quest.fetch_on_pickup` | Accept fetch, `add_item("iron_scrap")`, assert completed |
| `hub_m4.dialogue.holds_choiceless_line` | Start mira lore branch; assert runner still active after `start` before `advance` |
| `hub_m4.dialogue.single_node_confirm` | `dungeon_lore_default` holds until one `advance()` |
| `hub_m4.dialogue.fail_closed_typo` | `{ "minLvl": 1 }` evaluates false |
| `hub_m4.npc.shop_dialogue_first` | Aldric/Elara `dialogueId` routed through `dialogue_requested` |
| `hub_m4.quest.waves_kill_forward` | `waves_run.gd` forwards kills; three grunts complete quest |
| `hub_m4.quest.tracker_and_cleanup` | Tracker scene, `get_completed_quests`, no dead escape helpers |
| `hub_m4.quest.completed_list` | Completed quest returned by `get_completed_quests` |

## Related
- Existing state: [`../existing_codebase/dialogue-quests.md`](../existing_codebase/dialogue-quests.md)
- [`run-flow.md`](run-flow.md) (**RFL-01**), [`inventory-service.md`](inventory-service.md), [`npc-hub-services.md`](npc-hub-services.md), [`ui/dialogue_quests.md`](ui/dialogue_quests.md)
