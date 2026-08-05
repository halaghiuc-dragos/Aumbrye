# Diorama character skin — improvement plan

## Current state

Every body in the game is assembled at runtime from about ten `BoxMesh` primitives by `PixelDioramaStyle.add_box`, sized from the hardcoded `PROFILES` dictionary (`diorama_character_skin.gd:32-86`) plus a separately hardcoded quadruped (`:422-451`). Six humanoid profiles and one quadruped cover the player, all 30 definitions in `content/enemies/`, and all 11 in `content/bosses/`. No sprite, texture, voxel, or mesh asset exists anywhere in `apps/game/client/assets/`. See [`../existing_codebase/diorama-character-skin.md`](../existing_codebase/diorama-character-skin.md) for the full node-name contract and profile table.

The decision about what authored characters should be made of — pixel-art billboards, voxel volumes, or hand-modeled low-poly meshes — and the asset pipeline and file format that follow from it, belong to [`character-authoring.md`](character-authoring.md). This plan does not choose a format. It fixes the correctness bugs in the current builder, makes the rig contract enforceable, and turns `PROFILES` into data so that whatever authoring format wins can be dropped in behind a stable interface.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| SKN-01 | P0 | Six humanoid profiles and one quadruped are the entire character silhouette vocabulary for 41 enemy/boss definitions plus the player. A slime, a bat, a leech, and a knight share one 10-box upright body. | `diorama_character_skin.gd:32-86`, `:365-451`; profile-coverage table in the existing-code doc |
| SKN-02 | P0 | 11 of the 13 definitions with `enemy_type: "boss"` resolve to profile `"boss"`, which is absent from `PROFILES`, so `build_enemy_body` silently falls back to `melee` and every boss has the grunt silhouette. | `:210-217`, `:167`; `content/bosses/boss_castle_knight.json:22`, `content/enemies/swamp_hag.json:21` |
| SKN-03 | P0 | The visor lookup path is wrong, so the `Visor` mesh can never be hidden. `open` and `visor` head styles are visually identical, and `hood` renders hood plus visor. | `:111` reads `Mesh/Visor`; `:391-397` builds the node at `Head/Visor` |
| SKN-04 | P1 | Leaving first person calls `_set_meshes_visible(visual, true)`, which re-shows the `Visor` and `Hood` meshes that `_apply_player_appearance` hid. | `:289` vs `:113`, `:116` |
| SKN-05 | P1 | `theme_for_enemy_id` matches on the substring before the first `_`, so every `boss_*` and `miniboss_*` id resolves to `CASTLE` regardless of biome. `boss_frost_warlord` is castle-colored. | `:199-207`; `content/bosses/boss_frost_warlord.json:2` |
| SKN-06 | P1 | `feet_local_y` returns `0.0` for every profile and is the only input `character_floor_snap.align_diorama_visual` has, so per-profile foot alignment is unimplemented. | `:195-196`; `character_floor_snap.gd:29-30` |
| SKN-07 | P1 | Nothing validates the rig contract. A renamed or missing pivot silently drops animation tracks with no warning and no test. | `diorama_anim_library.gd:530-531`, `:546-547`; `diorama_anim_controller.gd:309`, `:321-322`; `diorama_anim_suite.gd:33-50` checks clip-table names only |
| SKN-08 | P1 | Hound `EarL`/`EarR` are `MeshInstance3D`, not pivots, so `collect_rest_pose` skips them and no clip can animate ears — the most legible motion cue a quadruped has. | `:434-435`, `:462-468` |
| SKN-09 | P1 | The quadruped reuses the biped `LegL`/`LegR` clip amplitudes against 0.30 m legs, and the hound has the highest `move_speed` in the game (5.5). | `:426`, `:442-449`; `diorama_anim_library.gd:59-66`; `content/enemies/frost_hound.json:8` |
| SKN-10 | P1 | The `"body"` material is the process-wide cached wall material for the theme, and `PixelDioramaSettings.apply_all()` clears that cache, orphaning already-built bodies so a live settings change does not repaint them. | `:359`; `pixel_diorama_style.gd:250-252`, `:69-73`; `pixel_diorama_settings.gd:183` |
| SKN-11 | P2 | `build_player_body` calls `_body_materials` twice, allocating two accent `ShaderMaterial` duplicates per build and giving the visor a different instance from the belt trim. | `:96-97`, `:352-354` |
| SKN-12 | P2 | The `"Shield"` preservation guard inside `attach_weapon` is unreachable: the loop iterates `WeaponMount`'s children, and `Shield` is only ever a child of `ShieldMount`. | `:236-239`, `:413-417` |
| SKN-13 | P1 | No equipment slot other than the weapon has any visual. Helms, plates, boots, gauntlets, and off-hand items in `content/items/equipment/` change nothing on the rig. | `:127-151` reads only the `trim` appearance index; `attach_weapon` mounts to `WeaponMount` only |

