# Dialogue and quest board — improvement plan

## Current state
The dialogue bar works in the hub: it runs branching nodes, dispatches four hub actions, and handles choices. Outside the hub it does not exist at all, so dungeon lore and NPC quest rooms silently do nothing when the player presses interact. The quest board is the only hub panel that never calls a `GameUISkin` helper, so it renders in Godot's default theme with no backdrop. Dialogue choices are not focusable; "selection" is a faint `modulate` tint on a non-focusable button. No portraits, no reveal pacing, no audio, no rewards display, no localization. See [`../existing_codebase/ui/dialogue_quests.md`](../existing_codebase/ui/dialogue_quests.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| DLG-01 | P0 | Dialogue is unreachable outside the hub. Dungeon lore and NPC quest rooms find the panel by group, and the only instance is in the hub scene, so `interact` at those rooms does nothing and does not even consume the input. | `hub.tscn:9`; `room_lore_content.gd:41-47`; `room_npc_quest_content.gd:45-47` |
| DLG-02 | P0 | The quest board is completely unskinned: no `apply_modal_menu`, no backdrop, no pixel filtering, default Godot theme, while every neighbouring hub panel is skinned. | `quest_board_ui.gd:16-23`; contrast `merchant_ui.gd:26` |
| DLG-03 | P0 | Dialogue choices cannot be focused: `focus_mode = FOCUS_NONE` with a hand-rolled index highlighted only by `modulate = Color(1.2, 1.2, 0.9)`. There is no focus owner, no theme focus style, and on the default theme the highlight is nearly invisible. | `dialogue_ui.gd:96-103`, `:113-119` |
| DLG-04 | P1 | Quest rewards are never shown, although every quest file declares gold and item rewards. | `content/quests/kill_grunts.json:8`; `quest_board_ui.gd:56-67` |
| DLG-05 | P1 | Input prompts are hardcoded English key names rather than live glyphs. | `dialogue_ui.gd:84`, `:86` |
| DLG-06 | P1 | No speaker portrait, no text reveal, no skip, no auto-advance, no audio, no history — the dialogue reads as a debug text dump. | `dialogue_ui.tscn:39-53`; `dialogue_ui.gd:76-82` |
| DLG-07 | P1 | Zero localization: hint strings, board strings, and all dialogue and quest content are literal English with no keys. | `dialogue_ui.gd:84-86`; `quest_board_ui.tscn:41-66`; `content/dialogue/*.json`; `content/quests/kill_grunts.json:3`, `:7` |
| DLG-08 | P1 | Raw ids and enum values reach the player: the available row shows `kill`/`fetch`, and acceptance prints the quest id. | `quest_board_ui.gd:58`, `:85` |
| DLG-09 | P1 | Both panels capture the mouse on close regardless of what else is open. | `dialogue_ui.gd:44-50`; `quest_board_ui.gd:38-42` |
| DLG-10 | P2 | Only `kill` quests show progress; fetch and escape quests show a static description. | `quest_board_ui.gd:65-67` |
| DLG-11 | P2 | `ActiveList` is a read-only text dump with no selection, detail, tracking, or abandon action. | `quest_board_ui.gd:22` |
| DLG-12 | P2 | Hub actions are dispatched with `get_parent().call(...)`, valid only while the panel is a direct child of the hub, and unknown action types are silently dropped. | `dialogue_ui.gd:126-136` |
| DLG-13 | P2 | A bottom dialogue bar dims the entire screen because `apply_modal_menu` inserts a full-rect backdrop. | `dialogue_ui.gd:24`; `game_ui_skin.gd:185-186` |
| DLG-14 | P2 | Font sizes `14` and `16` are hardcoded and re-overridden on every line instead of coming from theme variations. | `dialogue_ui.gd:79-81` |
| DLG-15 | P2 | The board panel uses fixed pixel offsets with no clamping to window size or UI scale. | `quest_board_ui.tscn:22-25` |

## Target design

### Dialogue as a global overlay
`DialogueUI` moves out of `hub.tscn` and becomes a child of the `PlayerControls` autoload layer, like the inventory and settings overlays, so lore rooms, NPC rooms, bosses, and the hub all reach the same instance. Room content keeps calling by group, and the group is now always populated. `PlayerControls.open_dialogue(id) -> bool` becomes the entry point, and the `action_triggered` dispatch stops using `get_parent()`:

