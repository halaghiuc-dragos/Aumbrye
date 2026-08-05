# Stair lever and floor menu

The stair lever is the interactable that moves the player between floors of a multi-floor run. It is created in code by `DungeonBuilder` in every room whose template id ends with `_stairs`, starts locked, and unlocks when the floor's boss dies. Interacting with it opens `StairMenu`, a code-built `Control` that offers ascend, descend, and retreat-to-hub.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/stair_lever.gd` | `Node3D` interactable: lock state, direction flags, prompt, menu handoff |
| `apps/game/client/scripts/ui/stair_menu.gd` | Modal `Control` with one button per available action |

## How it works

### Creation

`DungeonBuilder._setup_stair_levers()` (`dungeon_builder.gd:610-617`, called from `build_from_definition` at `:115`) walks every built room and creates a lever for each room whose `template_id` ends with `_stairs`. `_create_stair_lever(room)` (`:620-651`) builds:

```
StairLever (Node3D, stair_lever.gd)
  InteractArea (Area3D, layer 0, mask 2, 3 x 3 x 3 box)
  Label3D (billboard, font 24, at (0, 2.5, 0))
  <DioramaInteractableSkin.build_lever visuals>
```

The skin is applied at `:641`, before the node enters the tree, so `stair_lever.gd:19-20` sees an existing visual and does not build a second one.

Parenting prefers the room's `Props` node and falls back to the room root (`:642-646`). Placement (`_place_stair_lever_on_wall`, `:654-668`) prefers `SpawnPoints/LeverSpawn`, and otherwise guesses a west-wall position from the blockout's width and depth, defaulting to 8 x 16 when there is no blockout. Only `castle_stairs.tscn` has a `LeverSpawn` marker (`castle_stairs.tscn:44`), so the other nine themes use the guess.

`_stair_lever` is a single field (`dungeon_builder.gd:45`, `:651`). When a floor has more than one `_stairs` room, every room gets a lever but only the last one assigned is retained — and only the retained one is ever unlocked.

### Direction flags

`configure(can_ascend, can_descend, can_retreat = false)` (`stair_lever.gd:29-33`) is called twice with the same two expressions:

| Flag | Expression | Site |
|------|-----------|------|
| `can_ascend` | `not RunFlow.is_final_floor() or RunFlow.get_run_mode() == "endless"` | `dungeon_builder.gd:648`, `:673` |
| `can_descend` | `RunFlow.get_current_floor() > 1 and RunFlow.get_run_mode() != "endless"` | `:649`, `:674` |
| `can_retreat` | `RunFlow.get_run_mode() in ["endless", "castle"]` | `:675` only |

The creation call at `:650` passes only two arguments, so `can_retreat` is false until the unlock call supplies it.

### Lock and unlock

`_unlocked` starts false (`stair_lever.gd:12`), which suppresses both the prompt (`:94-96`) and all input (`:46`). `DungeonBuilder._unlock_stair_lever()` (`:671-677`) re-configures and unlocks, and is called from exactly two places:

- `_on_boss_defeated()` on non-final floors (`:605-606`) — on final floors the exit portal opens instead.
- `apply_snapshot()` when the snapshot has `bossDefeated` (`:856`).

So the boss of each floor is the key to the stairs.

### Interaction

`_unhandled_input` (`:45-66`) requires `interact`, proximity, and unlock, then branches:

1. If a node in the `stair_menu` group exposes `open_for_lever`, hand off to it and stop (`:48-52`). `CastleRun._wire_run_ui` always instantiates a `StairMenu` and adds it to the tree (`castle_run.gd:113-114`), and `StairMenu._ready` joins the group (`stair_menu.gd:14`), so in a normal run this branch always wins.
2. Otherwise the fallback modifier-key path: `CTRL` retreats (`:53-56`), `SHIFT` descends but is gated on `_can_ascend` (`:57-60`), a bare press ascends when `_can_ascend`, else descends when `_can_descend` (`:61-66`).