## Target design

### 1. Profiles become data, not a constant

Move the profile table out of GDScript into `content/characters/rigs/<profile>.json`, loaded through `ContentLoader` and cached in a new `CharacterRigCatalog` (`apps/game/client/scripts/art/characters/character_rig_catalog.gd`). Schema, one file per profile:

```json
{
  "id": "melee",
  "kind": "humanoid",
  "leg":   [0.24, 0.48, 0.28],
  "torso": [0.55, 0.64, 0.38],
  "head":  [0.36, 0.36, 0.36],
  "arm":   [0.22, 0.54, 0.22],
  "hip_x": 0.14,
  "shoulder_x": 0.33,
  "shoulder_ratio": 0.88,
  "head_accent": true,
  "visor": false,
  "extras": [],
  "anim_profile": "melee"
}
```

`kind` is `"humanoid"` or `"quadruped"`; the quadruped schema adds `body`, `head_offset`, `tail_offset`, `leg_height`, `front_z`, `rear_z`, and `ears`. `shoulder_ratio` promotes the currently hardcoded `0.88` at `:399` to data.

`PROFILES` stays in the script as the fallback used when `ContentLoader` returns nothing, so the game boots even with a broken content tree. Chosen over deleting it because `export_diorama_anim_libraries.gd` runs headless without autoloads (`export_diorama_anim_libraries.gd:3-4`) and needs a source of truth it can reach.

New profiles to add as data, each a distinct silhouette rather than a resized humanoid:

| Profile | Kind | Purpose | Content ids served |
|---------|------|---------|--------------------|
| `boss_humanoid` | humanoid | 1.35x brute proportions, twin shoulder plates, crested head | `boss_castle_knight`, `miniboss_castle_captain`, `boss_frost_warlord`, `boss_cathedral_hollow`, `crystal_sovereign`, `boss_crystal_sovereign` |
| `serpent` | serpent | segmented spine, no legs | `swamp_hydra`, `boss_swamp_devourer` |
| `caster` | humanoid | robed: single tapered skirt box instead of split legs, hood | `swamp_hag`, `swamp_witch`, `cathedral_acolyte`, `crystal_shade` |
| `flyer` | flyer | torso + two wing pivots + no legs, hovering root offset | `crystal_bat`, `crystal_wisp` |
| `blob` | blob | single squashable body box, no limbs | `crystal_slime`, `swamp_leech`, `swamp_swarm`, `swamp_toad` |
| `construct` | humanoid | `brute` with a floating-segment torso, gap between chest and hips | `crystal_golem`, `crystal_guardian`, `miniboss_crystal_guardian` |
| `bell` | static | suspended mass, no locomotion | `miniboss_cathedral_bell` |

`profile_for_enemy_data` becomes a table lookup instead of substring matching:

```gdscript
static func profile_for_enemy_data(data: Dictionary) -> String:
    var explicit := str(data.get("rig_profile", ""))
    if explicit != "" and CharacterRigCatalog.has(explicit):
        return explicit
    ...
```

with `rig_profile` added to every enemy and boss JSON file, and the substring rules kept only as a fallback. `build_enemy_body` stops falling back silently: an unknown profile calls `push_warning("DioramaCharacterSkin: unknown rig profile '%s', using melee")` so SKN-02 cannot recur unnoticed.

### 2. Rig contract validation

Add `static func validate_rig(visual: Node3D, profile: String) -> PackedStringArray` to `diorama_character_skin.gd`. It compares the pivots actually present against the `REQUIRED_PIVOTS` table below and returns one message per violation.

```gdscript
const REQUIRED_PIVOTS := {
    "humanoid": ["Root", "Torso", "Head", "ArmL", "ArmR", "LegL", "LegR", "ShieldMount", "WeaponMount"],
    "quadruped": ["Root", "Torso", "Head", "Tail", "LegL", "LegR", "LegBL", "LegBR"],
    "serpent": ["Root", "Torso", "Head", "Spine1", "Spine2", "Spine3", "TailTip"],
    "flyer": ["Root", "Torso", "Head", "WingL", "WingR"],
    "blob": ["Root", "Torso"],
    "viewmodel": ["ArmL", "ArmR", "ShieldMount", "WeaponMount"],
}
```

