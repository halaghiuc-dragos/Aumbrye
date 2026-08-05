# Dialogue and quests — improvement plan

## Current state
Branching dialogue and three quests are wired through hub Mira, the quest board, and `RunFlow` kill forwarding. See [`../existing_codebase/dialogue-quests.md`](../existing_codebase/dialogue-quests.md). Kill quests work end-to-end. Fetch never completes (`register_fetch` has no callers). Escape quests complete on any `run_ended`, including death — the same defect tracked as [`run-flow.md`](run-flow.md) **RFL-01**. Choiceless dialogue nodes with `next` auto-advance in the same frame as `line_changed`, so several hub lore lines never stay on screen. Aldric/Elara greetings are unreachable because shop `interactType` skips dialogue.

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| DLQ-01 | P0 | Escape quests complete on death/waves failure via unconditional `_on_run_ended` → `_check_escape_quests(true)` | `quest_service.gd:102-103`, `114-122`; cross-link **RFL-01** (`run_flow.gd:426`) |
| DLQ-02 | P0 | `fetch_scrap` can never complete — `QuestService.register_fetch` has zero callers; pickup path does not invoke it | `quest_service.gd:81-90`; `world_item_pickup.gd:50-53` |
| DLQ-03 | P0 | Choiceless nodes with `next` emit `line_changed` then immediately recurse/end, so UI never holds the line; single-node dialogues leave a dead visible panel | `dialogue_runner.gd:83-92`; `dialogue_ui.gd:36-41`, `122-123` |
| DLQ-04 | P1 | Kill quests make no progress in waves — kills go to `WavesRunService.register_kill` only | `waves_run.gd:207` vs `run_flow.gd:434-436` |
| DLQ-05 | P1 | Aldric/Elara `dialogueId` never emitted — `interactType` blacksmith/merchant fires `shop_requested` only | `npc_base.gd:53-56`; `blacksmith_aldric.json:5`, `merchant_elara.json:5` |
| DLQ-06 | P1 | Unknown condition keys evaluate `true` (typos silently pass) | `dialogue_conditions.gd:55` |
| DLQ-07 | P2 | No quest tracker HUD; completed quests invisible; no prerequisites; `check_escape_on_portal` dead; `_on_returned_to_hub` empty | `quest_service.gd:44-59`, `106-111` |

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
- [ ] Dying with active `escape_castle` leaves state `active` and gold unchanged; escaping completes once and grants +50 gold. (DLQ-01 / RFL-01)
- [ ] Picking up `iron_scrap` with active `fetch_scrap` completes the quest and grants +20 gold. (DLQ-02)
- [ ] `mira_greeting` `castle_lore` stays on screen until Enter; `dungeon_lore_default` requires one confirm then closes cleanly. (DLQ-03)
- [ ] Three `castle_grunt` kills in waves complete `kill_grunts` if accepted. (DLQ-04)
- [ ] Interacting with Aldric shows `aldric_greeting` before or as gate to the forge. (DLQ-05)
- [ ] Condition `{ "minLvl": 1 }` (typo) does not pass. (DLQ-06)

## Validation
Extend `hub_m4_suite.gd` (already has kill quest coverage):

| Assertion id | Checks |
|--------------|--------|
| `hub_m4.quest.escape_not_completed_on_death` | Same as RFL plan — death leaves quest active |
| `hub_m4.quest.fetch_on_pickup` | Accept fetch, `add_item("iron_scrap")`, assert completed |
| `hub_m4.dialogue.holds_choiceless_line` | Start mira lore branch; assert runner still active after `start` before `advance` |

## Related
- Existing state: [`../existing_codebase/dialogue-quests.md`](../existing_codebase/dialogue-quests.md)
- [`run-flow.md`](run-flow.md) (**RFL-01**), [`inventory-service.md`](inventory-service.md), [`npc-hub-services.md`](npc-hub-services.md), [`ui/dialogue_quests.md`](ui/dialogue_quests.md)
