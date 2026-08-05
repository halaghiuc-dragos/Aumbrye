# Input glyphs — improvement plan

## Current state
`input_glyph_service.gd` returns short hardcoded **strings** for nine actions across four device families (`input_glyph_service.gd:67-114`). It never queries `InputMap`, so the labels are a parallel truth that has already drifted: it reports `I` for `inventory` while `project.godot:250-255` binds that action to `Tab`, and it reports `Tab` for `lock_on`. `detect_family()` runs on every `get_action_glyph` call and decides purely on whether a joypad is *connected*, so an idle controller forces controller labels onto a keyboard player, and no signal exists to tell the HUD to rebuild when that changes (`combat_hud.gd:222-241` builds its hint once). There is no glyph art of any kind — the repo contains zero `.png`. See [`../existing_codebase/ui/input_glyphs.md`](../existing_codebase/ui/input_glyphs.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| GLY-01 | P0 | Glyph labels are wrong: the service tells the player to press `I` for the inventory, but the action is bound to `Tab`. Every prompt built from the keyboard table is unverified against the project bindings. | `input_glyph_service.gd:72` returns `"I"` for `inventory`; `project.godot:250-255` binds `physical_keycode 4194306` (`Tab`) |
| GLY-02 | P0 | Bindings are duplicated as literals instead of read from `InputMap`, so the tables cannot be correct by construction and cannot survive a rebind. | `input_glyph_service.gd:67-114`; no `InputMap.action_get_events` call anywhere in the file |
| GLY-03 | P0 | Prompts are plain body text, not glyph art, so the pixel-diorama UI shows `Press E` and `Dash Space` in the default sans-serif. | `get_action_glyph` returns `String` (`input_glyph_service.gd:26`); `apps/game/client/**/*.png` returns 0 files |
| GLY-04 | P1 | No `device_family_changed` signal, so `combat_hud.gd`'s control hint — built once in `_ready()` — shows keyboard glyphs for the rest of the session after a pad is plugged in. | `input_glyph_service.gd:1-24`; `combat_hud.gd:222-241` |
| GLY-05 | P1 | Detection is connection-based, not last-input-based: a docked controller that the player is not touching overrides live keyboard input. | `input_glyph_service.gd:12-15` |
| GLY-06 | P1 | Only nine actions are mapped. `heal`, `light_attack`, `heavy_attack`, `block`, `two_hand`, `weapon_art`, `talents`, `quick_slot_1..3` fall through to the first letter of the action name (keyboard) or the literal `A` / `Cross` / `Btn` (pads). | `input_glyph_service.gd:78,92,106,114`; `project.godot:161-296` defines all of the above |
| GLY-07 | P1 | `_generic_glyph` maps only three actions and returns `Btn` for everything else, so any non-Xbox, non-Sony pad — including Nintendo and Steam Deck GUIDs — shows meaningless labels. | `input_glyph_service.gd:109-114`, `:21-22` |
| GLY-08 | P1 | Every label is hardcoded English and none of `Press`, `Dash`, `Lock`, `Enter`, `Esc`, `Menu`, `Options` appears in `translations/strings.csv`. | `input_glyph_service.gd:39-60`; `translations/strings.csv:1-26` |
| GLY-09 | P2 | `detect_family()` per call costs a joypad enumeration and a GUID string lowercase per glyph; the inventory footer builds six glyphs per refresh, and `_refresh_all` runs on every cursor move. | `input_glyph_service.gd:27`; `inventory_ui.gd:835-842` called from `_update_detail` at `:506` |
| GLY-10 | P2 | Only `pads[0]` is inspected, so a second pad of a different family is ignored. | `input_glyph_service.gd:15-16` |
| GLY-11 | P2 | Consumers reference the class inconsistently — three files via `class_name`, three via `preload` const — making call sites harder to audit. | `stair_lever.gd:99` vs `combat_hud.gd:4` |

## Target design

### Bindings from `InputMap`, art from an atlas
The service becomes a two-stage resolver: `InputMap` gives the *physical* input for an action; a data manifest maps that physical input to an atlas cell and a fallback text label. Nothing about a binding is hardcoded.

```gdscript
class_name InputGlyphService

signal device_family_changed(family: DeviceFamily)   # on a real InputGlyphService autoload node

enum DeviceFamily { KEYBOARD, XBOX, PLAYSTATION, NINTENDO, STEAM_DECK, GENERIC }

static func current_family() -> DeviceFamily
static func get_action_glyph_texture(action: String) -> AtlasTexture   # null only if unmapped
static func get_action_glyph_text(action: String) -> String            # accessible fallback
static func get_action_display_name(action: String) -> String           # tr()-backed
static func format_action_hint(action: String) -> String                # text-only path
static func decorate_label(label: Label, action: String, prefix_key: String = "") -> void
```

`decorate_label` is the preferred call: it builds `RichTextLabel`-style inline art by appending a `TextureRect` sized to the label's font ascent inside an `HBoxContainer`, so prompts read as `[E] Floor options` with real pixel art. It replaces `format_interact_label` at `stair_lever.gd:99`, `boss_room_door.gd:105`, `final_boss_cannon.gd:116`.

Because `detect_family` needs to observe input events, the service gains a companion autoload node `InputGlyphWatcher` (`apps/game/client/scripts/ui/input_glyph_watcher.gd`, registered in `project.godot` `[autoload]`) that implements `_input` and updates the cached family. The static API stays for call-site compatibility; the signal lives on the watcher and is re-exposed as `InputGlyphService.watcher().device_family_changed`.

Rejected alternative: keeping everything static and polling in `_process`. Polling cannot distinguish "pad connected" from "pad in use", which is exactly GLY-05.

### Last-used-device tracking
`InputGlyphWatcher._input(event)`:

| Event type | Resulting family |
|---|---|
| `InputEventKey`, `InputEventMouseButton`, `InputEventMouseMotion` (with non-zero relative) | `KEYBOARD` |
| `InputEventJoypadButton`, `InputEventJoypadMotion` with `abs(axis_value) > 0.35` | family resolved from `Input.get_joy_guid(event.device)` |

The family changes only on a real event, and `device_family_changed` is emitted only on an actual transition. `Input.joy_connection_changed` is also connected so unplugging the active pad falls back to `KEYBOARD` immediately (GLY-04, GLY-05, GLY-10 — the family follows the pad that produced the event, not index 0).

GUID substring table, checked in order: `xinput` / `xbox` → `XBOX`; `sony` / `playstation` / `dualshock` / `dualsense` → `PLAYSTATION`; `nintendo` / `switch` / `joy-con` / `joy_con` → `NINTENDO`; `steam` / `valve` → `STEAM_DECK`; else `GENERIC` (GLY-07).

### Binding resolution
```gdscript
static func _primary_event(action: String, family: DeviceFamily) -> InputEvent
```

Walks `InputMap.action_get_events(action)` and returns the first event whose type matches the family (`InputEventKey` for `KEYBOARD`, `InputEventJoypadButton` / `InputEventJoypadMotion` for the pad families). The physical key is then turned into a display string with `OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode))`, which respects the user's keyboard layout — so an AZERTY player is told the right key. Joypad buttons resolve through the manifest by `button_index`.

This removes the entire keyboard table and makes GLY-01 unrepresentable: the label is derived from the binding.

### Glyph atlas
Ship `apps/game/client/assets/ui/input_glyphs.png`: **256 × 128 px**, a **16 × 8 grid of 16 × 16 px cells**, 128 cells. Manifest at `content/ui/input_glyph_atlas.json`:

```json
{
  "schemaVersion": 1,
  "texture": "res://assets/ui/input_glyphs.png",
  "cellSize": 16,
  "columns": 16,
  "rows": 8,
  "keyboard": { "E": {"col": 4, "row": 0}, "TAB": {"col": 0, "row": 2}, "SPACE": {"col": 1, "row": 2} },
  "xbox":     { "0": {"col": 0, "row": 4}, "1": {"col": 1, "row": 4} },
  "playstation": { "0": {"col": 0, "row": 5} },
  "nintendo": { "0": {"col": 0, "row": 6} },
  "generic":  { "0": {"col": 0, "row": 7} },
  "unknown":  {"col": 15, "row": 7}
}
```

Row layout: rows `0`-`1` letter keys, row `2` named keys (`TAB`, `SPACE`, `ENTER`, `ESC`, `SHIFT`, `CTRL`, `ALT`, arrows), row `3` mouse and modifiers, row `4` Xbox face/shoulder/stick, row `5` PlayStation, row `6` Nintendo, row `7` generic plus the `unknown` cell at `(15,7)`. Keyboard keys are keyed by `OS.get_keycode_string` output (uppercase); pad buttons by `JoyButton` index as a decimal string. Cell naming for source art layers: `glyph_<family>_<key>_16.png`.

`get_action_glyph_texture` returns the `unknown` cell and calls `push_warning` when a binding has no cell, so a new binding is loud rather than silently blank (GLY-03).

### Text fallback and accessibility
`get_action_glyph_text` remains for screen-reader-friendly and log output, and a new `AccessibilitySettings.prefer_text_glyphs: bool = false` forces `decorate_label` down the text path. Every remaining literal moves to `translations/strings.csv` (GLY-08).

### Full action coverage
`get_action_display_name` reads a manifest table rather than a `match`, covering all actions declared in `project.godot`: `move_forward`, `move_back`, `move_left`, `move_right`, `sprint`, `jump`, `dodge`, `light_attack`, `heavy_attack`, `block`, `lock_on`, `pause`, `interact`, `inventory`, `talents`, `heal`, `two_hand`, `weapon_art`, `quick_slot_1`, `quick_slot_2`, `quick_slot_3`, `zoom_in`, `zoom_out`, and the `ui_*` set. Each maps to a `tr()` key `ACTION_<UPPER>` (GLY-06).

### Caching
The resolved `{action, family} → AtlasTexture` pair is cached in a static dictionary, cleared on `device_family_changed` and on `InputMap` change. `current_family()` is a field read, not a poll (GLY-09).

### Call-site consistency
Every consumer uses the `class_name` `InputGlyphService` and drops the `preload` const (GLY-11).

## Work plan
1. **Watcher autoload** — add `input_glyph_watcher.gd`, register it in `project.godot` `[autoload]`, implement last-used-device tracking and `device_family_changed`; add the extended `DeviceFamily` enum and the GUID table (GLY-04, GLY-05, GLY-07, GLY-10).
2. **`InputMap`-derived labels** — add `_primary_event`, replace `_keyboard_glyph` with `OS.get_keycode_string` + `keyboard_get_keycode_from_physical`, delete the hardcoded keyboard table; add the family/action cache (GLY-01, GLY-02, GLY-09).
3. **Action name manifest** — add `content/ui/input_action_names.json` mapping every `project.godot` action to an `ACTION_*` translation key; add the keys to `strings.csv`; convert `get_action_display_name` (GLY-06, GLY-08).
4. **Glyph atlas** — commit `assets/ui/input_glyphs.png` and `content/ui/input_glyph_atlas.json`; add `get_action_glyph_texture` and `decorate_label`; add the `unknown` cell warning (GLY-03).
5. **Repoint consumers** — `combat_hud.gd:235-240` and `inventory_ui.gd:835-842` use `decorate_label` / textures and connect `device_family_changed`; `stair_lever.gd:99`, `boss_room_door.gd:105`, `final_boss_cannon.gd:116` use `decorate_label`; drop the `preload` consts (GLY-03, GLY-04, GLY-11).
6. **Text-glyph accessibility option** — add `AccessibilitySettings.prefer_text_glyphs` and its settings checkbox.

Step 2 lands before any art exists and already fixes the wrong-key bug; step 4 upgrades presentation without changing resolution logic.

## Data and schema changes
- New: `content/schemas/input-glyph-atlas.v1.json` — requires `schemaVersion`, `texture`, `cellSize`, `columns`, `rows`, `unknown`, and at least the `keyboard` map; every cell requires integer `col` / `row` in bounds.
- New: `content/ui/input_glyph_atlas.json` (manifest above).
- New: `content/schemas/input-action-names.v1.json` and `content/ui/input_action_names.json` mapping action → `ACTION_*` key.
- `apps/game/client/translations/strings.csv`: add `ACTION_*` keys for all actions listed above, plus `GLYPH_PRESS`.
- `apps/game/client/project.godot`: add `InputGlyphWatcher` under `[autoload]`.
- `AccessibilitySettings` gains `prefer_text_glyphs: bool = false`, persisted under the existing `accessibility` meta key (`accessibility_settings.gd:26-32`) — a meta key, so no `save_migrator.gd` bump.
- New asset: `assets/ui/input_glyphs.png` (256×128) with `.import` `filter=false`, `mipmaps=false`.

## Acceptance criteria
- [ ] `InputGlyphService.get_action_glyph_text("inventory")` equals `Tab` on a default keyboard layout, matching `project.godot:250-255`.
- [ ] For every action in `project.godot`'s `[input]` block, the keyboard label derives from `InputMap.action_get_events` and no keyboard label literal remains in `input_glyph_service.gd`.
- [ ] Changing a binding with `InputMap.action_erase_events` + `action_add_event` changes the reported label without a restart.
- [ ] Pressing a key while a gamepad is connected switches the reported family to `KEYBOARD`; pressing a pad button switches it back.
- [ ] `device_family_changed` fires exactly once per real transition and the combat HUD hint rebuilds on it.
- [ ] Unplugging the active pad reports `KEYBOARD` on the next frame.
- [ ] A Nintendo-GUID pad reports `NINTENDO`, not `GENERIC`.
- [ ] `get_action_glyph_texture` returns a non-null `AtlasTexture` for `interact`, `dodge`, `jump`, `lock_on`, `inventory`, `heal`, `talents`, `light_attack`, `heavy_attack`, `block` on every family.
- [ ] An unmapped binding returns the `unknown` cell and emits a warning naming the action.
- [ ] `get_action_display_name` returns a `tr()`-resolved string for every action, with no `match` in the function body.
- [ ] With `prefer_text_glyphs = true`, `decorate_label` adds no `TextureRect`.
- [ ] `current_family()` performs no `Input.get_connected_joypads()` call.
- [ ] No file under `apps/game/client/scripts` contains `preload("res://scripts/ui/input_glyph_service.gd")`.

## Validation
Extend `apps/game/client/scripts/validation/suites/m7_suite.gd` (which already exercises the service at `:441-442`):

| Test id | Assertion |
|---|---|
| `glyph.label_matches_inputmap` | for every action in `InputMap.get_actions()` with a key event, `get_action_glyph_text(action)` equals `OS.get_keycode_string` of that event's resolved keycode |
| `glyph.inventory_is_tab` | `get_action_glyph_text("inventory") == "Tab"` |
| `glyph.no_hardcoded_keyboard_table` | `input_glyph_service.gd` contains no `return "E"` and no `func _keyboard_glyph` |
| `glyph.rebind_reflected` | rebind `interact` to `KEY_Q`, assert the label becomes `Q`, then restore |
| `glyph.family_follows_last_input` | feed a synthetic `InputEventKey` then a synthetic `InputEventJoypadButton` and assert `current_family()` changes each time |
| `glyph.family_signal_once` | count `device_family_changed` emissions across two identical keyboard events; expect 1 |
| `glyph.disconnect_falls_back` | emitting `Input.joy_connection_changed(0, false)` yields `KEYBOARD` |
| `glyph.nintendo_family` | the GUID resolver returns `NINTENDO` for a GUID containing `nintendo` |
| `glyph.atlas_schema` | `content/ui/input_glyph_atlas.json` validates against `input-glyph-atlas.v1.json` |
| `glyph.atlas_texture_for_core_actions` | `get_action_glyph_texture` is non-null for the ten actions listed in the criteria, on all six families |
| `glyph.unknown_cell` | an action with no manifest cell returns the `unknown` region |
| `glyph.action_names_localized` | every action has an `ACTION_*` row in `strings.csv` whose value differs from the key |
| `glyph.no_family_poll` | `input_glyph_service.gd` contains `Input.get_connected_joypads` at most inside the watcher, not inside `current_family` |
| `glyph.consumers_use_class_name` | `combat_hud.gd` and `inventory_ui.gd` contain no `preload("res://scripts/ui/input_glyph_service.gd")` |

## Related
- Existing behavior: [`../existing_codebase/ui/input_glyphs.md`](../existing_codebase/ui/input_glyphs.md)
- Cross-system coordination: [`status_icons_glyphs.md`](status_icons_glyphs.md)
- [`combat_hud.md`](combat_hud.md) · [`inventory_ui.md`](inventory_ui.md) · [`settings.md`](settings.md)
- [`../accessibility.md`](../accessibility.md) · [`../player-controls.md`](../player-controls.md) · [`../project-config-autoloads.md`](../project-config-autoloads.md)
