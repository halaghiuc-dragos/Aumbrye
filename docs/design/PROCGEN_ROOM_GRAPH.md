# Room Graph Procedural Generation (Client)

> Two-phase Isaac / Shattered Pixel Dungeon–style generator for castle and endless modes.  
> Primary implementation: **GDScript** under `apps/game/client/scripts/dungeon/procgen/`.  
> C# `packages/procedural/` remains for API/server and CLI fallback.

## Pipeline

```
LocalProcgen.generate()
  └─ DungeonProcgen.generate()
       ├─ Phase 1: RoomGraphGenerator → RoomGraph
       ├─ Phase 2: RoomGraphAssigner + RoomGraphGeometry → rooms + edges
       ├─ RoomContentAssigner + RoomContentValidator → locks / roomContent
       ├─ ProcgenPlacements → enemies / loot / traps
       └─ DungeonDefinition dict → DungeonBuilder
```

## Phase 1 — Abstract grid graph

| File | Role |
|------|------|
| `room_graph_slot.gd` | Grid cell: type, door mask, distances |
| `room_graph_config.gd` | Room count, grid size, walk tuning (from biome JSON) |
| `room_graph_generator.gd` | Isaac-style walk, specials, validation, fallback chain |
| `room_graph.gd` | Validated graph container |
| `room_graph_debug.gd` | ASCII grid dump |
| `room_graph_paths.gd` | Critical path, branch checks |

Biome `roomCount` (e.g. forgotten_castle 18–22) drives the **walk target** (`min_rooms` / `max_rooms`). After the walk, `_fill_bounding_box()` adds filler rooms until the occupied bounding box is solid — total room count is typically 30–50+.

## Floor coverage + locks (2026-08-03)

| Feature | Implementation |
|---------|----------------|
| Bbox fill | `room_graph_generator._fill_bounding_box()` |
| Filler rooms | `type: filler`, empty content, hall templates |
| Per-room floors | `dungeon_builder` sets `skip_floor = false` |
| Shell padding | `SHELL_PADDING = 2` (visual ceiling only; floor slab non-collidable) |
| Locks | 1–3 per floor on critical path (`room_content_config`) |
| Keys | `dungeon_key` inventory item; interact at vault + door |

## Phase 2 — Geometry + content

| File | Role |
|------|------|
| `room_template_catalog.gd` | Door masks + room dimensions |
| `room_graph_assigner.gd` | Semantic ids, template picks, room types |
| `room_graph_geometry.gd` | Socket-aligned world positions + edges |
| `room_content_assigner.gd` | Traps, hazards, puzzles, NPC quests, lock/key |
| `room_content_validator.gd` | Start→boss solvability simulation |
| `room_content_types.gd` / `room_content_config.gd` | Content type constants + weights |
| `procgen_placements.gd` | Enemy/loot/trap placement |
| `dungeon_procgen.gd` | Orchestrator |

## DungeonDefinition fields (new)

| Field | Description |
|-------|-------------|
| `roomContent[]` | Per-room content type + template id |
| `locks[]` | Graph-constrained door locks + key room |
| `puzzles[]` | NPC quest / lever gates |

## Runtime content

`room_content_spawner.gd` (via `dungeon_builder.gd`) instantiates content scenes separate from structural room templates.

Run-scoped flags: `WorldState` autoload (resets on `RunFlow.run_ended`).

## Validation

| Suite | Tests |
|-------|-------|
| `room_graph_suite.gd` | Phase 1 determinism, ASCII, pipeline |
| `room_content_suite.gd` | Assignment, critical path, WorldState reset |
| `procgen_suite.gd` | Seed determinism, placement offset compat |

Run: `./scripts/run-mcp-validation.ps1`

## Fallback path

`local_procgen.gd`: GDScript generator primary; C# `procgen-cli` fallback if GDScript returns empty.

## Superseded / legacy

| Item | Status |
|------|--------|
| `packages/procedural/Layout/LayoutGraphGenerator.cs` | Superseded by GD room graph (server may still use C# pipeline) |
| `dungeon_builder.gd` → `_build_shortcut_corridors()` | Legacy one-way layout hack; remove when confirmed unused |
| Hand-authored M2 fixture layout | No longer used as fallback |

## Related

- [06-PROCEDURAL.md](../plan/systems/06-PROCEDURAL.md) — milestone map + server library
- [CASTLE_ROOM_SOCKETS.md](CASTLE_ROOM_SOCKETS.md) — doorway alignment rules
- [PROCgen_PIXEL_CHANGELOG_2026-08.md](PROCgen_PIXEL_CHANGELOG_2026-08.md)
