# Diorama weapon kit

Builds the hand-held weapon meshes mounted on character rigs. It is on the live play path: `DioramaCharacterSkin.attach_weapon` is its only builder caller (`diorama_character_skin.gd:454`, `:466`), reached from `DioramaAnimController.set_weapon` and `_finish_bind` (`diorama_anim_controller.gd:111-112`, `:191-198`). Every weapon is a runtime box assembly; there are no weapon mesh or texture assets under `apps/game/client/assets/`.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/art/props/diorama_weapon_kit.gd` | 269 lines: `KNOWN_KITS`, `ARCHETYPE_ALIASES`, `resolve_id`, `has_kit`, `build`, nine builder functions |
| `apps/game/client/scripts/art/characters/diorama_character_skin.gd` | Sole caller; mounts the kit and applies per-kit mount transforms |
| `apps/game/client/scripts/art/style/pixel_diorama_style.gd` | `add_box`, `make_material`, `make_accent_material` |
| `apps/game/client/scripts/art/characters/voxel_grid.gd` | `EDGE := 0.04` â€” axe, staff, and unknown kits size parts in multiples of this constant |

## How it works

Entry point: `DioramaWeaponKit.build(weapon_id, theme)` (`diorama_weapon_kit.gd:70-97`).

1. `resolve_id(weapon_id)` (`:53-63`) maps the incoming id to a kit id:
   - If `ARCHETYPE_ALIASES` has `weapon_id`, return the alias (`:54-55`).
   - Else if `archetype` argument is non-empty, return `archetype` (`:56-57`) â€” unused from `build`, which calls `resolve_id(weapon_id)` with no archetype (`:71`).
   - Else load `content/weapons/<weapon_id>.json` via `ContentLoader.load_json` and return its `archetype` when present (`:58-62`).
   - Else return `weapon_id` unchanged (`:63`).
2. `match kit_id` (`:72-97`) dispatches to a builder. Unknown ids log one `push_warning` per distinct id (`:94-96`, `_warned_unknown` at `:50`) and return `_build_unknown(theme)` â€” not a sword.
3. Each builder returns a `Node3D` root named `Weapon` with meta `weapon_kit_id` set to the resolved kit name (`:100-104`).

`has_kit(kit_id)` (`:66-67`) returns whether `kit_id` is in `KNOWN_KITS` (`:17-19`: `sword`, `greatsword`, `dagger`, `spear`, `bow`, `shield`, `axe`, `staff`, `unknown`).

### Kit silhouettes

| Kit id | Builder | Boxes | Silhouette |
|--------|---------|-------|------------|
| `sword` | `_build_sword(theme, 0.62, 0.09)` (`:73-74`) | 5 | `Grip`, `Guard`, `Blade`, `Fuller`, `Pommel` â€” blade hangs on `-Y` |
| `greatsword` | `_build_sword(theme, 0.95, 0.13)` (`:75-76`) | 5 | same five parts, longer/wider blade |
| `dagger` | `_build_sword(theme, 0.34, 0.07)` (`:77-78`) | 5 | same five parts, short blade |
| `spear` | `_build_spear(theme)` (`:79-80`) | 4 | `Grip`, `Shaft` 1.45 m, `Head`, `Collar` (`:231-239`) |
| `bow` | `_build_bow(theme)` (`:81-82`) | 5 | `Riser`, `LimbUpper`, `LimbLower`, `String`, `Grip` (`:243-255`) |
| `shield` | `_build_shield(theme)` (`:83-84`) | 4 | `Plate`, `Boss`, `RimTop`, `RimBottom` (`:258-267`) |
| `axe` | `_build_axe(theme)` (`:85-86`) | 3 | `Haft`, `Head`, `Collar` on `VoxelGrid.EDGE` grid (`:154-181`) |
| `staff` | `_build_staff(theme)` (`:87-88`) | 3 | `Shaft`, `Focus`, `Grip` on `VoxelGrid.EDGE` grid (`:184-210`) |
| `unknown` | `_build_unknown(theme)` (`:89-90`, `:93-97`) | 2 | `Stub`, `Mark` â€” obvious fallback, not a weapon silhouette (`:213-227`) |
| `""` | returns `null` (`:91-92`) | 0 | nothing mounted |

Three sword-class kits share `_build_sword` at different scales, so there are **six distinct silhouettes** in play: blade-and-crossguard (three scales), pole-and-head, bow, shield plate, haft-and-head (axe), and staff-with-focus.

Blades hang down the `-Y` axis of the mount (`:107-108`). Steel and grip colors are hardcoded: `BLADE_STEEL`, `BLADE_DARK`, `GRIP_LEATHER` (`:13-15`). Only accent parts (`Guard`, `Pommel`, `Collar`, bow `Grip`, shield `Boss`/rims, staff `Focus`, axe `Collar`) use `PixelStyle.make_accent_material(theme)`.

### Id resolution and live call sites

`ARCHETYPE_ALIASES` (`:22-48`) maps 25 content item ids and weapon ids onto kit ids, including `war_hammer` â†’ `axe`, `sage_staff` / `cathedral_arcane_staff` â†’ `staff`, and `castle_buckler` / `mythic_aegis` â†’ `shield`.

| Call site | Value passed as `weapon_id` |
|-----------|----------------------------|
| `player_anim_director.gd:774-778` | archetype string from `WeaponController.get_archetype()` (`weapon_controller.gd:169-170`), passed as both `weapon_id` and `archetype` to `set_weapon` |
| `player_anim_director.gd:173-175` (viewmodel) | archetype string only |
| `castle_enemy_base.gd:178` | `_data["weapon_kit"]` if present, else `_default_weapon_for_profile()` |
| `diorama_anim_controller.gd:111-112` | deferred apply of `_weapon_id` set earlier by `set_weapon` |

The key `weapon_kit` does not appear in any file under `content/` (only `castle_enemy_base.gd:178` reads it). Every enemy uses `_default_weapon_for_profile()` (`castle_enemy_base.gd:183-191`): `ranged` â†’ `"bow"`, `brute` â†’ `"greatsword"`, `caster`/`beast`/`hound` â†’ `""`, else â†’ `"sword"`.

Because the player path passes archetypes (`"axe"`, `"staff"`, etc.) and enemies pass those four literals, item-id aliases such as `iron_sword` â†’ `sword` are only exercised when something passes the item id directly (for example equipment preview or future `attach_weapon` callers). `training_sword` remains in `ARCHETYPE_ALIASES` (`:24`) but names no id in `content/`.

### Content coverage

**`content/weapons/*.json` (8 files)**

| Weapon id | `archetype` | Kit |
|-----------|------------|-----|
| `sword_basic`, `castle_sword` | `sword` | `sword` |
| `greatsword` | `greatsword` | `greatsword` |
| `dagger` | `dagger` | `dagger` |
| `spear` | `spear` | `spear` |
| `bow` | `bow` | `bow` |
| `axe` | `axe` | `axe` |
| `staff` | `staff` | `staff` |

**Weapon-bearing items** â€” 19 files under `content/items/equipment/` with a `weaponId`. Each `weaponId` points at a `content/weapons/` entry whose `archetype` selects the kit (or an alias overrides when the item id is passed directly). `war_hammer` (`weaponId: axe`, `war_hammer.json:15`), `sage_staff`, and `cathedral_arcane_staff` (`weaponId: staff`) now resolve to `axe` and `staff` kits respectively.

Eight sword-class items (`iron_sword`, `castle_sword`, `mythic_blade`, `flame_sword`, `frost_glacier_sword`, `knight_blade`, `frost_warlord_blade`, `crystal_shard_blade`) still share one `sword` mesh regardless of rarity or element.

Off-hand items `castle_buckler` and `mythic_aegis` have no `weaponId` and are never mounted. Aliases map their ids to `shield`, but `attach_weapon` only parents to `WeaponMount` (`diorama_character_skin.gd:454-484`). The `shield` profile's intrinsic `Shield` box on `ShieldMount` (`diorama_character_skin.gd:668-674`) is separate from `_build_shield`.

### Mount transforms

`attach_weapon` (`diorama_character_skin.gd:454-484`) after `build`:

- `bow`: if a `Bow` pivot exists, children are cleared and the kit parents there; otherwise a `Bow` pivot is created on `WeaponMount` (`:470-477`). Only the `ranged` profile pre-builds a decorative bow box on `Bow` (`:661-667`).
- `spear`: position `(0.04, -0.12, -0.22)`, rotation `(82Â°, 0, 2Â°)` (`:478-481`).
- Every other kit: identity transform at `WeaponMount`.
- On `ViewRoot`, shadow casting is disabled (`:482-483`).

Swing trails and hit VFX still anchor on `Facing/WeaponPivot/Hitbox` via `VfxService.resolve_combat_anchor` (`vfx_service.gd:115-127`); kits expose no `Tip` marker.

## Contracts

- **Kit root** â€” `Node3D` named `Weapon`, meta `weapon_kit_id` (string kit name).
- **Kit part names** â€” `Grip`, `Guard`, `Blade`, `Fuller`, `Pommel`, `Shaft`, `Head`, `Collar`, `Haft`, `Focus`, `Riser`, `LimbUpper`, `LimbLower`, `String`, `Plate`, `Boss`, `RimTop`, `RimBottom`, `Stub`, `Mark`. No `DioramaAnimLibrary` clip keys any part; the whole kit moves with the arm pivot.
- **Orientation** â€” melee blades and shields hang along `-Y` from the grip; spear shaft runs `+Y` before the caller rotates it; staff shaft runs `+Y` from grip.
- **`resolve_id`** â€” also read by `attach_weapon` for bow pivot retargeting (`diorama_character_skin.gd:468`).
- **JSON keys read indirectly** â€” `archetype` from `content/weapons/*.json` via `ContentLoader`; `weapon_kit` from enemy definitions (never present in content).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| All weapons are box assemblies; no weapon model or texture asset | PLACEHOLDER | `diorama_weapon_kit.gd:109-267`; no weapon mesh under `apps/game/client/assets/` |
| Six distinct silhouettes cover 8 weapon definitions and 19 weapon items | PLACEHOLDER | kit table above |
| `axe` and `staff` archetypes render dedicated kits | IMPLEMENTED | `diorama_weapon_kit.gd:85-88`, `:154-210`; `content/weapons/axe.json:4`, `staff.json:4` |
| Unknown ids warn once and render `unknown` stub, not a sword | IMPLEMENTED | `diorama_weapon_kit.gd:93-97`, `:213-227` |
| `war_hammer`, `sage_staff`, `cathedral_arcane_staff` render correct archetype kits | IMPLEMENTED | `ARCHETYPE_ALIASES` `:43-45`; content `weaponId` at `war_hammer.json:15`, `sage_staff.json:15`, `cathedral_arcane_staff.json:16` |
| `_build_shield` reachable only via alias; off-hand items never mounted | PARTIAL | `:83-84`, `:46-47`; `attach_weapon` has no `ShieldMount` path (`diorama_character_skin.gd:454-484`) |
| `training_sword` alias names nothing in `content/` | STUB | `diorama_weapon_kit.gd:24` |
| Kit geometry ignores rarity, tier, element, and item identity | PLACEHOLDER | `build` switches on kit id only (`:72-97`) |
| Blade and grip colors hardcoded; accent parts follow biome palette | PARTIAL | `diorama_weapon_kit.gd:13-15`; accent via `make_accent_material(theme)` |
| `weapon_kit_id` meta written and never read | STUB | `diorama_weapon_kit.gd:103`; no other reference in repo |
| Only `spear` has a per-kit mount transform | PARTIAL | `diorama_character_skin.gd:478-481` |
| Bow on non-`ranged` rig gets ad-hoc `Bow` pivot on hand mount | PARTIAL | `diorama_character_skin.gd:470-477`, `:661-667` |
| Kit reach unrelated to `weapon_controller._apply_hitbox_profile` depths | PARTIAL | hitbox at `weapon_controller.gd:669-699`; no `reach_m` on kits |
| VFX anchors on gameplay hitbox, not visible blade tip | PARTIAL | `vfx_service.gd:115-127` |
| Off-hand equipment (`castle_buckler`, `mythic_aegis`) has no visual | ABSENT | no `attach_offhand`; `ShieldMount` filled only by `shield` profile intrinsic box |
| No sheathed/holstered weapon pose | ABSENT | `attach_weapon` always mounts to `WeaponMount` |

## Related

- Improvement plan: [`../actual_improvements/diorama-weapon-kit.md`](../actual_improvements/diorama-weapon-kit.md) - **FINISHED**
- [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`diorama-anim-library.md`](diorama-anim-library.md)
- [`weapons.md`](weapons.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`content-data.md`](content-data.md), [`pixel-style.md`](pixel-style.md), [`vfx-service.md`](vfx-service.md)
- Authored props decision: [`character-authoring.md`](character-authoring.md)
- Cross-cutting: [`ARCHITECTURE.md`](../ARCHITECTURE.md), [`00-PLACEHOLDER-INVENTORY.md`](00-PLACEHOLDER-INVENTORY.md)
