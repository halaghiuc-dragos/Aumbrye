# Diorama character skin — improvement plan

## Status: FINISHED

## Current state

The primary build path loads 25 voxel rig manifests from `content/characters/` through `CharacterRigCatalog` and assembles `ArrayMesh` bodies via `build_from_manifest` (`diorama_character_skin.gd:733-794`, `character_rig_catalog.gd:50-104`). One hundred nineteen `.voxels.json` part files live under `apps/game/client/assets/characters/`. Player stature uses eight `player_warden*` manifests; enemies map to `enemy_hound`, `enemy_ranged`, `enemy_shield`, `enemy_brute`, `enemy_dummy`, or a biome-tinted `enemy_biome_*` biped. `PROFILES` plus `_build_humanoid` / `_build_quadruped` remain as the boot-safe box fallback when a manifest or mesh is missing (`:126-128`, `:379-383`). Head-style extras (`Visor`, `Hood`, trim pieces) are manifest-authored and visibility-toggled in `_apply_player_appearance` (`:179-194`). `apply_equipment` mounts voxel equipment meshes from item `visual` blocks (`:852-913`, `inventory_service.gd:399-409`). See [`../existing_codebase/diorama-character-skin.md`](../existing_codebase/diorama-character-skin.md) for the full node contract, profile table, and current-state matrix.

The format decision — voxel volumes vs sprites vs hand-modeled meshes — is settled in [`character-authoring.md`](character-authoring.md). This plan covers remaining correctness gaps, silhouette expansion, and test coverage on top of the shipped manifest pipeline.

## Gaps

| ID | Sev | Gap | Evidence | Status |
|----|-----|-----|----------|--------|
| SKN-01 | P0 | Seven archetype families and ten biome bipeds are the entire enemy silhouette vocabulary; bats, slimes, hydras, and knights share one of a few upright bodies | `character_rig_catalog.gd:90-104`; profile table in existing-code doc | OPEN |
| SKN-02 | P0 | `enemy_type: "boss"` is not in `PROFILES`; bosses resolve to the biome biped manifest, not a distinct boss rig | `diorama_character_skin.gd:434-441`, `:374`; `content/bosses/boss_castle_knight.json` | OPEN |
| SKN-03 | P0 | Visor lookup path was wrong so `open` and `visor` head styles were identical | was `:111` `Mesh/Visor` vs `:616-622` `Head/Visor` | FINISHED |
| SKN-04 | P1 | Leaving first person calls `_set_meshes_visible(visual, true)`, re-showing `Visor`/`Hood` that appearance hid | `:513-514` vs `:179-184` | OPEN |
| SKN-05 | P1 | `theme_for_enemy_id` prefix match sends `boss_*` and `miniboss_*` to `CASTLE` regardless of biome | `:407-431`; `boss_frost_warlord` → prefix `boss` → `CASTLE` | OPEN |
| SKN-06 | P1 | `feet_local_y` returns `0.0` for every profile; per-profile foot alignment unimplemented | `:403-404`; `character_floor_snap.gd:29-30` | OPEN |
| SKN-07 | P1 | No runtime `validate_rig`; renamed pivot drops animation tracks with no warning | `diorama_anim_library.gd:530-531`; partial coverage in `diorama_anim_suite.gd:303-345` | PARTIAL |
| SKN-08 | P1 | Hound box-fallback `EarL`/`EarR` are `MeshInstance3D`, not pivots; voxel hound has no ear parts | `_build_quadruped` `:670-675`; `enemy_hound.json` | OPEN |
| SKN-09 | P1 | Quadruped reuses biped `LegL`/`LegR` clip amplitudes | `diorama_anim_library.gd:59-66`; `frost_hound.json` `move_speed: 5.5` | OPEN |
| SKN-10 | P1 | Box-fallback `"body"` material is the shared cached wall material; no `retheme` for live bodies | `_body_materials` `:585`; voxel path duplicates per build `:842-849` | PARTIAL |
| SKN-11 | P2 | Box-fallback `build_player_body` calls `_body_materials` twice on the fallback branch | `:127-128` | OPEN |
| SKN-12 | P2 | `attach_weapon` `Shield` preservation on `WeaponMount` is unreachable (`Shield` is under `ShieldMount`) | `:459-462` vs shield built at `:643-648` | OPEN |
| SKN-13 | P1 | `apply_equipment` exists but only 3 of 78 equipment items define `visual` | `:852-913`; `castle_helm.json`, `castle_plate.json`, `iron_helm.json` only | PARTIAL |
| SKN-14 | P1 | Voxel manifest pipeline landed (catalog, builder, 25 manifests, suite contract test) | `character_rig_catalog.gd`, `build_from_manifest`, `diorama_anim_suite.gd:303-345` | FINISHED |
| SKN-15 | P1 | Player appearance extras (visor/hood/trim/hair/face/class armor) on manifest path | `_apply_player_appearance` `:170-351`; `player_warden.json` extras | FINISHED |

## Target design

