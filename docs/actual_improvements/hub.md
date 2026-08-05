# Hub — improvement plan

## Current state
The hub works: ten interactables, three run-mode menus wired to `RunFlow`, four service UIs, three data-driven NPCs, and a full procedural diorama pass. See [`../existing_codebase/hub.md`](../existing_codebase/hub.md). The problems are in the seams. The first-run tip system is a hardcoded GDScript array whose text is factually wrong about two key bindings, is overwritten a frame after it appears, double-fires with the interact action, and loads its state from the wrong character. `HubInteractable.interact_id` is an exported field with zero readers anywhere in the repository, so all ten landmarks are routed through ten hand-maintained booleans and a fixed `if / elif` chain instead. Two portals are hidden with their interact areas left live. Service and portal positions are declared twice, once in `hub.tscn` and once in `hub_diorama.gd`, and the diorama wins.

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| HUB-01 | P0 | Two of five hub tips name the wrong key: tip 2 says right-click for block (bound to `Q`), tip 5 says Esc for the inventory (bound to Tab) | `hub_tutorial_service.gd:14`, `hub_tutorial_service.gd:17` vs `project.godot:173-177`, `project.godot:250-255`, `hub.tscn:343` |
| HUB-02 | P0 | The tip text is written into `MessageLabel` by the deferred `_maybe_show_hub_tips`, then overwritten by `_boot_save_and_services` when it resumes after its `await`, so a first-time player usually never reads tip 1 | `hub.gd:81-82`, `hub.gd:86`, `hub.gd:94`, `hub.gd:419-420` |
| HUB-03 | P0 | The tip handler in `_input` does not mark the event handled, so one `interact` press both advances the tip and triggers the nearby portal or vendor | `hub.gd:429-432` vs `hub.gd:120-168` |
| HUB-04 | P0 | `HubTutorialService.load_from_save()` runs before the deferred save load, so on a character switch the tips state comes from the previous character's `meta` | `hub.gd:80` before `hub.gd:81`; `hub_tutorial_service.gd:21-25` reads `LocalSave.get_meta_data()` which is backed by `_cached_state` (`local_save.gd:396-398`) |
| HUB-05 | P1 | Tip content is a hardcoded GDScript array with no content file, no ordering rules, no per-tip trigger condition, and no localisation path | `hub_tutorial_service.gd:12-18`; nothing under `content/` mentions tips |
| HUB-06 | P1 | `HubInteractable.interact_id` is exported and never read; interact routing is ten booleans and a 40-line `if / elif` chain that must be edited for every new landmark | `hub_interactable.gd:11` (no other reference in the repository), `hub.gd:29-38`, `hub.gd:120-168`, `hub.gd:226-255` |
| HUB-07 | P1 | The Skies and Cathedral portals are hidden but their `InteractArea` nodes stay enabled, so the player gets a "coming soon" message from an invisible volume | `hub.gd:56-59`; `hub.tscn:493-501`, `hub.tscn:522-530` |
| HUB-08 | P1 | Hub messages appear on a `Label3D` fixed at world `(0, 3.5, 2)` while the player spawns at `(12, 0, 2)`, so the welcome message and every tip are 12 m to the player's left | `hub.tscn:258-262`, `hub_diorama.gd:29` |
| HUB-09 | P2 | Portal, arena-door, and service positions exist twice — in the `hub.tscn` transforms and in `hub_diorama.gd` constants — and the diorama silently overwrites the scene | `hub.tscn:92`, `hub.tscn:121` vs `hub_diorama.gd:160-181`; `hub.tscn:150`, `174`, `198`, `222` vs `hub_diorama.gd:135-145` |
| HUB-10 | P2 | `_update_prompt` runs every frame and iterates the `hub_npc` group plus reassigns `Label3D.text` even when nothing changed | `hub.gd:171-172`, `hub.gd:250-255` |
| HUB-11 | P2 | Entering an interact zone produces no audio and no visual highlight; the only feedback is the prompt label | `hub_interactable.gd:33-42` emits signals only |
| HUB-12 | P2 | `HubTutorialService` state lives in `static var`s on a `RefCounted`, so it is process-global rather than per-character, and `advance_tip` triggers a full `LocalSave.autosave()` per tip | `hub_tutorial_service.gd:8-10`, `hub_tutorial_service.gd:36` |

## Target design

### Tips become content, and become correct
The tip list moves out of GDScript into a content file so writers can edit it, glyphs can be substituted, and each tip can declare when it is relevant:

`content/hub/tips.json`:

```json
{
  "schemaVersion": 1,
  "tips": [
    {
      "id": "dodge_basics",
      "text": "Dodge with {dodge} to roll through attacks. Practice in the training arena.",
      "actions": ["dodge"],
      "showWhen": { "minLevel": 1 }
    },
    {
      "id": "block_basics",
      "text": "Block with {block}; a well-timed parry staggers enemies.",
      "actions": ["block"]
    },
    {
      "id": "ascend",
      "text": "Defeat the floor boss, then pull the stair lever to ascend.",
      "actions": []
    },
    {
      "id": "inventory",
      "text": "Open your inventory with {inventory} to equip better gear.",
      "actions": ["inventory"]
    }
  ]
}
```

Every `{action}` placeholder is resolved at display time through the input glyph helper (see [`ui/input_glyphs.md`](ui/input_glyphs.md)), which reads the live `InputMap`. That makes HUB-01 structurally impossible: a rebind changes the tip, and a tip naming an action that does not exist fails content validation instead of shipping.

The "secret rooms — listen for hidden passages" tip is dropped rather than reworded, because no audio cue for hidden rooms exists; it returns when the cue does.

```gdscript
## hub_tutorial_service.gd
const SAVE_KEY := "hub_tutorial"
const CONTENT_PATH := "res://../../../content/hub/tips.json"   ## resolved through ContentLoader

static func load_catalog() -> void                       ## via ContentLoader, cached
static func load_from_save() -> void
static func should_show_tips() -> bool
static func get_current_tip() -> String                  ## glyph-substituted, ready to display
static func current_tip_id() -> String
static func advance_tip() -> String
static func skip_all() -> void
static func reset_for_character() -> void                ## called on save_loaded
```

`get_current_tip()` returns the substituted string so no caller re-implements the placeholder pass.

### Tips own their own display surface
The overwrite race (HUB-02) is not fixable by reordering, because `_boot_save_and_services` legitimately wants to greet the player and both writers target one `Label3D`. Tips get their own surface and their own lifetime:

- `_maybe_show_hub_tips` writes to a dedicated `TipLabel` (a second `Label3D` above `MessageLabel`, or a screen-space panel in the hub HUD) that only the tip system touches.
- The tip surface is shown only while `HubTutorialService.should_show_tips()` and hidden the moment tips complete.
- `MessageLabel` keeps the welcome message, return message, and "coming soon" notices.

Sequencing is fixed as well: tips are shown from a `LocalSave.save_loaded` handler rather than a deferred call, so they are never displayed before the character they belong to is loaded. That single change also closes HUB-04, because `HubTutorialService.load_from_save()` moves into the same handler.

```gdscript
## hub.gd
func _ready() -> void:
    ...
    LocalSave.save_loaded.connect(_on_save_loaded)

func _on_save_loaded() -> void:
    HubTutorialService.load_from_save()
    _refresh_tip_surface()
```

### Input ownership
The tip handler moves from `_input` to `_unhandled_input`, placed before the interactable chain and returning early after marking the event handled:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if HubTutorialService.should_show_tips() and _handle_tip_input(event):
        get_viewport().set_input_as_handled()
        return
    if _any_ui_open():
        return
    ...
```

This gives an unambiguous rule: while tips are on screen, `interact` advances the tip; once they are done, `interact` uses the world. Chosen over letting both fire: the current behaviour means a new player standing near the castle portal opens the run menu while trying to read tip 1, which is the worst possible first minute.

### Id-driven interactables
`interact_id` gets its purpose. Each `HubInteractable` in `hub.tscn` declares its id, and `hub.gd` keeps one nearby id instead of ten booleans:

```gdscript
## hub_interactable.gd
@export var interact_id: String = ""
@export var prompt_text: String = "Interact (E)"
@export var enabled: bool = true      ## new; disables the area without hiding the parent

func set_enabled(value: bool) -> void  ## toggles monitoring and clears _near_player
```

```gdscript
## hub.gd
const INTERACT_HANDLERS := {
    "castle_portal": "_open_castle_menu",
    "endless_portal": "_open_endless_menu",
    "waves_portal": "_open_waves_menu",
    "skies_portal": "_show_coming_soon_skies",
    "cathedral_portal": "_show_coming_soon_cathedral",
    "arena_door": "_enter_arena",
    "blacksmith": "open_blacksmith",
    "merchant": "open_merchant",
    "storage": "open_storage",
    "quest_board": "open_quest_board",
}

