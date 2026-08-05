# Dungeon traps

Telegraphed spike floors and falling ceiling blocks placed from dungeon definitions, procgen, room content, and the final-boss spike burst. On the live castle/endless path whenever `placements.traps` or room trap content is present. Damage goes through child `trap_damage_area` → `Hurtbox.receive_hit` (i-frames and defense apply). Trigger detection uses player **body** distance, not hurtbox overlap.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/traps/spike_trap.gd` | IDLE → TELEGRAPH → ACTIVE → COOLDOWN state machine |
| `apps/game/client/scripts/dungeon/traps/falling_trap.gd` | IDLE → TELEGRAPH → FALLING → RESET |
| `apps/game/client/scenes/traps/spike_trap.tscn` | Telegraph mesh, spikes, `DamageArea` + `trap_damage_area` (18 / 10) |
| `apps/game/client/scenes/traps/falling_trap.tscn` | Falling block + `DamageArea` (25 / 20) |
| `apps/game/client/scripts/combat/trap_damage_area.gd` | Shared hit applicator (see combat-hazards) |

## How it works

### Spike trap (`spike_trap.gd`)

Exports: `damage 18`, `poise_damage 10`, `telegraph_time 1.2`, `active_time 0.6`, `cooldown_time 2.5`, `trigger_radius 3.0` (`:9-14`). `_ready` hides legacy `SpikesMesh`, builds diorama spikes, disables `$DamageArea.monitoring` (`:25-35`).

Each physics frame, if idle and `distance_to(player) <= trigger_radius`, enter TELEGRAPH (`:38-46`). ACTIVE shows spikes and sets `monitoring = true` (`:61-67`). Parent `@export damage` is unused — scene sets child `trap_damage_area.damage = 18`.

### Falling trap (`falling_trap.gd`)

Exports: `damage 25`, `poise_damage 20`, `telegraph_time 1.5`, `fall_speed 12`, `trigger_radius 2.5`. Trigger distance measured from `_block.global_position` to player (`:41-45`). FALLING enables `DamageArea.monitoring`; disables when block `y <= 0.2`; RESET waits 2s then restores (`:49-63`). Same unused parent damage exports.

### Placement

| Source | Mechanism | Evidence |
|--------|-----------|----------|
| Fixture / definition | `placements.traps[]` | e.g. `forgotten_castle_slice.json` |
| Builder | `_place_traps` after loot | `dungeon_builder.gd:110-111`, `:520-530` |
| Id → scene | `_trap_scene_for_id` | `falling_trap` → falling; `poison_pool`/`frost_trap` → poison; `shadow_trap` → spike; default spike (`:503-512`) |
| Procgen | Corridor trap + combat-room falling | `procgen_placements.gd:194-208` |
| Room content | `trap_spike_pack` at fixed `(0,0,2)` | `room_trap_content.gd:6-10` |
| Final boss | 8 spike bursts | `final_boss_forgotten_castle.gd:105-107` |

Only three trap-related scenes exist for builder mapping: spike, falling, poison pool. No `frost_trap.tscn` or `shadow_trap.tscn`.

### Damage path

Child `DamageArea` uses `trap_damage_area.gd` with `team = "trap"`, collision layer 4 / mask 8. Hits call `Hurtbox.receive_hit` — dodge i-frames, guard, and defense apply. Trap scripts never call `Health` or `StatusController` directly.

## Contracts

| Contract | Detail |
|----------|--------|
| Node | `$DamageArea` with `trap_damage_area.gd` |
| Team | `"trap"` |
| Trigger | Euclidean distance to `player` group body |
| Builder ids | `spike_trap` (default), `falling_trap`, `poison_pool`, aliases `frost_trap` / `shadow_trap` |

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Spike + falling combat loop | IMPLEMENTED | Scripts + scenes + Hurtbox path |
| Builder / procgen placement | IMPLEMENTED | `_place_traps`, procgen placements |
| Room `trap_spike_pack` | PARTIAL | Ignores entry dict; fixed offset only (`room_trap_content.gd:6-9`) |
| Controller `@export damage` | STUB | Unused; tscn child owns values |
| `frost_trap` / `shadow_trap` | FAKE | Aliased to poison / spike (`dungeon_builder.gd:507-510`) |
| Re-arm telegraph on falling trap | PARTIAL | RESET has no telegraph (`falling_trap.gd:56-63`) |

## Related

- Improvement plan: [`../actual_improvements/dungeon-traps.md`](../actual_improvements/dungeon-traps.md)
- [`combat-hazards.md`](combat-hazards.md), [`dungeon-builder.md`](dungeon-builder.md), [`bosses.md`](bosses.md), [`procgen-placements.md`](procgen-placements.md)
