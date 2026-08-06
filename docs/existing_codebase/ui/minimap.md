# Minimap

## Status: FINISHED

A `Control` that draws the real generated room graph with three-tier fog of war, uniform-scale projection, variable room footprints, type icons, a player facing arrow, and an optional full-map overlay. It is on the live play path in castle runs only: `combat_hud.tscn` embeds `MinimapAnchor/Minimap` but `MinimapAnchor.visible` is driven by `has_graph()`, so hub, waves, and debug arenas never show an empty widget.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/ui/minimap.gd` | `extends Control` â€” graph draw, reveal tiers, player marker, overlay mode |
| `apps/game/client/assets/ui/minimap_icons.png` | 32Ã—16 atlas, 4Ã—2 grid of 8Ã—8 type icons |
| `apps/game/client/scenes/ui/combat_hud.tscn` | Authored HUD; `MinimapAnchor/Minimap` uses `minimap.gd` |
| `apps/game/client/scripts/ui/combat_hud.gd` | Forwards API, `bind_player`, `map` overlay, `MinimapAnchor` visibility |
| `apps/game/client/scripts/dungeon/castle_run.gd:122-150` | Sole `configure_minimap` / `mark_room_visited` / `set_current_room` caller |
| `apps/game/client/scripts/dungeon/procgen/room_graph_geometry.gd:99-115` | Emits `size` and `kind` per room |
| `apps/game/client/scripts/dungeon/procgen/dungeon_procgen.gd:76` | Overrides `kind` to `key` when `roomContent[].keyId` is set |
| `apps/game/client/scripts/validation/suites/room_graph_suite.gd` | Minimap regression tests (`map.*`) |

## How it works

### Data intake
`configure(definition)` copies `rooms`, `edges`, and `branchPreviews` from the dungeon definition, builds `_room_by_id`, `_center_by_id`, and `_neighbors` caches, and clears reveal state.

Each `rooms[]` entry reads: `id`, `transform.x` / `transform.z`, optional `size.x` / `size.z` (world metres), and optional `kind` (`combat`, `treasure`, `shop`, `key`, `boss`, `entrance`, `stairs`, `unknown`).

### Reveal tiers
`enum RevealTier { UNKNOWN, SEEN, VISITED }` stored in `_reveal`.

`mark_visited(room_id)` sets the room to `VISITED` and each graph neighbour to at least `SEEN`. Edges draw only when both endpoints are `>= SEEN`; `SEEN` rooms render as outlines, `VISITED` rooms as filled rects. Dashed lines mark edges touching a `SEEN` endpoint.

### Projection
`_recompute_bounds()` seeds accumulators from the first room (no forced world-origin inclusion). `_map_point()` uses a single uniform scale `minf(map_w / bounds_w, map_h / bounds_h) * _zoom` and `.floor()` for pixel snapping.

### Player marker
`bind_player(player: Node3D)` tracks the player. `_process` redraws at 10 Hz when the player moves more than 0.25 m. A 7 px triangle at the projected XZ position rotates by `player.global_rotation.y`.

### Drawing order (`_draw`)
1. Background `COLOR_BG` + 1 px outline.
2. Gated edges (solid or dashed).
3. `SEEN` outlines / `VISITED` filled rects sized from `size` (fallback 9Ã—9 px).
4. 8Ã—8 type icon per visited room from `minimap_icons.png`.
5. Branch preview markers (gold circle / red diamond).
6. Player arrow.
7. Legend row (overlay mode only).

### Visibility and overlay
`has_graph()` returns `not _rooms.is_empty()`. `combat_hud.gd` sets `Minimap.visible` from it after `configure_minimap`.

Pressing `map` (`M` keyboard, joypad button 6) opens a `MenuShell` modal with a second `minimap.gd` instance in `enable_overlay_mode()`: full-rect, `mouse_filter = STOP`, mouse-wheel zoom `0.5`â€“`4.0`, middle-drag pan, legend with `tr()` labels. `ui_cancel` closes the overlay and unpauses.

## Contracts
- Public API: `configure`, `mark_visited`, `set_current_room`, `bind_player`, `has_graph`, `export_state` / `import_state`, `enable_overlay_mode` / `disable_overlay_mode`.
- Forwarded through `combat_hud.gd`: `configure_minimap`, `mark_room_visited`, `set_current_room`.
- Input action: `map` in `project.godot`.
- Translation keys: `MAP_TITLE`, `MAP_HINT`, `MAP_LEGEND_*`.
- No autoload dependency, no save state.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Room graph source | IMPLEMENTED | `minimap.gd:configure`; `dungeon_procgen.gd:85` |
| Fog of war on rooms | IMPLEMENTED | `RevealTier` gating in `_draw_rooms` |
| Fog of war on edges | IMPLEMENTED | `_should_draw_edge` requires both `>= SEEN` |
| Player position + facing | IMPLEMENTED | `bind_player`, `_draw_player_marker` |
| Room footprints | IMPLEMENTED | `_room_pixel_size` from `size` |
| Uniform aspect ratio | IMPLEMENTED | `_uniform_scale` |
| Pixel snapping | IMPLEMENTED | `.floor()` in `_map_point` |
| Bounds without origin bias | IMPLEMENTED | first-room seed in `_recompute_bounds` |
| Room-type icons | IMPLEMENTED | `minimap_icons.png`, `_draw_room_icon` |
| Branch preview markers | IMPLEMENTED | `_draw_branch_previews` |
| Hub/waves/arena visibility | IMPLEMENTED | `has_graph()` + `combat_hud.gd:configure_minimap` |
| Full-map overlay | IMPLEMENTED | `combat_hud.gd:_open_map_overlay`, `map` action |
| Legend | IMPLEMENTED | `_draw_legend` in overlay mode |
| Procgen `size` / `kind` | IMPLEMENTED | `room_graph_geometry.gd:107-108`, `dungeon_procgen.gd:_annotate_minimap_key_rooms` |
| Validation | IMPLEMENTED | `room_graph_suite.gd` `map.*` tests |

## Related
- Improvement plan: [`../actual_improvements/ui/minimap.md`](../actual_improvements/ui/minimap.md) - **FINISHED**
- [`combat_hud.md`](combat_hud.md)
- [`../room-graph-procgen.md`](../room-graph-procgen.md) Â· [`../room-content.md`](../room-content.md) Â· [`../castle-run.md`](../castle-run.md)