var _nearby: Array[String] = []   ## ordered by entry, most recent last

func _nearest_interact_id() -> String
```

Instead of a fixed `if / elif` priority, the most recently entered zone wins, which matches what the player expects when two zones overlap. Prompt text comes from the interactable that owns `_nearest_interact_id()`, so `_update_prompt` no longer walks a ten-branch chain.

Adding a landmark becomes: place the node, set `interact_id`, add one row to `INTERACT_HANDLERS`. A row naming a method that does not exist fails a validation assertion.

### Disabled means disabled
`SkiesPortal` and `CathedralPortal` set `enabled = false` on their interact areas instead of only hiding the parent. Their "coming soon" state is expressed once, in the scene, rather than as a hidden node plus a live area plus a hardcoded message string. When the content ships, the flag flips and the handler is replaced.

### One source of truth for layout
`hub_diorama.gd` stops repositioning nodes that the scene already places. `_position_portals`, `_position_player_spawn`, and `_position_service_npcs` are deleted, and the `hub.tscn` transforms are corrected once to the positions the diorama currently forces:

| Node | Corrected `hub.tscn` position |
|------|------------------------------|
| `CastlePortal` | `(12, 0, -17)` |
| `UmbralEndlessPortal` | `(6, 0, -17)` |
| `UmbralWavesPortal` | `(0, 0, -17)` |
| `ArenaDoor` | `(-6, 0, -17)` |
| `SkiesPortal` | `(-12, 0, -17)` |
| `CathedralPortal` | `(-18, 0, -17)` |
| `Player` | `(12, 0, 2)` |

`_service_world_position` is replaced by a lookup of the actual node transform, so tent dressing follows the scene rather than a parallel constant table:

```gdscript
static func _service_world_position(hub: Node3D, service_name: String) -> Vector3:
    var node := hub.get_node_or_null(service_name) as Node3D
    return node.position if node else Vector3.ZERO
```

Chosen over deleting the scene transforms and treating the diorama as authoritative: a designer opening `hub.tscn` must see the real layout, and a scene that lies about where things are makes every future edit guesswork.

### Interact feedback
`HubInteractable` gains the feedback the hub currently lacks, in one place rather than ten:

```gdscript
@export var enter_sound: StringName = &"ui_interact_near"
@export var highlight_target: NodePath   ## optional mesh or Node3D to pulse
```

On `player_entered` it plays the cue through `AudioDirector` once per entry and starts a subtle emissive pulse on `highlight_target`; on exit it stops. The tent ridge signs and portal glows are the natural highlight targets and already exist as named nodes.

### Cheaper prompt updates
`_update_prompt` moves from `_process` to being called on `player_entered`, `player_exited`, and any UI open or close, with the text written only when it differs from the current value. The `hub_npc` group walk disappears because NPC interact areas become ordinary `interact_id` entries (`npc:blacksmith_aldric` and so on) resolved through `NpcCatalog`.

### Per-character, throttled tip state
`HubTutorialService` keeps its static API but its state is reset by `reset_for_character()` on `save_loaded`, and `save()` uses the deferred autosave priority from [`local-save.md`](local-save.md) rather than a full write per tip.

## Work plan

1. **Add `content/hub/tips.json`, its schema, and `HubTutorialService.load_catalog` with glyph substitution** — new content file, `content/schemas/hub-tips.v1.json`, `hub_tutorial_service.gd:12-18` replaced by catalog-backed storage, `scripts/validate-content/validate.mjs` mapping. Closes HUB-01, HUB-05.
2. **Give tips their own display surface and move display to a `save_loaded` handler** — `hub.tscn` gains `TipLabel`, `hub.gd:80-82` and `hub.gd:413-420` rewritten, `HubTutorialService.reset_for_character` added. Closes HUB-02, HUB-04.
3. **Move tip input into `_unhandled_input` ahead of the interact chain and mark it handled** — `hub.gd:120-168`, `hub.gd:423-432`. Closes HUB-03.
4. **Add `enabled` / `set_enabled` to `HubInteractable`, set `interact_id` on all ten areas in `hub.tscn`, and replace the ten booleans with `_nearby` plus `INTERACT_HANDLERS`** — `hub_interactable.gd`, `hub.tscn`, `hub.gd:29-38`, `hub.gd:120-168`, `hub.gd:199-255`, `hub.gd:365-410`. Closes HUB-06.
5. **Disable the Skies and Cathedral interact areas in the scene** — `hub.tscn:493`, `hub.tscn:522`, remove the visibility toggle at `hub.gd:56-59`. Closes HUB-07.
6. **Correct the `hub.tscn` transforms and delete `_position_portals`, `_position_player_spawn`, `_position_service_npcs`, and `_service_world_position`'s constant table** — `hub.tscn`, `hub_diorama.gd:135-145`, `hub_diorama.gd:160-196`, `hub_diorama.gd:699-722`. Closes HUB-09.
7. **Move the message surface to follow the player, or move the player spawn to face the message** — preferred: anchor `MessageLabel` and `TipLabel` to a `Node3D` above the player rather than to world origin. Closes HUB-08.
8. **Add `enter_sound` and `highlight_target` to `HubInteractable`; wire the ridge signs and portal glows** — `hub_interactable.gd`, `hub_diorama.gd` sign and glow nodes. Closes HUB-11.
9. **Make `_update_prompt` event-driven and idempotent; fold NPCs into `interact_id`** — `hub.gd:171-172`, `hub.gd:226-255`, `npc_base.gd:22`. Closes HUB-10.
10. **Throttle tip persistence** — `hub_tutorial_service.gd:36` uses `LocalSave.request_autosave(LocalSave.SavePriority.DEFERRED)`. Depends on [`local-save.md`](local-save.md). Closes HUB-12.

## Data and schema changes

**New content file:** `content/hub/tips.json` as above.

**New schema:** `content/schemas/hub-tips.v1.json`

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Hub tips",
  "type": "object",
  "additionalProperties": false,
  "required": ["schemaVersion", "tips"],
  "properties": {
    "schemaVersion": { "const": 1 },
    "tips": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "text"],
        "properties": {
          "id": { "type": "string", "pattern": "^[a-z0-9_]+$" },
          "text": { "type": "string", "minLength": 8 },
          "actions": {
            "type": "array",
            "items": { "type": "string", "pattern": "^[a-z0-9_]+$" }
          },
          "showWhen": { "$ref": "condition.v1.json" }
        }
      }
    }
  }
}
```

