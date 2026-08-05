# Diorama room dressing

Three scripts spawn every prop in the game at runtime from `BoxMesh` primitives. `DioramaRoomDressing` dresses dungeon rooms and places their torches; `DioramaInteractableSkin` skins chests, levers, portals, traps, and pickups; `DioramaPropFactory` builds four reference props and is not used by gameplay. There are 90 room scenes — ten biomes × nine template suffixes — and exactly nine dressing recipes between them, so every biome's hall is the same two pillars and the same sconce spacing in a different colour. No prop has collision except the obstacle-course blocks, and three `DioramaInteractableSkin` builders read a property that does not exist on the material they hold.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/diorama_room_dressing.gd` | Per-suffix room dressing, ceiling/wall/room lighting, obstacle course |
| `apps/game/client/scripts/art/props/diorama_interactable_skin.gd` | 13 `build_*` skins for interactables, plus `make_telegraph_material()` |
| `apps/game/client/scripts/art/props/diorama_prop_factory.gd` | `create_prop()` / `create_prop_named()` for crate, pillar, torch, banner |
| `apps/game/client/scripts/art/props/diorama_prop_kit.gd` | `@tool` script that lays the four props out 2.5 m apart for editor reference |
| `apps/game/client/scenes/art/diorama_prop_kit.tscn` | Two-node scene holding that script |

## How it works

### `DioramaRoomDressing.apply_to_room()`

(`:12-53`) Called once per room from `castle_room_scene.gd:23` with `room_id.hash()` as the seed.

1. Bails if `room.get_blockout()` is null.
2. Seeds a `RandomNumberGenerator` from `room_seed` or `room.room_id.hash()`.
3. Bails if a `Props/DioramaDressing` child already exists; otherwise creates it.
4. Resolves `_room_suffix(template_id)` against `ROOM_SUFFIXES` (`:6-9`): `entrance`, `stairs`, `courtyard`, `hall`, `treasure`, `secret`, `arena`, `boss`, `puzzle`.
5. Fetches the biome's floor, wall, and accent materials from `BiomeRegistry`.
6. `room_type == "obstacle"` short-circuits to `_spawn_obstacle_course()` and returns; otherwise a `match` on the suffix dispatches, with an unmatched suffix falling through to `_spawn_generic_corners()`.

The nine recipes:

| Suffix | Contents |
|--------|----------|
| `entrance` (`:192-197`) | Two 2.8 m corner pillars, two braziers, one banner |
| `boss` (`:200-206`) | `BossPlatform` slab `half_w * 1.4` wide, two 3.2 m pillars, two braziers at energy 0.7, one accent fill at y 4.5 |
| `courtyard` (`:209-214`) | Four `_spawn_prop_cluster()` groups, one 2.5 × 2.5 `CenterPlinth` |
| `hall` (`:217-224`) | Wall sconces every 3.5 m down both long walls, two 2.6 m pillars at mid-depth |
| `treasure` (`:227-229`) | One `Pedestal`, one accent fill |
| `secret` (`:232-234`) | One `SecretPanel` box on the left wall, one accent fill |
| `stairs` (`:237-242`) | Skips entirely if a sibling `StairRamp` exists; else a `StairRampAccent` slab and two sconces |
| `arena` (`:245-249`) | `ArenaRing` slab at `half_w * 1.2`, two 2.2 m pillars, one brazier |
| `puzzle` (`:252-257`) | `PuzzleCore` box, four `PuzzleOrb_<i>` boxes on a 2.5 m circle, one brazier |
| (fallback) `_spawn_generic_corners` (`:280-306`) | Two braziers in opposite corners, jittered ±0.8 m by the room RNG |

`_spawn_obstacle_course()` (`:260-277`) is the only recipe that creates collision: six `_add_obstacle_block()` `StaticBody3D` bodies on layer 1 mask 0 — two platforms, a low wall, two dividers, a dash pillar — plus two braziers.

`_spawn_prop_cluster()` (`:384-392`) seeds its own RNG from `hash(biome_id) + rng_seed * 97`, so the four clusters in a biome's courtyard are byte-identical in every run.

### Lighting