```gdscript
DialogueActions.dispatch(action)   # resolves the target service or hub node explicitly
```

with an explicit action registry (`open_blacksmith`, `open_merchant`, `open_quest_board`, `open_storage`, `complete_quest`, `give_item`, `set_flag`, `start_run`) and a warning on an unknown type instead of silence (DLG-01, DLG-12).

### Authored dialogue bar
```
DialogueUI (Control, full rect, mouse_filter IGNORE)
├── ColorRect "LowerVignette"        bottom-anchored gradient, not a full-screen dim
└── PanelContainer "Panel"           DialoguePanel variation, bottom-centered, clamped
    └── MarginContainer → HBoxContainer "Row"
        ├── PanelContainer "PortraitFrame"
        │   └── TextureRect "Portrait"        96 × 96, from speaker content
        └── VBoxContainer "TextColumn"
            ├── HBoxContainer "SpeakerRow"
            │   ├── Label "SpeakerLabel"      DialogueSpeaker variation
            │   └── Label "SpeakerTitle"      DialogueSpeakerTitle
            ├── RichTextLabel "TextLabel"     DialogueBody, bbcode on, visible_ratio driven
            ├── VBoxContainer "ChoicesBox"
            │   └── DialogueChoice × n        (Button, FOCUS_ALL)
            └── HBoxContainer "HintRow"       glyph + caption from make_symbol_caption_row
```

- `TextLabel` reveals with `visible_ratio` at `40` characters per second, scaled by an `AccessibilitySettings.text_speed` row (`instant` allowed); `ui_accept` during reveal completes the line instead of advancing (DLG-06).
- Choices become real `Button`s with `FOCUS_ALL` and a `DialogueChoice` theme variation carrying a visible focus style, and the first is focused when the line finishes revealing. The manual index and the `modulate` tint are deleted (DLG-03).
- Font sizes come from the `DialogueSpeaker` and `DialogueBody` theme variations multiplied by the shared `UITextScale`, not from per-line overrides (DLG-14).
- The full-screen backdrop is replaced by the bottom `LowerVignette`, so the world stays visible during conversation (DLG-13).
- Cues through `AudioDirector`: `dialogue_open`, `dialogue_blip` (every third revealed character, pitch-varied per speaker), `dialogue_choice_move`, `dialogue_choice_confirm`, `dialogue_close` (DLG-06).
- `ui_page_prev` opens a `DialogueHistory` scroll of the last 20 lines in the current conversation (DLG-06).

Speaker data moves to `content/speakers/<id>.json`: `nameKey`, `titleKey`, `portraitPath`, `blipPitch`. Dialogue nodes reference `speakerId` and use `textKey` instead of literal `text`; existing literals become the default English rows in `strings.csv` (DLG-07).

### Quest board rebuilt on the shared shell
The board becomes a `MenuModal` (see [`menu_shell.md`](menu_shell.md)) with two tabs and quest cards instead of two `ItemList`s:

```
QuestBoard (MenuModal)
└── Panel → Margin → VBoxContainer
    ├── Label "TitleLabel"                MenuTitle
    ├── HBoxContainer "TabBar"            Available │ Active │ Completed
    ├── HBoxContainer "Body"
    │   ├── ScrollContainer → VBoxContainer "QuestCards"
    │   │   └── QuestCard × n
    │   └── PanelContainer "QuestDetail"
    │       ├── Label "TitleLabel" + Label "TypeLabel"      localized type name
    │       ├── Label "Description"
    │       ├── VBoxContainer "Objectives"     one row per objective with n/m and a check mark cell
    │       └── VBoxContainer "Rewards"
    │           ├── HBoxContainer: currency icon + gold amount
    │           └── HBoxContainer: item icon + name × quantity
    └── HBoxContainer "FooterRow"        Accept │ Track │ Abandon │ Close + glyph hints
```