`showWhen` reuses the dialogue condition block so tips can be gated by level, flag, or quest state with no new evaluator; see [`dialogue-quests.md`](dialogue-quests.md).

**Save format:** `meta.hub_tutorial` changes from `{"enabled", "completed", "index"}` to id-based state, because an integer index breaks the moment a tip is inserted or removed:

```json
"hub_tutorial": {
  "enabled": true,
  "completed": false,
  "seen": ["dodge_basics", "block_basics"]
}
```

`_migrate_v4_to_v5` (the shared bump in [`save-migrator.md`](save-migrator.md)) converts the old shape by taking the first `index` tip ids from the catalog order:

```gdscript
var tut: Dictionary = meta.get("hub_tutorial", {})
if tut.has("index") and not tut.has("seen"):
    var seen: Array[String] = []
    var ordered := HubTutorialService.catalog_ids()
    for i in mini(int(tut.get("index", 0)), ordered.size()):
        seen.append(ordered[i])
    tut["seen"] = seen
    tut.erase("index")
```

**Failure and recovery behaviour:**

| Situation | Behaviour |
|-----------|-----------|
| `content/hub/tips.json` missing or unparseable | `should_show_tips()` returns false, one `push_warning`, the hub runs with no tips; no crash and no blank label |
| A tip names an unbound action | Content validation fails; at runtime the placeholder renders as the raw action name and one warning is emitted |
| `meta.hub_tutorial.seen` contains an id no longer in the catalog | Ignored for progression and dropped on the next save |
| A tip's `showWhen` references an unregistered flag | `DialogueConditions.evaluate` returns the same result it does today; the flag registry check in [`character-service.md`](character-service.md) catches it at validation time |
| An `INTERACT_HANDLERS` row names a missing method | `hub.interact.handlers_exist` fails; at runtime the interact is a no-op with one warning rather than a crash |
| An `InteractArea` has an empty `interact_id` | `push_warning` at `_ready` naming the node path; the area is disabled so it cannot produce a silent dead zone |
| `hub.tscn` is missing a node `hub.gd` requires | Unchanged: `@onready` produces a hard failure. A `hub.scene.required_nodes_present` assertion catches it in CI first |

