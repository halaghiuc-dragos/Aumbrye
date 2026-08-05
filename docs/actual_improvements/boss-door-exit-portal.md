# Boss door and exit portal — improvement plan

## Current state

The two interactables that frame the climax of a floor are the least authored objects in the game: no scene files, node trees built from `BoxMesh` primitives in `DungeonBuilder`, and no audio or VFX. Functionally the door works — open, commit, seal, release — but any `interact` press opens it, a sealed door gives the player no feedback, `ExitPortal.activate()` has no callers, and the portal is silently orphaned in the 72 room scenes with no `Props` node. Walking into the portal ends the run with no confirmation. See [`../existing_codebase/boss-door-exit-portal.md`](../existing_codebase/boss-door-exit-portal.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| BDP-01 | P0 | The exit portal is constructed and skinned before its `Props` parent is checked, so on the 72 scenes without a `Props` node the portal is orphaned and the final floor cannot be completed | `dungeon_builder.gd:577-599`; `Props` present in 18 of 90 scenes |
| BDP-02 | P0 | Walking into the portal completes the run instantly with no confirmation, so an accidental step forfeits a run in progress | `exit_portal.gd:16-18` |
| BDP-03 | P1 | Neither object has a scene file; both are `BoxMesh` trees built in `DungeonBuilder` | `dungeon_builder.gd:696-764,577-599` |
| BDP-04 | P1 | The boss door opens on any `interact` press — no key, token, or prerequisite | `boss_room_door.gd:30-37` |
| BDP-05 | P1 | A sealed door hides its label, so the player gets no explanation for why they cannot leave | `boss_room_door.gd:101-106` |
| BDP-06 | P1 | `ExitPortal.activate()` has no callers; the builder mutates `monitoring` and `visible` directly, so the script's own contract is bypassed | `exit_portal.gd:11-13`, `dungeon_builder.gd:140-142` |
| BDP-07 | P1 | The boss door is built on every floor from the hardcoded room id `"boss"`, even when no boss was placed | `dungeon_builder.gd:696-697`, `:534-536` |
| BDP-08 | P2 | `seal_door()` sets `_opened = false`, so `is_opened()` reports false while the player is sealed inside the arena | `boss_room_door.gd:59-68` |
| BDP-09 | P2 | Neither script emits audio or VFX for open, seal, release, or portal activation | no `AudioDirector` or `VfxService` reference in either file |
| BDP-10 | P2 | The suites only assert the two nodes exist; nothing asserts the door blocks, seals, or that the portal fires | `dungeon_suite.gd:76-99`, `m5_suite.gd:215`, `m6_suite.gd:383-391` |
| BDP-11 | P2 | The portal has no `deactivate()`, so it cannot be closed once opened | `exit_portal.gd` |
| BDP-12 | P2 | `forgotten_castle_slice.gd` reaches the portal through a hardcoded node path | `forgotten_castle_slice.gd:47` |

## Target design

Both objects become authored scenes with real state machines, and the boss door becomes a gate the player earns rather than a switch they flip.

### 1. Authored scenes (BDP-03, BDP-09)

New `apps/game/client/scenes/dungeon/boss_room_door.tscn`:

```
BossRoomDoor (Node3D, boss_room_door.gd)
  Frame (Node3D)                      <- authored arch geometry, biome material slot
  Barrier (StaticBody3D, layer 1)
    BarrierShape (CollisionShape3D)
    Mesh (MeshInstance3D)             <- authored gate leaves, not a box
  Runes (Node3D)                      <- emissive detail for the sealed state
  InteractArea (Area3D, mask 2)
  Label3D
  AudioStreamPlayer3D
```

New `apps/game/client/scenes/dungeon/exit_portal.tscn`:

```
ExitPortal (Area3D, exit_portal.gd, mask 2)
  CollisionShape3D
  Visual (Node3D)                     <- portal ellipse shader quad, see portal-ellipse-shader.md
  Label3D
  AudioStreamPlayer3D
```

`DungeonBuilder` instantiates and positions them instead of constructing 60 lines of nodes each. Both scenes expose a `configure(biome_id)` that swaps the material set from `BiomeRegistry`, so the door and portal look like the biome they are in.

Audio: `door_open`, `door_seal`, `door_release`, `portal_open`, `portal_enter` cues via `AudioDirector`; VFX via `VfxService` for the seal (a rune flare) and the portal activation. Both are declared in the biome kit ([`biome-registry.md`](biome-registry.md) BIO-01) rather than hardcoded.

### 2. Portal correctness and consent (BDP-01, BDP-02, BDP-06, BDP-11)

Rewrite `_create_exit_portal` to resolve the parent first:

```gdscript
func _create_exit_portal(room: RoomTemplate) -> Area3D:
    var props := room.get_node_or_null("Props")
    if props == null:
        push_error("Exit portal: room %s has no Props node" % room.room_id)
        return null
    var portal := EXIT_PORTAL_SCENE.instantiate() as Area3D
    var marker := room.get_node_or_null("Props/ExitPortalMarker") as Node3D
    if marker == null:
        push_error("Exit portal: room %s has no ExitPortalMarker" % room.room_id)
        return null
    portal.position = marker.position
    props.add_child(portal)
    portal.configure(biome_id)
    return portal
```

Both failures are errors, not fallbacks — the `(0, 1.5, 12)` guess is exactly how a portal ends up inside a wall. `Props` and `ExitPortalMarker` land in every scene via [`room-templates.md`](room-templates.md) RTP-07.

`ExitPortal` grows a real state machine and an interaction step (BDP-02):

```gdscript
enum State { DORMANT, ACTIVE }

func activate() -> void:
    if _state == State.ACTIVE:
        return
    _state = State.ACTIVE
    monitoring = true
    visible = true
    _label.text = "%s  Leave the dungeon" % InputGlyphService.format_interact_label()
    AudioDirector.play_cue(&"portal_open")

func deactivate() -> void:
    _state = State.DORMANT
    monitoring = false
    visible = false

func _unhandled_input(event: InputEvent) -> void:
    if _state != State.ACTIVE or not _near_player or not event.is_action_pressed("interact"):
        return
    get_viewport().set_input_as_handled()
    RunOutcomeConfirm.ask("Leave with your loot?", func(): RunFlow.complete_run_via_portal())
```

`body_entered` now only sets `_near_player` and shows the prompt. The confirmation reuses the existing pause-menu style modal (owned by [`ui/run_outcome.md`](ui/run_outcome.md)); if that modal is not wanted, the fallback is a 1.5 second hold on `interact` rather than a single press. Either way the run cannot end by accident.

`DungeonBuilder.open_exit_portal()` calls `portal.activate()` and nothing else (BDP-06). `deactivate()` gives the waves and endless modes a way to close the portal when a run continues (BDP-11).

`forgotten_castle_slice.gd` looks the portal up through `builder.get_room(...)` plus a named child rather than a full hardcoded path (BDP-12).

### 3. The door as an earned gate (BDP-04, BDP-05, BDP-08)

Collapse the two booleans into one enum and add a prerequisite:

```gdscript
enum State { LOCKED, CLOSED, OPEN, SEALED, RELEASED }
```

| State | Barrier | Prompt | Entered from |
|-------|---------|--------|--------------|
| `LOCKED` | solid | "Sealed - find the Boss Sigil" | initial, when the floor has a sigil requirement |
| `CLOSED` | solid | interact glyph + "Enter the arena" | initial without a requirement, or after `LOCKED` is satisfied |
| `OPEN` | disabled | none | `open_door()` |
| `SEALED` | solid | "The way back is sealed" | `seal_door()` |
| `RELEASED` | disabled | none | `release_door()` |

`is_opened()` becomes `state in [State.OPEN, State.RELEASED]`, which removes the `_opened = false` lie (BDP-08). The sealed state keeps its label visible with an explanatory line so the player understands the commitment (BDP-05).

The prerequisite (BDP-04) is a **Boss Sigil**: a `sigil_<floor>` item dropped by the floor's miniboss, or — when the floor has no miniboss — no requirement at all, so the change is additive rather than a hard gate on every floor. The requirement is declared per dungeon in the catalog entry (`content/dungeons/<id>.json`, see [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md)) as `bossDoorRequirement: "none" | "sigil" | "all_keys"`, and `DungeonBuilder` passes it to `configure()`. `all_keys` means every lock on the floor must be opened first, which makes the lock-and-key loop from [`room-content.md`](room-content.md) RMC-01 matter for progression.

### 4. Build only what exists (BDP-07)

`_setup_boss_door` takes the boss room id from `definition.placements.exit` rather than the literal `"boss"`, and returns early when `placements.boss` is null. `CastleRun._is_player_deep_in_boss_room` reads the same id from the definition instead of its `BOSS_ROOM_ID` constant.

### 5. Behavioral test coverage (BDP-10)

The current assertions ("the node exists") would pass for an orphaned portal and a door with a disabled collider. Replace them with the assertions below.

## Work plan

1. **Portal parent check first** — the rewritten `_create_exit_portal`, errors instead of fallbacks (BDP-01). Land with [`room-templates.md`](room-templates.md) RTP-07 so every scene has `Props` and `ExitPortalMarker`.
2. **`activate()` / `deactivate()`** — `open_exit_portal` calls the script; add the state enum (BDP-06, BDP-11).
3. **Confirmation on exit** — prompt plus interact press plus modal (BDP-02).
4. **Door state enum** — replace the two booleans, keep the sealed label visible (BDP-05, BDP-08).
5. **Boss room id from the definition** — builder and `CastleRun` (BDP-07).
6. **Authored scenes** — `boss_room_door.tscn`, `exit_portal.tscn`, `configure(biome_id)`, builder instantiates them (BDP-03).
7. **Audio and VFX cues** — five cues, two VFX (BDP-09).
8. **Door requirement** — `bossDoorRequirement` in the dungeon catalog entry, sigil item, `all_keys` mode (BDP-04).
9. **Cleanup** — `forgotten_castle_slice.gd` path (BDP-12).

## Data and schema changes

- `content/schemas/dungeon-catalog-entry.v1.json` (new in [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md)) gains `bossDoorRequirement`: enum `none` | `sigil` | `all_keys`, default `none`.
- `content/schemas/biome-definition.v2.json` (new in [`biome-registry.md`](biome-registry.md)) gains an `audioCues` block containing `door_open`, `door_seal`, `door_release`, `portal_open`, `portal_enter`.
- New item `content/items/quest/boss_sigil.json` plus a drop entry on each biome's miniboss.
- New scenes `apps/game/client/scenes/dungeon/boss_room_door.tscn` and `exit_portal.tscn`.
- Save format: the run snapshot gains `bossDoorState` (the enum name) so a resumed run restores `SEALED` rather than inferring it from `bossDefeated`. `save_migrator.gd` defaults a missing value to `CLOSED`, or `RELEASED` when `bossDefeated` is true.

## Acceptance criteria

- [ ] On every biome's final floor, the exit portal has a non-null parent under the boss room's `Props` node (BDP-01).
- [ ] Entering the portal area does not complete the run; only a confirmed interact does (BDP-02).
- [ ] `DungeonBuilder` contains no `Area3D.new()` or `StaticBody3D.new()` for the door or the portal (BDP-03).
- [ ] With `bossDoorRequirement = "sigil"` and no sigil held, `interact` does not open the door and the prompt names the requirement (BDP-04).
- [ ] In the sealed state the label is visible and non-empty (BDP-05).
- [ ] `open_exit_portal()` sets `monitoring` only via `ExitPortal.activate()` (BDP-06).
- [ ] A definition with `placements.boss == null` produces no `BossRoomDoor` node (BDP-07).
- [ ] `is_opened()` is false in `CLOSED` and `LOCKED`, true in `OPEN` and `RELEASED`, and false in `SEALED`, and `state` is the only stored field (BDP-08).
- [ ] Opening, sealing, and releasing the door each emit exactly one audio cue (BDP-09).
- [ ] A snapshot taken while sealed restores to `SEALED` (save format).

## Validation

Extend `apps/game/client/scripts/validation/suites/dungeon_suite.gd`, replacing the two existence checks at `:76-99`:

- `test_boss_door_blocks` — build a floor; assert `BarrierShape.disabled == false` and that a physics ray from the approach side to the arena side hits the barrier body.
- `test_boss_door_opens_and_seals` — call `open_door()`, assert the shape is disabled; move a stub player past the depth threshold and step physics, assert `is_sealed()` and that the shape is re-enabled.
- `test_boss_door_release` — emit boss defeat, assert `is_opened()` and the shape is disabled.
- `test_boss_door_requirement` — with `bossDoorRequirement = "sigil"`, simulate an `interact` without the item and assert the state stays `LOCKED`; add the item and assert it becomes `CLOSED` then `OPEN`.
- `test_exit_portal_parented` — for all 10 biomes, build the final floor and assert the portal's parent is the boss room's `Props` node and its global position is inside the room's AABB.
- `test_exit_portal_requires_confirm` — activate the portal, move a stub player in, step physics, assert `RunFlow.complete_run_via_portal` was not called; then confirm and assert it was.
- `test_exit_portal_activate_path` — assert `monitoring` is false until `activate()` is called and that `open_exit_portal()` routes through it.
- `test_no_door_without_boss` — build a definition with a null boss placement, assert `get_boss_door() == null`.

Extend `apps/game/client/scripts/validation/suites/flow_suite.gd`:

- `test_portal_completes_run` — with a confirmed interact, assert `RunFlow` reaches the run-outcome state exactly once even if the player re-enters the area.

Extend `apps/game/client/scripts/validation/suites/m6_suite.gd` (which already loops the biomes at `:383`):

- replace the existence assertion with `test_boss_door_functional_per_biome` — open, seal, and release the door in each of the 10 biomes.

Manual checklist: confirm the authored door reads as a gate under the fixed diorama camera, that the sealed rune state is legible from the arena side, and that the portal's ellipse shader matches [`portal-ellipse-shader.md`](../existing_codebase/portal-ellipse-shader.md).

## Related

- [`../existing_codebase/boss-door-exit-portal.md`](../existing_codebase/boss-door-exit-portal.md)
- [`dungeon-builder.md`](dungeon-builder.md) — DBL-10, DBL-13, DBL-14 are the builder half of this work
- [`room-templates.md`](room-templates.md) — RTP-07 `Props` and `ExitPortalMarker` in every scene
- [`room-content.md`](room-content.md) — RMC-01 keys, which `all_keys` depends on
- [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md) — `bossDoorRequirement` per dungeon
- [`biome-registry.md`](biome-registry.md) — audio cues and material sets
- [`castle-run.md`](castle-run.md) — the lifecycle driver
- [`run-flow.md`](run-flow.md) — `complete_run_via_portal`
- [`bosses.md`](bosses.md) — the sigil drop
- [`ui/run_outcome.md`](ui/run_outcome.md) — the confirmation modal
- [`ui/input_glyphs.md`](ui/input_glyphs.md) — prompt text
- [`audio-director.md`](audio-director.md), [`vfx-service.md`](vfx-service.md) — cues
