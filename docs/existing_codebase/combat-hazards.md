# Combat hazards

Telegraphed boss zones, enemy projectiles, environmental poison pools, and the unused swamp cleanse marker. On the live play path: boss kits spawn arena/pillar hazards; swamp/procgen room content spawns poison pools; archers fire `enemy_projectile`. Damage routing is split — most hazards go through `Hurtbox.receive_hit` (i-frames and defense apply); poison applies status by body overlap and ticks `Health` directly (bypasses Hurtbox).

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/combat/poison_hazard.gd` | Poison pool: body overlap → `StatusController.apply_status` |
| `apps/game/client/scripts/combat/trap_damage_area.gd` | Shared `Area3D` applicator: `DamageInfo` → `receive_hit` |
| `apps/game/client/scripts/combat/enemy_projectile.gd` | Ranged projectile; child `Hitbox` for damage |
| `apps/game/client/scripts/bosses/arena_hazard.gd` | Telegraph → ACTIVE → FADE fire-styled zone |
| `apps/game/client/scripts/bosses/crystal_pillar_hazard.gd` | Same lifecycle; crystal pillar visual |
| `apps/game/client/scripts/bosses/swamp_cleanse_zone.gd` | Visual countdown; no collision / cleanse logic |
| `apps/game/client/scenes/bosses/arena_hazard.tscn` | Child `DamageArea` + `trap_damage_area` (damage 8, poise 5) |
| `apps/game/client/scenes/bosses/crystal_pillar_hazard.tscn` | Child `DamageArea` (damage 10, poise 8) |
| `apps/game/client/scenes/combat/enemy_projectile.tscn` | Projectile + Hitbox (`team = "enemy"`) |

## How it works

### Through Hurtbox (i-frames + guard + defense)

`trap_damage_area.gd:14-33` starts with `monitoring = false`. Parent hazards enable it while ACTIVE. On `area_entered`, if the area has `receive_hit` and a different `team`, it builds `DamageInfo` and calls `receive_hit`. That is the full `hurtbox.gd:34-61` pipeline: dodge i-frames early-return, parry/block, defense (`DEFENSE_PER_POINT := 0.02`), resistances, then `Health.take_damage`.

Consumers: `arena_hazard`, `crystal_pillar_hazard`, and dungeon trap `DamageArea` children (see [`dungeon-traps.md`](dungeon-traps.md)).

`enemy_projectile.gd:17-33` configures and enables a child `Hitbox`; `hitbox.gd` scans overlaps and calls the same `receive_hit`. Comment at projectile line 3 documents dodge i-frame intent. Lifetime 4s; world raycast (mask 1) destroys early (`:36-51`).

### Bypass Hurtbox — poison

`poison_hazard.gd:35-40` filters `player` group bodies and calls `StatusController.apply_status(poison_status, 1, 4.0)`. Scene `poison_pool.tscn` uses `collision_mask = 2` (player body), not hurtbox layer 8. Tick interval default 1.5s (`:7`, `:22-28`).

Poison DoT from `content/statuses/poison.json` is applied in `StatusController` via `Health.take_damage` — `Health` has no i-frame or defense gate (`health.gd:29-36`). Standing in a pool while dodging still receives the status; ticks ignore i-frames.

### Boss hazard lifecycle

`arena_hazard.gd` / `crystal_pillar_hazard.gd`: TELEGRAPH (mesh tint) → ACTIVE (`monitoring = true`) → FADE → `queue_free`. Exports: arena `damage=8`, `telegraph_time=1.0`, `active_time=2.5`; pillar `damage=10`, `telegraph_time=1.2`, `active_time=3.0`. **Parent `@export var damage` is never read** — the child `trap_damage_area` owns the numbers.

Spawners: `castle_knight._spawn_ground_hazard`, `swamp_hydra._spawn_poison_pool` (instantiates `arena_hazard.tscn`, not poison pool), `crystal_sovereign` PILLAR_CALL.

### Cleanse zone

`swamp_cleanse_zone.gd`: `cleanse_duration = 4.0`, fades mesh alpha, exposes `is_cleanse_active()`. Scene has mesh only — no `Area3D` collision. No script in the client calls `is_cleanse_active`. Hydra still spawns zones every 8s in phase 2 (`swamp_hydra.gd:50-55`, `:158-163`).

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
| Hurtbox path | `trap_damage_area` / `Hitbox` → `receive_hit` → defense / i-frames |
| Poison path | Body overlap → `StatusController` → DoT → `Health.take_damage` |
| Team | Hazards use `team = "trap"`; projectile Hitbox `team = "enemy"` |
| Collision | Trap damage areas layer 4 / mask 8; poison pool mask 2 |
| Signals | None on hazard scripts; projectile relies on Hitbox internals |

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Arena / pillar telegraphed damage | IMPLEMENTED | Through Hurtbox via `trap_damage_area` |
| Enemy projectile | IMPLEMENTED | Through Hitbox → Hurtbox |
| Poison pool status apply | IMPLEMENTED | Bypasses Hurtbox (`poison_hazard.gd:35-40`) |
| Poison DoT vs i-frames | PARTIAL | Ticks ignore dodge (`status_controller` → `Health`) |
| Swamp cleanse | PLACEHOLDER | Visual only (`swamp_cleanse_zone.gd:29-30`) |
| Hazard `@export damage` | STUB | Never forwarded to child (`arena_hazard.gd:9`) |
| Hydra "poison pool" spawn | FAKE | Spawns fire `arena_hazard` (`swamp_hydra.gd:148-155`) |
| `frost_trap` id | FAKE | Maps to poison pool scene (`dungeon_builder.gd:507-512`) |

## Related

- Improvement plan: [`../actual_improvements/combat-hazards.md`](../actual_improvements/combat-hazards.md)
- [`dungeon-traps.md`](dungeon-traps.md), [`bosses.md`](bosses.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`statuses-and-buffs.md`](statuses-and-buffs.md), [`dodge.md`](dodge.md)