`apply_ceiling_lighting(room, biome_id, lighting_role)` (`:76-107`), called from `floor_shell_builder.gd:42`:
- Creates `Props/CeilingLighting`, bailing if it exists.
- `spacing_scale` is 1.35 for `trap`/`hazard`, 0.85 for `boss`, 0.75 for `empty`/`rest`, else 1.0.
- `spacing = clamp(min(width, depth) * 0.52 * scale, 6.0, 8.5)`, then a nested `while` grid spawns a `_spawn_ceiling_torch()` at `y = WALL_HEIGHT - 0.35` (5.65 m; `castle_room_constants.gd:8` sets `WALL_HEIGHT = 6.0`).
- Then `_spawn_wall_midpoint_torches()` (four, one per wall midpoint at half wall height) and `_spawn_room_center_fill()` (one omni at 0.42 × wall height with `ROOM_FILL_ENERGY`).

`apply_arena_ceiling_lighting(parent, half_extent, biome_id)` (`:160-173`), called from `floor_shell_builder.gd:63`, places five ceiling torches: four inset 2.5 m from the corners plus one at the centre.

Every light is created through `VisualLighting.configure_soft_omni()`, which forces `shadow_enabled = false`:

| Spawner | Mesh | Light | Energy / range |
|---------|------|-------|----------------|
| `_spawn_brazier` (`:313-319`) | `Brazier` 0.45×0.7×0.45 in the **accent** material | `BrazierLight` at +1.1 m | caller-supplied (0.4–0.7), range 9.0 |
| `_spawn_wall_sconce` (`:322-325`) | `Sconce` 0.25×0.5×0.35 | none of its own | — |
| `_spawn_wall_torch` (`:328-339`) | `WallTorch` 0.22×0.42×0.28 | `WallTorchLight` at +0.05 m | `WALL_TORCH_ENERGY` 0.78, range 10.0 |
| `_spawn_ceiling_torch` (`:342-353`) | `CeilingTorch` 0.35×0.25×0.35 | `CeilingTorchOmni` at −0.18 m | `TORCH_OMNI_ENERGY` 0.92, range 13.5 |
| `_add_spot` (`:413-423`) | none | `AccentFill` omni | `energy * 0.9`, range 10.0 |

`_spawn_wall_sconce()` adds its `Sconce` box and then calls `_spawn_wall_torch()` at the **same position** whenever `biome_id != ""`, so a hall wall carries two interpenetrating boxes per sconce.

`_biome_light_color()` (`:440-442`) returns the biome's `ambient_color` from `BiomeRegistry.get_lighting_profile()`, so torch light is exactly the ambient hue. `_material_light_color()` (`:426-437`) probes a `ShaderMaterial` for `color_accent`, `color_base`, then `base_color`, falls back to a `StandardMaterial3D` albedo, then the biome colour, then `Color(0.9, 0.75, 0.5)`.

### `DioramaInteractableSkin`

`VISUAL_NAME = "DioramaVisual"`. `resolve_biome(node, fallback)` (`:20-29`) checks a `biome_id` meta, then the `waves_run` group, then `RunFlow.current_biome_id`, then the fallback.

`_make_root()` adds a `DioramaVisual` child; `_remove_visual()` frees any existing one plus any direct child literally named `MeshInstance3D`. `_add_box()` forwards to `PixelStyle.add_box()`. `_add_orb()` (`:212-222`) builds a `SphereMesh` with `PixelStyle.make_material(color, color)`.

