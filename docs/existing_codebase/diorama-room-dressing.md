# Diorama room dressing

Three scripts spawn every prop in the game at runtime from `BoxMesh` primitives. `DioramaRoomDressing` dresses dungeon rooms and places their torches; `DioramaInteractableSkin` skins chests, levers, portals, traps, pickups, and room-content props; `DioramaPropFactory` builds four reference props and is not used by gameplay. There are 110 room scenes â€” ten biomes Ã— eleven template suffixes â€” and exactly nine dressing recipes between them (a tenth `corridor` suffix and any unknown suffix fall through to `_spawn_generic_corners()`), so every biome's hall is the same two pillars and the same sconce spacing in a different colour. No decorative prop has collision except the obstacle-course blocks, and three `DioramaInteractableSkin` builders read a property that does not exist on the material they hold.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/diorama_room_dressing.gd` | Per-suffix room dressing, ceiling/wall/room lighting, obstacle course |
| `apps/game/client/scripts/art/props/diorama_interactable_skin.gd` | 15 `build_*` skins for interactables and room content, plus `make_telegraph_material()` |
| `apps/game/client/scripts/art/props/diorama_prop_factory.gd` | `create_prop()` / `create_prop_named()` for crate, pillar, torch, banner |
| `apps/game/client/scripts/art/props/diorama_prop_kit.gd` | `@tool` script that lays the four props out 2.5 m apart for editor reference |
| `apps/game/client/scenes/art/diorama_prop_kit.tscn` | Two-node scene holding that script |

## How it works

### `DioramaRoomDressing.apply_to_room()`

(`:19-60`) Called once per room from `castle_room_scene.gd:33` with `room_id.hash()` as the seed.

1. Bails if `room.get_blockout()` is null.
2. Seeds a `RandomNumberGenerator` from `room_seed` or `room.room_id.hash()`.
3. Bails if a `Props/DioramaDressing` child already exists; otherwise creates it.
4. Resolves `_room_suffix(template_id)` against `ROOM_SUFFIXES` (`:6-16`): `entrance`, `stairs`, `courtyard`, `hall`, `treasure`, `secret`, `arena`, `boss`, `puzzle`. Templates ending in `_corridor` (and any other unmatched suffix) do not match and fall through to `_spawn_generic_corners()`.
5. Fetches the biome's floor, wall, and accent materials from `BiomeRegistry`.
6. `room_type == "obstacle"` short-circuits to `_spawn_obstacle_course()` and returns; otherwise a `match` on the suffix dispatches, with an unmatched suffix falling through to `_spawn_generic_corners()`.

The nine recipes:

| Suffix | Contents |
|--------|----------|
| `entrance` (`:213-225`) | Two 2.8 m corner pillars, two braziers, one banner |
| `boss` (`:228-247`) | `BossPlatform` slab `half_w * 1.4` wide, two 3.2 m pillars, two braziers at energy 0.7, one accent fill at y 4.5 |
| `courtyard` (`:250-270`) | Four `_spawn_prop_cluster()` groups, one 2.5 Ã— 2.5 `CenterPlinth` |
| `hall` (`:273-287`) | Wall sconces every 3.5 m down both long walls, two 2.6 m pillars at mid-depth |
| `treasure` (`:290-292`) | One `Pedestal`, one accent fill |
| `secret` (`:295-301`) | One `SecretPanel` box on the left wall, one accent fill |
| `stairs` (`:304-317`) | Skips entirely if a sibling `StairRamp` exists; else a `StairRampAccent` slab and two sconces |
| `arena` (`:320-337`) | `ArenaRing` slab at `half_w * 1.2`, two 2.2 m pillars, one brazier |
| `puzzle` (`:340-351`) | `PuzzleCore` box, four `PuzzleOrb_<i>` boxes on a 2.5 m circle, one brazier |
| (fallback) `_spawn_generic_corners` (`:402-428`) | Two braziers in opposite corners, jittered Â±0.8 m by the room RNG â€” also used for `corridor` templates |

`_spawn_obstacle_course()` (`:354-399`) is the only recipe that creates collision: six `_add_obstacle_block()` `StaticBody3D` bodies on layer 1 mask 0 â€” two platforms, a low wall, two dividers, a dash pillar â€” plus two braziers.

`_spawn_prop_cluster()` (`:519-538`) seeds its own RNG from `hash(biome_id) + rng_seed * 97`, so the four clusters in a biome's courtyard are byte-identical in every run.

### Lighting