`_finish_bind` calls it and `push_warning`s each message (`diorama_anim_controller.gd:85-89`). The suite assertion is in the Validation section below.

### 3. Head style, first person, and appearance

- Fix the visor path to `head.get_node_or_null("Visor")` (`:111`).
- Build the `Hood` box unconditionally at rig-build time inside `_build_humanoid` when `spec.hood_capable` is set, so `_apply_player_appearance` only toggles visibility and never mutates geometry. This removes the "create on demand" branch at `:117-126` and makes the appearance step idempotent.
- Replace `_set_meshes_visible(visual, true)` (`:289`) with a restore that re-applies the appearance-driven visibility. Introduce `const APPEARANCE_TOGGLED_MESHES := ["Visor", "Hood"]` and a `_reapply_appearance_visibility(visual, head_style)` helper; store the active head style as metadata on the `DioramaVisual` node (`visual.set_meta("head_style", head_style)`) so `apply_first_person` can restore without re-reading `CharacterService`.
- `HEAD_OPEN` gets a visible difference: a `Brow` accent box across the upper head, absent for `visor` and `hood`.

### 4. Theme resolution

Replace prefix splitting (`:199-207`) with an explicit map plus a biome fallback:

```gdscript
const ENEMY_THEME_OVERRIDES := { "training": PixelStyle.PaletteTheme.CASTLE }

static func theme_for_enemy_id(enemy_id: String) -> int:
    if ENEMY_THEME_OVERRIDES.has(enemy_id):
        return ENEMY_THEME_OVERRIDES[enemy_id]
    var biome := EnemyCatalog.get_definition(enemy_id).get("biome", "")
    if biome != "":
        return PixelStyle.theme_from_biome(biome)
    return PixelStyle.PaletteTheme.CASTLE
```

This requires a `biome` key on every enemy and boss definition; `PixelStyle.theme_from_biome` already handles all eleven biome ids (`pixel_diorama_style.gd:200-221`).

### 5. Material-instance ownership

State and enforce one rule: **cached materials are read-only shared resources; anything that mutates a material must own a per-instance duplicate.**

- `_body_materials` gains a `per_instance: bool = false` argument. When `true` it returns duplicates of both `body` and `accent`. `build_player_body`, `build_enemy_body`, and `build_training_dummy` pass `true`, because bodies are the only geometry in the game whose materials are mutated at runtime (flash, dissolve, tint). Static level geometry keeps the shared cache.
- `build_player_body` calls `_body_materials` once and reuses the dictionary (fixes SKN-11).
- `DioramaVisual` gets `visual.set_meta("owned_materials", true)` so `MaterialFlash` and `MaterialDissolve` can assert on it rather than duplicating defensively; see [`material-flash.md`](material-flash.md) and [`material-dissolve.md`](material-dissolve.md).
- Add `static func retheme(visual: Node3D, theme: int) -> void` which rebuilds the two materials and reassigns `material_override` across the rig, so `PixelDioramaSettings.apply_all()` can repaint existing bodies instead of orphaning them (SKN-10). `pixel_diorama_settings.gd:189` already walks the current scene; extend `_apply_materials_recursive` to call `retheme` when it meets a node with the `owned_materials` meta.

### 6. Foot alignment

`feet_local_y(profile)` returns the actual lowest point of the rig for that profile, computed from the catalog entry rather than hardcoded:

```gdscript
static func feet_local_y(profile: String) -> float:
    var spec := CharacterRigCatalog.get_rig(profile)
    match str(spec.get("kind", "humanoid")):
        "quadruped", "serpent": return 0.0
        "flyer": return float(spec.get("hover_height", 0.6))
        _: return 0.0
```

Humanoid feet already sit on the rig origin, so `0.0` is correct there and the comment at `:193-194` stays true; the value stops being a lie for flyers, which currently have their hover baked nowhere.

### 7. Equipment silhouettes

`attach_equipment(visual, slots: Dictionary, theme: int)` adds accent boxes per equipped slot, driven by a new `rig_overlay` key on equipment JSON:

```json
"rig_overlay": { "part": "Head", "shape": [0.34, 0.14, 0.36], "offset": [0.0, 0.30, 0.0], "material": "accent" }
```

