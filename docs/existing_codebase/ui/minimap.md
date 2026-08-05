# Minimap

A `Control` that draws the real generated room graph with `_draw()` primitives. It reveals only rooms the player has entered, highlights the current room, and draws a marker for each unvisited branch target. It is on the live play path in castle runs only: the control is instantiated in every scene by `combat_hud.gd:552-558`, but only `castle_run.gd` ever supplies it with data, so in the hub, the waves run, and the debug arenas it draws nothing.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/ui/minimap.gd` | `extends Control` — 145 lines, whole minimap |
| `apps/game/client/scripts/ui/combat_hud.gd:552-558` | instantiates it as `Minimap` at `Vector2(size.x - 156.0, 20.0)` |
| `apps/game/client/scripts/dungeon/castle_run.gd:104-149` | only caller of `configure` / `mark_visited` / `set_current_room`, via the HUD forwarding methods |
| `apps/game/client/scripts/dungeon/procgen/dungeon_procgen.gd:98-140` | produces the `rooms` / `edges` / `branchPreviews` dictionary the minimap reads |

## How it works

### Data intake
`configure(definition)` (`minimap.gd:20`) copies three arrays straight out of the dungeon definition and clears all reveal state:
- `definition["rooms"]` — each entry is a `Dictionary` with `id` and `transform: {x, y, z, yaw}`.
- `definition["edges"]` — each entry has `from` and `to` room ids.
- `definition["branchPreviews"]` — each entry has `fromRoomId`, `toRoomId`, and `hint` (`"reward"` or anything else, treated as danger).

This is the same generated structure `dungeon_procgen.gd` emits (`:98` for `branchPreviews`, `room_graph_geometry.gd:99` for each room's `transform`), so the map reflects the real graph rather than a hand-drawn stand-in.

`mark_visited(room_id)` (`:30`) sets `_visited[room_id] = true` and redraws. `set_current_room(room_id)` (`:37`) stores the id and redraws. `castle_run.gd:118-125` calls both on every room change.

### Bounds and projection
`_recompute_bounds()` (`:73`) seeds `min_x`, `max_x`, `min_z`, `max_z` at `0.0` and folds every room's `transform.x` / `transform.z` in, producing `_bounds = Rect2(min_x, min_z, max(1.0, width), max(1.0, height))`. Because the accumulators start at `0.0` rather than at the first room's coordinates, the bounds always include world origin whether or not a room sits there.

`_map_point(world_xz, map_rect)` (`:102`) normalizes each axis against `_bounds` (defaulting to `0.5` when an axis has zero extent) and maps it linearly into `map_rect`. World `+Z` maps to screen `+Y`, and the two axes are scaled independently, so a non-square dungeon is stretched to fill the widget.

### Drawing
`_draw()` (`:47`) returns immediately when `_rooms` is empty. Otherwise, in order:
1. `map_rect = Rect2(6, 6, size.x - 12, size.y - 12)` (`PADDING = 6.0`).
2. A full-size background `draw_rect` in `COLOR_BG = Color(0.05, 0.05, 0.08, 0.82)` and a 1 px `Color(0.2, 0.18, 0.16)` outline.
3. Every edge in `_edges` as a 1 px `COLOR_EDGE = Color(0.35, 0.33, 0.30, 0.7)` line — including edges to rooms the player has never seen.
4. Every **visited** room as a `9×9` square (`CELL = 10.0`, drawn at `CELL * 0.9`), `COLOR_CURRENT = Color(0.95, 0.78, 0.28)` for the current room, `COLOR_VISITED = Color(0.55, 0.52, 0.48, 0.95)` otherwise.
5. `_draw_branch_previews(map_rect)` (`:117`) — for each preview whose `fromRoomId` equals the current room and whose `toRoomId` is not yet visited: a radius-3 gold circle for `hint == "reward"`, otherwise a radius-3 red diamond built from `draw_colored_polygon`.

`_ready()` (`:42`) sets `custom_minimum_size = Vector2(140, 140)` and `mouse_filter = MOUSE_FILTER_IGNORE`.

## Contracts
- Public API: `configure(Dictionary)`, `mark_visited(String)`, `set_current_room(String)`. All three are invoked through `combat_hud.gd`'s `configure_minimap` / `mark_room_visited` / `set_current_room` wrappers (`combat_hud.gd:508-521`), which use `has_method` guards.
- Dungeon-definition keys read: `rooms[].id`, `rooms[].transform.x`, `rooms[].transform.z`, `edges[].from`, `edges[].to`, `branchPreviews[].fromRoomId`, `branchPreviews[].toRoomId`, `branchPreviews[].hint`.
- No autoload dependency, no save state, no signal emitted or consumed.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Room graph source | IMPLEMENTED — reads the generated definition, not a placeholder | `minimap.gd:21-23`; `dungeon_procgen.gd:98`, `room_graph_geometry.gd:99` |
| Fog of war on rooms | IMPLEMENTED — unvisited rooms are not drawn | `minimap.gd:65-66` |
| Fog of war on edges | BROKEN — all edges are drawn regardless of visit state, so the full graph shape is visible from the first room | `minimap.gd:53-60` |
| Player position marker | ABSENT — only the current *room* is tinted; there is no dot for the player and no facing indicator | `minimap.gd:67-69`; no reader of player position in the file |
| Room shape and size | PLACEHOLDER — every room is the same `9×9` square regardless of its real footprint | `minimap.gd:69` |
| Aspect ratio | PARTIAL — axes are normalized independently, so non-square layouts are stretched | `minimap.gd:107-114` |
| Bounds computation | PARTIAL — accumulators start at `0.0`, so world origin is always inside `_bounds` even with no room there | `minimap.gd:74-77` |
| Room-type iconography (shop, treasure, boss, key) | ABSENT — `_draw` reads only `id` and `transform` from each room entry | `minimap.gd:61-69` |
| Branch preview markers | IMPLEMENTED — gold circle / red diamond primitives | `minimap.gd:130-144` |
| Minimap in hub, waves, arenas | PARTIAL — control exists but is never configured, so `_draw` returns at line 49 | only `configure_minimap` caller is `castle_run.gd:107` |
| Legend or key | ABSENT — no text is drawn anywhere in the file | `minimap.gd:47-70` |
| Zoom, pan, or full-map view | ABSENT — no input handling; `mouse_filter = IGNORE` | `minimap.gd:44` |
| Pixel snapping | ABSENT — `draw_rect` / `draw_line` / `draw_circle` receive unrounded floats, unlike `combat_hud.gd:413-414` which floors reticle coordinates | `minimap.gd:60`, `:69`, `:133` |
| Nearest-neighbour filtering | ABSENT — no `texture_filter` assignment; the widget is pure vector drawing | `minimap.gd:42-45` |

## Related
- Improvement plan: [`../actual_improvements/ui/minimap.md`](../actual_improvements/ui/minimap.md)
- [`combat_hud.md`](combat_hud.md)
- [`../room-graph-procgen.md`](../room-graph-procgen.md) · [`../room-content.md`](../room-content.md) · [`../castle-run.md`](../castle-run.md) · [`../dungeon-builder.md`](../dungeon-builder.md)