The fallback is unreachable in `CastleRun`, is keyboard-only (`Input.is_key_pressed` rather than an action), and its `SHIFT` branch tests the wrong flag.

`_use_lever(direction)` (`:69-76`) emits `lever_used` and calls `RunFlow.ascend_floor()` or `RunFlow.descend_floor()`. `lever_used` has no listeners anywhere in `apps/`.

The prompt is a single line, `"<glyph> Floor options"` (`:99`), with no floor number and no indication of which directions are available.

### StairMenu

`stair_menu.gd` is built entirely in code from `GameUISkinScript` helpers (`:43-62`): a backdrop, a center panel, a margin, a `VBoxContainer`, and a `"Stair Lever"` title. `_rebuild_buttons` (`:65-78`) clears everything except the title and appends a plain `Button` per action, reading the lever's private fields through `_lever.get("_can_ascend")` and friends (`:72-77`). "Retreat to hub" is additionally gated on `RunFlow.can_retreat_to_hub()`.

`open_for_lever` (`:25-31`) shows the panel, sets `MOUSE_FILTER_STOP`, and frees the mouse. `close_menu` (`:34-40`) hides it, re-captures the mouse, and emits `closed`.

Notable behavior:

- The tree is never paused. `process_mode` is `PROCESS_MODE_ALWAYS` (`:16`) but nothing sets `get_tree().paused`, so enemies keep acting and hitting the player while the menu is open with a free cursor.
- No button receives focus and there is no focus-neighbor wiring, so the menu is mouse-only.
- `close_menu` unconditionally re-captures the mouse, so closing the stair menu while another menu is open steals mouse mode.
- The lever's `_unhandled_input` is not suppressed while the menu is open, so a second `interact` press re-enters `open_for_lever` and rebuilds the buttons.
- `_use_lever` reaches into the lever's private method by name (`:89-90`).
- The buttons are unstyled `Button` instances, unlike the title which goes through the skin.

### Floor transition and arrival

`RunFlow.ascend_floor()` (`run_flow.gd:524-534`) requires an active run, `_boss_defeated`, the current floor in `_cleared_floors`, and — in castle mode — `current_floor < max_floors`. `descend_floor()` (`:537-545`) requires `current_floor > 1` and refuses in endless mode. Both stash the current floor in the definition cache, move `current_floor`, and `await _transition_floor(ascending)`, which regenerates or reuses the floor, writes `dungeon_definition`, `floor_transition`, and `run_snapshot` root metas, and reloads the run scene (`:548-574`).

`CastleRun` then calls `_restore_saved_snapshot()` (`castle_run.gd:47`) followed by `_apply_floor_transition_spawn()` (`:48`). `_restore_saved_snapshot` removes the `run_snapshot` meta at `:311`, and `_apply_floor_transition_spawn` returns immediately when that meta is missing (`:286-287`). The stair-room spawn therefore never runs: after a floor transition the player appears at the new floor's start-room `PlayerSpawn` rather than at its stairs.

`RunFloorConfig.find_stairs_room_id(definition)` (`run_floor_config.gd:47-53`) picks the first room whose `templateId` ends with `_stairs` **or** whose `type` is `corridor`, and falls back to the literal `"stairs"`. That is a different rule from the builder's lever rule at `:615`. `stairs_spawn_facing_y` (`:56-63`) dereferences `stair_room` without a null check.

### What the suites assert

| Suite | Line | Assertion |
|-------|------|-----------|
| `m7_suite.gd` | `:330-341` | `load("res://scripts/dungeon/stair_lever.gd") != null` |
| `m7_suite.gd` | `:342-349` | `stairs_spawn_facing_y(null, true)` returns a float — the argument is `null`, which dereferences null at `run_floor_config.gd:58` |
| `m7_suite.gd` | `:903` | the lever source text contains the substring `retreat_to_hub` |

Nothing asserts a lever is created, placed inside the room, unlocked by the boss, or that ascending changes the floor.