Slots covered: `head` -> `Head`, `chest` -> `Torso`, `hands` -> `ArmL`/`ArmR`, `feet` -> `LegL`/`LegR`, `offhand` -> `ShieldMount`. Overlays are named `Overlay<Slot>` and are freed and rebuilt whenever equipment changes, exactly as `attach_weapon` handles `WeaponMount`. The `trim` appearance index keeps working and is applied first, so a player with no equipment still reads as customized.

### 8. Quadruped and ear pivots

`_build_quadruped` becomes catalog-driven and promotes `EarL`/`EarR` to pivots with a `Mesh` child each, matching the pattern every other part uses. Leg amplitudes move to the animation layer; see [`diorama-anim-library.md`](diorama-anim-library.md) gaps ANL-02 and ANL-06.

## Work plan

1. **Fix the visor path and head styles** — `diorama_character_skin.gd:111` becomes `head.get_node_or_null("Visor")`; add the `Brow` box for `HEAD_OPEN`; build `Hood` at rig-build time and delete the on-demand branch at `:117-126`. Closes SKN-03.
2. **Fix first-person restore** — add `APPEARANCE_TOGGLED_MESHES`, `_reapply_appearance_visibility`, and the `head_style` meta; replace the `_set_meshes_visible` call at `:289`. Closes SKN-04.
3. **Add `validate_rig` and wire the warning** — new function in `diorama_character_skin.gd`; call it from `diorama_anim_controller._finish_bind` after `collect_rest_pose`. Closes SKN-07.
4. **Add `CharacterRigCatalog` and `content/characters/rigs/*.json` for the seven existing profiles** — no behavior change; `PROFILES` becomes the fallback. `_build_humanoid` and `_build_quadruped` read from the catalog.
5. **Add `rig_profile` to every enemy and boss JSON; add the `boss_humanoid` and `construct` rigs** — `profile_for_enemy_data` prefers `rig_profile`; `build_enemy_body` warns on an unknown profile. Closes SKN-02 for the six boss ids listed above.
6. **Add the `caster`, `flyer`, `blob`, `serpent`, and `bell` rig kinds** — new builder functions plus catalog entries plus `REQUIRED_PIVOTS` rows; assign them via `rig_profile`. Closes SKN-01.
7. **Add `biome` to every enemy and boss JSON and rewrite `theme_for_enemy_id`** — closes SKN-05.
8. **Material ownership** — add `per_instance` to `_body_materials`, single-call in `build_player_body`, `owned_materials` meta, `retheme`, and the `pixel_diorama_settings` hook. Closes SKN-10 and SKN-11.
9. **Promote hound ears to pivots and make `feet_local_y` catalog-driven** — closes SKN-08 and SKN-06.
10. **Delete the unreachable `"Shield"` guard in `attach_weapon`** — closes SKN-12.
11. **Add `attach_equipment` and `rig_overlay` on equipment JSON** — closes SKN-13.

Each step leaves the game runnable: steps 1-3 and 10 are local edits, step 4 is a pure refactor behind a fallback, and steps 5-9 and 11 are additive.

## Data and schema changes

- New directory `content/characters/rigs/` with one JSON per rig profile. New schema `content/schemas/character_rig.schema.json` describing `id`, `kind`, the box-size arrays, `hip_x`, `shoulder_x`, `shoulder_ratio`, `head_accent`, `visor`, `hood_capable`, `extras`, `hover_height`, `anim_profile`.
- New required keys on every file in `content/enemies/` and `content/bosses/`: `rig_profile` (string, must match a rig id) and `biome` (string, must match a `BiomeRegistry` id). Update `content/schemas/enemy.schema.json`.
- New optional key `rig_overlay` on files in `content/items/equipment/`. Update `content/schemas/item.schema.json`.
- No save-format change. Appearance is unchanged, so no `save_migrator.gd` version bump is required.

## Acceptance criteria

