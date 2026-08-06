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

`_apply_tick` (`:107`) computes tick damage with resistances and routes through `Hurtbox.receive_periodic_damage` when a hurtbox exists (`:116-118`), so defense applies and i-frames can block ticks mid-roll.

`_recalc_modifiers()` (`:116`) recomputes two aggregates from scratch: `_slow_multiplier` is the minimum `slowMultiplier` across active statuses, and `_stunned` is true if any active status has a nonzero `stunDuration`. The *value* of `stunDuration` is never used — a status with `stunDuration: 0.1` and `duration: 8.0` would stun for 8 seconds.

Consumers: `locomotion.gd:104-106` multiplies target speed by `get_slow_multiplier()`; `weapon_controller.gd:573-575` blocks all attack input while `is_stunned()`; `combat_hud.gd:183-203` renders one icon per active status using `StatusIconAtlas.get_icon(status_id, Color.from_string(def.iconColor, WHITE))` with a `"<name> x<stacks>"` tooltip.

### Who applies statuses

| Path | Applies | Reaches |
|------|---------|---------|
| `hurtbox.gd` lazy `StatusController` + `try_apply_status` | Whatever the hitbox or hazard was configured with | Any victim body — controller created on demand if absent |
| `weapon_controller.gd` | Attack `status`, else weapon `status_on_hit` | Enemies via lazy controller |
| `castle_enemy_base.gd:647-648` | Enemy `status_on_hit` + `status_stacks_on_hit` | The player |
| `swamp_hag.gd:59`, `castle_archer.gd:88`, `crystal_guardian.gd:59`, `crystal_sovereign.gd:98`, `swamp_hydra.gd:113` | Same, via `enemy_projectile.launch` | The player |
| `poison_hazard.gd` | `poison` via `Hurtbox.try_apply_status` | The player — respects i-frames and guard |
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
| Status stacking, refresh, expiry, ticks | IMPLEMENTED | `status_controller.gd:26-68` |
| Status ticks through hurtbox periodic path | IMPLEMENTED | `status_controller.gd:116-118`, `hurtbox.gd:151-156` |
| Lazy enemy `StatusController` | IMPLEMENTED | `hurtbox.gd:275-293` |
| Player-to-enemy status (e.g. dagger bleed) | IMPLEMENTED | Lazy controller + `weapon_controller.gd` status fields |
| Slow (`freeze`) and stun aggregation | IMPLEMENTED | `status_controller.gd`, `locomotion.gd`, `weapon_controller.gd` |
| Status HUD icons with authored `iconColor` | IMPLEMENTED | `combat_hud.gd:183-203` |
| Enemy-to-player status application | IMPLEMENTED | `castle_enemy_base.gd`, projectile callers |
| Relic grant, stack cap and save round-trip | IMPLEMENTED | `run_buffs.gd`, `inventory_service.gd`, `local_save.gd` |
| `burn` / `stun` gameplay appliers | PARTIAL | `burn` debug-only; `stun` still no content applier |
| `stunDuration` semantics | PARTIAL | Treated as boolean; stun lasts full status `duration` |
| Status VFX, audio or on-body visual | ABSENT | HUD icon only |
| Status build-up / resistance | ABSENT | No `buildup`/`threshold` in schema |
| Relic stat coverage | PARTIAL | Elemental damage relics now reach pipeline via `flat_damage_bonus` |
| Enemy status HUD display | ABSENT | `combat_hud.gd` binds player controller only |

## Related

- Improvement plan: [`../actual_improvements/statuses-and-buffs.md`](../actual_improvements/statuses-and-buffs.md) — **FINISHED**
- [`hit-hurtboxes.md`](hit-hurtboxes.md) — the `StatusController` lookup that drops player statuses
- [`combat-core.md`](combat-core.md) — `DamageInfo.status_id`, resistances
- [`weapons.md`](weapons.md) — `status_on_hit` and per-attack `status`
- [`enemies.md`](enemies.md), [`bosses.md`](bosses.md) — enemy-side appliers
- [`combat-hazards.md`](combat-hazards.md) — `poison_hazard`
- [`ui/status_icon_atlas.md`](ui/status_icon_atlas.md), [`ui/combat_hud.md`](ui/combat_hud.md)
- [`loot-and-equipment.md`](loot-and-equipment.md), [`inventory-service.md`](inventory-service.md), [`local-save.md`](local-save.md)