## Contracts

- Node-name contract read by `stair_lever.gd:21-22`: `InteractArea`, `Label3D`; the diorama visual is named `DioramaSkin.VISUAL_NAME`.
- Room contract: `Props` (preferred parent), `SpawnPoints/LeverSpawn` (preferred placement), `SpawnPoints/PlayerSpawn` (arrival).
- Template contract: the lever exists only if some room's `templateId` ends with `_stairs`.
- Group contract: any node in group `stair_menu` with `open_for_lever(lever)` intercepts the interaction.
- Private-field contract: `StairMenu` reads `_can_ascend`, `_can_descend`, `_can_retreat` and calls `_use_lever` on the lever.
- `RunFlow.ascend_floor()`, `descend_floor()`, `retreat_to_hub()`, `can_retreat_to_hub()` are the outbound API.
- Signals: `lever_used(direction)` (no listeners), `StairMenu.closed` (no listeners).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Lever creation, lock, unlock on boss death | IMPLEMENTED | `dungeon_builder.gd:610-677` |
| Ascend / descend / retreat through `RunFlow` | IMPLEMENTED | `stair_lever.gd:69-76`, `run_flow.gd:491-545` |
| Menu built from the UI skin helpers | IMPLEMENTED | `stair_menu.gd:43-62` |
| Floor-transition spawn at the stairs | BROKEN | `run_snapshot` meta removed at `castle_run.gd:311` before `_apply_floor_transition_spawn` reads it at `:286` |
| One retained lever per floor | BROKEN | `dungeon_builder.gd:651` overwrites `_stair_lever`; extra levers stay locked forever |
| Lever placement outside the castle theme | PLACEHOLDER | only `castle_stairs.tscn:44` has `LeverSpawn`; the rest use the guess at `dungeon_builder.gd:660-668` |
| Modifier-key fallback path | PARTIAL | unreachable when a `StairMenu` exists, keyboard-only, and `SHIFT` descend is gated on `_can_ascend` (`stair_lever.gd:53-66`) |
| Menu does not pause the run | PARTIAL | `process_mode` set, `get_tree().paused` never set (`stair_menu.gd:16`) |
| Menu keyboard / gamepad navigation | ABSENT | no `grab_focus`, no focus neighbors (`stair_menu.gd:81-85`) |
| Prompt detail (target floor, directions) | ABSENT | single generic line (`stair_lever.gd:99`) |
| Lever animation, audio, VFX | ABSENT | no `AnimationPlayer`, `AudioDirector`, or `VfxService` reference in either file |
| Descend danger / cost feedback | ABSENT | no confirmation on either direction |
| `lever_used` consumers | ABSENT | no listeners in `apps/` |
| Behavioral suite coverage | ABSENT | `m7_suite.gd:330-349` only checks the script loads |
| `stairs_spawn_facing_y` null guard | BROKEN | `run_floor_config.gd:58` dereferences the argument; `m7_suite.gd:343` passes `null` |

## Related

- Improvement plan: [`../actual_improvements/stair-lever.md`](../actual_improvements/stair-lever.md)
- [`dungeon-builder.md`](dungeon-builder.md) — creation, placement, unlock
- [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md) — `RunFloorConfig`, floor limits, seed mixing
- [`room-templates.md`](room-templates.md) — `_stairs` templates, `LeverSpawn`, `Props`
- [`run-flow.md`](run-flow.md) — `ascend_floor`, `descend_floor`, `retreat_to_hub`
- [`castle-run.md`](castle-run.md) — instantiates `StairMenu`, applies the transition spawn
- [`boss-door-exit-portal.md`](boss-door-exit-portal.md) — the final-floor exit
- [`ui/menu_shell.md`](ui/menu_shell.md), [`ui/game_ui_skin.md`](ui/game_ui_skin.md) — the skin the menu borrows from
- [`ui/input_glyphs.md`](ui/input_glyphs.md) — prompt glyph
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — `build_lever`
