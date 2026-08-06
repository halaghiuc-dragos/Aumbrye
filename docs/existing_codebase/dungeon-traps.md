# Dungeon traps

Telegraphed spike floors, falling ceiling blocks, poison pools, frost pools, and shadow spike variants placed from dungeon definitions, procgen, room content, and the final-boss spike burst. On the live castle/endless path whenever `placements.traps` or room trap content is present. Damage goes through child `TrapDamageArea` â†’ `Hurtbox.receive_hit` (i-frames and defense apply). Trigger detection uses player **body** distance; `trigger_radius` is clamped to at least the `DamageArea` horizontal half-extent plus 0.5 m.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/traps/spike_trap.gd` | IDLE â†’ TELEGRAPH â†’ ACTIVE â†’ COOLDOWN state machine |
| `apps/game/client/scripts/dungeon/traps/falling_trap.gd` | IDLE â†’ TELEGRAPH â†’ FALLING â†’ RESET |
| `apps/game/client/scenes/traps/spike_trap.tscn` | Telegraph mesh, `DamageArea` + `TrapDamageArea` (18 / 10 scene defaults) |
| `apps/game/client/scenes/traps/shadow_trap.tscn` | Purple telegraph spike trap (reuses `spike_trap.gd`) |
| `apps/game/client/scenes/traps/frost_trap.tscn` | Frost-styled poison pool (`poison_hazard.gd`) |
| `apps/game/client/scenes/traps/falling_trap.tscn` | Falling block + `DamageArea` (25 / 20) |
| `apps/game/client/scenes/traps/poison_pool.tscn` | Swamp poison pool |
| `apps/game/client/scripts/combat/trap_damage_area.gd` | Shared hit applicator with ACTIVE overlap scan |
| `apps/game/client/scripts/content/trap_catalog.gd` | Resolves trap id â†’ scene path from `content/traps/*.json` |
| `apps/game/client/scripts/dungeon/room_content/room_trap_content.gd` | `trap_spike_pack` room content spawner |

## How it works

### Spike trap (`spike_trap.gd`)

Exports: `damage 18`, `poise_damage 10`, `telegraph_time 1.2`, `active_time 0.6`, `cooldown_time 2.5`, `trigger_radius 3.0` (`:9-14`). `_ready` builds diorama spikes via `DioramaSkin.build_spikes`, forwards `@export` damage to `$DamageArea`, disables damage, and syncs `trigger_radius` from the collision shape (`:25-35`, `:76-91`).

Each physics frame, if idle and `distance_to(player) <= trigger_radius`, enter TELEGRAPH (`:42-46`). ACTIVE shows spikes and calls `_hitbox.set_damage_active(true)` which enables monitoring and scans overlapping hurtboxes (`:61-66`, `trap_damage_area.gd:22-46`).

### Falling trap (`falling_trap.gd`)

Exports: `damage 25`, `poise_damage 20`, `telegraph_time 1.5`, `fall_speed 12`, `trigger_radius 2.5`. Trigger distance measured from `_block.global_position` to player (`:44-50`). FALLING enables damage via `set_damage_active(true)`; on floor contact disables damage, restores block to `_rest_y`, enters RESET cooldown (`:60-65`). IDLE only after RESET timer expires (`:66-69`).

### TrapDamageArea (`trap_damage_area.gd`)

`set_damage_active(true)` sets `monitoring` and calls `scan_overlapping_areas()` â€” a one-shot `intersect_shape` pass over the `CollisionShape3D` matching `area_entered` hit logic (`:22-66`). Cooldown per hurtbox instance id via `hit_interval` (default 0.5 s).

### Placement

| Source | Mechanism | Evidence |
|--------|-----------|----------|
| Fixture / definition | `placements.traps[]` | e.g. `forgotten_castle_slice.json` |
| Builder | `_place_traps` after loot | `dungeon_builder.gd:693-705` |
| Id â†’ scene | `TrapCatalog.get_scene_path` via `_trap_scene_for_id` | `trap_catalog.gd:9-17`; `dungeon_builder.gd:679-684` |
| Procgen | Corridor trap from biome `trapPool` + combat-room falling | `procgen_loot_tables.gd:23-29`; `procgen_placements.gd` |
| Room content | `trap_spike_pack` at anchor + entry `x`/`y`/`z` (default `z=2`) | `room_trap_content.gd:7-14` |
| Final boss | 8 spike bursts | `final_boss_forgotten_castle.gd:105-107` |

Five trap scenes exist, each backed by `content/traps/<id>.json`: `spike_trap`, `falling_trap`, `poison_pool`, `frost_trap`, `shadow_trap`.

### Damage path

Child `DamageArea` uses `trap_damage_area.gd` (`class_name TrapDamageArea`) with `team = "trap"`, collision layer 4 / mask 8. Hits call `Hurtbox.receive_hit` â€” dodge i-frames, guard, and defense apply. Trap scripts never call `Health` or `StatusController` directly. `frost_trap.tscn` uses `poison_hazard.gd` (body overlap, separate hazard path).

## Contracts

| Contract | Detail |
|----------|--------|
| Node | `$DamageArea` with `TrapDamageArea` (spike/falling/shadow) |
| Team | `"trap"` |
| Trigger | Euclidean distance to `player` group body; radius >= damage footprint + 0.5 m |
| Builder ids | Resolved via `TrapCatalog` from `content/traps/*.json` |
| Room content keys | `x`, `y`, `z` (optional offsets added to `PropAnchor_0`; default `z=2`) |

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Spike + falling combat loop | IMPLEMENTED | Scripts + scenes + Hurtbox path |
| Builder / procgen placement | IMPLEMENTED | `_place_traps`, `TrapCatalog`, biome `trapPool` |
| Room `trap_spike_pack` | IMPLEMENTED | Entry offset + anchor (`room_trap_content.gd:7-14`) |
| Controller `@export damage` | IMPLEMENTED | Forwarded in `_ready` (`spike_trap.gd:31-32`; `falling_trap.gd:33-34`) |
| ACTIVE overlap scan | IMPLEMENTED | `trap_damage_area.gd:22-46` |
| Frost / shadow trap scenes | IMPLEMENTED | `frost_trap.tscn`, `shadow_trap.tscn` + JSON defs |
| Falling trap re-arm telegraph | IMPLEMENTED | Ceiling restore before IDLE (`falling_trap.gd:60-69`) |
| Diorama spikes | IMPLEMENTED | Legacy `SpikesMesh` removed (`spike_trap.tscn`, `shadow_trap.tscn`) |

## Related

- Improvement plan: [`../actual_improvements/dungeon-traps.md`](../actual_improvements/dungeon-traps.md) - **FINISHED**
- [`combat-hazards.md`](combat-hazards.md), [`dungeon-builder.md`](dungeon-builder.md), [`bosses.md`](bosses.md), [`procgen-placements.md`](procgen-placements.md)