- [ ] Selecting `Open face`, `Visor helm`, and `Hooded` in character creation produces three visually distinct heads, and the visor is absent for `Open face` and `Hooded`.
- [ ] Toggling to first person and back leaves the head exactly as it was before the toggle, verified by comparing `Visor.visible` and `Hood.visible` before and after.
- [ ] `build_enemy_body` emits a warning naming the profile whenever the requested profile is not in the catalog, and no shipped enemy or boss definition triggers that warning.
- [ ] Each of `boss_castle_knight`, `miniboss_castle_captain`, `boss_frost_warlord`, `boss_cathedral_hollow`, `crystal_sovereign`, and `boss_crystal_sovereign` renders with a silhouette whose bounding box differs from `castle_grunt`'s by more than 25 percent in at least two axes.
- [ ] `crystal_bat` and `crystal_wisp` render with no leg pivots and no `Bow` pivot.
- [ ] `crystal_slime`, `swamp_leech`, `swamp_swarm`, and `swamp_toad` render with no arm or leg pivots.
- [ ] `swamp_hydra` and `boss_swamp_devourer` render with at least three spine pivots and no `LegL`/`LegR`.
- [ ] `theme_for_enemy_id("boss_frost_warlord")` returns `PaletteTheme.FROZEN`, and no shipped boss id resolves to `CASTLE` unless its biome is the forgotten castle.
- [ ] `validate_rig` returns an empty array for every rig the skin can build, for every profile in the catalog.
- [ ] `feet_local_y` returns a non-zero value for every rig whose lowest geometry is not at the rig origin.
- [ ] Building one player body allocates exactly one `body` and one `accent` `ShaderMaterial`, verified by instance identity of `material_override` across the rig's meshes.
- [ ] Changing the pixel-diorama display settings while a body exists repaints that body rather than leaving it on an orphaned material.
- [ ] Equipping `castle_plate`, `castle_helm`, `castle_boots`, `castle_gauntlets`, and `castle_buckler` each adds a visible overlay box to the rig, and unequipping removes it.

## Validation

Extend `apps/game/client/scripts/validation/suites/diorama_anim_suite.gd` and add `apps/game/client/scripts/validation/suites/character_rig_suite.gd` (category `graphics`, milestone tag `M7.graphics.rig`). Assertions:

- `character_rig.pivot_contract` — for every profile in the catalog, build the rig into a detached `Node3D`, run `validate_rig`, assert the returned array is empty. Message lists the missing pivots on failure.
- `character_rig.rest_pose_keys` — for each profile, assert `collect_rest_pose(visual).keys()` equals the expected set exactly (the per-profile table in the existing-code doc). Catches both missing and unexpected pivots, including a pivot accidentally turned into a `MeshInstance3D`.
- `character_rig.profiles_resolve` — for every file in `content/enemies/` and `content/bosses/`, assert `profile_for_enemy_data(definition)` names a profile present in the catalog. Fails today for the 11 `"boss"` definitions.
- `character_rig.theme_resolves_to_biome` — for every enemy and boss id, assert `theme_for_enemy_id(id) == PixelStyle.theme_from_biome(definition["biome"])`.
- `character_rig.silhouette_distinct` — compute the AABB of each built rig and assert no two profiles share an AABB within 5 percent on all three axes. Catches a new profile that is just a resized humanoid.
- `character_rig.head_style_distinct` — build the player body once per head style and assert the set of visible mesh names differs between all three.
- `character_rig.material_instances_owned` — build a player body and assert every `material_override` in the rig is distinct from `PixelStyle.make_wall_material(theme)` by instance identity.
- `character_rig.exporter_rest_poses_match` — for each of the six profiles in `export_diorama_anim_libraries.REST_POSES`, build the rig and assert each recorded `position` matches `collect_rest_pose` to within 1e-4. Guards SKN-01's data move against the exporter drifting.
- `character_rig.no_authored_character_assets` — assert the count of files under `res://assets/` with a mesh or image extension is exactly the expected number, so the day authored assets do land the check has to be updated deliberately. Until [`character-authoring.md`](character-authoring.md) lands, this documents the placeholder state rather than passing it silently.

Manual checklist, only where automation is genuinely impossible:
- Hound gait reads as a trot rather than a shuffle at `move_speed: 5.5`.
- Boss silhouettes are legible at the 480x270 internal resolution from the default third-person camera distance.

## Related
- Current behavior: [`../existing_codebase/diorama-character-skin.md`](../existing_codebase/diorama-character-skin.md)
- Authoring format and asset pipeline decision: [`character-authoring.md`](character-authoring.md)
- [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-anim-controller.md`](diorama-anim-controller.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`diorama-weapon-kit.md`](diorama-weapon-kit.md)
- [`material-flash.md`](material-flash.md), [`material-dissolve.md`](material-dissolve.md), [`pixel-style.md`](pixel-style.md), [`character-appearance.md`](character-appearance.md), [`character-floor-snap.md`](character-floor-snap.md), [`enemies.md`](enemies.md), [`bosses.md`](bosses.md), [`00-QUALITY-BAR.md`](00-QUALITY-BAR.md)
