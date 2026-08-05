# Character floor snap

`CharacterFloorSnap` is a three-function static helper that places a `CharacterBody3D` so its collision-shape bottom sits on a given floor height, and offsets a diorama rig so its feet land on the same plane. It is on the live play path: every enemy, boss, and player spawn in the castle run, waves run, and procedural dungeons goes through it.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/characters/character_floor_snap.gd` | `class_name CharacterFloorSnap extends RefCounted`, all `static` |

Callers:

| Caller | Line | Call |
|--------|------|------|
| `apps/game/client/scripts/dungeon/dungeon_builder.gd` | `:443` | `snap_feet_to_floor(_player)` at the entrance spawn |
| `apps/game/client/scripts/dungeon/dungeon_builder.gd` | `:471` | `snap_feet_to_floor(enemy)` before `room.add_child(enemy)` |
| `apps/game/client/scripts/dungeon/dungeon_builder.gd` | `:558` | `snap_feet_to_floor(_boss)` |
| `apps/game/client/scripts/dungeon/castle_run.gd` | `:345` | `snap_feet_to_floor(_player, floor_y)` with a raycast result |
| `apps/game/client/scripts/dungeon/castle_run.gd` | `:354`, `:381`, `:388` | `snap_feet_to_floor(_player)` on load and on room teleport |
| `apps/game/client/scripts/dungeon/waves_run.gd` | `:195` | `snap_feet_to_floor(enemy)` |
| `apps/game/client/scripts/enemies/castle_enemy_base.gd` | `:113` | `align_diorama_visual(self, _diorama_visual, _anim_profile)` |

## How it works

`collision_bottom_local(body)` (`:7`) reads the child node named exactly `CollisionShape3D`, starts from `collision.position.y`, and subtracts half the height for a `CapsuleShape3D`, `BoxShape3D`, or `CylinderShape3D`. Any other shape type, a missing node, or a null shape returns `0.0`.

`snap_feet_to_floor(body, floor_y = 0.0)` (`:21`) writes `body.position.y = floor_y - collision_bottom_local(body)`. It writes `position`, not `global_position`, so `floor_y` is expressed in the parent's local space. That is why the default of `0.0` is correct for `dungeon_builder.gd:471`, where enemies are children of a room node whose own transform carries the world floor height.

`align_diorama_visual(body, visual, profile)` (`:26`) writes `visual.position.y = -body.position.y - DioramaCharacterSkin.feet_local_y(profile)`. `feet_local_y` ignores its argument and always returns `0.0` (`diorama_character_skin.gd:195-196`), so in practice this is `visual.position.y = -body.position.y`.

## The two body conventions

The helper exists because the player and the enemies use opposite collision conventions.

| | Player | Enemies |
|---|--------|---------|
| `CollisionShape3D` offset | `y = 0.8` (`player.tscn:43`) | none, shape centred on the origin (for example `castle_knight.tscn:42-43`) |
| Capsule height | `1.6` (`player.tscn:24`) | `2.4` for the knight (`castle_knight.tscn:11`) |
| `collision_bottom_local` | `0.8 - 0.8 = 0.0` | `0.0 - 1.2 = -1.2` |
| `snap_feet_to_floor` result on a floor at 0 | `position.y = 0.0` | `position.y = 1.2` |
| Rig placement | rig is a child of `Facing` at the body origin, which is already at the feet; `align_diorama_visual` is never called on the player | body origin floats 1.2 m up, so `align_diorama_visual` pushes `DioramaVisual` down by 1.2 m to reach the floor |

The rig itself always has its feet at its own origin — the legs are built as pivots at `y = leg.y` with their meshes offset downward by half the leg height (`diorama_character_skin.gd:379-382`), which is what makes `feet_local_y() == 0.0` true for every profile.

## Contracts

- The body must have a direct child named exactly `CollisionShape3D`. `player.tscn:42` and every enemy scene satisfy this; a body whose shape is nested deeper silently gets `0.0`.
- Only `CapsuleShape3D`, `BoxShape3D`, and `CylinderShape3D` are understood.
- `snap_feet_to_floor` must be called before or during the frame the body is parented, and it overwrites `position.y` — any caller that wants a specific spawn height must pass it as `floor_y`.
- `align_diorama_visual` assumes the visual is a direct child of the body (or of a zero-offset child of it) and that the body's `position.y` equals its height above the target floor.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Collision-bottom computation for the three supported shapes | IMPLEMENTED | `character_floor_snap.gd:7-18` |
| Feet snap for player, enemies, and bosses | IMPLEMENTED | `character_floor_snap.gd:21-23` plus the eight call sites above |
| Rig alignment for enemies | IMPLEMENTED | `character_floor_snap.gd:26-30`, `castle_enemy_base.gd:113` |
| `feet_local_y(profile)` | FAKE | Takes a profile and always returns `0.0`; the parameter is named `_profile` and unused (`diorama_character_skin.gd:195-196`). Callers appear to be profile-aware but are not |
| Floor detection | ABSENT from this file | Only `castle_run.gd:343` supplies a real raycast height (`_raycast_floor_y`); the other seven call sites rely on the parent transform and the `0.0` default. There is no raycast, no `PhysicsDirectSpaceState3D` query, and no fallback in `character_floor_snap.gd` |
| Slope alignment | ABSENT | Only `position.y` is written; nothing reads the floor normal or rotates the rig |
| Continuous foot snapping | ABSENT | One-shot only. Nothing calls it per frame, so a body that ends a physics step slightly above or below the floor stays there until the next spawn or teleport |
| Rig alignment for the player | Not applicable by design | The player's collision offset already puts the origin at the feet; `align_diorama_visual` is never called with the player (grep of the eight call sites) |
| Non-capsule enemy bodies | Untested | No enemy scene uses `CylinderShape3D`; the branch at `:16-17` has no exercised call path |
| Validation coverage | ABSENT | No suite under `apps/game/client/scripts/validation/suites/` references `CharacterFloorSnap` or `feet_local_y` |

## Related
- Improvement plan: [`../actual_improvements/character-floor-snap.md`](../actual_improvements/character-floor-snap.md)
- [`diorama-character-skin.md`](diorama-character-skin.md), [`locomotion.md`](locomotion.md), [`player-combat.md`](player-combat.md)
- [`dungeon-builder.md`](dungeon-builder.md), [`castle-run.md`](castle-run.md), [`waves-run.md`](waves-run.md), [`enemies.md`](enemies.md), [`floor-shell.md`](floor-shell.md)
