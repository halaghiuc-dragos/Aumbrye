# Diorama weapon kit

Builds the hand-held weapon meshes mounted on character rigs. It is on the live play path: `DioramaCharacterSkin.attach_weapon` is its only caller (`diorama_character_skin.gd:242`, `:244`), reached from `DioramaAnimController.set_weapon` and `_finish_bind` (`diorama_anim_controller.gd:103`, `:140`). Every weapon in the game is boxes; there are no weapon models or textures in the repo.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/props/diorama_weapon_kit.gd` | 126 lines: alias table, `resolve_id`, `build`, six builder functions |
| `apps/game/client/scripts/art/characters/diorama_character_skin.gd` | Sole caller; mounts the kit and applies per-kit mount transforms |
| `apps/game/client/scripts/art/style/pixel_diorama_style.gd` | `add_box`, `make_material`, `make_accent_material` |

## Kit shapes

`build(weapon_id, theme)` (`:35-53`) resolves an id and matches it:

| Kit id | Builder | Boxes | Silhouette |
|--------|---------|-------|-----------|
| `sword` | `_build_sword(theme, 0.62, 0.09)` | 5 | `Grip` 0.063 x 0.16 x 0.063, `Guard` 0.234 x 0.05 x 0.099, `Blade` 0.09 x 0.62 x 0.036, `Fuller` 0.036 x 0.558 x 0.045, `Pommel` 0.081 x 0.06 x 0.081 |
| `greatsword` | `_build_sword(theme, 0.95, 0.13)` | 5 | same five parts scaled to a 0.95 m blade, 0.13 m wide |
| `dagger` | `_build_sword(theme, 0.34, 0.07)` | 5 | same five parts scaled to a 0.34 m blade, 0.07 m wide |
| `spear` | `_build_spear(theme)` | 4 | `Grip` 0.07 x 0.12 x 0.07, `Shaft` 0.07 x 1.45 x 0.07, `Head` 0.11 x 0.30 x 0.05, `Collar` 0.13 x 0.05 x 0.09 |
| `bow` | `_build_bow(theme)` | 5 | `Riser` 0.07 x 0.34 x 0.07, `LimbUpper`/`LimbLower` 0.06 x 0.30 x 0.06, `String` 0.02 x 0.92 x 0.02, `Grip` 0.09 x 0.06 x 0.09 |
| `shield` | `_build_shield(theme)` | 4 | `Plate` 0.10 x 0.62 x 0.50, `Boss` 0.05 x 0.16 x 0.16, `RimTop`/`RimBottom` 0.04 x 0.66 x 0.06 |
| `""` | returns `null` (`:50-51`) | 0 | nothing mounted |
| anything else | falls through to `_build_sword(theme, 0.62, 0.09)` (`:52-53`) | 5 | the plain sword |

Three of the six shapes are the same `_build_sword` call at different scales, so there are **four distinct silhouettes** in the game: blade-and-crossguard, pole-and-head, bow, and shield plate.

Every kit root is a `Node3D` named `Weapon` with `set_meta("weapon_kit_id", <name>)` (`:56-60`). Blades hang down the `-Y` axis of the mount, matching the hand mount at the bottom of the arm pivot (`:63-64`).

Colors are hardcoded and theme-independent: `BLADE_STEEL = Color(0.74, 0.78, 0.84)`, `BLADE_DARK = Color(0.34, 0.36, 0.42)`, `GRIP_LEATHER = Color(0.30, 0.20, 0.14)` (`:12-14`). Only the `accent` parts (`Guard`, `Pommel`, `Collar`, bow `Grip`, shield `Boss`/rims) use `PixelStyle.make_accent_material(theme)` and therefore track the biome palette.

## Id resolution

`resolve_id(weapon_id, archetype = "")` (`:27-32`):
1. If `ARCHETYPE_ALIASES` has `weapon_id`, return the alias.
2. Else if `archetype != ""`, return `archetype`.
3. Else return `weapon_id`.

`ARCHETYPE_ALIASES` (`:17-24`): `sword_basic` -> `sword`, `training_sword` -> `sword`, `training_greatsword` -> `greatsword`, `rogue_dagger` -> `dagger`, `hunter_bow` -> `bow`, `guard_spear` -> `spear`.

`build` calls `resolve_id(weapon_id)` with no archetype (`:36`), so only step 1 and step 3 can fire from `build`.

### What the live call sites actually pass

| Call site | Value passed as `weapon_id` |
|-----------|----------------------------|
| `player_anim_director.gd:264-265` | the **archetype** string from `WeaponController.get_archetype()` (`weapon_controller.gd:155-156`), passed as both `weapon_id` and `archetype` |
| `player_anim_director.gd:79` (viewmodel) | the archetype string, with `archetype` left empty |
| `castle_enemy_base.gd:119` | `_data["weapon_kit"]` if present, else `_default_weapon_for_profile()` |
| `training_grunt.gd:42` | the literal `"sword"` |

The key `weapon_kit` does not appear in any file under `content/` (grepped repo-wide: the only hits are the code at `castle_enemy_base.gd:119` and the meta name at `diorama_weapon_kit.gd:59`). So every enemy uses `_default_weapon_for_profile()` (`castle_enemy_base.gd:124-132`): `ranged` -> `"bow"`, `brute` -> `"greatsword"`, `caster`/`beast`/`hound` -> `""`, everything else -> `"sword"`.

Because the player path passes archetypes and the enemy path passes those four literals, **five of the six alias entries are unreachable in play**: nothing ever passes `sword_basic`, `training_sword`, `training_greatsword`, `rogue_dagger`, `hunter_bow`, or `guard_spear` to `resolve_id`. `training_sword` is not even an id that exists in `content/` — the greatsword item id is `training_greatsword` (`content/items/equipment/greatsword_item.json:2`) and there is no `training_sword` anywhere in the repo.

## Weapon ids in content versus kits

### `content/weapons/*.json` (8 files)

| Weapon id | `archetype` | Kit resolved from archetype | Dedicated mesh? |
|-----------|------------|---------------------------|-----------------|
| `sword_basic` | `sword` | `sword` | yes |
| `castle_sword` | `sword` | `sword` | yes |
| `greatsword` | `greatsword` | `greatsword` | yes |
| `dagger` | `dagger` | `dagger` | yes |
| `spear` | `spear` | `spear` | yes |
| `bow` | `bow` | `bow` | yes |
| `axe` | `axe` | falls through at `:52-53` | **no — renders as the plain sword** |
| `staff` | `staff` | falls through at `:52-53` | **no — renders as the plain sword** |

`axe` and `staff` are the only two archetypes with no kit. Both are first-class archetypes elsewhere: `DioramaAnimLibrary.WEAPON_ATTACKS` gives `axe` a heavy/light-3/heavy combo and `staff` a thrust/light-2/thrust combo (`diorama_anim_library.gd:425-426`), and `heavy_clip_for` special-cases `staff` (`diorama_anim_library.gd:441-442`). So an axe swings an axe combo while displaying a sword, and a staff thrusts while displaying a sword.

### Weapon-bearing items in `content/items/equipment/` (19 files with a `weaponId`)

Each item's `weaponId` points at a `content/weapons/` entry, whose `archetype` selects the kit.

| Kit rendered | Items |
|--------------|-------|
| `sword` (0.62 m blade) | `iron_sword`, `crystal_shard_blade` (via `sword_basic`); `castle_sword`, `mythic_blade`, `flame_sword`, `frost_glacier_sword`, `knight_blade`, `frost_warlord_blade` (via `castle_sword`) |
| `greatsword` | `training_greatsword` |
| `dagger` | `rogue_dagger`, `venom_dagger`, `swamp_toxin_dagger`, `cathedral_shadow_dagger` |
| `spear` | `guard_spear` |
| `bow` | `hunter_bow`, `crystal_bow` |
| **plain sword fallback** | `war_hammer` (`weaponId: axe`), `sage_staff` (`weaponId: staff`), `cathedral_arcane_staff` (`weaponId: staff`) |

So `war_hammer`, `sage_staff`, and `cathedral_arcane_staff` are the three shipped items that render as an unrelated generic box weapon. A further eight distinct sword-class items share one identical mesh regardless of rarity, element, or tier — `flame_sword`, `venom_dagger`, `frost_glacier_sword`, and `mythic_blade` have no visual difference from `iron_sword` or `rogue_dagger` beyond the biome accent color on the guard and pommel.

The remaining 44 files in `content/items/equipment/` have no `weaponId` (helms, plates, boots, gauntlets, rings, amulets, charms, cloaks, banners, chalices, crowns, `castle_buckler`, `mythic_aegis`). None of them has any visual representation on the rig: `attach_weapon` only ever mounts a weapon, and `_apply_player_appearance` only adds `BeltTrim`/`Pauldron` boxes from the `trim` appearance index (`diorama_character_skin.gd:127-151`), not from equipment.

## Mount transforms

`attach_weapon` (`diorama_character_skin.gd:230-259`) applies per-kit handling after `build`:

- `bow`: if a `Bow` pivot exists anywhere in the rig, its children are freed and the kit is parented there instead of to `WeaponMount` (`:245-252`). Only the `ranged` profile has a `Bow` pivot (`diorama_character_skin.gd:407-412`), so a player with a bow gets the bow parented to the bare hand mount.
- `spear`: position `(0.04, -0.12, -0.22)`, rotation `(82 deg, 0, 2 deg)` so the 1.45 m shaft points forward for thrusts (`:253-256`).
- Every other kit: identity transform at `WeaponMount`, i.e. hanging straight down from the hand.
- On `ViewRoot`, shadow casting is disabled on the kit (`:257-258`).

## Contracts

- **Kit root name** — `Weapon`, with meta `weapon_kit_id`.
- **Kit part names** — `Grip`, `Guard`, `Blade`, `Fuller`, `Pommel`, `Shaft`, `Head`, `Collar`, `Riser`, `LimbUpper`, `LimbLower`, `String`, `Plate`, `Boss`, `RimTop`, `RimBottom`. No clip in `DioramaAnimLibrary` keys any of them; the whole kit moves with the arm pivot.
- **Kit orientation** — blades and shields hang along `-Y` from the grip; the spear's shaft runs `+Y` and is rotated into place by the caller.
- **`resolve_id` is also read by the caller** to decide mount retargeting (`diorama_character_skin.gd:244`).
- **JSON keys read indirectly** — `archetype` from `content/weapons/*.json` via `WeaponController.get_archetype()`; `weapon_kit` from enemy definitions (never present).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| All weapons are box assemblies; no weapon model or texture asset exists | PLACEHOLDER | `:65-125`; `apps/game/client/assets` contains no mesh or image asset besides `icon.svg` |
| Four distinct silhouettes cover 8 weapon definitions and 19 weapon items | PLACEHOLDER | table above |
| `axe` and `staff` archetypes silently render as the plain sword | BROKEN | `:37-53` has no `axe`/`staff` branch; `content/weapons/axe.json:4`, `content/weapons/staff.json:4` |
| `war_hammer`, `sage_staff`, `cathedral_arcane_staff` render as an unrelated sword | BROKEN | `content/items/equipment/war_hammer.json:15`, `sage_staff.json:15`, `cathedral_arcane_staff.json:16` |
| `_build_shield` has no reachable call site: nothing resolves to `"shield"` | STUB | `:48-49`; the four live call sites pass archetypes or the literals `bow`/`greatsword`/`sword`/`""` |
| 5 of 6 `ARCHETYPE_ALIASES` entries are unreachable; `training_sword` names nothing in the repo | STUB | `:17-24`; call-site table above |
| Kit geometry ignores rarity, tier, element, and item identity | PLACEHOLDER | `:35-53` switches on kit id only |
| Blade and grip colors are hardcoded and do not follow the biome palette | PARTIAL | `:12-14`, `:67-69`; only accent parts use `make_accent_material(theme)` |
| `weapon_kit_id` meta is written and never read | STUB | `:59`; no other reference in the repo |
| Only `spear` has a per-kit mount transform | PARTIAL | `diorama_character_skin.gd:253-256` |
| A bow on a non-`ranged` rig mounts to the bare hand instead of a bow pivot | PARTIAL | `diorama_character_skin.gd:245-252`, `:407-412` |
| Off-hand equipment (`castle_buckler`, `mythic_aegis`) has no visual | ABSENT | `attach_weapon` mounts to `WeaponMount` only; `ShieldMount` is populated only by the `shield` profile's intrinsic box (`diorama_character_skin.gd:413-417`) |
| Armor, helm, boot, glove, and jewelry items have no visual | ABSENT | `diorama_character_skin.gd:127-151` reads only the `trim` appearance index |

## Related
- Improvement plan: [`../actual_improvements/diorama-weapon-kit.md`](../actual_improvements/diorama-weapon-kit.md)
- [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-viewmodel.md`](diorama-viewmodel.md)
- [`weapons.md`](weapons.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`content-data.md`](content-data.md), [`pixel-style.md`](pixel-style.md)
- Cross-cutting decision on authored props and characters: [`character-authoring.md`](character-authoring.md)