### 1. Distinct silhouettes per content role

Keep manifests in `content/characters/` (not the originally proposed `content/characters/rigs/` split — manifests already live there). Add archetypes with distinct pivot layouts rather than resized bipeds:

| Archetype id | `profile` kind | Purpose | Content ids |
|--------------|----------------|---------|-------------|
| `enemy_boss_humanoid` | `biped` | 1.35× brute, shoulder plates, crested head | six castle/frost/cathedral/crystal bosses |
| `enemy_serpent` | `serpent` | segmented spine, no legs | `swamp_hydra`, `boss_swamp_devourer` |
| `enemy_caster` | `biped` | robed skirt, hood | `swamp_hag`, `cathedral_acolyte`, `crystal_shade` |
| `enemy_flyer` | `flyer` | wings, no legs, hover offset | `crystal_bat`, `crystal_wisp` |
| `enemy_blob` | `blob` | single squashable body | `crystal_slime`, `swamp_leech`, `swamp_swarm`, `swamp_toad` |
| `enemy_construct` | `biped` | floating torso segment | `crystal_golem`, `crystal_guardian` |
| `enemy_bell` | `static` | suspended mass | `miniboss_cathedral_bell` |

`profile_for_enemy_data` gains an explicit `rig_profile` key on enemy/boss JSON with substring rules kept as fallback. `archetype_for_enemy` prefers `rig_profile` → manifest id. Unknown profile: `push_warning` and fall back to biome biped.

Extend `VoxelGrid.REQUIRED_PIVOTS` with `serpent`, `flyer`, `blob`, `static` rows.

### 2. Rig contract validation at bind time

Add `static func validate_rig(visual: Node3D, profile: String) -> PackedStringArray` comparing present pivots to `VoxelGrid.REQUIRED_PIVOTS[profile]`. Call from `diorama_anim_controller._finish_bind` after `collect_rest_pose`; `push_warning` each message. Keep `diorama_anim_suite._test_rig_contracts` as the CI gate.

### 3. First-person restore

Replace `_set_meshes_visible(visual, true)` (`:513-514`) with `_reapply_appearance_visibility(visual)` that re-reads `head_style` from metadata or `CharacterService` and restores only `APPEARANCE_EXTRAS` visibility. Store `head_style` on `DioramaVisual` meta during `_apply_player_appearance`.

### 4. Theme resolution from biome data

Replace prefix splitting (`:407-431`) with `EnemyCatalog.get_definition(enemy_id)["biome"]` → `PixelStyle.theme_from_biome(biome)` (`pixel_diorama_style.gd:200-221`), plus a small `ENEMY_THEME_OVERRIDES` map for `training`. Requires `biome` on every enemy and boss JSON.

### 5. Material ownership on box fallback

Voxel path already duplicates per build (`_make_voxel_material` `:842-849`). Box fallback should match: `per_instance: bool` on `_body_materials`, single call in `build_player_body`, `owned_materials` meta on `DioramaVisual`, and `retheme(visual, theme)` callable from `PixelDioramaSettings.apply_to_scene` when settings change.

### 6. Foot alignment

`feet_local_y(profile)` reads lowest joint Y from the manifest (or `hover_height` for flyers) instead of returning `0.0`.

### 7. Equipment visuals at scale

Keep `apply_equipment` and the `visual` dict shape (`attach`, `mesh`, `hide`). Add `visual` blocks (and `.voxels.json` or `.mesh` assets) for every armor slot item that should change silhouette: helm, chest, hands, feet, off-hand.

### 8. Quadruped ears and leg clips

Promote hound ears to pivots in `enemy_hound.json` extras or parts. Per-archetype leg amplitudes move to animation data; see [`diorama-anim-library.md`](diorama-anim-library.md) ANL-02 and ANL-06.

## Work plan

1. **First-person appearance restore** — `_reapply_appearance_visibility`, `head_style` meta; replace `:513-514`. Closes SKN-04.
2. **`validate_rig` + bind warning** — `diorama_character_skin.gd`; wire `diorama_anim_controller._finish_bind`. Closes SKN-07 remainder.
3. **`rig_profile` on enemy/boss JSON + new archetype manifests** — `enemy_boss_humanoid`, `enemy_flyer`, `enemy_blob`, `enemy_serpent`, `enemy_caster`, `enemy_construct`, `enemy_bell`. Closes SKN-01, SKN-02.
4. **`biome` key + rewrite `theme_for_enemy_id`** — closes SKN-05.
5. **Box-fallback material ownership** — `per_instance`, `owned_materials` meta, `retheme`. Closes SKN-10, SKN-11.
6. **Catalog-driven `feet_local_y`** — closes SKN-06.
7. **Hound ear pivots + quadruped clip tables** — closes SKN-08, SKN-09.
8. **Delete unreachable `Shield` guard on `WeaponMount`** — closes SKN-12.
9. **Equipment `visual` blocks for all armor tiers** — closes SKN-13.
10. **Voxel manifest pipeline** — landed. Closes SKN-14, SKN-15. **DONE**
11. **Visor path fix + manifest extras for head styles** — landed. Closes SKN-03. **DONE**

