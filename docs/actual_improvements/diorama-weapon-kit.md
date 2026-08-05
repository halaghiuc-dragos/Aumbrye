# Diorama weapon kit — improvement plan

## Current state

`DioramaWeaponKit.build` returns one of four box silhouettes — blade-and-crossguard, pole-and-head, bow, shield plate — for 8 weapon definitions and 19 weapon-bearing items. Three of the six `match` arms are the same `_build_sword` call at different scales (`:38-43`), `shield` has no reachable caller, and any unrecognized id falls through to the plain sword (`:52-53`). Colors are hardcoded and theme-independent except for accent parts. See [`../existing_codebase/diorama-weapon-kit.md`](../existing_codebase/diorama-weapon-kit.md).

Whether weapons should eventually be authored assets rather than box assemblies belongs to [`character-authoring.md`](character-authoring.md). This plan makes the current box kit complete, data-driven, honest about archetype, and consistent with the gameplay hitbox profiles that already exist per archetype.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| WKT-01 | P0 | The `axe` and `staff` archetypes have no kit and fall through to `_build_sword(theme, 0.62, 0.09)`. Both are first-class archetypes in gameplay: `weapon_controller._apply_hitbox_profile` gives `axe` a 1.4 x 0.9 x 1.5 hitbox at 0.75 m and `staff` a 0.8 x 0.7 x 2.0 hitbox at 1.1 m, so a staff strikes 2 m ahead while displaying a 0.62 m sword. | `:52-53`; `weapon_controller.gd:547-552`; `content/weapons/axe.json:4`, `content/weapons/staff.json:4` |
| WKT-02 | P0 | Three shipped items render as an unrelated weapon: `war_hammer` (`weaponId: axe`), `sage_staff` and `cathedral_arcane_staff` (`weaponId: staff`) all appear as the plain sword. | `content/items/equipment/war_hammer.json:15`, `sage_staff.json:15`, `cathedral_arcane_staff.json:16`; `:52-53` |
| WKT-03 | P0 | Unknown ids are silently rewritten to a sword. A typo in `weapon_kit` or a new archetype produces a plausible-looking wrong weapon with no warning. | `:52-53` |
| WKT-04 | P1 | Eight distinct sword-class items share one identical mesh: `iron_sword`, `crystal_shard_blade`, `castle_sword`, `mythic_blade`, `flame_sword`, `frost_glacier_sword`, `knight_blade`, `frost_warlord_blade`. Rarity, element, and tier have no visual expression. | `:35-53` switches on kit id only |
| WKT-05 | P1 | `_build_shield` is unreachable: no live call site resolves to `"shield"`, and the off-hand items `castle_buckler` and `mythic_aegis` have no `weaponId` and are never mounted. The `shield` rig profile carries its own intrinsic `Shield` box instead. | `:48-49`; `diorama_character_skin.gd:413-417`; the four call sites pass archetypes or `bow`/`greatsword`/`sword`/`""` |
| WKT-06 | P1 | The kit's silhouette has no relationship to the archetype's hitbox reach. `greatsword` swings a 1.8 m-deep hitbox with a 0.95 m blade; `dagger` a 0.9 m hitbox with a 0.34 m blade. Nothing keeps them in step. | `:39-43`; `weapon_controller.gd:534-558` |
| WKT-07 | P1 | Trail and impact VFX anchor on `Facing/WeaponPivot/Hitbox`, a gameplay node with no connection to the rendered kit, so a swing trail does not follow the visible blade. Kits expose no tip marker to anchor against. | `vfx_service.gd:69-81`; `player_anim_director.gd:288-292`; `castle_enemy_base.gd:135-137` |
| WKT-08 | P1 | Blade and grip colors are hardcoded constants, so a weapon's steel is identical in every biome and carries no material or element identity. Only `Guard`, `Pommel`, `Collar`, bow `Grip`, and the shield accents follow the palette. | `:12-14`, `:67-70` |
| WKT-09 | P1 | Only `spear` gets a mount transform; every other kit hangs straight down from the hand. A bow on a rig without a `Bow` pivot (that is, on the player) mounts to the bare hand mount pointing down. | `diorama_character_skin.gd:245-256`, `:407-412` |
| WKT-10 | P1 | Five of the six `ARCHETYPE_ALIASES` entries are unreachable, and `training_sword` names nothing in the repo. The `weapon_kit` key that `castle_enemy_base` reads does not appear in any `content/` file, so every enemy falls back to `_default_weapon_for_profile()` and `caster`/`beast`/`hound` carry nothing. | `:17-24`; `castle_enemy_base.gd:119`, `:124-132` |
| WKT-11 | P2 | Kit dimensions are absolute, so a 0.95 m greatsword on a hound or a scaled-down rig is proportionally wrong; nothing scales the kit by the wielder's bulk. | `:39`; `diorama_character_skin.gd:107` |
| WKT-12 | P2 | `weapon_kit_id` meta is written on every kit root and never read anywhere in the repo. | `:59` |
| WKT-13 | P2 | Weapons are always drawn. There is no sheathed or holstered position, so an idle character in the hub holds a bare blade. | `diorama_character_skin.gd:230-259` mounts to `WeaponMount` only |

