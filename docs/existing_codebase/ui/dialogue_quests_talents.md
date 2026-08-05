# Dialogue, quests, and talents — coordination

How the three progression-facing panels fit together today: NPC dialogue routes to hub services, the quest board accepts quests that complete silently during runs, and the talent panel spends points nothing else ever mentions.

## Surfaces
| Surface | Script | Owner | Focus on open |
|---|---|---|---|
| Dialogue bar | `scripts/ui/dialogue_ui.gd` (137) | `hub.tscn:9`, hub scene only | no focus at all — choices are `FOCUS_NONE` (`dialogue_ui.gd:98`) |
| Quest board | `scripts/ui/quest_board_ui.gd` (89) | `hub.tscn:13`, hub scene only | `_available_list.grab_focus()` (`quest_board_ui.gd:35`) |
| Talents | `scripts/ui/talents_ui.gd` (172) | `PlayerControls` autoload (`player_controls.gd:27`) | none; a private `_cursor` is driven from `_unhandled_input` (`talents_ui.gd:76-85`) |

Three panels, three different navigation models: a manual index with a `modulate` tint, a focused `ItemList`, and an unfocused `ItemList` with an out-of-band cursor.

## The chains that connect them

### NPC to service
```
hub.gd NPC interact → _dialogue_ui.start_dialogue(id)      hub.gd:352
DialogueRunner emits action_triggered                       dialogue_runner.gd
dialogue_ui._on_action_triggered → get_parent().call(...)   dialogue_ui.gd:126-136
   open_blacksmith / open_merchant / open_quest_board / open_storage → hub.gd:179-192
```
The dispatch depends on the dialogue panel being a direct child of the hub node, and unknown action types are silently dropped (`dialogue_ui.gd:126-136`).

`DialogueRunner` can also complete a quest directly through the `complete_quest` action (`dialogue_runner.gd:132-133`), which is the only quest-turn-in path that a player action can trigger.

### Quest lifecycle
```
Board accept → QuestService.accept_quest            quest_board_ui.gd:84
During a run  → register_kill / register_fetch / escape check   quest_service.gd:62-122
On threshold  → complete_quest → _grant_rewards      quest_service.gd:32-41, 125-133
Signal        → quest_updated → only quest_board_ui refreshes   quest_board_ui.gd:23
```
Rewards are granted with `CharacterService.add_gold` and `InventoryService.add_item` (`quest_service.gd:129-133`) and no UI is shown, so a quest can complete mid-run and the player learns about it only by reopening the board.

### Progression to talents
```
Kills/XP → ProgressionService → progression_changed
Consumers: combat_hud.gd:95-96, character_service.gd:31, inventory_service.gd:20, talents_ui.gd:24
get_available_talent_points() is read in exactly one place: talents_ui.gd:112
```
Nothing outside the talent panel mentions unspent points: no HUD badge, no toast, no menu marker (1 match for `get_available_talent_points` across `apps/game/client/scripts/`).

## Shared state
| Concern | Where it lives |
|---|---|
| Quest state and progress | `CharacterService.set_quest_state` / `set_quest_progress` (`quest_service.gd:26-27`) |
| Talent ranks and points | `ProgressionService` (`progression_service.gd:26`, `:91`) |
| Respec | `BlacksmithService.respec_talents()`, surfaced only as a code-added blacksmith button (`blacksmith_ui.gd:27-30`, `:126-129`) |
| Content | `content/dialogue/*.json` (5), `content/quests/*.json` (3), `content/talents/tree.json` (3 branches × 6 nodes) |

## Localization status across the three
| Surface | Localized |
|---|---|
| Talent branch and node names | yes — `tr()` at `talents_ui.gd:165`, keys at `strings.csv:5-25` |
| Everything else in the talent panel | no — `talents_ui.gd:28`, `:41`, `:112`, `:141` |
| Dialogue speaker, body, choices | no — literal English in content (`content/dialogue/aldric_greeting.json:6-11`) |
| Quest titles, descriptions, board chrome | no — literal English in content and scene (`content/quests/kill_grunts.json:3`, `:7`; `quest_board_ui.tscn:41-66`) |