`apply_ceiling_lighting(room, biome_id, lighting_role)` (`:85-120`), called from `floor_shell_builder.gd:29`:
- Creates `Props/CeilingLighting`, bailing if it exists.
- `spacing_scale` is 1.35 for `trap`/`hazard`, 0.85 for `boss`, 0.75 for `empty`/`rest`, else 1.0.
- `spacing = clamp(min(width, depth) * 0.52 * scale, 6.0, 8.5)`, then a nested `while` grid spawns a `_spawn_ceiling_torch()` at `y = WALL_HEIGHT - 0.35` (5.65 m; `castle_room_constants.gd:8` sets `WALL_HEIGHT = 6.0`).
- Then `_spawn_wall_midpoint_torches()` (four, one per wall midpoint at half wall height) and `_spawn_room_center_fill()` (one omni at 0.42 Ã— wall height with `ROOM_FILL_ENERGY`).

`apply_arena_ceiling_lighting(parent, half_extent, biome_id)` (`:171-194`), called from `floor_shell_builder.gd:50`, places five ceiling torches: four inset 2.5 m from the corners plus one at the centre.

Every light is created through `VisualLighting.configure_soft_omni()`, which forces `shadow_enabled = false` (`visual_lighting.gd:140-147`):

| Spawner | Mesh | Light | Energy / range |
|---------|------|-------|----------------|
| `_spawn_brazier` (`:439-452`) | `BrazierMesh` 0.45Ã—0.7Ã—0.45 in the **accent** material | `BrazierLight` at +1.1 m | caller-supplied (0.4â€“0.7), range 9.0 |
| `_spawn_wall_sconce` (`:455-460`) | `Sconce` 0.25Ã—0.5Ã—0.35 | none of its own | â€” |
| `_spawn_wall_torch` (`:463-476`) | `WallTorch` 0.22Ã—0.42Ã—0.28 | `WallTorchLight` at +0.05 m | `WALL_TORCH_ENERGY` 0.78, range 10.0 |
| `_spawn_ceiling_torch` (`:479-492`) | `CeilingTorch` 0.35Ã—0.25Ã—0.35 | `CeilingTorchOmni` at âˆ’0.18 m | `TORCH_OMNI_ENERGY` 0.92, range 13.5 |
| `_add_spot` (`:575-584`) | none | `AccentFill` omni | `energy * 0.9`, range 10.0 |

`_spawn_wall_sconce()` adds its `Sconce` box and then calls `_spawn_wall_torch()` at the **same position** whenever `biome_id != ""`, so a hall wall carries two interpenetrating boxes per sconce.

`_biome_light_color()` (`:601-603`) returns the biome's `ambient_color` from `BiomeRegistry.get_lighting_profile()`, so torch light is exactly the ambient hue. `_material_light_color()` (`:587-598`) probes a `ShaderMaterial` for `color_accent`, `color_base`, then `base_color`, falls back to a `StandardMaterial3D` albedo, then the biome colour, then `Color(0.9, 0.75, 0.5)`.

### `DioramaInteractableSkin`

`VISUAL_NAME = "DioramaVisual"`. `resolve_biome(node, fallback)` (`:20-29`) checks a `biome_id` meta, then the `waves_run` group, then `RunFlow.current_biome_id`, then the fallback.

`_make_root()` adds a `DioramaVisual` child; `_remove_visual()` frees any existing one plus any direct child literally named `MeshInstance3D`. `_add_box()` forwards to `PixelStyle.add_box()`. `_add_orb()` (`:265-277`) builds a `SphereMesh` with `PixelStyle.make_material(color, color)`.

| Builder | Contents | Callers |
|---------|----------|---------|
| `build_chest` (`:32-48`) | 4 boxes + emissive orb | `loot_chest.gd:19` |
| `build_waves_chest` (`:51-53`) | `build_chest` with a rarity glow from `WAVES_RARITY_GLOW` (6 colours) | `waves_chest.gd:16` |
| `build_lever` (`:56-71`) | 3 boxes + orb | `stair_lever.gd:35`, `room_puzzle_content.gd:23` |
| `build_bonfire` (`:74-84`) | 2 boxes + 2 orbs | `room_rest_content.gd:19` |
| `build_lectern` (`:87-96`) | 3 boxes | `room_lore_content.gd:27` |
| `build_npc` (`:99-108`) | 2 boxes + accent orb | `room_npc_quest_content.gd:16` |
| `build_portal` (`:111-127`) | 2 pillars, lintel, pad, orb, glow slab, 2 accent strips | `room_merchant_content.gd:27` |
| `build_exit_portal` (`:130-133`) | `build_portal` at 0.85 scale | `exit_portal.gd:30` |
| `build_loot_pickup` (`:136-147`) | 2 boxes + orb, `bob_base_y` meta | `xp_shard_pickup.gd:21`, `world_item_pickup.gd:17` |
| `build_cannon` (`:150-163`) | 3 boxes + 3 crystal orbs | `final_boss_cannon.gd:22` |
| `build_boss_door_frame` (`:166-177`) | 4 boxes, root renamed `DoorFrameVisual` | `boss_room_door.gd:49` |
| `build_spikes` (`:180-192`) | Base slab + 4Ã—4 spike grid | `spike_trap.gd:27` |
| `build_falling_block` (`:195-203`) | 2 boxes | `falling_trap.gd:29` |
| `build_poison_pool` (`:206-224`) | Rim, pool slab on a pulsing glow material, 4 corner posts | `poison_hazard.gd:19` |
| `build_crystal_pillar` (`:227-236`) | 2 emissive boxes | `final_boss_crystal.gd:17`, `crystal_pillar_hazard.gd:22` |
| `make_telegraph_material` (`:239-240`) | `PixelStyle.make_material(color, color * 0.5)` | 6 trap/hazard/content call sites |

