# Diorama room dressing — improvement plan

## Current state

Every prop in the game is a `BoxMesh` created at runtime by one of nine hard-coded GDScript recipes. Ten biomes × nine room suffixes gives 90 room scenes and they share those nine recipes, so a Frozen Reaches hall and a Cathedral hall are the same two pillars at the same coordinates in a different hue. The dressing is fully deterministic, so the same room looks identical in every run of every profile. No prop collides except the obstacle-course blocks. Torch fixtures use the biome accent surface material rather than an emissive, so they do not glow. Three interactable builders read a property that does not exist on the material they are holding. See [`../existing_codebase/diorama-room-dressing.md`](../existing_codebase/diorama-room-dressing.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| DRD-01 | P0 | `build_portal`, `build_loot_pickup`, and `build_cannon` pass `glow.emission` to `_add_orb()`, but `glow` holds the `ShaderMaterial` returned by `PixelStyle.make_emissive_material()` (declared `-> Material`). Neither `Material` nor `ShaderMaterial` has an `emission` property; the emissive shader's uniforms are `color_core`, `color_edge`, and `emission_energy`. All three are reachable from live gameplay: exit portals, XP shards, world item pickups, and the final boss cannon. | `diorama_interactable_skin.gd:79`, `:101`, `:118`; `pixel_diorama_style.gd:374-382`; `pixel_diorama_emissive.gdshader`; callers `dungeon_builder.gd:595`, `xp_shard_pickup.gd:21`, `world_item_pickup.gd:17`, `final_boss_cannon.gd:22` |
| DRD-02 | P0 | Nine recipes dress 90 rooms. Every biome's `hall` is two 2.6 m pillars and sconces every 3.5 m; every `puzzle` is one core box and four orbs at 2.5 m on a circle. Biome identity is carried entirely by three material colours, so a run through ten biomes visits the same nine rooms ten times. | `diorama_room_dressing.gd:33-53`, `:192-257`; 90 files under `apps/game/client/scenes/rooms/` |
| DRD-03 | P0 | Dressing has no run-to-run variation. `prop_rng` is seeded from the room id and then passed only to `_spawn_generic_corners`; `_spawn_prop_cluster` discards it and reseeds from `hash(biome_id)`. Every other recipe is a fixed list of coordinates. The same room in the same biome is byte-identical forever. | `diorama_room_dressing.gd:16-17`, `:53`, `:386` |
| DRD-04 | P1 | No authored prop art of any kind. `DioramaPropFactory` builds four props from three boxes each and is dead code; the live recipes build theirs inline from `_add_box`. There is no prop catalogue, no data, and no asset. | `diorama_prop_factory.gd:53-147`; only caller `diorama_prop_kit.gd:23`, whose scene nothing instances; `_add_box` at `diorama_room_dressing.gd:400-410` |
| DRD-05 | P1 | Props do not collide. `_add_obstacle_block()` is the only `StaticBody3D` in the file, so the player walks through pillars, braziers, pedestals, plinths, banners, and puzzle orbs. A room's geometry reads as solid and is not. | `diorama_room_dressing.gd:356-381`; every other spawner calls `_add_box` (`:400-410`), a bare `MeshInstance3D` |
| DRD-06 | P1 | Light fixtures do not emit light-coloured pixels. Braziers, wall torches, and ceiling torches use the biome **accent surface** material, so the fixture is a matte box with an invisible omni floating near it. Combined with `_biome_light_color()` returning the biome's ambient colour, a lit room has no visible light source and no colour contrast between fill and torch. | `diorama_room_dressing.gd:314`, `:329`, `:343`, `:440-442` |
| DRD-07 | P1 | `_spawn_wall_sconce()` adds a `Sconce` box and then calls `_spawn_wall_torch()` at the identical position, so every hall wall carries two interpenetrating boxes and two z-fighting faces per sconce. | `diorama_room_dressing.gd:322-325` |
| DRD-08 | P1 | Light count is high and every light is shadowless. A 20 × 20 room gets roughly nine ceiling torches, four wall torches, and a room fill from `apply_ceiling_lighting()` alone, plus recipe braziers — fourteen-plus omnis, none casting a shadow, all the same hue. | `diorama_room_dressing.gd:98-107`, `:313-353`; `visual_lighting.gd:138` |
| DRD-09 | P2 | `apply_to_waves_arena()` (19 lines) and `apply_shell_lighting()` (20 lines) have no callers. `apply_shell_lighting()` is the only reader of `VisualLighting.SHELL_TORCH_SPACING`, and `SHELL_TORCH_ENERGY` has no reader at all. | `diorama_room_dressing.gd:56-74`, `:138-157`; `visual_lighting.gd:19-20` |
| DRD-10 | P2 | `DioramaPropFactory`, `diorama_prop_kit.gd`, and `diorama_prop_kit.tscn` are a dead three-file chain kept for editor reference. `create_prop_named()`'s string front door has no caller at all. | `diorama_prop_factory.gd:24-36`; `diorama_prop_kit.tscn` is instanced nowhere |
| DRD-11 | P2 | `DioramaRoomDressing._add_box(parent, pos, size, ...)` and `PixelDioramaStyle.add_box(parent, size, position, ...)` have their first two arguments swapped, which is a silent-corruption footgun when code moves between the files. `_add_spot()` creates an `OmniLight3D` named `AccentFill`. `_material_light_color()` probes a `base_color` parameter no shader declares. | `diorama_room_dressing.gd:400-410`, `:413-423`, `:429`; `pixel_diorama_style.gd:422-443` |
| DRD-12 | P2 | Dressing emits no audio and no ambient VFX. A brazier does not crackle and does not drop embers, so a lit room is silent and static. | no `AudioDirector` or `VfxService` reference in `diorama_room_dressing.gd` |
| DRD-13 | P2 | No validation exercises dressing. `m7_suite.gd:315-321` greps `biome_registry.gd` for a string; nothing calls `apply_to_room()` or inspects the result. | `m7_suite.gd:315-321` |

## Target design

### 1. Fix `glow.emission`

`_add_orb()` already takes a `Color`. The three call sites pass the palette colour the property access was reaching for:

```gdscript
var glow_color := PixelStyle.get_palette_color(theme, PixelStyle.PaletteSlot.EMISSIVE)
_add_orb(root, glow_color, Vector3(0.0, 0.35, 0.0), 0.55, Vector3(0.18, 0.08, 0.18))
```

Three lines, no behaviour change beyond the effect actually appearing. Closes DRD-01.

### 2. Prop catalogue as content

`content/art/props.json`, validated by `content/schemas/prop.v1.json`. Each prop is a part list in the same shape as the structures proposed in [`pixel-style.md`](pixel-style.md), so one loader serves both.

```json
{
  "version": 1,
  "props": {
    "brazier_iron": {
      "tags": ["light", "floor", "castle", "vault"],
      "footprint": [0.6, 0.6],
      "parts": [
        { "name": "Bowl",  "size": [0.45, 0.35, 0.45], "pos": [0, 0.5, 0],  "mat": "metal" },
        { "name": "Stem",  "size": [0.16, 0.5, 0.16],  "pos": [0, 0.25, 0], "mat": "metal" },
        { "name": "Foot",  "size": [0.5, 0.1, 0.5],    "pos": [0, 0.05, 0], "mat": "metal" },
        { "name": "Coals", "size": [0.34, 0.12, 0.34], "pos": [0, 0.7, 0],  "mat": "emissive" }
      ],
      "collision": [ { "size": [0.5, 0.9, 0.5], "pos": [0, 0.45, 0] } ],
      "light": { "slot": "emissive", "energy": 0.7, "range": 9.0, "offset": [0, 1.1, 0], "flicker": 0.14 },
      "sfx": { "loop": "brazier_crackle", "radius": 6.0 },
      "vfx": { "ambient": "ember_drift" }
    }
  }
}
```

`mat` values resolve against the palette slots (`floor`, `wall`, `accent`, `wood`, `metal`, `emissive`), so a prop is automatically recoloured per biome without a per-biome copy. `tags` drive placement. `light.slot` means the omni takes the palette's emissive colour rather than the ambient colour, which is what fixes DRD-06's lack of contrast.

```gdscript
## Instantiates a catalogued prop, including collision, light, looping audio,
## and ambient VFX. Unknown ids return an empty Node3D and warn once.
static func spawn_prop(parent: Node3D, prop_id: String, theme: PixelDioramaStyle.PaletteTheme,
        transform: Transform3D) -> Node3D
```

`DioramaPropFactory` becomes this loader — `create_prop()` and `create_prop_named()` are replaced, `diorama_prop_kit.gd` becomes an editor gallery that iterates every catalogued prop instead of a hard-coded four, and `diorama_prop_kit.tscn` stays as the art-review scene. Closes DRD-04, DRD-10, and the collision half of DRD-05.

Rejected alternative: authoring each prop as its own `.tscn`. Rejected because a `.tscn` bakes its materials, so per-biome recolouring would need 10 copies of every prop, and `hide_legacy_meshes()` would fight the authored children.

### 3. Room dressing as data

`content/art/room_dressing.json`, validated by `content/schemas/room-dressing.v1.json`. A recipe is a list of weighted placement rules rather than a list of coordinates:

```json
{
  "version": 1,
  "recipes": {
    "hall": {
      "extends": "base_interior",
      "rules": [
        { "zone": "wall_long", "prop": "sconce_wall", "spacing": [3.0, 4.5], "jitter": 0.25, "required": true },
        { "zone": "floor_mid", "prop_any": ["pillar_stone", "pillar_broken"], "count": [2, 2], "mirror": "x" },
        { "zone": "floor_edge", "prop_any": ["crate_wood", "barrel", "rubble_pile"], "count": [1, 4], "jitter": 0.6 },
        { "zone": "corner", "prop": "cobweb", "count": [0, 2], "biomes": ["forgotten_castle", "the_vault"] }
      ]
    },
    "cathedral_hall": { "extends": "hall", "rules": [ { "zone": "wall_long", "prop": "stained_arch", "spacing": [6.0, 6.0] } ] }
  },
  "room_recipe_map": { "cathedral_hall": "cathedral_hall", "*_hall": "hall" }
}
```

Zones are computed from the blockout: `wall_long`, `wall_short`, `corner`, `floor_edge`, `floor_mid`, `centre`, `ceiling`. `room_recipe_map` supports an exact template id first and then a `*_<suffix>` wildcard, so a biome can override one room type without duplicating the other eight — that is the mechanism that closes DRD-02 without writing 90 recipes by hand. The migration writes the nine current recipes plus a handful of biome overrides, and grows from there.

Placement uses the room RNG for real:

```gdscript
## Dresses a room from its recipe. All randomness derives from `room_seed`, so a
## given seed always produces the same room, and different seeds differ.
static func apply_to_room(room: RoomTemplate, biome_id: String, room_seed: int) -> void
```

Every `count`, `spacing`, `jitter`, and `prop_any` choice draws from that one `RandomNumberGenerator`. `_spawn_prop_cluster()`'s private reseed is deleted. Closes DRD-02, DRD-03.

Rejected alternative: authoring the props directly into the 90 room `.tscn` files. Rejected because it eliminates run-to-run variation entirely and multiplies the maintenance of every prop change by 90.

### 4. Collision and navigation

Every prop with a `collision` block spawns a `StaticBody3D` on layer 1 mask 0, exactly as `_add_obstacle_block()` does today. Props also declare `footprint`, and the placer rejects a position whose footprint overlaps an already-placed footprint or the room's spawn/exit clearance radius (2.5 m), retrying up to eight times before skipping the rule. This is what stops a pillar spawning on the exit portal — a failure the current fixed coordinates avoid only by being fixed.

Failure behaviour: a rule that cannot place its minimum count logs one debug line naming the room and the rule index and continues. A dressing pass never blocks room construction. Closes DRD-05.

### 5. Lighting

- Torch and brazier fixtures get their `Coals`/`Flame` part on the `emissive` slot, so the fixture visibly glows.
- `light.slot = "emissive"` makes the omni take the palette's emissive colour, giving warm torches against a cool ambient instead of the current monochrome. `_biome_light_color()` is deleted.
- `_spawn_wall_sconce()` becomes a single `sconce_wall` prop whose part list contains the bracket and the flame — one node tree, no overlap. Closes DRD-07.
- The torch grid moves into the recipe as a `ceiling` zone rule with `spacing` and a `max_lights` budget, and the two brightest per room pass `cast_shadows = true` to the extended `configure_soft_omni()` described in [`visual-lighting.md`](visual-lighting.md). A room profile field `max_lights` (default 8) caps the total; excess grid positions place an unlit fixture. Closes DRD-06, DRD-08.
- `flicker` per prop attaches `VisualLighting.attach_flicker()`.

### 6. Ambience

`sfx.loop` attaches an `AudioStreamPlayer3D` with `unit_size` from `radius`, `vfx.ambient` attaches a low-rate `GPUParticles3D` from the VFX effect catalogue. Both are skipped when `PixelDioramaSettings.particle_quality == 0` or the audio bus is muted, and both are culled with the prop's visibility. Closes DRD-12.

### 7. Cleanup

Delete `apply_to_waves_arena()` and `apply_shell_lighting()`, or wire the latter into `floor_shell_builder.gd` if shell torches are still wanted — the decision belongs with [`floor-shell.md`](floor-shell.md), and this plan assumes deletion plus removing `SHELL_TORCH_SPACING` and `SHELL_TORCH_ENERGY`. Delete `DioramaRoomDressing._add_box()` in favour of `PixelDioramaStyle.add_box()` so the argument order exists once. Rename `_add_spot()` to `_add_accent_fill()`. Drop the `base_color` probe from `_material_light_color()`. Closes DRD-09, DRD-11.

## Work plan

1. **Fix `glow.emission`** — three lines in `diorama_interactable_skin.gd`. Independent, fixes live breakage. Closes DRD-01.
2. **Sconce overlap and small cleanup** — `_spawn_wall_sconce`, `_add_box` de-duplication, `_add_spot` rename, `base_color` probe, delete the two unused entry points and the two orphan constants. Independent. Closes DRD-07, DRD-09, DRD-11.
3. **Prop catalogue** — `content/schemas/prop.v1.json`, `content/art/props.json` with roughly 30 props (transcribing the boxes the current recipes build, plus the four from `DioramaPropFactory`), `spawn_prop()`, prop-kit gallery. Depends on the structure loader from [`pixel-style.md`](pixel-style.md) step 6 for the shared part-list format. Closes DRD-04, DRD-05, DRD-10.
4. **Recipe data and placer** — `content/schemas/room-dressing.v1.json`, `content/art/room_dressing.json` with the nine base recipes, zone computation, footprint rejection, seeded placement. Depends on 3. Closes DRD-02, DRD-03.
5. **Biome recipe overrides** — one override per biome for `hall`, `boss`, and `courtyard` to start; content work, no code. Depends on 4.
6. **Lighting** — emissive fixture parts, `light.slot`, `max_lights`, shadow budget, flicker. Depends on 3 and on the `visual-lighting.md` steps 4 and 5. Closes DRD-06, DRD-08.
7. **Ambience** — depends on 3, on the VFX effect catalogue, and on the audio work. Closes DRD-12.
8. **Validation** — Closes DRD-13.

Steps 1 and 2 are a single sitting and should land first.

## Data and schema changes

- New `content/schemas/prop.v1.json` and `content/art/props.json` (~30 props).
- New `content/schemas/room-dressing.v1.json` and `content/art/room_dressing.json` (9 base recipes plus overrides).
- `diorama_prop_factory.gd` loses `PropKind`, `create_prop()`, `create_prop_named()`, and the four `_make_*` functions, and gains `spawn_prop()`.
- `diorama_room_dressing.gd` loses the nine `_spawn_*` recipes, `_spawn_prop_cluster`, `_add_biome_banner`, `_add_box`, `_biome_light_color`, `apply_to_waves_arena`, `apply_shell_lighting`.
- `visual_lighting.gd` loses `SHELL_TORCH_SPACING` and `SHELL_TORCH_ENERGY`.
- New audio keys `brazier_crackle` and per-prop loops — see [`audio-director.md`](audio-director.md).
- New VFX effect `ember_drift` — see [`vfx-service.md`](vfx-service.md).
- No save-format change, so no `save_migrator.gd` version bump. Dressing is rebuilt from the room seed on every load, so old saves are unaffected.

## Acceptance criteria

- [ ] Entering a room with an exit portal, picking up an XP shard, and reaching the final boss cannon all produce a visible glow orb and no property-access error. (DRD-01)
- [ ] A `cathedral_hall` and a `castle_hall` at the same size are visually distinguishable by prop silhouette, not only by colour. (DRD-02)
- [ ] The same room id dressed with two different seeds produces different prop counts and positions; the same seed twice produces identical output. (DRD-03)
- [ ] Adding a prop to `props.json` and referencing it from a recipe puts it in the world with no code change. (DRD-04)
- [ ] Walking into a pillar, a brazier, and a pedestal stops the player. (DRD-05)
- [ ] A brazier's coals are visibly brighter than its bowl, and its light is warmer than the room ambient. (DRD-06)
- [ ] A hall wall shows one sconce mesh per position with no z-fighting. (DRD-07)
- [ ] A 20 × 20 room contains at most `max_lights` omnis, of which at most two cast shadows. (DRD-08)
- [ ] `rg "apply_to_waves_arena|apply_shell_lighting|SHELL_TORCH"` returns no hits outside docs. (DRD-09)
- [ ] The prop-kit scene shows every catalogued prop. (DRD-10)
- [ ] Standing near a brazier plays a crackle that attenuates with distance and drops occasional embers. (DRD-12)

## Validation

New suite `apps/game/client/scripts/validation/suites/room_dressing_suite.gd`, category `content`:

| Test id | Assertion |
|---------|-----------|
| `dressing.props_json_loads` | `content/art/props.json` parses and validates against `prop.v1.json` |
| `dressing.recipes_json_loads` | `content/art/room_dressing.json` parses and validates against `room-dressing.v1.json` |
| `dressing.prop_refs_resolve` | every `prop` and every `prop_any` entry in every recipe exists in the prop catalogue |
| `dressing.mat_slots_valid` | every part's `mat` is one of the six documented palette slots |
| `dressing.recipe_coverage` | every one of the 90 room template ids resolves through `room_recipe_map` (exact or wildcard) to a declared recipe |
| `dressing.extends_terminates` | no `extends` chain contains a cycle and every parent exists |
| `dressing.unknown_prop_safe` | `spawn_prop(parent, "nope", ...)` returns an empty `Node3D`, warns once, and does not warn again |
| `dressing.deterministic_by_seed` | dressing a room twice with seed 12345 produces identical child names and positions |
| `dressing.varies_by_seed` | seeds 1 and 2 on the same room produce different child counts or positions in at least 8 of 10 sampled rooms |
| `dressing.no_footprint_overlap` | for 50 seeded rooms, no two placed props' footprints overlap |
| `dressing.spawn_clearance` | no prop is placed within 2.5 m of the room's spawn point or exit marker |
| `dressing.min_count_failure_is_soft` | a recipe whose rules cannot fit still returns a dressed room and pushes no error |
| `dressing.collision_present` | every prop declaring `collision` yields a `StaticBody3D` on layer 1 mask 0 with the declared shape count |
| `dressing.light_budget` | no dressed room exceeds its `max_lights`, and at most two omnis have `shadow_enabled == true` |
| `dressing.light_uses_emissive_slot` | a brazier's omni colour equals the palette `EMISSIVE` slot, not the biome ambient |
| `dressing.fixture_is_emissive` | every prop declaring a `light` has at least one part on the `emissive` slot |
| `dressing.no_duplicate_child_names` | a dressed room has no two siblings with the same name |
| `dressing.idempotent` | calling `apply_to_room()` twice adds no second `DioramaDressing` |
| `dressing.sfx_keys_exist` | every `sfx.loop` key resolves in `AudioDirector` |
| `dressing.vfx_ids_exist` | every `vfx.ambient` id exists in the VFX effect catalogue |
| `skin.no_emission_property_access` | `diorama_interactable_skin.gd` contains no `.emission` member access on a `PixelStyle` result |
| `skin.builders_have_callers` | every `build_*` in `diorama_interactable_skin.gd` has at least one call site outside the file |

Manual checklist:

- Walk the same seed twice and a different seed once: the first two must match, the third must not.
- Stand in a castle hall and a cathedral hall side by side and confirm they read as different places.
- Confirm no prop blocks a doorway or the exit portal across ten generated floors.

## Related
- Existing behaviour: [`../existing_codebase/diorama-room-dressing.md`](../existing_codebase/diorama-room-dressing.md)
- [`pixel-style.md`](pixel-style.md) — the shared part-list format, the palette slots, and `add_box`
- [`character-authoring.md`](character-authoring.md) — the same authored-parts direction applied to characters
- [`visual-lighting.md`](visual-lighting.md) — the shadow budget, flicker, and `configure_soft_omni()` signature this plan depends on
- [`portal-ellipse-shader.md`](portal-ellipse-shader.md) — the `glow.emission` fix is shared, and `build_portal` gains the real portal shader
- [`biome-registry.md`](biome-registry.md) — the material and light-colour source being replaced
- [`room-templates.md`](room-templates.md), [`room-content.md`](room-content.md), [`procgen-placements.md`](procgen-placements.md) — the 90 rooms and the other placement passes the footprint check must respect
- [`floor-shell.md`](floor-shell.md) — owns the `apply_shell_lighting()` deletion decision
- [`dungeon-builder.md`](dungeon-builder.md), [`dungeon-traps.md`](dungeon-traps.md), [`loot-and-equipment.md`](loot-and-equipment.md) — interactable skin consumers
- [`vfx-service.md`](vfx-service.md), [`audio-director.md`](audio-director.md) — ambient embers and brazier crackle
- [`content-data.md`](content-data.md) — where the two new JSON files live
