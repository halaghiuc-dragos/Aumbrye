# Diorama weapon kit — improvement plan

## Status: FINISHED

## Current state

`DioramaWeaponKit` ships nine kit ids (`sword`, `greatsword`, `dagger`, `spear`, `bow`, `shield`, `axe`, `staff`, `unknown`) built from runtime boxes. P0 correctness gaps are closed: `axe` and `staff` have dedicated silhouettes, `war_hammer` / `sage_staff` / `cathedral_arcane_staff` resolve to them, and unknown ids log `push_warning` once and render an `unknown` stub instead of masquerading as a sword. `resolve_id` loads `content/weapons/<id>.json` for archetype fallback; `ARCHETYPE_ALIASES` maps 25 item and weapon ids. Validation covers archetype coverage in `diorama_anim_suite.gd` and regression guards in `quality_bar_suite.gd`. Remaining presentation gaps (per-item variants, off-hand mounting, VFX tip markers, sheathing) stay PLACEHOLDER on the box-kit path — see [`../existing_codebase/diorama-weapon-kit.md`](../existing_codebase/diorama-weapon-kit.md).

Whether weapons should eventually be authored voxel assets rather than box assemblies belongs to [`character-authoring.md`](character-authoring.md). This plan's FINISHED scope is the quality-bar fix tracked as CHA-08 in that doc.

## Gaps

| ID | Sev | Gap | Evidence | Status |
|----|-----|-----|----------|--------|
| WKT-01 | P0 | `axe` and `staff` had no kit and fell through to `_build_sword(theme, 0.62, 0.09)` while gameplay hitboxes were 1.5 m and 2.0 m deep | `weapon_controller.gd:685-690`; `content/weapons/axe.json:4`, `staff.json:4` | **FINISHED** — `_build_axe`, `_build_staff` at `diorama_weapon_kit.gd:154-210` |
| WKT-02 | P0 | `war_hammer`, `sage_staff`, `cathedral_arcane_staff` rendered as the plain sword | `war_hammer.json:15`, `sage_staff.json:15`, `cathedral_arcane_staff.json:16` | **FINISHED** — aliases `:43-45` + archetype resolution `:58-62` |
| WKT-03 | P0 | Unknown ids silently became a sword with no warning | prior `:_` branch | **FINISHED** — `push_warning` `:94-96`, `_build_unknown` `:213-227` |
| WKT-04 | P1 | Eight sword-class items share one mesh; rarity/element/tier have no visual expression | `build` matches kit id only (`:72-97`) | **DEFERRED** — box-kit path; authored weapon voxels per [`character-authoring.md`](character-authoring.md) |
| WKT-05 | P1 | `_build_shield` unreachable from play; off-hand buckler/aegis never mounted | `attach_weapon` → `WeaponMount` only (`diorama_character_skin.gd:454-484`) | **DEFERRED** — `attach_offhand` tracked in [`diorama-viewmodel.md`](diorama-viewmodel.md) VMD-08 |
| WKT-06 | P1 | Kit silhouette reach unrelated to hitbox depth | `weapon_controller.gd:669-699` vs blade lengths in `_build_sword` | **DEFERRED** — accepted on box kits; tune when kits become data-driven |
| WKT-07 | P1 | VFX anchors on `Facing/WeaponPivot/Hitbox`, not visible blade | `vfx_service.gd:115-127` | **DEFERRED** — needs `Tip` markers; blocked on kit structure decision |
| WKT-08 | P1 | Blade/grip colors hardcoded; no element identity on steel | `diorama_weapon_kit.gd:13-15` | **DEFERRED** — variant tints belong with authored weapons |
| WKT-09 | P1 | Only `spear` has a per-kit mount transform; hand-mounted bow points down | `diorama_character_skin.gd:470-481` | **DEFERRED** — mount table when kits move to content |
| WKT-10 | P1 | Dead aliases and no content-driven archetype lookup | prior 6-entry alias table | **FINISHED** — 25-entry `ARCHETYPE_ALIASES` `:22-48`, `ContentLoader` archetype `:58-62`, `has_kit` `:66-67`, `diorama_anim.weapon_kit_coverage` |
| WKT-11 | P2 | Kit dimensions absolute; no wielder height scale | `diorama_character_skin.gd` height via manifests, not weapon scale | **DEFERRED** |
| WKT-12 | P2 | `weapon_kit_id` meta written and never read | `diorama_weapon_kit.gd:103` | **DEFERRED** — consumer is sheathing (WKT-13) |
| WKT-13 | P2 | Weapons always drawn; no hub sheathe pose | `attach_weapon` always uses `WeaponMount` | **DEFERRED** — hub polish; depends on sheath pivot design |

## Target design

### Shipped: expanded GDScript box kits (chosen)

Keep per-archetype builder functions in `diorama_weapon_kit.gd`. Adding a silhouette remains a code change, which is acceptable while all weapons are procedural boxes.