| Builder | Contents | Callers |
|---------|----------|---------|
| `build_chest` (`:32-46`) | 4 boxes + emissive orb | `loot_chest.gd:19`, `room_lore_content.gd:27` |
| `build_waves_chest` (`:49-51`) | `build_chest` with a rarity glow from `WAVES_RARITY_GLOW` (6 colours) | `waves_chest.gd:16` |
| `build_lever` (`:54-64`) | 3 boxes + orb | `stair_lever.gd:20`, `dungeon_builder.gd:641` |
| `build_portal` (`:67-83`) | 2 pillars, lintel, pad, orb, glow slab, 2 accent strips | `dungeon_builder.gd:595` via `build_exit_portal`, `room_merchant_content.gd:27` |
| `build_exit_portal` (`:86-89`) | `build_portal` at 0.85 scale | `dungeon_builder.gd:595` |
| `build_loot_pickup` (`:92-103`) | 2 boxes + orb, `bob_base_y` meta | `xp_shard_pickup.gd:21`, `world_item_pickup.gd:17` |
| `build_cannon` (`:106-119`) | 3 boxes + 3 crystal orbs | `final_boss_cannon.gd:22` |
| `build_boss_door_frame` (`:122-133`) | 4 boxes, root renamed `DoorFrameVisual` | `dungeon_builder.gd:750` |
| `build_spikes` (`:136-148`) | Base slab + 4×4 spike grid | `spike_trap.gd:30` |
| `build_falling_block` (`:151-159`) | 2 boxes | `falling_trap.gd:29` |
| `build_poison_pool` (`:162-175`) | Rim, pool slab on a pulsing glow material, 4 corner posts | `poison_hazard.gd:17` |
| `build_crystal_pillar` (`:178-185`) | 2 emissive boxes | `final_boss_crystal.gd:17`, `crystal_pillar_hazard.gd:22` |
| `make_telegraph_material` (`:188-189`) | `PixelStyle.make_material(color, color * 0.5)` | 6 trap/hazard/content call sites |

### `DioramaPropFactory` and the prop kit

`create_prop(kind, biome_id)` (`:9-21`) maps the `PropKind` enum to `_make_crate` (3 boxes), `_make_pillar` (3 boxes), `_make_torch` (3 boxes plus a 0.55-energy `OmniLight3D` at range 4.5), `_make_banner` (3 boxes). `create_prop_named()` (`:24-36`) is the string front door and warns on an unknown name.

The only caller of either is `diorama_prop_kit.gd:23`, whose only host is `diorama_prop_kit.tscn`. No scene, script, or `.tscn` in the repo instances `diorama_prop_kit.tscn`, so the whole three-file chain is editor-reference material.

## Contracts

