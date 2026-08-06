# Dialogue and quests

Two small systems that share one storage bag. `DialogueCatalog` / `DialogueConditions` / `DialogueRunner` execute JSON branching trees; `QuestCatalog` / `QuestService` track three quests. Both write through `CharacterService.flags` and `CharacterService.quests`. There are five dialogue files and three quest files.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/dialogue/dialogue_catalog.gd` | `DialogueCatalog.get_dialogue(id)` — loads `content/dialogue/*.json` |
| `apps/game/client/scripts/dialogue/dialogue_conditions.gd` | `DialogueConditions.evaluate(condition)` — nine condition kinds |
| `apps/game/client/scripts/dialogue/dialogue_runner.gd` | `DialogueRunner` — node walk, choices, five action types |
| `apps/game/client/scripts/quests/quest_catalog.gd` | `QuestCatalog.get_definition(id)` / `get_all_ids()` |
| `apps/game/client/scripts/quests/quest_service.gd` | `QuestService` autoload — accept, complete, kill/fetch/escape tracking, rewards |
| `apps/game/client/scripts/ui/dialogue_ui.gd`, `quest_board_ui.gd`, `quest_tracker_ui.gd` | Presentation; see [`ui/dialogue_quests.md`](ui/dialogue_quests.md) |
| `content/dialogue/*.json` | `aldric_greeting`, `elara_greeting`, `mira_greeting`, `dungeon_npc_stranded`, `dungeon_lore_default` |
| `content/quests/*.json` | `kill_grunts`, `fetch_scrap`, `escape_castle` |

## How it works

### Dialogue document shape
Every file is `{"id", "startNode", "nodes": {<nodeId>: node}}`. A node may carry `speaker`, `text`, `condition`, `fallback`, `actions`, `next`, `auto`, and `choices`. A choice carries `text`, optional `condition`, optional `actions`, and optional `next`. The literal `"end"` and an empty string both terminate.

### `DialogueRunner`
| Function | Lines | Behaviour |
|----------|-------|-----------|
| `start(dialogue_id)` | 19-26 | Loads the document, sets `_current_node_id` from `startNode` (default `"start"`), sets `_active`, and calls `_advance_to_node` synchronously |
| `_advance_to_node(node_id)` | 67-92 | Ends when the node is missing; evaluates `node.condition` and jumps to `fallback` or ends when false; applies `node.actions`; emits `line_changed(speaker, text, visibleChoices)`; when there are no visible choices, holds the line unless `node.auto` is true, then follows `next` or ends |
| `select_choice(index)` | 29-43 | Applies the choice's `actions`, then advances to `choice.next` or ends |
| `advance()` | 46-57 | Only does anything when there are no visible choices; follows `node.next` |
| `end_dialogue()` | 60-64 | Clears state and emits `dialogue_ended` |
| `_get_visible_choices(node)` | 107-112 | Filters `choices` by `DialogueConditions.evaluate(choice.condition)` |
| `_execute_action(action)` | 123-137 | See the action table below |

Action types:

| `type` | Effect | Line |
|--------|--------|------|
| `set_flag` | `CharacterService.set_flag(action.flag, action.value ?? true)` | 127 |
| `add_gold` | `CharacterService.add_gold(action.amount)` | 129 |
| `start_quest` | `QuestService.accept_quest(action.questId)` | 131 |
| `complete_quest` | `QuestService.complete_quest(action.questId)` | 133 |
| `open_blacksmith`, `open_merchant`, `open_quest_board`, `open_storage` | Re-emitted as `action_triggered(action)` for the UI to handle | 134-135 |
| anything else | Also re-emitted as `action_triggered(action)` | 136-137 |

### `DialogueConditions.evaluate(condition)`
Returns `true` for `null`, a non-Dictionary, or an empty Dictionary (lines 8-13). Recognised keys, checked in order (lines 15-55):

| Key | Semantics |
|-----|-----------|
| `all` | Every entry must evaluate true |
| `any` | At least one entry must evaluate true |
| `not` | Negates the nested block |
| `flag` | `CharacterService.get_flag(flag) == condition.value` (default expected value `true`, default stored value `false`) |
| `minLevel` / `maxLevel` | `CharacterService.get_level()` bounds (`maxLevel` default 999) |
| `quest` | `CharacterService.get_quest_state(quest) == condition.state` (default `"active"`) |
| `gold` | `CharacterService.gold >= condition.gold` |
| `minRuns` | `int(flag "runs_started") >= condition.minRuns` |
| `minDeaths` | `int(flag "deaths") >= condition.minDeaths` |

Unrecognised keys log `push_warning` and return `false` (lines 55-56).

### Dialogue content
| File | Nodes | Notable |
|------|-------|---------|
| `aldric_greeting.json` | `start` (3 choices), `tips` | `open_blacksmith` action; `tips` has `condition: {minLevel: 1}` |
| `elara_greeting.json` | `start` (4 choices), `many_deaths`, `veteran` | `open_merchant` action; the two lore branches are gated on `minDeaths: 3` and `minRuns: 5`; the start text claims "Stock refreshes each visit" |
| `mira_greeting.json` | `start` (4 choices), `castle_lore`, `castle_repeat` | `open_quest_board` action; `castle_lore` sets `heard_castle_lore` and the two branches are gated on that flag |
| `dungeon_npc_stranded.json` | `start` only | Sets `met_dungeon_npc`; `next: "end"` |
| `dungeon_lore_default.json` | `start` only | `next: "end"` |

Reachability: `mira_greeting` is reached from `NpcMira` (`interactType: dialogue`). `aldric_greeting` and `elara_greeting` are reached from `NpcAldric` / `NpcElara` via `dialogue_requested` before shop actions (`npc_base.gd:53-64`). `dungeon_npc_stranded` and `dungeon_lore_default` are reached from dungeon room content; see [`room-content.md`](room-content.md).

### Quests
`QuestCatalog` is the same directory walk as the other catalogs, keyed by `id`, skipping files without one (`quest_catalog.gd:24-44`).

`QuestService` is an autoload with `process_mode = PROCESS_MODE_ALWAYS`. It connects `RunFlow.run_started` and `RunFlow.run_ended` (lines 14-16).

Three states only: `inactive`, `active`, `completed` (lines 7-9). There is no turn-in state.

| Function | Lines | Behaviour |
|----------|-------|-----------|
| `accept_quest(id)` | 21-31 | Requires a known definition and a state that is neither active nor completed; sets `active`, sets progress `{"count": 0}`, emits `quest_updated` |
| `complete_quest(id)` | 34-43 | Requires a known definition and `active`; grants rewards, sets `completed`, emits `quest_updated` |
| `get_available_quests()` | 46-53 | Every definition whose state is `inactive` — no level, flag, or prerequisite gating |
| `get_active_quests()` | 56-61 | Every definition whose state is `active` |
| `get_completed_quests()` | 64-69 | Every definition whose state is `completed` |
| `register_kill(enemy_id)` | 72-88 | For each active `kill` quest, skips when `targetId` and `enemy_id` are both non-empty and differ, increments `progress.count`, and completes at `requiredCount` (default 1) |
| `register_fetch(item_id)` | 91-100 | For each active `fetch` quest whose `targetItemId` matches, completes immediately |
| `register_run_outcome(outcome, context)` | 103-104 | Completes escape quests only when `outcome == OUTCOME_ESCAPED` |
| `_on_run_started()` | 107-113 | Resets active `escape` quests' progress to `{"escaped": false}` |
| `_on_run_ended(results)` | 116-122 | Clears escape progress for active escape quests |
| `_check_escape_quests(escaped)` | 125-133 | Completes every active `escape` quest when `escaped` is true |
| `_grant_rewards(def)` | 136-144 | `rewards.gold` through `CharacterService.add_gold`; each `rewards.items[]` entry through `InventoryService.add_item(itemId, quantity)` |

### Quest content
| File | `type` | Target | Rewards |
|------|--------|--------|---------|
| `kill_grunts.json` | `kill` | `targetId: castle_grunt`, `requiredCount: 3` | 30 gold, 1 `health_potion` |
| `fetch_scrap.json` | `fetch` | `targetItemId: iron_scrap` | 20 gold |
| `escape_castle.json` | `escape` | none | 50 gold |

### End-to-end trace: `kill_grunts`
1. Player interacts with `NpcMira` -> `hub.gd:351-352` -> `DialogueUI.start_dialogue("mira_greeting")`.
2. Choice "Check the quest board" fires the `open_quest_board` action, re-emitted as `action_triggered` and handled by `dialogue_ui.gd:126-128`.
3. `quest_board_ui._on_accept_pressed` (`quest_board_ui.gd:78-88`) calls `QuestService.accept_quest("kill_grunts")` -> state `active`, progress `{"count": 0}`.
4. In a run, `castle_enemy_base.gd:295` calls `RunFlow.register_kill(enemy_id)`, which forwards to `QuestService.register_kill` (`run_flow.gd:434-436`). In waves, `waves_run.gd:_on_enemy_died` also calls `QuestService.register_kill(enemy_id)`.
5. On the third `castle_grunt`, `count >= 3` -> `complete_quest` -> `_grant_rewards` adds 30 gold and one `health_potion`, state becomes `completed`.
6. Completed quests appear in `get_completed_quests` and on the quest board completed list; active quests show on `QuestTrackerUI` in hub and combat HUD.

## Contracts
**Signals:** `DialogueRunner.line_changed(speaker, text, choices)`, `dialogue_ended`, `action_triggered(action)`; `QuestService.quest_updated(quest_id, state)`.

**Signal consumers:** the runner's three are consumed by `dialogue_ui.gd:26-28`; `quest_updated` by `quest_board_ui.gd:23` and `quest_tracker_ui.gd`.

**Signals consumed:** `RunFlow.run_started`, `RunFlow.run_ended`.

**Autoload dependencies:** `CharacterService`, `QuestService`, `InventoryService`, `ContentLoader`, `RunFlow`; static classes `DialogueCatalog`, `DialogueConditions`, `QuestCatalog`.

**Save keys:** `quests[<id>]` (state String) and `quests[<id>_progress]` (Dictionary), both through `CharacterService`; `flags[...]` for every `set_flag` action.

**Content keys read — dialogue:** `id`, `startNode`, `nodes`, `speaker`, `text`, `condition`, `fallback`, `actions`, `next`, `auto`, `choices[].text`, `choices[].condition`, `choices[].actions`, `choices[].next`.

**Content keys read — quests:** `id`, `title`, `description`, `type`, `targetId`, `targetItemId`, `requiredCount`, `rewards.gold`, `rewards.items[].itemId`, `rewards.items[].quantity`.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| JSON branching dialogue with conditional choices | IMPLEMENTED | `dialogue_runner.gd:107-112`, `dialogue_conditions.gd:7-56` |
| Nine condition kinds including `all` / `any` / `not` | IMPLEMENTED | `dialogue_conditions.gd:15-53` |
| Unknown condition keys fail closed | IMPLEMENTED | `dialogue_conditions.gd:55-56` |
| Five dialogue action types | IMPLEMENTED | `dialogue_runner.gd:123-137` |
| Choiceless line hold until advance | IMPLEMENTED | `dialogue_runner.gd:83-92`; optional `auto` key |
| Kill quest tracking and completion | IMPLEMENTED | `quest_service.gd:72-88`, driven by `run_flow.gd:434-436` and `waves_run.gd:207-212` |
| Fetch quest on inventory add | IMPLEMENTED | `inventory_service.gd` → `register_fetch` |
| Escape quest outcome gating | IMPLEMENTED | `quest_service.gd:103-104`, `register_run_outcome` |
| Quest rewards (gold and items) | IMPLEMENTED | `quest_service.gd:136-144` |
| Quest board accept flow | IMPLEMENTED | `quest_board_ui.gd:78-88` |
| Completed quest list on board | IMPLEMENTED | `quest_board_ui.gd`, `get_completed_quests` |
| Quest tracker HUD | IMPLEMENTED | `quest_tracker_ui.gd`, hub + `combat_hud.gd` |
| Aldric/Elara dialogue reachability | IMPLEMENTED | `npc_base.gd:53-64` |
| Quest turn-in | ABSENT | Only three states exist (`quest_service.gd:7-9`); rewards are granted at completion |
| Quest prerequisites, level gating, repeats | ABSENT | `get_available_quests` returns every `inactive` definition with no gating |
| Dialogue node cycle protection | BROKEN | `_advance_to_node` recurses with no visited set (`dialogue_runner.gd:75`, `dialogue_runner.gd:92`), so a content cycle is unbounded recursion |
| Repeated node actions | PARTIAL | `node.actions` run every time the node is entered (`dialogue_runner.gd:79`), so an `add_gold` on a revisitable node pays repeatedly; no content does this today |
| Dialogue localisation | ABSENT | Text is inline in the content JSON with no key indirection |

## Related
- Improvement plan: [`../actual_improvements/dialogue-quests.md`](../actual_improvements/dialogue-quests.md)
- [`character-service.md`](character-service.md), [`npc-hub-services.md`](npc-hub-services.md), [`hub.md`](hub.md), [`run-flow.md`](run-flow.md), [`inventory-service.md`](inventory-service.md), [`content-catalog.md`](content-catalog.md), [`content-data.md`](content-data.md), [`room-content.md`](room-content.md), [`waves-run.md`](waves-run.md), [`ui/dialogue_quests.md`](ui/dialogue_quests.md)