`build_portal`, `build_loot_pickup`, and `build_cannon` pass `glow.emission` or `crystal.emission` to `_add_orb()` (`:123`, `:145`, `:162`). `glow` / `crystal` are `ShaderMaterial` values from `PixelStyle.make_emissive_material()` (`pixel_diorama_style.gd:394-402`), which has no `emission` property; the shader uniforms are `color_core`, `color_edge`, and `emission_energy` (`pixel_diorama_emissive.gdshader:9-13`).

### `DioramaPropFactory` and the prop kit

`create_prop(kind, biome_id)` (`:9-21`) maps the `PropKind` enum to `_make_crate` (3 boxes), `_make_pillar` (3 boxes), `_make_torch` (3 boxes plus a 0.55-energy `OmniLight3D` at range 4.5 using the palette `EMISSIVE` slot), `_make_banner` (3 boxes). `create_prop_named()` (`:24-38`) is the string front door and warns on an unknown name.

The only caller of either is `diorama_prop_kit.gd:23`, whose only host is `diorama_prop_kit.tscn`. No scene, script, or `.tscn` in the repo instances `diorama_prop_kit.tscn`, so the whole three-file chain is editor-reference material.

## Contracts

- `Props` is created on demand under a `RoomTemplate` and holds the `DioramaDressing` and `CeilingLighting` subtrees; both are guarded by node-existence checks so the passes are idempotent.
- `DioramaInteractableSkin.VISUAL_NAME = "DioramaVisual"` is on `hide_legacy_meshes()`'s skip list (`pixel_diorama_style.gd:1027`), which is how a skinned interactable keeps its new geometry.
- `_remove_visual()` frees direct children named exactly `MeshInstance3D`, which is the implicit contract with the blockout `.tscn` files.
- `_add_obstacle_block()` uses collision layer 1, mask 0.
- `apply_to_room()` requires `room.get_blockout()`, `blockout.room_width`, `blockout.room_depth`, `room.room_id`, `room.template_id`, `room.room_type`.
- `DioramaRoomDressing._add_box(parent, pos, size, ...)` takes position before size; `PixelDioramaStyle.add_box(parent, size, position, material, name)` takes size before position.
- `build_loot_pickup()` sets a `bob_base_y` meta consumed by the pickup scripts.
- `WAVES_RARITY_GLOW` has six entries and is indexed by a clamped rarity.
- `_spawn_brazier()` attaches `AudioDirector.attach_loop_emitter(brazier, "brazier", 6.0)` (`:452`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Nine per-suffix dressing recipes dispatched by template id | IMPLEMENTED | `diorama_room_dressing.gd:40-60`, `:213-351` |
| `corridor` and unknown suffixes use generic-corner fallback only | PLACEHOLDER | `ROOM_SUFFIXES` (`:6-16`) omits `corridor`; `_spawn_generic_corners` (`:402-428`) |
| Ceiling torch grid with role-based spacing, wall torches, room fill | IMPLEMENTED | `:85-146` |
| Arena ceiling lighting (five torches) | IMPLEMENTED | `apply_arena_ceiling_lighting` (`:171-194`); caller `floor_shell_builder.gd:50` |
| 15 interactable skins + `make_telegraph_material`, all wired to live callers | IMPLEMENTED | callers table above |
| `build_portal`, `build_loot_pickup`, `build_cannon` read `glow.emission` / `crystal.emission` | BROKEN | `diorama_interactable_skin.gd:123`, `:145`, `:162`; `make_emissive_material` (`pixel_diorama_style.gd:394-402`) returns `ShaderMaterial` with no `emission` member |
| 110 room scenes share 9 dressing recipes (+ generic fallback) | PLACEHOLDER | 110 files under `apps/game/client/scenes/rooms/` (10 biomes Ã— 11 suffixes); one `match` arm each in `:40-60` |
| Dressing is deterministic and identical across runs | PLACEHOLDER | `prop_rng` (`:23-24`) is passed only to `_spawn_generic_corners` (`:60`); `_spawn_prop_cluster` reseeds from `hash(biome_id)` (`:528`) |
| Every prop is a `BoxMesh`; no authored prop art exists | PLACEHOLDER | `_add_box` (`:560-572`); no mesh or texture assets in `apps/game/client/assets/` for room props |
| Props have no collision except obstacle blocks | PARTIAL | `_add_obstacle_block` (`:495-516`) is the only `StaticBody3D`; pillars, braziers, banners, plinths, pedestals are walk-through |
| Torch and brazier geometry is not emissive | PARTIAL | `_spawn_brazier` (`:446`), `_spawn_wall_torch` (`:466`), `_spawn_ceiling_torch` (`:482`) all use the biome accent surface material |
| Torch light colour equals the biome ambient colour | PARTIAL | `_biome_light_color` (`:601-603`) returns `get_lighting_profile().ambient_color` |
| Sconces spawn two overlapping boxes | BROKEN | `_spawn_wall_sconce` (`:455-460`) adds `Sconce` then calls `_spawn_wall_torch` at the identical `pos` |
| Light count per room is high and entirely shadowless | PARTIAL | a 20 Ã— 20 room yields roughly 9 ceiling torches + 4 wall torches + 1 fill from `:112-120`, plus recipe braziers, all through `configure_soft_omni` (`visual_lighting.gd:147`) |
| Brazier loop audio on spawn | IMPLEMENTED | `AudioDirector.attach_loop_emitter` (`diorama_room_dressing.gd:452`); key `"brazier"` exercised in `audio_suite.gd:463` |
| `_add_spot()` creates an `OmniLight3D` named `AccentFill` | PARTIAL | `:575-584` â€” the name says spot, the node is an omni |
| `apply_to_waves_arena()` | STUB | defined `:63-82`; no caller |
| `apply_shell_lighting()` | STUB | defined `:149-168`; no caller. It is the only reader of `VisualLighting.SHELL_TORCH_SPACING`, and `SHELL_TORCH_ENERGY` has no reader at all (`visual_lighting.gd:19-20`) |
| `DioramaPropFactory`, `diorama_prop_kit.gd`, `diorama_prop_kit.tscn` | STUB | `create_prop` called only from `diorama_prop_kit.gd:23`; nothing instances `diorama_prop_kit.tscn` |
| `_add_box` duplicates `PixelDioramaStyle.add_box` with the arguments swapped | PARTIAL | `diorama_room_dressing.gd:560-572` vs `pixel_diorama_style.gd:442-454` |
| `_material_light_color()` probes a `base_color` parameter that no shader declares | PARTIAL | `:590`; the surface shader declares `color_base` (`pixel_diorama_surface.gdshader:10`) |
| No ambient VFX from dressing | ABSENT | no `VfxService` reference in `diorama_room_dressing.gd` |
| Validation coverage for dressing | PARTIAL | `m7_suite.gd:340-357` greps `floor_shell_builder.gd` and `biome_registry.gd` for indoor lighting strings; no suite exercises `apply_to_room`, the recipes, the prop factory, or the skins |

## Related
- Improvement plan: [`../actual_improvements/diorama-room-dressing.md`](../actual_improvements/diorama-room-dressing.md) - **FINISHED**
- [`pixel-style.md`](pixel-style.md) â€” `add_box`, the palette, and the materials every prop uses
- [`character-authoring.md`](character-authoring.md) â€” the same `BoxMesh` assembly problem applied to characters
- [`visual-lighting.md`](visual-lighting.md) â€” `configure_soft_omni`, the torch constants, and the shadowless policy
- [`biome-registry.md`](biome-registry.md) â€” supplies the three materials and the light colour
- [`room-templates.md`](room-templates.md), [`room-content.md`](room-content.md) â€” the 110 room scenes and their content passes
- [`floor-shell.md`](floor-shell.md) â€” calls both lighting entry points
- [`dungeon-builder.md`](dungeon-builder.md) â€” room assembly; exit portal skin is on `exit_portal.gd`
- [`portal-ellipse-shader.md`](portal-ellipse-shader.md) â€” the portal shader `build_portal` does not use
- [`dungeon-traps.md`](dungeon-traps.md), [`loot-and-equipment.md`](loot-and-equipment.md) â€” trap and pickup skin consumers
- [`audio-director.md`](audio-director.md) â€” brazier loop emitter
- [`00-PLACEHOLDER-INVENTORY.md`](00-PLACEHOLDER-INVENTORY.md)
