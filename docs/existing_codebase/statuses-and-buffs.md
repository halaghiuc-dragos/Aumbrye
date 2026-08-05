# Statuses and buffs

Two unrelated systems that share this topic. `StatusController` applies timed damage-over-time and control effects from `content/statuses/`; `RunBuffs` is an autoload holding run-scoped relics from `content/relics/` whose stats merge into the equipment stat pipeline. Both are on the live play path, but `StatusController` exists on exactly one scene.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/combat/statuses/status_catalog.gd` | `StatusCatalog`: static, lazily-loaded definition cache |
| `apps/game/client/scripts/combat/statuses/status_controller.gd` | `StatusController` node: active stacks, ticks, slow and stun aggregation |
| `apps/game/client/scripts/combat/run_buffs.gd` | `RunBuffs` autoload: relic list, stacking, stat totals, save round-trip |
| `apps/game/client/scripts/content/relic_catalog.gd` | `RelicCatalog`: static relic definition cache |
| `content/statuses/*.json` | Five definitions: `bleed`, `burn`, `freeze`, `poison`, `stun` |
| `content/relics/*.json` | Eleven relic definitions |
| `content/schemas/status-definition.v1.json`, `content/schemas/relic-definition.v1.json` | Schemas, both `additionalProperties: false` |

## How it works

### StatusCatalog

`_ensure_loaded()` (`status_catalog.gd:20`) opens `ContentLoader.content_path("content/statuses")` with `DirAccess`, loads every `.json`, and keys the result by its `id`. The cache is a `static var` and is never invalidated. `get_definition(id)` returns `{}` for anything unknown; `all_ids()` is called only by `m5_suite.gd:265`.

### Status definitions

Every authored status, in full:

| id | `damageType` | `tickDamage` | `tickInterval` | `maxStacks` | `duration` | Extra |
|----|-------------|--------------|----------------|-------------|------------|-------|
| `bleed` | physical | 2 | 0.8 s | 5 | 6.0 s | — |
| `burn` | fire | 3 | 1.0 s | 3 | 5.0 s | — |
| `poison` | poison | 2.5 | 1.2 s | 4 | 8.0 s | — |
| `freeze` | frost | 0 | 1.0 s | 1 | 3.0 s | `slowMultiplier: 0.45` |
| `stun` | physical | 0 | 1.0 s | 1 | 1.2 s | `stunDuration: 1.2` |

The schema permits exactly `id`, `name`, `damageType`, `tickDamage`, `tickInterval`, `maxStacks`, `duration`, `slowMultiplier`, `stunDuration`, `iconColor`.

### StatusController

`status_controller.gd`. Exports `health_path` (resolved once in `_ready()`) and `team`. State is `_active: Dictionary` keyed by status id, each entry `{stacks, remaining, tick_timer}`.

`apply_status(status_id, stacks = 1, duration_override = -1.0)` (`:41`) returns early on an empty id or an unknown definition. For an already-active status it raises `stacks` up to `maxStacks` and takes `maxf(remaining, duration)` — a refresh, never an extension beyond the base duration. For a new status it stores `mini(stacks, maxStacks)` and seeds `tick_timer` with `tickInterval`, so the first tick fires one interval after application, not immediately.

`_physics_process(delta)` (`:22`) decrements `remaining` and `tick_timer` for every active entry, fires `_apply_tick` when `tick_timer` reaches 0, resets `tick_timer` to the definition's `tickInterval`, collects expired ids, removes them, and calls `_recalc_modifiers()` **every frame** — which itself emits `statuses_changed` every frame while anything is active (`:125`).

`_apply_tick` (`:94`) computes `tickDamage * stacks`, resolves resistances via the parent's `get_enemy_id()`, and calls `_health.take_damage(...)` directly. It does not go through `Hurtbox`, so defense metas, guard, i-frames, backstab and `HitFeedback` are all bypassed for damage over time.

`_recalc_modifiers()` (`:116`) recomputes two aggregates from scratch: `_slow_multiplier` is the minimum `slowMultiplier` across active statuses, and `_stunned` is true if any active status has a nonzero `stunDuration`. The *value* of `stunDuration` is never used — a status with `stunDuration: 0.1` and `duration: 8.0` would stun for 8 seconds.

Consumers: `locomotion.gd:104-106` multiplies target speed by `get_slow_multiplier()`; `weapon_controller.gd:573-575` blocks all attack input while `is_stunned()`; `combat_hud.gd:183-203` renders one icon per active status using `StatusIconAtlas.get_icon(status_id, Color.from_string(def.iconColor, WHITE))` with a `"<name> x<stacks>"` tooltip.

### Who applies statuses

| Path | Applies | Reaches |
|------|---------|---------|
| `hurtbox.gd:159-167` on any hit carrying `status_id` | Whatever the hitbox was configured with | Only a victim with a `StatusController` child node |
| `weapon_controller.gd:348` | Attack `status`, else weapon `status_on_hit` | Enemies — which have no `StatusController` |
| `castle_enemy_base.gd:647-648` | Enemy `status_on_hit` + `status_stacks_on_hit` | The player |
| `swamp_hag.gd:59`, `castle_archer.gd:88`, `crystal_guardian.gd:59`, `crystal_sovereign.gd:98`, `swamp_hydra.gd:113` | Same, via `enemy_projectile.launch` | The player |
| `poison_hazard.gd:35-40` | `poison`, 1 stack, 4.0 s override — called directly on the body, bypassing `Hurtbox` | The player |
| `combat_hud.gd:354-359` | `burn` on the F8 debug key | The player |
| `m5_suite.gd:286` | `burn` via `debug_apply` | Test player |

Authored appliers by status:

- `poison` — `content/enemies/swamp_hag.json:23`, `swamp_witch.json:25`, `swamp_leech.json:22`, `content/bosses/swamp_hydra.json:23`, plus `poison_hazard.gd`.
- `freeze` — `content/enemies/frost_knight.json:21`, `frost_raider.json:21`, `frost_hound.json:21`, `frost_archer.json:21` (all with `status_stacks_on_hit: 2`).
- `bleed` — `content/weapons/dagger.json:6,18,28,38,50` only, i.e. player-to-enemy only.
- `burn` — no gameplay applier. Only the F8 debug key and `m5_suite`.
- `stun` — no applier anywhere in the repo.

### RunBuffs

`run_buffs.gd`, autoload (`project.godot:38`), `process_mode = PROCESS_MODE_ALWAYS`. `_active` is an array of `{relicId, stacks}`.

`add_relic(id)` (`:25`) rejects unknown ids and ids already at `maxStacks`, otherwise appends or increments and emits `buffs_changed`. `get_stat_totals()` (`:48`) sums each relic's `stats` dictionary multiplied by its stack count. `clear_all()`, `to_save_array()` and `from_save_array(data)` complete the API.

Grant path: `inventory_service.gd:36-43` — `add_item()` reads the item definition's `runRelicId` and calls `RunBuffs.add_relic()` when a run is active. Eleven material items under `content/items/materials/` carry a `runRelicId`.

Consumption: `inventory_service.gd:118` merges `RunBuffs.get_stat_totals()` into `get_equipment_stats()`, which flows into `apply_equipment_to_player_node()`. `local_save.gd:551-552,586,645-646` round-trips the array under the `runRelics` save key. `run_flow.gd:349,371,411,825` calls `clear_all()` on run boundaries.

Relic stat coverage:

| Relic | Stat | Reaches gameplay |
|-------|------|------------------|
| `iron_will` | `maxHealth: 15` (x3) | Yes — `inventory_service.gd:189-190` |
| `bloodlust` | `damagePercent: 5` (x2) | Yes — `damage_multiplier` |
| `relic_flame_core` | `damagePercent: 5` | Yes |
| `swift_step` | `moveSpeedPercent: 10` | Yes — `move_speed_multiplier` |
| `relic_shadow_veil` | `moveSpeed: 0.05` | Yes |
| `relic_stone_heart` | `armor: 8` | Yes — folded into the `combat_defense` meta at `inventory_service.gd:212` |
| `relic_frost_shard` | `frostDamage: 4` | No — folded into `bonusDamage` (`equipment.gd:150-151`), which `flat_damage_bonus()` never reads |
| `relic_poison_vial` | `poisonDamage: 4` | No — same |
| `relic_sun_medallion` | `healthRegen: 1` | No — in `Equipment.STAT_KEYS` but read by no gameplay system |
| `relic_wind_charm` | `attackSpeed: 0.04` | No — not in `STAT_KEYS`, not read anywhere |
| `relic_bloodstone` | `lifesteal: 0.03` | No — not in `STAT_KEYS`, not read anywhere |

## Contracts

- **Node name:** `StatusController` as a child of a `CharacterBody3D`. Resolved by literal name at `hurtbox.gd:165`, `weapon_controller.gd:573`, `locomotion.gd:104`, `poison_hazard.gd:38`, `combat_hud.gd:85`.
- **`@export`s:** `health_path` (read once in `_ready()`), `team`.
- **Signals:** `StatusController.statuses_changed`, `RunBuffs.buffs_changed`.
- **JSON keys read:** statuses — `id`, `damageType`, `tickDamage`, `tickInterval`, `maxStacks`, `duration`, `slowMultiplier`, `stunDuration`, `iconColor`. Relics — `id`, `maxStacks`, `stats`, plus `name` and `description` in UI. Enemies — `status_on_hit`, `status_stacks_on_hit`. Weapons — `status_on_hit`, `status`, `status_stacks`. Items — `runRelicId`.
- **Save key:** `runRelics`, an array of `{relicId, stacks}` (`local_save.gd:586`).
- **Content directories:** `content/statuses/`, `content/relics/`, resolved through `ContentLoader.content_path()`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Status stacking, refresh, expiry, ticks | IMPLEMENTED | `status_controller.gd:22-60` |
| Slow (`freeze`) and stun aggregation | IMPLEMENTED | `status_controller.gd:116-125`, `locomotion.gd:104-106`, `weapon_controller.gd:573-575` |
| Status HUD icons with authored `iconColor` | IMPLEMENTED | `combat_hud.gd:183-203` |
| Enemy-to-player status application | IMPLEMENTED | `castle_enemy_base.gd:647-648`, `content/enemies/frost_knight.json:21-22` |
| Player-to-enemy status application | BROKEN | `hurtbox.gd:165` needs a `StatusController` child; no enemy scene has one — `StatusController` appears only in `player.tscn:89`. The dagger's authored `bleed` (`content/weapons/dagger.json:18,28,38,50`) never lands |
| `burn` | PLACEHOLDER | Authored at `content/statuses/burn.json`; applied only by the F8 debug key (`combat_hud.gd:357`) and `m5_suite.gd:286` |
| `stun` | PLACEHOLDER | Authored at `content/statuses/stun.json`; no applier anywhere in the repo |
| `stunDuration` semantics | PARTIAL | `status_controller.gd:123-124` treats any nonzero value as a boolean; the stun lasts the status `duration`, not `stunDuration` |
| Status damage bypassing mitigation | PARTIAL | `status_controller.gd:100` calls `_health.take_damage()` directly, so defense, guard, i-frames and `HitFeedback` never apply to ticks |
| `_recalc_modifiers` cost | PARTIAL | `status_controller.gd:38,125` — called every physics frame while any status is active, emitting `statuses_changed` every frame |
| Status resistance or build-up | ABSENT | No `buildup`, `threshold` or `resist` key in `content/schemas/status-definition.v1.json`; a status applies at full stacks on the first hit |
| Status VFX, audio or on-body visual | ABSENT | Only a HUD icon; no `VfxService` call, no `AudioDirector` cue and no material tint is driven by an active status |
| Status display for enemies | ABSENT | `combat_hud.gd:85` binds the player's controller only |
| Relic grant, stack cap and save round-trip | IMPLEMENTED | `inventory_service.gd:36-43`, `run_buffs.gd:25-45`, `local_save.gd:551-552,586` |
| Relic stat coverage | PARTIAL | 6 of 11 relics reach gameplay. `relic_frost_shard`, `relic_poison_vial`, `relic_sun_medallion`, `relic_wind_charm` and `relic_bloodstone` grant `frostDamage`, `poisonDamage`, `healthRegen`, `attackSpeed` and `lifesteal`, none of which any gameplay system reads |
| Relic triggers and effects | ABSENT | `content/schemas/relic-definition.v1.json:6-17` allows only `id`, `name`, `description`, `maxStacks`, `stats`; `RunBuffs`'s entire API is `get_stat_totals()` |
| `StatusCatalog._definitions` invalidation | PARTIAL | `status_catalog.gd:4,21-22` — a `static var` cache with no reset; a content hot-reload is not picked up |

## Related

- Improvement plan: [`../actual_improvements/statuses-and-buffs.md`](../actual_improvements/statuses-and-buffs.md)
- [`hit-hurtboxes.md`](hit-hurtboxes.md) — the `StatusController` lookup that drops player statuses
- [`combat-core.md`](combat-core.md) — `DamageInfo.status_id`, resistances
- [`weapons.md`](weapons.md) — `status_on_hit` and per-attack `status`
- [`enemies.md`](enemies.md), [`bosses.md`](bosses.md) — enemy-side appliers
- [`combat-hazards.md`](combat-hazards.md) — `poison_hazard`
- [`ui/status_icon_atlas.md`](ui/status_icon_atlas.md), [`ui/combat_hud.md`](ui/combat_hud.md)
- [`loot-and-equipment.md`](loot-and-equipment.md), [`inventory-service.md`](inventory-service.md), [`local-save.md`](local-save.md)