## Target design

### 1. Kits described by data, built by one generic assembler

Replace the `match` in `build` with a lookup into a new `content/weapons/kits.json`, so adding a silhouette is a content change and an unknown id is an error rather than a sword.

```json
{
  "axe": {
    "silhouette": "haft_head",
    "parts": [
      {"name": "Grip",  "size": [0.075, 0.16, 0.075], "pos": [0, 0.02, 0],      "material": "grip"},
      {"name": "Haft",  "size": [0.07, 0.68, 0.07],   "pos": [0, -0.40, 0],     "material": "wood"},
      {"name": "HeadPlate", "size": [0.06, 0.30, 0.22], "pos": [0.09, -0.66, 0], "material": "steel"},
      {"name": "HeadBeard", "size": [0.05, 0.14, 0.10], "pos": [0.14, -0.56, 0], "material": "steel"},
      {"name": "Butt",  "size": [0.05, 0.12, 0.09],   "pos": [-0.07, -0.66, 0], "material": "accent"},
      {"name": "Collar","size": [0.10, 0.06, 0.10],   "pos": [0, -0.72, 0],     "material": "accent"}
    ],
    "tip": [0.0, -0.86, 0.0],
    "mount": {"pos": [0.02, -0.02, 0.0], "rot_deg": [0, 0, 0]},
    "reach_m": 0.9
  }
}
```

`build(weapon_id, theme, context)` resolves the id, loads the entry, and calls a single `_assemble(entry, theme)` that walks `parts` and calls `PixelStyle.add_box`. An id with no entry gets `push_warning` plus a visually obvious fallback: a magenta `Node3D` named `WeaponMissing` with a single 0.1 x 0.5 x 0.1 box, so a missing kit is caught in the first playtest instead of masquerading as a sword. Closes WKT-03.

Rejected alternative: keeping the GDScript builders and adding two more functions. That fixes WKT-01 in ten lines but leaves every future weapon a code change, and leaves no place to express rarity or element variants.

### 2. Per-weapon silhouette specs

All parts are on the 0.02 m grid used by the bodies (`diorama_weapon_kit.gd:6-7`). `tip` is a `Marker3D` named `Tip` at the far end of the striking surface, used by section 4. `reach_m` is the distance from the mount to `Tip` and must match the archetype's hitbox depth within 20 percent (section 5).

| Kit | Silhouette | Parts | Overall | `reach_m` | Mount |
|-----|-----------|-------|---------|----------|-------|
| `dagger` | blade-and-guard, 0.34 m blade, 0.07 m wide | `Grip`, `Guard`, `Blade`, `Fuller`, `Pommel` | 0.53 m | 0.53 | identity |
| `sword` | blade-and-crossguard, 0.62 m blade, 0.09 m wide | as today | 0.81 m | 0.81 | identity |
| `greatsword` | 1.05 m blade, 0.14 m wide, two-hand grip 0.26 m, ricasso block below the guard | `Grip`, `GripLower`, `Guard`, `Ricasso`, `Blade`, `Fuller`, `Pommel` | 1.35 m | 1.35 | `rot_deg` `(0, 0, 6)` so the long blade clears the shin |
| `axe` | offset head on a haft: asymmetric mass on `+X`, bearded lower edge, counterweight butt | `Grip`, `Haft`, `HeadPlate`, `HeadBeard`, `Butt`, `Collar` | 0.86 m | 0.90 | `(0.02, -0.02, 0)` |
| `hammer` (new kit id) | square head, no cutting edge; `war_hammer` maps here instead of `axe` | `Grip`, `Haft`, `HeadBlock` 0.20 x 0.22 x 0.20, `HeadFace` accent, `Spike`, `Butt` | 0.84 m | 0.90 | `(0.02, -0.02, 0)` |
| `spear` | pole-and-head, 1.45 m shaft | as today | 1.75 m | 1.68 | `(0.04, -0.12, -0.22)`, `rot_deg` `(82, 0, 2)` |
| `staff` | long shaft with a crowning emissive orb and two binding rings; no blade | `Grip`, `Shaft` 0.06 x 1.55 x 0.06, `RingUpper`, `RingLower`, `Crown` 0.13 x 0.13 x 0.13 emissive, `Ferrule` | 1.85 m | 1.90 | `rot_deg` `(75, 0, 0)` so the crown leads on a thrust |
| `bow` | riser, two limbs, string | as today | 0.94 m tall | 1.0 | `rot_deg` `(0, 0, 90)` when mounted to a hand rather than a `Bow` pivot, so the limbs run vertical and the string faces forward |
| `shield` | plate, boss, two rims | as today | 0.62 x 0.50 | — | `ShieldMount`, `rot_deg` `(0, 0, 0)` |
| `buckler` (new kit id) | small round-read plate 0.36 x 0.34, single central boss | `Plate`, `Boss`, `Rim` | 0.36 | — | `ShieldMount` |

