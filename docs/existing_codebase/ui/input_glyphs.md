# Input glyphs

`InputGlyphService` maps an input action name to a short **text** label describing the button that triggers it, switching table by detected controller family. It is on the live play path: the combat HUD control hint, the inventory footer hint, and three world-space interaction prompts all read from it. It returns plain strings, never textures — there is no glyph art in the repo.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/ui/input_glyph_service.gd` | `class_name InputGlyphService` — 115 lines, whole service |
| `apps/game/client/scripts/ui/combat_hud.gd:235-240` | builds the permanent bottom control hint from `format_action_hint` |
| `apps/game/client/scripts/ui/inventory_ui.gd:835-842` | builds the inventory footer hint from `get_action_glyph` |
| `apps/game/client/scripts/dungeon/stair_lever.gd:99` | `"%s Floor options" % format_interact_label()` |
| `apps/game/client/scripts/dungeon/boss_room_door.gd:105` | `format_interact_label()` |
| `apps/game/client/scripts/dungeon/final_boss_cannon.gd:116` | `"%s Fire cannon!" % format_interact_label()` |
| `apps/game/client/scripts/validation/suites/m7_suite.gd:441-442` | asserts a non-empty glyph and label |

## How it works

### Device detection
`enum DeviceFamily { KEYBOARD, XBOX, PLAYSTATION, GENERIC }` (`input_glyph_service.gd:6`) with `static var _family := DeviceFamily.KEYBOARD` (`:8`).

`detect_family()` (`:11`) reads `Input.get_connected_joypads()`. Empty → `KEYBOARD`. Otherwise it lowercases `Input.get_joy_guid(pads[0])` and matches substrings: `xbox` or `xinput` → `XBOX`; `sony`, `playstation`, or `dualshock` → `PLAYSTATION`; anything else → `GENERIC`. Only pad index `0` is consulted.

`get_action_glyph(action)` (`:26`) calls `detect_family()` on **every** invocation — so each label built for each action polls the joypad list and GUID.

Detection is based purely on whether a pad is *connected*, not on which device last produced input. A connected-but-idle gamepad forces controller glyphs even while the player uses the keyboard.

### Glyph tables
Four `match` tables, each returning a string:

| Action | `_keyboard_glyph` (`:67`) | `_xbox_glyph` (`:81`) | `_playstation_glyph` (`:95`) | `_generic_glyph` (`:109`) |
|---|---|---|---|---|
| `interact` | `E` | `A` | `Cross` | `Btn 0` |
| `ui_accept` | `Enter` | `A` | `Cross` | `Btn 0` |
| `ui_cancel` | `Esc` | `B` | `Circle` | `Btn 1` |
| `inventory` | `I` | `Y` | `Triangle` | `Btn` |
| `pause` | `Esc` | `Menu` | `Options` | `Btn` |
| `lock_on` | `Tab` | `RB` | `R1` | `Btn` |
| `sprint` | `Shift` | `LS` | `L3` | `Btn` |
| `dodge` | `Space` | `B` | `Circle` | `Btn` |
| `jump` | `F` | `A` | `Cross` | `Btn` |
| anything else | first character of the action name, uppercased | `A` | `Cross` | `Btn` |

Every value is a hardcoded literal. `InputMap` is never queried, so the tables do not reflect `project.godot`'s actual bindings and cannot reflect a rebind.

Verifying the keyboard table against `apps/game/client/project.godot`: `interact` is bound to physical keycode `69` = `E` (`:279`), `inventory` to `4194306` = `Tab` — **not** `I` (`:252`), `lock_on` to the binding at `:180`, `dodge` at `:156`, `jump` at `:150` (physical keycode `32` = space is what `dodge` reports; `jump` reports `F`). The `inventory` mismatch is the clearest divergence: `project.godot:252` binds `inventory` to `Tab` while the service reports `I`, and `lock_on` reports `Tab`.

### Display names
`get_action_display_name(action)` (`:43`) maps `dodge` → `Dash`, `sprint` → `Sprint`, `lock_on` → `Lock`, `inventory` → `Inventory`, `interact` → `Interact`, `jump` → `Jump`, `pause` → `Pause`, and otherwise `action.replace("_", " ").capitalize()`.

### Formatters
- `format_interact_label(prefix = "Press")` (`:39`) → `"Press E"` on keyboard.
- `format_action_hint(action)` (`:63`) → `"<display name> <glyph>"`, e.g. `"Dash Space"`.

Both compose with a plain `"%s %s"`, so the button label is inline body text with no visual separation from the verb.

## Contracts
- Public API: `detect_family()`, `get_action_glyph(action)`, `get_action_display_name(action)`, `format_interact_label(prefix)`, `format_action_hint(action)`. All static; the class is a `RefCounted` used without instantiation.
- Consumers reference the class two different ways: by `class_name` (`InputGlyphService` in `stair_lever.gd`, `boss_room_door.gd`, `final_boss_cannon.gd`) and by `preload` const (`combat_hud.gd:4`, `inventory_ui.gd:10`, `m7_suite.gd:5`).
- No signal is emitted, so consumers cannot know when the device family changes.
- No autoload dependency; only the `Input` singleton.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Text glyph labels per device family | IMPLEMENTED | `input_glyph_service.gd:26-36`, `:67-114` |
| Glyph **art** (icon font, atlas, or `AtlasTexture` per button) | ABSENT — the service returns `String`; `apps/game/client/**/*.png` returns 0 files | `input_glyph_service.gd:26` return type |
| Bindings read from `InputMap` | ABSENT — all four tables are hardcoded literals | `input_glyph_service.gd:67-114` |
| Keyboard table matches `project.godot` | BROKEN for `inventory` — the service reports `I`, the project binds `Tab` (`physical_keycode 4194306`) | `input_glyph_service.gd:72` vs `project.godot:250-255` |
| Rebind support | ABSENT — nothing in the repo remaps actions at runtime and the service could not follow it if it did | grep `InputMap.action_erase_events` returns no hit under `apps/game/client/scripts` |
| Device-change notification | ABSENT — no signal, so `combat_hud.gd:222-241` keeps stale glyphs for the whole session | `input_glyph_service.gd:1-11` |
| Last-used-device tracking | ABSENT — detection is connection-based, so an idle pad overrides live keyboard use | `input_glyph_service.gd:12-15` |
| Multiple pad support | PARTIAL — only `pads[0]` is inspected | `input_glyph_service.gd:15-16` |
| Detection cost | PARTIAL — `detect_family()` runs per `get_action_glyph` call, so one hint string costs six GUID lookups | `input_glyph_service.gd:27`; `inventory_ui.gd:835-842` |
| Nintendo / Steam Deck families | ABSENT — GUIDs fall through to `GENERIC`, which returns `Btn 0` / `Btn 1` / `Btn` | `input_glyph_service.gd:21-22`, `:109-114` |
| Localization | ABSENT — `Press`, `Dash`, `Sprint`, `Lock`, `Inventory`, `Interact`, `Jump`, `Pause`, `Enter`, `Esc`, `Menu`, `Options` are hardcoded English and absent from `translations/strings.csv` | `input_glyph_service.gd:39-60`; `translations/strings.csv:1-26` |
| `_generic_glyph` coverage | PARTIAL — only `interact`, `ui_accept`, `ui_cancel` are mapped; everything else is the literal `Btn` | `input_glyph_service.gd:109-114` |

## Related
- Improvement plan: [`../actual_improvements/ui/input_glyphs.md`](../actual_improvements/ui/input_glyphs.md)
- Cross-system coordination: [`../actual_improvements/ui/status_icons_glyphs.md`](../actual_improvements/ui/status_icons_glyphs.md)
- [`combat_hud.md`](combat_hud.md) · [`inventory_ui.md`](inventory_ui.md) · [`status_icon_atlas.md`](status_icon_atlas.md)
- [`../accessibility.md`](../accessibility.md) · [`../player-controls.md`](../player-controls.md) · [`../project-config-autoloads.md`](../project-config-autoloads.md)
