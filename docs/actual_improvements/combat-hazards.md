# Combat hazards — improvement plan

## Status: FINISHED

## Current state

Boss telegraphed zones and enemy projectiles correctly route through `Hurtbox.receive_hit`, so dodge i-frames and guard work. Environmental poison pools and poison DoT ticks bypass that pipeline entirely. Swamp "cleanse" zones are visual props with an unused `is_cleanse_active()` API. Hydra phase-2 pools spawn fire-styled `arena_hazard` while naming the function `_spawn_poison_pool`. Parent hazard `@export damage` values never reach the damaging child. See [`../existing_codebase/combat-hazards.md`](../existing_codebase/combat-hazards.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| HAZ-01 | P0 | `poison_hazard` applies status on body overlap — dodge i-frames do not block application | `poison_hazard.gd:35-40` vs `hurtbox.gd:37-39` |
| HAZ-02 | P0 | Poison DoT calls `Health.take_damage` directly — bypasses i-frames and guard | `status_controller.gd` tick path; `health.gd:29-36` |
| HAZ-03 | P1 | `swamp_cleanse_zone` has no collision and `is_cleanse_active()` is never called | `swamp_cleanse_zone.gd:29-30` |
| HAZ-04 | P1 | Hydra `_spawn_poison_pool` instantiates `arena_hazard.tscn` (direct trap damage), not poison | `swamp_hydra.gd:9`, `:148-155` |
| HAZ-05 | P1 | `@export damage` on arena/pillar hazards unused; hydra `set("damage", 6.0)` ineffective | `arena_hazard.gd:9`; `crystal_pillar_hazard.gd:9` |
| HAZ-06 | P2 | `trap_damage_area` uses `area_entered` only — no continuous overlap scan like `Hitbox` | `trap_damage_area.gd:15-33` vs `hitbox.gd:95-113` |
| HAZ-07 | P2 | Procgen `frost_trap` / `shadow_trap` ids map to poison pool / spike, not distinct types | `dungeon_builder.gd:507-512` |
| HAZ-08 | P2 | Poison pool detects bodies (mask 2); damage traps detect hurtboxes (mask 8) — inconsistent model | `poison_pool.tscn` vs spike/arena scenes |

## Target design

### One damage admission policy (HAZ-01, HAZ-02)

Chosen: **all player-harming effects admit through Hurtbox or an explicit shared gate**, so dodge/guard semantics stay one place.

1. Poison pool becomes an `Area3D` that overlaps the player Hurtbox (mask 8) and, on interval, calls a new `Hurtbox.try_apply_status(status_id, stacks, duration)` which:
   - returns early if dodge i-frames active (same check as `receive_hit`);
   - optionally respects guard (block = no status, or reduced duration — pick **block denies status** for clarity);
   - then calls `StatusController.apply_status`.
2. Status ticks that deal HP call `Hurtbox.receive_periodic_damage(amount, type)` (or reuse `receive_hit` with a `DamageInfo` flagged `periodic = true`) so i-frames still apply during a roll mid-tick. Defense applies; backstab does not.

Rejected: leaving poison as "environmental unavoidable" without documenting it — the projectile comment already promises i-frame rollability for ranged threats; pools should match unless a status JSON key `ignores_iframes: true` is set and shown in UI.

### Cleanse as real counterplay (HAZ-03, HAZ-04)

- Add `Area3D` to `swamp_cleanse_zone.tscn` (player body or hurtbox — body is enough for standing in the circle).
- While active: `clear_status("poison")` on overlap and set a short `cleanse_buff` / flag that `try_apply_status` rejects for `poison`.
- Hydra `_spawn_poison_pool` instantiates `poison_pool.tscn`. Keep `arena_hazard` only for knight slam fire zones.

### Damage export forwarding (HAZ-05)

In hazard `_ready`:

```gdscript
if _damage_area and _damage_area.get("damage") != null:
    _damage_area.damage = damage
    _damage_area.poise_damage = poise_damage  # if exported
```

Same pattern on spike/falling trap controllers (TRP-01).

### Overlap reliability (HAZ-06)

On transition to ACTIVE, after `monitoring = true`, call a one-shot scan of `get_overlapping_areas()` and run the same hit logic as `area_entered`. Matches Hitbox behaviour when the player is already standing in the telegraph.

### Trap id honesty (HAZ-07)

Until frost/shadow scenes exist: stop emitting those ids from `procgen_loot_tables`, or map them only after scenes ship. Prefer renaming table entries to `poison_pool` / `spike_trap` over silent aliases.

## Work plan

1. **`Hurtbox.try_apply_status` + periodic damage admission** — `hurtbox.gd`, `status_controller.gd`. Closes HAZ-01, HAZ-02.
2. **Retarget `poison_hazard` to hurtbox mask + try_apply_status** — `poison_hazard.gd`, `poison_pool.tscn`. Closes HAZ-08 for poison.
3. **Wire cleanse zone Area3D + clear/block poison** — `swamp_cleanse_zone.gd` / `.tscn`. Closes HAZ-03.
4. **Hydra spawns real poison pools; forward hazard damage exports** — `swamp_hydra.gd`, hazard scripts. Closes HAZ-04, HAZ-05.
5. **ACTIVE enter overlap scan on `trap_damage_area`** — `trap_damage_area.gd` + parent call, or scan helper. Closes HAZ-06.
6. **Fix procgen trap id table** — `procgen_loot_tables.gd` / builder map. Closes HAZ-07.

## Data and schema changes

| Change | File |
|--------|------|
| Optional `ignores_iframes` / `ignores_guard` on status definitions | `content/schemas` status schema + `content/statuses/poison.json` defaults `false` |
| No save format change | — |

## Acceptance criteria

- [ ] Dodging through a poison pool during i-frames does not apply poison. (HAZ-01)
- [ ] A poison tick that fires during i-frames deals 0 HP. (HAZ-02)
- [ ] Standing in an active cleanse zone clears poison and blocks re-application until the zone expires. (HAZ-03)
- [ ] Hydra phase-2 pools apply poison status (not arena fire damage 8). (HAZ-04)
- [ ] `hazard.damage = 6` before add_child results in child `trap_damage_area.damage == 6`. (HAZ-05)
- [ ] Player standing still in a telegraph when it goes ACTIVE takes damage within one physics frame. (HAZ-06)
- [ ] Procgen swamp corridors emit `poison_pool` (or a real frost scene), never a mislabeled alias without a matching scene. (HAZ-07)

## Validation

| Assertion id | Checks |
|--------------|--------|
| `haz.poison.blocked_by_iframes` | Force `iframes_active`, overlap poison, assert no status |
| `haz.poison.tick_respects_iframes` | Apply poison, force i-frames on tick, assert HP unchanged |
| `haz.cleanse.clears_and_blocks` | Poisoned player enters cleanse, assert clear + re-enter pool no reapply |
| `haz.hydra.spawns_poison_pool` | Call hydra spawn helper, assert instance script is `poison_hazard` |
| `haz.trap_area.active_scan` | Place hurtbox overlapping disabled area, enable monitoring + scan, assert hit |

## Related

- Existing state: [`../existing_codebase/combat-hazards.md`](../existing_codebase/combat-hazards.md)
- [`dungeon-traps.md`](dungeon-traps.md), [`bosses.md`](bosses.md) (BOS-03/04/09), [`dodge.md`](dodge.md), [`statuses-and-buffs.md`](statuses-and-buffs.md)
