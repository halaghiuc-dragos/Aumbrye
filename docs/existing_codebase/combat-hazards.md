# Combat hazards

Telegraphed boss zones, enemy projectiles, environmental poison pools, and swamp cleanse markers. On the live play path: boss kits spawn arena/pillar hazards and poison pools; archers fire `enemy_projectile`. Damage and status routing converge on `Hurtbox`: direct hits via `receive_hit`, poison via `try_apply_status`, DoT ticks via `receive_periodic_damage`.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/combat/poison_hazard.gd` | Poison pool: overlap → `Hurtbox.try_apply_status` |
| `apps/game/client/scripts/combat/trap_damage_area.gd` | Shared `Area3D` applicator: `DamageInfo` → `receive_hit` |
| `apps/game/client/scripts/combat/enemy_projectile.gd` | Ranged projectile; child `Hitbox` for damage |
| `apps/game/client/scripts/bosses/arena_hazard.gd` | Telegraph → ACTIVE → FADE fire-styled zone |
| `apps/game/client/scripts/bosses/crystal_pillar_hazard.gd` | Same lifecycle; crystal pillar visual |
| `apps/game/client/scripts/bosses/swamp_cleanse_zone.gd` | Visual countdown + poison clear on player overlap |
| `apps/game/client/scenes/bosses/arena_hazard.tscn` | Child `DamageArea` + `trap_damage_area` (damage 8, poise 5) |
| `apps/game/client/scenes/bosses/crystal_pillar_hazard.tscn` | Child `DamageArea` (damage 10, poise 8) |
| `apps/game/client/scenes/combat/enemy_projectile.tscn` | Projectile + Hitbox (`team = "enemy"`) |

## How it works

### Through Hurtbox (i-frames + guard + defense)

`trap_damage_area.gd:14-33` starts with `monitoring = false`. Parent hazards enable it while ACTIVE. On `area_entered`, if the area has `receive_hit` and a different `team`, it builds `DamageInfo` and calls `receive_hit`. That is the full `hurtbox.gd:34-61` pipeline: dodge i-frames early-return, parry/block, defense (`DEFENSE_PER_POINT := 0.02`), resistances, then `Health.take_damage`.

Consumers: `arena_hazard`, `crystal_pillar_hazard`, and dungeon trap `DamageArea` children (see [`dungeon-traps.md`](dungeon-traps.md)).

`enemy_projectile.gd:17-33` configures and enables a child `Hitbox`; `hitbox.gd` scans overlaps and calls the same `receive_hit`. Comment at projectile line 3 documents dodge i-frame intent. Lifetime 4s; world raycast (mask 1) destroys early (`:36-51`).

### Poison through Hurtbox

`poison_hazard.gd:44-57` resolves the player's `Hurtbox` (or calls `try_apply_status` on overlapping hurtbox areas). `Hurtbox.try_apply_status` (`hurtbox.gd:135-148`) respects dodge i-frames and active guard before calling `StatusController.apply_status`.

Poison DoT ticks route through `StatusController._apply_tick` → `Hurtbox.receive_periodic_damage` (`status_controller.gd:116-118`), so defense applies and i-frames can block ticks.

### Boss hazard lifecycle

`arena_hazard.gd` / `crystal_pillar_hazard.gd`: TELEGRAPH → ACTIVE (`monitoring = true`) → FADE → `queue_free`. Parent `@export damage` forwards to child `trap_damage_area` in `_ready` (`arena_hazard.gd:27-30`).

Spawners: `castle_knight._spawn_ground_hazard`, `swamp_hydra._spawn_poison_pool` (`poison_pool.tscn`), `crystal_sovereign` PILLAR_CALL.

### Cleanse zone

`swamp_cleanse_zone.gd`: `cleanse_duration = 4.0`, fades mesh alpha, clears player `poison` status when the player stands within `cleanse_radius` (`:35-48`). Hydra spawns zones every 8s in phase 2 (`swamp_hydra.gd`).

### Placement of poison pools

| Path | Evidence |
|------|----------|
| `definition.placements.traps` via `_place_traps` | `dungeon_builder.gd:520-530` |
| Trap id map: `poison_pool` / `frost_trap` → poison scene | `dungeon_builder.gd:503-512` |
| Room content `hazard_poison_zone` | `room_hazard_content.gd` |
| Procgen swamp corridor trap | `procgen_loot_tables.gd` |

## Contracts

| Contract | Detail |
|----------|--------|
| Hurtbox path | `trap_damage_area` / `Hitbox` → `receive_hit` → full mitigation chain |
| Poison path | `poison_hazard` → `try_apply_status` → `StatusController`; ticks → `receive_periodic_damage` |
| Team | Hazards use `team = "trap"`; projectile Hitbox `team = "enemy"` |
| Collision | Trap damage areas layer 4 / mask 8; poison pool overlaps player body and hurtbox areas |
| Signals | None on hazard scripts; projectile relies on Hitbox internals |

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Arena / pillar telegraphed damage | IMPLEMENTED | `trap_damage_area` → `receive_hit` |
| Enemy projectile | IMPLEMENTED | `Hitbox` → `Hurtbox` |
| Poison pool via `try_apply_status` | IMPLEMENTED | `poison_hazard.gd:44-57` |
| Poison DoT through hurtbox periodic path | IMPLEMENTED | `status_controller.gd:116-118` |
| Swamp cleanse | IMPLEMENTED | `swamp_cleanse_zone.gd:35-48` |
| Hazard `@export damage` forwarding | IMPLEMENTED | `arena_hazard.gd:27-30` |
| Hydra poison pool spawn | IMPLEMENTED | `swamp_hydra.gd:9,149-154` |
| `frost_trap` id mapping | PARTIAL | Still maps to poison pool scene (`dungeon_builder.gd`) |
| Continuous trap overlap scan | PARTIAL | `trap_damage_area` uses `area_entered` only |

## Related

- Improvement plan: [`../actual_improvements/combat-hazards.md`](../actual_improvements/combat-hazards.md) — **FINISHED**
- [`dungeon-traps.md`](dungeon-traps.md), [`bosses.md`](bosses.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`statuses-and-buffs.md`](statuses-and-buffs.md), [`dodge.md`](dodge.md)
