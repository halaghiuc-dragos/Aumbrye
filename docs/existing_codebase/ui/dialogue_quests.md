# Dialogue and quest board

Two hub panels: a bottom dialogue bar driven by `DialogueRunner`, and a quest board with an available/active list.

## Files
| Script | Lines | Scene |
|---|---|---|
| `apps/game/client/scripts/ui/dialogue_ui.gd` | 137 | `scenes/ui/dialogue_ui.tscn` (54 lines) |
| `apps/game/client/scripts/ui/quest_board_ui.gd` | 89 | `scenes/ui/quest_board_ui.tscn` (67 lines) |

Both are instanced only in `scenes/hub/hub.tscn` (`:9`, `:13`). The hub starts dialogue at `hub.gd:352` and opens the board at `hub.gd:191-192`.

## Dialogue UI
```
DialogueUI (Control, full rect, mouse_filter 2, group "dialogue_ui")
└── PanelContainer "Panel"      bottom-centered, 640 wide, 196 tall, 24 px above the bottom edge
    └── MarginContainer "Margin" (16/12)
        └── VBoxContainer "VBox"
            ├── Label "SpeakerLabel"
            ├── Label "TextLabel"     autowrap
            ├── VBoxContainer "ChoicesBox"    choice Buttons built per line
            └── Label "HintLabel"
```
| Concern | Behavior |
|---|---|
| Runner | `DialogueRunner.new()` in `_ready`, signals `line_changed`, `dialogue_ended`, `action_triggered` (`:25-28`) |
| Start | `start_dialogue(id)` returns false if the runner rejects the id (`:35-41`) |
| Line | `_on_line_changed` sets speaker and text, then overrides font sizes to `int(14 * subtitle_scale)` and `int(16 * subtitle_scale)` (`:76-81`) |
| Choices | rebuilt per line as `Button`s with `focus_mode = FOCUS_NONE`; selection is the local `_selected_index`, highlighted by `modulate = Color(1.2, 1.2, 0.9)` (`:89-119`) |
| Input | `ui_cancel` closes; with no choices `ui_accept`/`interact` advance; with choices `ui_up`/`ui_down` move the index and accept selects (`:53-73`) |
| Actions | `open_blacksmith`, `open_merchant`, `open_quest_board`, `open_storage` forwarded via `get_parent().call(...)` (`:126-136`) |
| Styling | `apply_modal_menu(self, "Panel")` — creates a full-screen backdrop through `ensure_backdrop` (`:24`; `game_ui_skin.gd:185-186`) |

Dialogue content lives in `content/dialogue/*.json` (five files) as literal English `speaker`, `text`, and choice `text` fields with no localization keys, no portrait path, and no audio cue (`content/dialogue/aldric_greeting.json:6-11`).

## Quest board UI
```
QuestBoardUI (Control, full rect, mouse_filter 2)
└── PanelContainer "Panel"      (520 × 400 fixed offsets)
    └── MarginContainer "Margin" (12)
        └── VBoxContainer "VBox"
            ├── Label "Title"            "Quest Board (Optional)"
            ├── ItemList "AvailableList"  min height 100
            ├── ItemList "ActiveList"     min height 80
            ├── Label "DetailLabel"      "Quests never block the portal."
            └── HBoxContainer "Buttons"  Accept Quest │ Close
```
| Concern | Behavior |
|---|---|
| Available rows | `QuestService.get_available_quests()`, text `"%s — %s"` of title and raw `type` (`:56-59`) |
| Active rows | title plus description, with `" (n/m)"` appended for `type == "kill"` (`:61-67`) |
| Detail | description of the selected available quest (`:70-75`) |
| Accept | `QuestService.accept_quest`, then `"Quest accepted: %s"` with the raw quest id (`:78-88`) |
| Refresh | on `QuestService.quest_updated` (`:23`) |