`ARCHETYPE_ALIASES` is deleted and replaced by an `aliases` block in `kits.json` populated from actual content ids, so an alias that names nothing fails the validation suite instead of sitting dead. Closes WKT-01, WKT-02, WKT-05, WKT-10, and the silhouette half of WKT-06.

### 3. Rarity, element, and tier expression

Each kit entry gains a `variants` block keyed on the item's rarity band and elemental damage type, applied as additive parts and material overrides rather than separate silhouettes:

```json
"variants": {
  "rarity": {
    "rare":     {"add": [{"name": "InlayA", "size": [0.02, 0.34, 0.05], "pos": [0, -0.42, 0.02], "material": "accent"}]},
    "epic":     {"add": ["InlayA", "InlayB"], "material_overrides": {"steel": "steel_bright"}},
    "legendary":{"add": ["InlayA", "InlayB", "CrownGem"], "emissive": {"part": "CrownGem", "energy": 1.2}}
  },
  "element": {
    "fire":  {"tint": {"steel": [0.86, 0.52, 0.30], "accent": [1.0, 0.62, 0.24]}, "emissive_part": "Fuller"},
    "frost": {"tint": {"steel": [0.72, 0.86, 0.94], "accent": [0.62, 0.86, 1.0]}, "emissive_part": "Fuller"},
    "poison":{"tint": {"steel": [0.66, 0.82, 0.52], "accent": [0.58, 0.90, 0.40]}, "emissive_part": "Fuller"},
    "arcane":{"tint": {"steel": [0.78, 0.70, 0.94], "accent": [0.74, 0.56, 1.0]}, "emissive_part": "Crown"}
  }
}
```

`build` receives the item's `rarity` and damage type from the caller (`attach_weapon` gains a `context: Dictionary` argument populated by `WeaponController` from the equipped item), so `flame_sword` and `frost_glacier_sword` differ at a glance: the same silhouette with a tinted fuller that glows. `iron_sword` stays plain. This closes WKT-04 without needing eight hand-built meshes.

### 4. Tip marker and VFX anchoring

Every kit gains a `Marker3D` named `Tip` at its `tip` coordinate. `VfxService.resolve_combat_anchor` gains a preferred lookup order: the wielder's `WeaponMount/Weapon/Tip`, then `Facing/WeaponPivot/Hitbox`, then the current fallbacks. Swing trails then start at the visible blade tip and inherit its motion. Closes WKT-07. The kit part names stay unkeyed by animation; the whole kit still moves with the arm.

### 5. Material ownership rules for kits

`PixelStyle.make_material` caches by color string in `_prop_material_cache` (`pixel_diorama_style.gd:407-409`, `:418`) and `make_accent_material` caches per theme (`:313-319`). Every sword in the process therefore shares one steel material instance. The rules the kit assembler must follow:

