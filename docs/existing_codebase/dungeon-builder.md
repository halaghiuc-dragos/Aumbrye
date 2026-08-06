# Dungeon builder

`DungeonBuilder` turns a `DungeonDefinition` dictionary into a live scene under a single `DungeonRoot`: instantiates room templates, opens blockout doors along edges, builds per-floor navigation maps and cross-room `NavLinks`, spawns enemies, chests, traps, cover, room content, interactable secret mechanisms, the boss, boss door, exit portal, and stair levers, and owns the enemy/chest snapshot round-trip.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/dungeon_builder.gd` | Builder, `DungeonRoot` lifecycle, snapshots, floor cache |
| `apps/game/client/scripts/dungeon/room_template.gd` | Room prefab; `socket_toward()`, `socket_for_direction()` |
| `apps/game/client/scripts/dungeon/castle/castle_blockout.gd` | Blockout navmesh; deterministic `sample_random_nav_point(rng)` |
| `apps/game/client/scripts/dungeon/stair_collision_builder.gd` | Collision body for stair ramps |
| `apps/game/client/scripts/dungeon/doorway_socket.gd` | `Marker3D` doorway attachment; `is_secret` read by secret placement |
| `apps/game/client/scripts/dungeon/illusory_wall.gd` | Interactable secret wall; `mark_revealed()` |
| `apps/game/client/scripts/dungeon/hidden_lever.gd` | Interactable secret lever; `mark_used()` |
| `apps/game/client/scripts/dungeon/waves_difficulty.gd` | Waves-mode HP/damage multipliers |
| `apps/game/client/scenes/dungeon/illusory_wall.tscn` | Illusory wall scene |
| `apps/game/client/scenes/dungeon/hidden_lever.tscn` | Hidden lever scene |

## How it works

### Entry points

| Function | Line | Use |
|----------|------|-----|
| `build(parent, player, fixture_path)` | `:77` | loads fixture JSON, default `content/fixtures/forgotten_castle_slice.json` |
| `build_from_definition(parent, player, def)` | `:83` | procgen path |
| `build_from_source(...)` | `:87` | shared implementation |

`build_from_source` creates `DungeonRoot` with `Entities` and `Rooms` children (`:112-117`). Unknown templates abort the build via `_build_rooms() -> bool` and `_abort_build()` (`:118-119`, `:176-207`).

Build order (`:120-142`): `_build_rooms` → `_setup_floor_nav_map` → `_sync_blockout_doors_from_edges` → `_wire_shortcut_edges` → `_build_doorway_bridges` → `_build_height_transitions` → `_build_floor_shell` → `_build_landmarks` → `_place_cover` → `_place_secret_mechanisms` → `_build_nav_links` → spawn/placement passes → boss/portal/lever/door setup.

### Navigation

`_setup_floor_nav_map()` (`:210`) creates one `RID` per floor, assigns every room `NavigationRegion3D` and all `NavigationLink3D` nodes to it.

`_build_nav_links()` (`:525`) adds bidirectional `NavigationLink3D` children under `DungeonRoot/NavLinks`, with endpoints 0.5 units back into each room from the resolved sockets (`:541-551`).

`_open_blockout_door_toward()` (`:257`) uses `from_room.socket_toward(to_room)` and sets the blockout door flag from `socket.direction`.

`_sample_placement_offset()` (`:567`) rejection-samples via `blockout.sample_random_nav_point(_placement_rng)` when `sampleNavmesh: true`; chests also pass `_placement_inside_room()` (`:595`).

### Secrets

`_place_secret_mechanisms()` (`:445`) instantiates `illusory_wall.tscn` or `hidden_lever.tscn` under `Props`, keyed by `secret_room_id` meta. `reveal_secret(secret_room_id)` (`:485`) opens doors and calls `mark_revealed` / `mark_used`. `socket_for_direction(..., prefer_secret: true)` prefers sockets with `is_secret`.

### Boss, portal, levers, unload

- `_setup_boss_door()` uses `placements.exit` room, skips when no boss (`:881`).
- `_create_exit_portal()` requires `Props`; `open_exit_portal()` calls `ExitPortal.activate()` (`:160`).
- `_stair_levers: Array[Node3D]` tracks every stair room; `get_stair_levers()` exposed (`:830`).
- `configure(can_ascend, can_descend, can_retreat)` at both lever call sites.
- `unload_from_parent()` frees the entire `DungeonRoot` subtree (`:1099`).
- `_apply_floor_scaling()` applies `WavesDifficulty` in waves mode (`:1130`).

### Snapshots and cache

Same as before: `capture_enemy_states`, `capture_loot_states`, `apply_snapshot`, static `_floor_definition_cache` paired with `RunFlow.floor_definitions`.

## Contracts

- Definition keys: `rooms[]`, `edges[]`, `placements.{enemies,loot,traps,secrets,cover,boss,exit,entrance}`, `landmarks[]`, `roomContent[]`, `locks[]`, `isFinalFloor`.
- Room scene nodes: `CastleBlockout`, `DoorwaySockets/*`, `Props`, `Props/BossSpawn`, `Props/ExitPortalMarker`, `Props/StairRamp`, `SpawnPoints/PlayerSpawn`, `SpawnPoints/LeverSpawn`.
- Run scene nodes created: `DungeonRoot/{Entities,Rooms,NavLinks,Landmarks,DoorwayBridges,FloorShell}`.
- Signals: `build_complete`, `boss_defeated`, `snapshot_dirty`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Room instantiation | IMPLEMENTED | `dungeon_builder.gd:176-207` |
| Unknown template abort | IMPLEMENTED | `:176-207`, `_abort_build` |
| Per-floor navigation map | IMPLEMENTED | `:210-225` |
| Cross-room nav links | IMPLEMENTED | `:525-551` |
| Room-scoped nav sampling | IMPLEMENTED | `:567-577`, `castle_blockout.gd:308` |
| Socket-correct door opening | IMPLEMENTED | `:257-276`, `room_template.gd:38` |
| Secret mechanisms | IMPLEMENTED | `:445-516`, `illusory_wall.gd`, `hidden_lever.gd` |
| Enemy snap after parenting | IMPLEMENTED | `:615-641` |
| Multiple stair levers | IMPLEMENTED | `:780-831` |
| DungeonRoot cleanup | IMPLEMENTED | `:1099-1128` |
| Boss door from exit placement | IMPLEMENTED | `:881-955` |
| Exit portal via activate() | IMPLEMENTED | `:160`, `:743-771` |
| Waves difficulty scaling | IMPLEMENTED | `:1130`, `waves_difficulty.gd` |
| Height transitions | IMPLEMENTED | `:336-377` |
| Shortcut edges | IMPLEMENTED | `:240-255` |
| Snapshot capture/apply | IMPLEMENTED | `:1009-1059` |
| Doorway bridges | PARTIAL | `:278-334` — errors when span ≥ 0.5 instead of stub bridges; clone themes may still lack aligned sockets until room-templates RTP work lands |
| Clone theme Props | IMPLEMENTED | seven clone `_stairs` / `_boss` scenes now include `Props` + markers |

`content/fixtures/dungeon_definition_v1_minimal.json` uses valid `castle_courtyard` / `castle_hall` templates.

## Related

- Improvement plan: [`../actual_improvements/dungeon-builder.md`](../actual_improvements/dungeon-builder.md) — **FINISHED**
- [`procgen-placements.md`](procgen-placements.md), [`room-content.md`](room-content.md), [`room-templates.md`](room-templates.md)
- [`floor-shell.md`](floor-shell.md), [`boss-door-exit-portal.md`](boss-door-exit-portal.md), [`stair-lever.md`](stair-lever.md)
- [`biome-registry.md`](biome-registry.md), [`run-flow.md`](run-flow.md), [`castle-run.md`](castle-run.md)