## Acceptance criteria
- [ ] Every hub tip that names a control renders the live binding, and rebinding `block` to `F` changes the tip text without a code edit. (HUB-01)
- [ ] A brand-new character reads tip 1 on the tip surface, and the welcome message appears on `MessageLabel` at the same time without either clobbering the other. (HUB-02)
- [ ] While tips are visible, standing on the castle portal and pressing `interact` advances the tip and does not open the run menu. (HUB-03)
- [ ] Creating character B after finishing tips on character A shows B the tips from the start. (HUB-04)
- [ ] Adding a tip to `content/hub/tips.json` changes the in-game sequence with no GDScript change. (HUB-05)
- [ ] Adding an eleventh landmark requires only a node with an `interact_id` and one `INTERACT_HANDLERS` row. (HUB-06)
- [ ] Walking through the Skies portal's former volume produces no prompt and no message. (HUB-07)
- [ ] The welcome message and tips are legible from the player spawn without turning the camera. (HUB-08)
- [ ] Opening `hub.tscn` in the editor shows the portals on the north wall where they appear in game. (HUB-09)
- [ ] Standing still in the hub performs no per-frame group query and no `Label3D.text` assignment. (HUB-10)
- [ ] Entering the blacksmith zone plays one cue and pulses the ridge sign; leaving stops it. (HUB-11)
- [ ] Advancing all tips produces one deferred save write rather than one per tip. (HUB-12)

## Validation
Extend `apps/game/client/scripts/validation/suites/hub_m4_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `hub.tips.load_from_content` | `HubTutorialService.catalog_ids()` matches the ids in `content/hub/tips.json` in order |
| `hub.tips.actions_are_bound` | Every action named by a tip exists in `InputMap.get_actions()` |
| `hub.tips.glyph_substitution` | `get_current_tip()` contains no `{` and names the current binding for the tip's action |
| `hub.tips.state_is_per_character` | Completing tips, switching characters, and reloading yields `should_show_tips() == true` for the second character |
| `hub.tips.seen_survives_catalog_insert` | Inserting a tip at position 0 does not re-show already-seen tips |
| `hub.tips.migrate_index_to_seen` | A v4 `meta.hub_tutorial` with `index: 2` migrates to a two-entry `seen` array |
| `hub.tips.input_is_consumed` | With tips visible, an `interact` press advances the tip and leaves `_nearby` handlers untriggered |
| `hub.tips.surface_not_clobbered` | After `_on_save_loaded` and `_boot_save_and_services` both complete, the tip surface still shows tip 1 and `MessageLabel` shows the welcome message |
| `hub.interact.every_area_has_id` | Every `HubInteractable` under the hub scene has a non-empty `interact_id` |
| `hub.interact.handlers_exist` | Every `INTERACT_HANDLERS` value is a method on the hub script |
| `hub.interact.ids_are_unique` | No two interact areas share an id |
| `hub.interact.most_recent_zone_wins` | Entering the merchant zone then the storage zone prompts for storage |
| `hub.interact.disabled_area_is_inert` | A disabled area emits no `player_entered` and produces no prompt |
| `hub.scene.required_nodes_present` | Every `@onready` path in `hub.gd` resolves in an instanced `hub.tscn` |
| `hub.layout.scene_matches_runtime` | The six portal, player, and four service node positions after `HubDiorama.apply` equal their `hub.tscn` transforms |
| `hub.prompt.is_event_driven` | Ten seconds of idle `_process` performs zero `Label3D.text` writes |
| `hub.feedback.enter_cue_once` | Entering a zone plays exactly one cue; re-entering after exit plays one more |

Extend `apps/game/client/scripts/validation/suites/content_suite.gd` with `content.hub_tips.schema_valid` (validates `content/hub/tips.json` against `hub-tips.v1.json`) and `content.hub_tips.conditions_resolve` (every `showWhen` block parses through `DialogueConditions.evaluate` without error).

## Related
- Existing state: [`../existing_codebase/hub.md`](../existing_codebase/hub.md)
- [`npc-hub-services.md`](npc-hub-services.md), [`dialogue-quests.md`](dialogue-quests.md), [`character-service.md`](character-service.md), [`character-appearance.md`](character-appearance.md), [`local-save.md`](local-save.md), [`save-migrator.md`](save-migrator.md), [`run-flow.md`](run-flow.md), [`content-catalog.md`](content-catalog.md), [`content-data.md`](content-data.md), [`ui/hub_vendors.md`](ui/hub_vendors.md), [`ui/run_portals.md`](ui/run_portals.md), [`ui/input_glyphs.md`](ui/input_glyphs.md)