- **Shared cached materials are read-only.** Anything that needs to mutate a uniform (element tint, rarity brightness, dissolve, flash) duplicates first. This is the same rule stated in [`diorama-character-skin.md`](diorama-character-skin.md) and [`material-flash.md`](material-flash.md).
- **Base parts with no variant treatment use the cached instance directly**, so the common case allocates nothing.
- **A part carrying a variant tint gets exactly one duplicate per kit instance**, created by the assembler and reused for every part sharing that material slot within the kit.
- **Emissive variant parts use `make_glow_material`**, which is not cached (`pixel_diorama_style.gd:354-367`), so it already yields a fresh instance per part.
- **The assembler never writes `flash_amount` or `dissolve_clip`**; those slots belong to `MaterialFlash` and `MaterialDissolve`.

### 6. Wielder scaling and sheathing

`build` takes the wielder's height scale from the rig (`diorama_character_skin.gd:107`) and multiplies every part position and size by it, clamped to `[0.75, 1.4]`, so a scaled rig carries a proportional weapon. Closes WKT-11.

`attach_weapon` gains a `sheathed` flag. When set, the kit is parented to a new `Sheath` pivot on `Torso` at `(0.14, -0.06, 0.10)` with `rot_deg` `(12, 0, 24)` for blades and `(0, 0, 0)` on the back for polearms and bows, and unparented back to `WeaponMount` when combat starts. The hub uses sheathed; runs use drawn. Closes WKT-13. `weapon_kit_id` meta is read by the sheath logic to pick the sheath transform, which closes WKT-12.

## Work plan

1. **Add `axe` and `staff` builders and a `hammer` kit id; point `war_hammer` at `hammer`; warn and build `WeaponMissing` on an unknown id** — the smallest change that ends the three shipped weapons pretending to be swords. Closes WKT-01, WKT-02, WKT-03.
2. **Introduce `content/weapons/kits.json` plus `_assemble`, and port all existing kits to it, deleting the per-kit builder functions and `ARCHETYPE_ALIASES`** — behavior-identical port verified by comparing box counts, sizes, and positions against the current builders. Closes WKT-10.
3. **Add `Tip` markers to every kit entry and extend `VfxService.resolve_combat_anchor` to prefer them** — closes WKT-07.
4. **Add `reach_m` per kit and a validation assertion against `weapon_controller._apply_hitbox_profile`; adjust `greatsword` to a 1.05 m blade and `dagger` reach so the two agree** — closes WKT-06.
5. **Add per-kit `mount` transforms to `kits.json` and move the hardcoded spear transform out of `attach_weapon`; add the bow's hand-mount rotation** — closes WKT-09.
6. **Add the `buckler` kit and route off-hand items to `ShieldMount` through a new `attach_offhand`; map `castle_buckler` to `buckler` and `mythic_aegis` to `shield`** — closes WKT-05.
7. **Add the `variants` block, thread rarity and element context from `WeaponController` into `attach_weapon` and `build`, and implement the duplicate-on-variant material rule** — closes WKT-04 and WKT-08.
8. **Scale kits by the wielder's height scale** — closes WKT-11.
9. **Add the `Sheath` pivot and the `sheathed` flag, driven by hub versus run context** — closes WKT-13 and WKT-12.

Steps 1-6 each leave every weapon renderable. Step 7 degrades gracefully: an item with no rarity or element context builds the base kit.

## Data and schema changes

- New file `content/weapons/kits.json` with the shape in section 1, plus a top-level `aliases` map. New schema `content/schemas/weapon_kits.schema.json` requiring `silhouette`, `parts` (each with `name`, `size`, `pos`, `material`), `tip`, `mount`, and `reach_m`, with `variants` optional.
- `content/items/equipment/war_hammer.json` — `weaponId` changes from `axe` to a new `content/weapons/hammer.json` with `archetype: "hammer"`, and `weapon_controller._apply_hitbox_profile` gains a `hammer` case matching the current `axe` numbers. Existing `content/schemas/weapon.schema.json` must accept the new archetype value.
- `content/items/equipment/castle_buckler.json` and `mythic_aegis.json` gain `offhandKit: "buckler"` / `"shield"`. Schema `content/schemas/item.schema.json` gains the optional `offhandKit` key.
- No save-format change; equipment ids and weapon ids are unchanged except `war_hammer`'s `weaponId`, which is resolved at load time and not persisted, so no `save_migrator.gd` bump is required.

## Acceptance criteria