- `Props` is created on demand under a `RoomTemplate` and holds the `DioramaDressing` and `CeilingLighting` subtrees; both are guarded by node-existence checks so the passes are idempotent.
- `DioramaInteractableSkin.VISUAL_NAME = "DioramaVisual"` is on `hide_legacy_meshes()`'s skip list (`pixel_diorama_style.gd:972`), which is how a skinned interactable keeps its new geometry.
- `_remove_visual()` frees direct children named exactly `MeshInstance3D`, which is the implicit contract with the blockout `.tscn` files.
- `_add_obstacle_block()` uses collision layer 1, mask 0.
- `apply_to_room()` requires `room.get_blockout()`, `blockout.room_width`, `blockout.room_depth`, `room.room_id`, `room.template_id`, `room.room_type`.
- `DioramaRoomDressing._add_box(parent, pos, size, mat, name)` takes position before size; `PixelDioramaStyle.add_box(parent, size, position, material, name)` takes size before position.
- `build_loot_pickup()` sets a `bob_base_y` meta consumed by the pickup scripts.
- `WAVES_RARITY_GLOW` has six entries and is indexed by a clamped rarity.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Nine per-suffix dressing recipes dispatched by template id | IMPLEMENTED | `diorama_room_dressing.gd:33-53`, `:192-257` |
| Ceiling torch grid with role-based spacing, wall torches, room fill | IMPLEMENTED | `:76-135` |
| 13 interactable skins, all wired to live callers | IMPLEMENTED | callers table above |
| `build_portal`, `build_loot_pickup`, `build_cannon` read `glow.emission` | BROKEN | `diorama_interactable_skin.gd:79`, `:101`, `:118`. `glow` is the value of `PixelStyle.make_emissive_material()`, declared `-> Material` (`pixel_diorama_style.gd:374`) and actually a `ShaderMaterial` on `pixel_diorama_emissive.gdshader`. Neither type declares an `emission` property; the shader's uniforms are `color_core`, `color_edge`, `emission_energy`. Reachable from `dungeon_builder.gd:595`, `xp_shard_pickup.gd:21`, `world_item_pickup.gd:17`, `final_boss_cannon.gd:22` |
| 90 room scenes share 9 dressing recipes | PLACEHOLDER | 90 files under `apps/game/client/scenes/rooms/` (10 biomes × 9 suffixes); one `match` arm each in `:33-53` |
| Dressing is deterministic and identical across runs | PLACEHOLDER | `prop_rng` (`:16-17`) is passed only to `_spawn_generic_corners` (`:53`); `_spawn_prop_cluster` reseeds from `hash(biome_id)` (`:386`) |
| Every prop is a `BoxMesh`; no authored prop art exists | PLACEHOLDER | `_add_box` (`:400-410`); no mesh or texture assets in `apps/game/client/assets/` |
| Props have no collision except obstacle blocks | PARTIAL | `_add_obstacle_block` (`:356-381`) is the only `StaticBody3D`; pillars, braziers, banners, plinths, pedestals are walk-through |
| Torch and brazier geometry is not emissive | PARTIAL | `_spawn_brazier` (`:314`), `_spawn_wall_torch` (`:329`), `_spawn_ceiling_torch` (`:343`) all use the biome accent surface material, so the fixture itself does not glow |
| Torch light colour equals the biome ambient colour | PARTIAL | `_biome_light_color` (`:440-442`) returns `get_lighting_profile().ambient_color` |
| Sconces spawn two overlapping boxes | BROKEN | `_spawn_wall_sconce` (`:322-325`) adds `Sconce` then calls `_spawn_wall_torch` at the identical `pos` |
| Light count per room is high and entirely shadowless | PARTIAL | a 20 × 20 room yields roughly 9 ceiling torches + 4 wall torches + 1 fill from `:98-107`, plus recipe braziers, all through `configure_soft_omni` (`visual_lighting.gd:138`) |
| `_add_spot()` creates an `OmniLight3D` named `AccentFill` | PARTIAL | `:413-423` — the name says spot, the node is an omni |
| `apply_to_waves_arena()` | STUB | defined `:56-74`; no caller |
| `apply_shell_lighting()` | STUB | defined `:138-157`; no caller. It is the only reader of `VisualLighting.SHELL_TORCH_SPACING`, and `SHELL_TORCH_ENERGY` has no reader at all |
| `DioramaPropFactory`, `diorama_prop_kit.gd`, `diorama_prop_kit.tscn` | STUB | `create_prop` called only from `diorama_prop_kit.gd:23`; nothing instances `diorama_prop_kit.tscn` |
| `_add_box` duplicates `PixelDioramaStyle.add_box` with the arguments swapped | PARTIAL | `diorama_room_dressing.gd:400-410` vs `pixel_diorama_style.gd:422-443` |
| `_material_light_color()` probes a `base_color` parameter that no shader declares | PARTIAL | `:429`; the surface shader declares `color_base` (`pixel_diorama_surface.gdshader:10`) |
| No audio or VFX from dressing | ABSENT | no `AudioDirector` or `VfxService` reference in `diorama_room_dressing.gd` |
| Validation coverage | PARTIAL | `m7_suite.gd:315-321` asserts `biome_registry.gd` contains the string `uses_indoor_lighting`; no suite exercises `apply_to_room`, the recipes, the prop factory, or the skins |

## Related
- Improvement plan: [`../actual_improvements/diorama-room-dressing.md`](../actual_improvements/diorama-room-dressing.md)
- [`pixel-style.md`](pixel-style.md) — `add_box`, the palette, and the materials every prop uses
- [`character-authoring.md`](character-authoring.md) — the same `BoxMesh` assembly problem applied to characters
- [`visual-lighting.md`](visual-lighting.md) — `configure_soft_omni`, the torch constants, and the shadowless policy
- [`biome-registry.md`](biome-registry.md) — supplies the three materials and the light colour
- [`room-templates.md`](room-templates.md), [`room-content.md`](room-content.md) — the 90 room scenes and their content passes
- [`floor-shell.md`](floor-shell.md) — calls both lighting entry points
- [`dungeon-builder.md`](dungeon-builder.md) — the largest `DioramaInteractableSkin` consumer
- [`portal-ellipse-shader.md`](portal-ellipse-shader.md) — the portal shader `build_portal` does not use
- [`dungeon-traps.md`](dungeon-traps.md), [`loot-and-equipment.md`](loot-and-equipment.md) — trap and pickup skin consumers
- [`00-PLACEHOLDER-INVENTORY.md`](00-PLACEHOLDER-INVENTORY.md)