`talents_ui.gd:165` is the only `tr(` call in the client. `strings.csv` contains `UI_PAUSE` and `UI_RESUME` (`:2-3`) that no script uses.

## Current state
| Cross-cutting concern | Status | Evidence |
|---|---|---|
| Reachability outside the hub | BROKEN — dialogue and the quest board exist only in `hub.tscn`, while dungeon lore and NPC quest rooms look the dialogue panel up by group, so those rooms do nothing in a run | `hub.tscn:9`, `:13`; `room_lore_content.gd:41-47`; `room_npc_quest_content.gd:45-47` |
| Quest completion feedback | ABSENT — rewards are granted silently; `quest_updated` has exactly one listener, the board itself | `quest_service.gd:125-133`; `quest_board_ui.gd:23` |
| Unspent talent points signalling | ABSENT — no HUD or menu indicator; the value is read in one place | `talents_ui.gd:112`; 1 match for `get_available_talent_points` |
| Navigation consistency | BROKEN — three different selection models across three sibling panels, two of them not using focus at all | `dialogue_ui.gd:96-119`; `quest_board_ui.gd:35`; `talents_ui.gd:76-85` |
| Icons | ABSENT — dialogue, quests, and talents are entirely text; no atlas is referenced by any of the three | `dialogue_ui.tscn:39-53`; `quest_board_ui.gd:56-67`; `talents_ui.gd:108-110` |
| Skinning consistency | BROKEN — dialogue calls `apply_modal_menu`, talents uses `MenuShell.build_modal`, and the quest board calls neither, so the board is the one unskinned hub panel | `dialogue_ui.gd:24`; `talents_ui.gd:28`; `quest_board_ui.gd:16-23` |
| Raw identifiers shown | PARTIAL — quest type enums and quest ids on the board, stat ids in the talent detail | `quest_board_ui.gd:58`, `:85`; `talents_ui.gd:128-135` |
| Rewards presentation | ABSENT — quest `rewards` and talent `costPerRank` are both in content and neither is displayed | `content/quests/kill_grunts.json:8`; `content/talents/tree.json:13` |
| Mouse mode handling | BROKEN — all three set `Input.mouse_mode` directly, and all three capture on close regardless of what remains open | `dialogue_ui.gd:40`, `:49`; `quest_board_ui.gd:34`, `:41`; `talents_ui.gd:53`, `:60` |
| Pause behavior | PARTIAL — none of the three pauses the tree, so all three can float over live gameplay | `dialogue_ui.gd:35-41`; `quest_board_ui.gd:30-35`; `talents_ui.gd:48-53` |
| Front-end isolation | BROKEN — the talent panel self-opens on the `talents` action and lives on the always-present autoload layer, so it can open over the title screen and main menu | `talents_ui.gd:63-67`; `player_controls.gd:27` |
| Input collisions | BROKEN — `talents` and `heal` share gamepad button `7` | `project.godot:271-276`, `:283-288` |
| Quest tracking in the HUD | ABSENT — no tracked quest, and the HUD objective banner is not fed by `QuestService` | `quest_service.gd:1-133` has no HUD consumer |

## Related
- Per-surface docs: [`dialogue_quests.md`](dialogue_quests.md) · [`talents.md`](talents.md)
- Improvement plan: [`../actual_improvements/ui/dialogue_quests_talents.md`](../actual_improvements/ui/dialogue_quests_talents.md)
- [`hub_vendors.md`](hub_vendors.md) · [`combat_hud.md`](combat_hud.md) · [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`run_outcome.md`](run_outcome.md)
- [`../dialogue-quests.md`](../dialogue-quests.md) · [`../progression-service.md`](../progression-service.md) · [`../npc-hub-services.md`](../npc-hub-services.md) · [`../room-content.md`](../room-content.md) · [`../content-data.md`](../content-data.md)