- [ ] An equipped `axe` renders a haft with an offset head; an equipped `staff` renders a long shaft with a crowning orb. Neither shows a crossguard.
- [ ] `war_hammer` renders a hammer, `sage_staff` and `cathedral_arcane_staff` render staffs.
- [ ] Building an unknown weapon id logs a warning and produces a visually obvious `WeaponMissing` marker, not a sword.
- [ ] Every archetype in `content/weapons/*.json` has a `kits.json` entry, and every alias in `kits.json` names an id that exists in `content/`.
- [ ] For every archetype, the kit's `reach_m` is within 20 percent of the hitbox depth `weapon_controller._apply_hitbox_profile` assigns to it.
- [ ] A swing trail originates at the kit's `Tip` node position, verified by comparing the emitted VFX position against `Tip.global_position` within 0.05 m.
- [ ] `castle_buckler` and `mythic_aegis` appear on the character's `ShieldMount` when equipped.
- [ ] `flame_sword`, `frost_glacier_sword`, and `iron_sword` are visually distinguishable at the 480x270 internal resolution while sharing the sword silhouette.
- [ ] A bow equipped on a rig without a `Bow` pivot is oriented with its limbs vertical and its string facing forward.
- [ ] No kit writes to a cached `ShaderMaterial`: after building 50 kits of mixed elements, the cached steel material's `color_base` is unchanged.
- [ ] A rig with a 0.8 height scale carries a proportionally scaled weapon.
- [ ] A character in the hub has its weapon on a `Sheath` pivot, and it moves to `WeaponMount` on entering a run.

## Validation

New suite `apps/game/client/scripts/validation/suites/weapon_kit_suite.gd`, category `graphics`, following the structure of `diorama_anim_suite.gd`:

- `weapon_kit.kits_json_valid` — `kits.json` parses and validates against `weapon_kits.schema.json`.
- `weapon_kit.archetype_coverage` — for every `archetype` value in `content/weapons/*.json`, assert `kits.json` has an entry. Fails today for `axe` and `staff`.
- `weapon_kit.item_weapon_ids_resolve` — for every `weaponId` in `content/items/equipment/*.json`, resolve to a weapon, then to a kit, and assert the kit id is not the sword fallback unless the archetype is a sword class. Fails today for `war_hammer`, `sage_staff`, `cathedral_arcane_staff`.
- `weapon_kit.aliases_name_real_ids` — every key in the `aliases` block exists as a weapon id, an item id, or an archetype. Fails today for `training_sword`.
- `weapon_kit.unknown_id_warns` — `build("not_a_weapon", theme)` returns a node named `WeaponMissing` and records one warning.
- `weapon_kit.reach_matches_hitbox` — for every archetype, assert `abs(reach_m - hitbox_depth) / hitbox_depth <= 0.2` using the numbers from `_apply_hitbox_profile`.
- `weapon_kit.tip_marker_present` — every built kit has a `Tip` child whose local position equals the entry's `tip` within 1e-4.
- `weapon_kit.grid_aligned` — every part position and size component is a multiple of 0.005 m, so nothing lands off the pixel grid at the shipped internal resolution.
- `weapon_kit.no_cached_material_mutation` — record `color_base` on the cached steel and accent materials, build one kit of every id and every element variant, and assert both are unchanged.
- `weapon_kit.variant_duplicates_bounded` — building a fully variant-tinted legendary kit creates at most one duplicate `ShaderMaterial` per distinct material slot in that kit.
- `weapon_kit.mount_transform_applied` — for `spear`, `staff`, `greatsword`, and hand-mounted `bow`, assert the mounted kit's local rotation equals the entry's `mount.rot_deg` within 1e-3 rad.
- `weapon_kit.offhand_items_mount` — `castle_buckler` and `mythic_aegis` produce a kit parented to `ShieldMount`.
- `weapon_kit.silhouette_distinct` — for each pair of kit ids, assert their part-count-plus-bounding-box signatures differ, so no two archetypes render identically. Fails today for `sword`/`axe`/`staff`.

Manual checklist:
- Each archetype is identifiable from its silhouette alone in a single frame at 480x270, with the palette accent removed.
- Element-tinted weapons read as the same weapon family, not as a different weapon.

## Related
- Current behavior: [`../existing_codebase/diorama-weapon-kit.md`](../existing_codebase/diorama-weapon-kit.md)
- Authored props and characters decision: [`character-authoring.md`](character-authoring.md)
- [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`diorama-anim-library.md`](diorama-anim-library.md)
- [`weapons.md`](weapons.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`content-data.md`](content-data.md), [`pixel-style.md`](pixel-style.md), [`vfx-service.md`](vfx-service.md), [`validation-suites.md`](validation-suites.md)