`QuestCard`:
```
QuestCard (Button, FOCUS_ALL, toggle_mode)
├── TextureRect "TypeIcon"     24 × 24 from quest_icons atlas cell per quest type
├── VBoxContainer: Label "TitleLabel" · Label "SummaryLabel"
├── ProgressBar "ProgressBar"  visible when the quest has a counted objective
└── TextureRect "StateMark"    active / complete cell
```

Quest icon atlas: `assets/ui/atlas/quest_icons.png`, `4 × 2` grid of `24 × 24` cells, ids `quest_kill`, `quest_fetch`, `quest_escape`, `quest_explore`, `state_active`, `state_complete`, `state_available`, `state_tracked`.

Objectives become a uniform content shape so progress is not special-cased for `kill`:

```json
"objectives": [
  { "id": "slay", "kind": "kill", "targetId": "castle_grunt", "count": 3, "descKey": "QUEST_KILL_GRUNTS_OBJ" }
]
```

`QuestService.get_objective_progress(quest_id)` returns `[{id, current, required, done}]`, which both the board and the HUD objective marker read (DLG-04, DLG-08, DLG-10, DLG-11).

`Track` writes the tracked quest id to `WorldState`, which the HUD objective banner displays; `Abandon` requires a confirmation and returns the quest to available.

Board styling comes from the shell, so `apply_modal_menu` is no longer needed and the panel is clamped (DLG-02, DLG-15). `MenuStack` owns `ui_cancel` and mouse mode for both panels (DLG-09).

Rejected alternative: leaving the two `ItemList`s and only adding `apply_modal_menu`. It would fix the visual mismatch and none of the information gaps — rewards, objectives, and tracking all need per-row structure.

## Work plan
1. **Move `DialogueUI` to the `PlayerControls` layer**, add `open_dialogue`, and keep the group registration (DLG-01).
2. **Explicit `DialogueActions` registry** with a warning on unknown types (DLG-12).
3. **Author the dialogue bar** with portrait, reveal, focusable choices, hint glyph row, bottom vignette (DLG-03, DLG-05, DLG-06, DLG-13, DLG-14).
4. **Speaker content files and `textKey` migration** for the five dialogue files (DLG-07).
5. **Dialogue audio cues and history overlay** (DLG-06).
6. **Quest objectives schema** and `QuestService.get_objective_progress` (DLG-10).
7. **Quest board on `MenuModal`** with tabs, cards, detail, rewards, track, abandon (DLG-02, DLG-04, DLG-08, DLG-11, DLG-15).
8. **Quest icon atlas** and localized type names (DLG-08).
9. **`MenuStack` ownership of cancel and mouse mode** for both panels (DLG-09).

## Data and schema changes
- `content/dialogue/*.json`: `speakerId` and `textKey` replace `speaker`/`text`; choice `textKey` replaces `text`.
- New `content/speakers/*.json` with `nameKey`, `titleKey`, `portraitPath`, `blipPitch`.
- `content/quests/*.json`: `titleKey`, `descKey`, `objectives[]`, `rewards` unchanged but now displayed.
- New `assets/ui/atlas/quest_icons.png` (`4 × 2` grid, `24 × 24` cells) and speaker portrait assets.
- New `scenes/ui/dialogue_ui.tscn` rebuild, `scenes/ui/dialogue_choice.tscn`, `scenes/ui/quest_board.tscn`, `scenes/ui/quest_card.tscn`, `scripts/ui/dialogue_history.gd`, `scripts/dialogue/dialogue_actions.gd`.
- `QuestService`: `get_objective_progress`, `abandon_quest`, tracked-quest state in `WorldState`.
- `AccessibilitySettings`: new `text_speed`.
- `strings.csv`: `DLG_HINT_ADVANCE`, `DLG_HINT_CHOOSE`, `DLG_HISTORY_TITLE`, `QUEST_BOARD_TITLE`, `QUEST_TAB_*`, `QUEST_TYPE_*`, `QUEST_ACCEPT`, `QUEST_TRACK`, `QUEST_ABANDON`, `QUEST_ABANDON_CONFIRM`, `QUEST_REWARDS`, `QUEST_OBJECTIVES`, plus every migrated dialogue and quest string.