## Data and schema changes

- New manifest files under `content/characters/` for each archetype in the silhouettes table. Extend `VoxelGrid.REQUIRED_PIVOTS` and add `profile` enum values (`serpent`, `flyer`, `blob`, `static`) to manifest JSON convention.
- New required keys on `content/enemies/` and `content/bosses/`: `rig_profile` (string) and `biome` (string matching `BiomeRegistry`). Update `content/schemas/enemy.schema.json`.
- Optional `visual` on `content/items/equipment/` (already used by three items). Update `content/schemas/item.schema.json`.
- No save-format change. No `save_migrator.gd` version bump.

## Acceptance criteria

- [x] `build_from_manifest` assembles every manifest in `CharacterRigCatalog.list_archetype_ids()` with `ArrayMesh` parts, not `BoxMesh` (SKN-14).
- [x] `diorama_anim.rig_contract` passes for all 25 manifests (SKN-14).
- [x] Selecting `open`, `visor`, and `hood` toggles `Visor.visible` and `Hood.visible` on the manifest player rig (SKN-03, SKN-15).
- [ ] Toggling first person and back leaves `Visor`/`Hood` visibility unchanged (SKN-04).
- [ ] Each boss id renders with a bounding box differing from `castle_grunt`'s biome biped by >25% on at least two axes (SKN-01, SKN-02).
- [ ] `crystal_bat` and `crystal_wisp` have no leg pivots (SKN-01).
- [ ] `crystal_slime`, `swamp_leech`, `swamp_swarm`, `swamp_toad` have no arm or leg pivots (SKN-01).
- [ ] `theme_for_enemy_id("boss_frost_warlord")` returns `PaletteTheme.FROZEN` (SKN-05).
- [ ] `validate_rig` returns empty for every built rig; bind logs on violation (SKN-07).
- [ ] `feet_local_y` returns non-zero for flyers when implemented (SKN-06).
- [ ] Equipping `castle_plate`, `castle_helm`, `castle_boots`, `castle_gauntlets`, and `castle_buckler` each adds a visible overlay (SKN-13).
- [ ] Box-fallback player build allocates one `body` and one `accent` instance (SKN-11).

## Validation

**Existing** — `apps/game/client/scripts/validation/suites/diorama_anim_suite.gd`:

| Assertion id | Checks | Status |
|--------------|--------|--------|
| `diorama_anim.rig_contract` | Every manifest builds, satisfies `VoxelGrid.REQUIRED_PIVOTS`, clip tracks resolve, no `BoxMesh`, uniform scale | DONE |
| `diorama_anim.authored_libraries` | `.res` animation libraries present per profile | DONE |

**To extend** — same suite or new `character_rig_suite.gd` (`M7.graphics.rig`):

| Assertion id | Checks | Gap |
|--------------|--------|-----|
| `character_rig.profiles_resolve` | Every enemy/boss JSON `rig_profile` (or fallback) maps to a manifest | SKN-02 |
| `character_rig.theme_resolves_to_biome` | `theme_for_enemy_id(id) == PixelStyle.theme_from_biome(def["biome"])` | SKN-05 |
| `character_rig.silhouette_distinct` | No two archetype AABBs match within 5% on all axes | SKN-01 |
| `character_rig.head_style_distinct` | Visible mesh set differs across three head styles | SKN-03 |
| `character_rig.first_person_restore` | `Visor`/`Hood` visibility unchanged after FP toggle | SKN-04 |
| `character_rig.equipment_visuals` | Items with `visual` attach `EquipVisual_*` nodes | SKN-13 |

Run: `powershell -File scripts/godot-bin.ps1 --headless --path apps/game/client --script res://scripts/validation/validation_main.gd -- --suite=diorama_anim_suite`

Manual checklist:
- Hound gait reads as a trot at `move_speed: 5.5` (SKN-09).
- Boss silhouettes legible at 480×270 from default third-person camera (SKN-01).

## Related
- Current behavior: [`../existing_codebase/diorama-character-skin.md`](../existing_codebase/diorama-character-skin.md)
- [`character-authoring.md`](character-authoring.md), [`character-appearance.md`](character-appearance.md)
- [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-anim-controller.md`](diorama-anim-controller.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`diorama-weapon-kit.md`](diorama-weapon-kit.md)
- [`material-flash.md`](material-flash.md), [`material-dissolve.md`](material-dissolve.md), [`pixel-style.md`](pixel-style.md), [`character-floor-snap.md`](character-floor-snap.md), [`enemies.md`](enemies.md), [`bosses.md`](bosses.md)
- Rollups: [`ARCHITECTURE.md`](../ARCHITECTURE.md), [`00-QUALITY-BAR.md`](00-QUALITY-BAR.md), [`00-PLACEHOLDER-INVENTORY.md`](../existing_codebase/00-PLACEHOLDER-INVENTORY.md)