Quest completion is automatic inside `QuestService` (`quest_service.gd:78`, `:90`, `:122`) or through a dialogue `complete_quest` action (`dialogue_runner.gd:132-133`); the board has no turn-in interaction.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Branching dialogue with choices and actions | IMPLEMENTED in the hub | `:35-73`, `:126-136`; `hub.gd:352` |
| Dialogue outside the hub | BROKEN — `room_lore_content.gd:44-47` and `room_npc_quest_content.gd:45-47` locate the panel with `get_first_node_in_group("dialogue_ui")`, but `DialogueUI` is instanced only in `hub.tscn:9`, so in a dungeon the lookup returns null and pressing `interact` at a lore or NPC room does nothing and consumes no input | `hub.tscn:9`; `room_lore_content.gd:41-47`; `room_npc_quest_content.gd:45-47` |
| Quest board styling | BROKEN — `quest_board_ui.gd` never calls `apply_modal_menu` or any `GameUISkin` helper, so the board renders with Godot's default theme, no backdrop, and no pixel filtering while every other hub panel is skinned | `:16-23` (no `GameUISkin` reference anywhere in the file); contrast `merchant_ui.gd:26` |
| Dialogue choice focus | BROKEN — choice buttons are created with `focus_mode = FOCUS_NONE` and the "selection" is a `modulate` tint of `Color(1.2, 1.2, 0.9)`, so there is no focus owner, no theme focus style, and the highlight is a faint brightening | `:96-103`, `:113-119` |
| Input prompts | PARTIAL — hint text hardcodes `"Enter to continue — Esc to close"` and `"D-pad + Enter to choose — Esc to close"` as plain words while `InputGlyphService` exists | `:84`, `:86`; `input_glyph_service.gd` |
| Speaker portraits | ABSENT — no portrait node in the scene and no `portraitPath` in any dialogue file | `dialogue_ui.tscn:39-53`; `content/dialogue/aldric_greeting.json:5-13` |
| Typewriter / pacing | ABSENT — the full line appears instantly, with no reveal, skip, or auto-advance | `:76-82` |
| Dialogue audio | ABSENT — no voice blip, page turn, or choice sound | `:76-119` |
| Dialogue history | ABSENT — no backlog or re-read of previous lines | `:76-82` |
| Localization | ABSENT — hint strings, `"???"` fallback, board title, detail text, both button labels, and all dialogue and quest content text are literal English | `:84-86`, `:97`; `quest_board_ui.tscn:41-66`; `content/dialogue/*.json`; `content/quests/kill_grunts.json:3`, `:7`; 0 `tr(` calls |
| Quest rewards | ABSENT — every quest file has a `rewards` block with gold and items and the board never shows it | `content/quests/kill_grunts.json:8`; `:56-67` |
| Raw ids and enums in text | PARTIAL — the available row shows the raw `type` (`kill`, `fetch`), and acceptance reports the raw quest id | `:58`, `:85` |
| Non-kill progress | PARTIAL — only `type == "kill"` gets a progress counter; fetch and escape quests show description text only | `:65-67` |
| Active list interaction | STUB — `ActiveList` has no `item_selected` connection and no actions; it is a read-only text dump | `:22` connects only `AvailableList` |
| Quest icons | ABSENT — both lists are text rows | `:56-67` |
| Mouse mode on close | BROKEN — both panels capture the mouse unconditionally on close, regardless of what is still open | `:44-50`; `quest_board_ui.gd:38-42` |
| Dialogue backdrop | PARTIAL — a bottom bar dims the whole screen because `apply_modal_menu` inserts a full-rect backdrop | `:24`; `game_ui_skin.gd:185-186` |
| Font handling | PARTIAL — font sizes are hardcoded `14` and `16` in the script and overridden per line rather than coming from theme variations | `:79-81` |
| Action coupling | PARTIAL — the four supported actions are dispatched by `get_parent().call(...)`, so they work only while the panel is a direct child of the hub; unknown action types are silently dropped | `:126-136` |
| Board sizing | PARTIAL — fixed pixel offsets, no clamping to window size or UI scale | `quest_board_ui.tscn:22-25` |

## Related
- Improvement plan: [`../actual_improvements/ui/dialogue_quests.md`](../actual_improvements/ui/dialogue_quests.md)
- Coordination: [`dialogue_quests_talents.md`](dialogue_quests_talents.md)
- [`talents.md`](talents.md) · [`hub_vendors.md`](hub_vendors.md) · [`game_ui_skin.md`](game_ui_skin.md) · [`input_glyphs.md`](input_glyphs.md) · [`settings.md`](settings.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md)
- [`../dialogue-quests.md`](../dialogue-quests.md) · [`../npc-hub-services.md`](../npc-hub-services.md) · [`../hub.md`](../hub.md) · [`../room-content.md`](../room-content.md) · [`../content-data.md`](../content-data.md)