## Acceptance criteria
- [ ] Pressing interact at a dungeon lore room or NPC room opens the dialogue bar.
- [ ] The quest board uses the shared panel style, has a backdrop, and is pixel-filtered like every other hub panel.
- [ ] Dialogue choices are real focus owners with a visible focus style; the first choice is focused when a line finishes.
- [ ] Text reveals over time, `ui_accept` completes a revealing line, and a second press advances.
- [ ] Each speaker shows a portrait and a name resolved from content.
- [ ] Dialogue history shows the last 20 lines of the current conversation.
- [ ] The world remains visible during dialogue; no full-screen dim.
- [ ] Every quest card shows a type icon, and counted objectives show a progress bar for all quest types, not only kills.
- [ ] The detail pane lists objectives with `n/m` and rewards with gold and item icons.
- [ ] No raw quest id or enum value appears in any visible string.
- [ ] Quests can be tracked, and the tracked quest appears on the HUD objective banner.
- [ ] Abandoning a quest requires a confirmation and returns it to Available.
- [ ] Neither script writes `Input.mouse_mode`.
- [ ] Switching to a stub locale changes every dialogue line, choice, quest title, description, and objective.

## Validation
Extend `apps/game/client/scripts/validation/suites/hub_m4_suite.gd` and add `dialogue` and `quest` cases:

| Test id | Assertion |
|---|---|
| `dialogue.available_in_dungeon` | in a generated castle floor, `get_first_node_in_group("dialogue_ui")` is non-null and `start_dialogue` returns true |
| `dialogue.lore_room_opens` | simulating `interact` at a lore room opens the bar and marks the input handled |
| `dialogue.choices_focusable` | every choice button has `focus_mode == FOCUS_ALL` and the first is the focus owner after reveal |
| `dialogue.no_modulate_selection` | `dialogue_ui.gd` contains no `modulate` assignment for selection |
| `dialogue.reveal_and_skip` | a line reveals over time; `ui_accept` sets `visible_ratio == 1.0` without advancing; the next press advances |
| `dialogue.portrait_present` | each of the five dialogue files resolves a speaker with a non-null portrait |
| `dialogue.actions_registry` | each supported action type dispatches, and an unknown type logs a warning |
| `dialogue.no_parent_call` | `dialogue_ui.gd` contains no `get_parent().call` |
| `dialogue.no_full_dim` | the built tree has no full-rect backdrop child |
| `dialogue.history` | after three lines, the history overlay lists three entries |
| `dialogue.localized` | every visible dialogue string resolves from a `strings.csv` key |
| `quest.board_skinned` | the board's panel uses the shared panel `StyleBoxFlat` and a backdrop exists |
| `quest.cards_have_icons` | every quest card has a non-null `TypeIcon.texture` |
| `quest.rewards_shown` | the detail pane for `kill_grunts` shows `30` gold and one `health_potion` with an icon |
| `quest.objectives_uniform` | every quest in `content/quests/` has an `objectives` array, and progress is shown for a fetch quest |
| `quest.no_raw_ids` | no visible label equals a quest id or a raw type string |
| `quest.track_sets_hud` | tracking a quest sets the HUD objective text to that quest's objective |
| `quest.abandon_confirm` | abandoning opens a confirmation and, once confirmed, the quest returns to Available |
| `quest.focus_on_open` | focus owner is the first quest card |
| `quest.no_mouse_mode` | neither script contains `Input.mouse_mode` |
| `quest.panel_clamped` | at a `1280 × 720` viewport the board fits inside the window |

## Related
- Existing behavior: [`../existing_codebase/ui/dialogue_quests.md`](../existing_codebase/ui/dialogue_quests.md)
- Coordination: [`dialogue_quests_talents.md`](dialogue_quests_talents.md)
- [`talents.md`](talents.md) · [`hub_vendors.md`](hub_vendors.md) · [`menu_shell.md`](menu_shell.md) · [`input_glyphs.md`](input_glyphs.md) · [`combat_hud.md`](combat_hud.md) · [`settings.md`](settings.md)
- [`../dialogue-quests.md`](../dialogue-quests.md) · [`../npc-hub-services.md`](../npc-hub-services.md) · [`../room-content.md`](../room-content.md) · [`../world-state.md`](../world-state.md) · [`../content-data.md`](../content-data.md)