1. **`KNOWN_KITS` and `has_kit`** — explicit allow-list (`:17-19`, `:66-67`) so `diorama_anim_suite` can assert every `content/weapons/*.json` archetype resolves to a real kit.
2. **`ARCHETYPE_ALIASES`** — maps equipment item ids (and a few weapon ids) to kit ids so callers can pass either an archetype or an item id (`:22-48`).
3. **Content archetype fallback** — `resolve_id` loads `content/weapons/<weapon_id>.json` when no alias matches (`:58-62`), so `weaponId` chains work without duplicating every weapon id in the alias table.
4. **`_build_axe` / `_build_staff`** — voxel-grid-aligned haft/head and shaft/focus silhouettes (`:154-210`), distinct from `_build_sword`.
5. **`_build_unknown`** — two-box stub plus one-time `push_warning` (`:213-227`); closes the silent-sword failure mode.

Rejected alternative for this phase: `content/weapons/kits.json` plus a generic `_assemble` loader. That is the right end state for authored voxel weapons, but it is unnecessary overhead while every weapon is still boxes and no variant system consumes the data. Revisit when [`character-authoring.md`](character-authoring.md) adds weapon voxel manifests.

### Deferred: data-driven kits, variants, and presentation polish

When weapons leave the box-kit path, port silhouettes to `content/weapons/kits.json` with `parts`, `tip`, `mount`, `reach_m`, and optional `variants` for rarity/element. Wire `VfxService.resolve_combat_anchor` to prefer `WeaponMount/Weapon/Tip`. Add `attach_offhand` for `ShieldMount`, wielder scale, and hub sheathing. Details remain in the gap table above (WKT-04–WKT-09, WKT-11–WKT-13).

## Work plan

1. **Add `_build_axe`, `_build_staff`, and `_build_unknown`; warn on unknown ids** — `diorama_weapon_kit.gd`. Closes WKT-01, WKT-02, WKT-03. **Done.**
2. **Expand `ARCHETYPE_ALIASES`, add `has_kit`, load archetype from `content/weapons/*.json`** — `diorama_weapon_kit.gd`. Closes WKT-10. **Done.**
3. **Assert archetype coverage in validation** — `diorama_anim_suite.gd:_test_weapon_kit_coverage`, `quality_bar_suite.gd` CHA-08 guards. **Done.**

Steps 1–3 each leave every weapon renderable. Deferred gaps (WKT-04–WKT-09, WKT-11–WKT-13) stay documented as PLACEHOLDER surfaces in the existing-code doc until authored weapons or viewmodel off-hand work lands.

## Data and schema changes

None for the FINISHED scope. Equipment `weaponId` values are unchanged (`war_hammer` still points at `axe` in `war_hammer.json:15`). No save-format change; no `save_migrator.gd` bump.

Deferred work (not in this FINISHED scope) would add `content/weapons/kits.json`, `weapon_kits.schema.json`, optional `offhandKit` on equipment items, and a `hammer` archetype if `war_hammer` should diverge from `axe` visually.

## Acceptance criteria

- [x] An equipped `axe` renders a haft with an offset head; an equipped `staff` renders a long shaft with a focus orb. Neither shows a crossguard. (WKT-01)
- [x] `war_hammer`, `sage_staff`, and `cathedral_arcane_staff` render `axe` and `staff` kits, not the plain sword. (WKT-02)
- [x] Building an unknown weapon id logs a warning and produces the `unknown` stub mesh, not a sword. (WKT-03)
- [x] Every archetype in `content/weapons/*.json` has a kit entry verified by `diorama_anim.weapon_kit_coverage`. (WKT-10)
- [x] `quality_bar_suite` asserts `_build_axe`, `_build_staff`, and `_build_unknown` exist. (WKT-01, WKT-03)

Deferred criteria (WKT-04–WKT-09, WKT-11–WKT-13) are not asserted until the deferred design lands.

## Validation

| Suite | Test id | Assertions |
|-------|---------|------------|
| `diorama_anim_suite.gd` | `diorama_anim.weapon_kit_coverage` | For every `content/weapons/*.json`, `WeaponKit.resolve_id(weapon_id, archetype)` returns a kit id where `has_kit` is true (`:348-376`) |
| `quality_bar_suite.gd` | `quality.character.weapon_kit_expanded` | File contains `_build_unknown`, `_build_axe`, `_build_staff` (`:195-207`) |
| `quality_bar_suite.gd` | `quality.character.comment_cleanup` | No stale `0.02 m grid` comment; references `VoxelGrid.EDGE` (`:241-253`) |

Manual checklist (deferred presentation gaps):

- Each archetype silhouette is identifiable at 480×270 with accent parts neutralized (WKT-04, WKT-09).
- Swing trail origin matches visible blade tip within 0.05 m (WKT-07).

## Related

- Current behavior: [`../existing_codebase/diorama-weapon-kit.md`](../existing_codebase/diorama-weapon-kit.md)
- [`character-authoring.md`](character-authoring.md) — CHA-08 weapon-kit quality bar; future authored weapon voxels
- [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`diorama-anim-library.md`](diorama-anim-library.md)
- [`weapons.md`](weapons.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`content-data.md`](content-data.md), [`pixel-style.md`](pixel-style.md), [`vfx-service.md`](vfx-service.md), [`validation-suites.md`](validation-suites.md)
- [`00-QUALITY-BAR.md`](00-QUALITY-BAR.md), [`ARCHITECTURE.md`](../ARCHITECTURE.md)
