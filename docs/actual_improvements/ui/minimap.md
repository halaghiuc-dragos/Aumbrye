# Minimap — improvement plan

## Current state
`minimap.gd` draws the real generated room graph — it reads `rooms[].transform`, `edges`, and `branchPreviews` from the same dictionary `dungeon_procgen.gd` produces, so the layout is honest rather than a stand-in (`minimap.gd:20-27`). What is missing is everything that makes a map usable: all edges are drawn regardless of whether the player has seen them, there is no player dot or facing indicator, every room is an identical `9×9` square with no room-type icon, the two axes are normalized independently so non-square dungeons are stretched, and the widget is only ever configured by `castle_run.gd:107`, so the hub, waves run, and arenas render an empty control. See [`../existing_codebase/ui/minimap.md`](../existing_codebase/ui/minimap.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| MAP-01 | P0 | Edge fog of war is inverted: every edge in the graph is drawn from the first frame, so the player can read the whole dungeon topology — including the route to the boss — before exploring. Room fog of war is therefore cosmetic. | `minimap.gd:53-60` draws all `_edges` with no `_visited` check, contrasted with `:65-66` which skips unvisited rooms |
| MAP-02 | P0 | No player marker and no facing indicator. Only the current room is tinted gold, which is useless in the large rooms `room_graph_geometry.gd` generates. | `minimap.gd:67-69`; the file never reads a player node or camera |
| MAP-03 | P1 | Every room is the same `9×9` square. Room footprint, corridor versus chamber, and dead ends are indistinguishable. | `minimap.gd:69` uses the constant `CELL = 10.0` for all rooms |
| MAP-04 | P1 | No room-type iconography. `_draw` reads only `id` and `transform`, so treasure, shop, key, and boss rooms look identical once visited. | `minimap.gd:61-69` |
| MAP-05 | P1 | The minimap is dead weight in the hub, the waves run, and both debug arenas: `combat_hud.gd` instantiates it in every scene but only `castle_run.gd` calls `configure`, so `_draw` returns at line 49 and an empty 140×140 control sits in the corner. | `minimap.gd:48-49`; sole `configure_minimap` caller `castle_run.gd:107` |
| MAP-06 | P1 | Independent per-axis normalization stretches non-square dungeons, so relative distances on the map do not match the world. | `minimap.gd:107-114` |
| MAP-07 | P1 | Nothing is pixel-snapped, so map lines and squares shimmer under the low-res viewport that `combat_hud.gd:413-414` explicitly floors for. | `minimap.gd:60`, `:69`, `:133` |
| MAP-08 | P2 | `_recompute_bounds` seeds its accumulators at `0.0` instead of the first room's coordinates, so `_bounds` always contains world origin and the drawn graph is offset toward a corner whenever no room sits near it. | `minimap.gd:74-88` |
| MAP-09 | P2 | No legend and no full-map view: `mouse_filter = MOUSE_FILTER_IGNORE` and there is no input handling, so the player cannot expand or inspect the map. | `minimap.gd:44` |
| MAP-10 | P2 | `_room_center` performs a linear scan of `_rooms` on every call, and `_draw` calls it two to three times per edge and once per room, giving O(rooms × edges) per redraw. | `minimap.gd:91-99` called from `:56-57`, `:67`, `:128-129` |

## Target design

### Reveal model
Introduce three explicit reveal tiers, stored per room id, and drive edges from them:

| Tier | Meaning | Room drawn as | Edge drawn as |
|---|---|---|---|
| `UNKNOWN` | never entered, never adjacent to a visited room | not drawn | not drawn |
| `SEEN` | adjacent to a visited room via a traversed door, but not entered | outline only, `COLOR_SEEN = Color(0.32, 0.30, 0.28, 0.75)` | dashed 1 px `COLOR_EDGE` |
| `VISITED` | entered | filled, `COLOR_VISITED` | solid 1 px `COLOR_EDGE` |

`mark_visited(room_id)` promotes that room to `VISITED` and every graph neighbour to at least `SEEN`. An edge is drawn only when both endpoints are at least `SEEN`. This keeps forward progress legible without leaking unexplored topology (MAP-01).

Rejected alternative: revealing edges on door *use* only. It hides the branch choice the player is standing in front of, which contradicts the `branchPreviews` feature already shipped at `minimap.gd:117-144`.

### Player marker
`configure` gains an optional player reference and the widget tracks it directly:

```gdscript
func bind_player(player: Node3D) -> void
func _process(_delta: float) -> void   # queue_redraw() at 10 Hz when the player has moved > 0.25 m
```

Draw an authored 7×7 arrow from the HUD atlas rotated by the player's yaw, at `_map_point(Vector2(player.global_position.x, player.global_position.z))`. `combat_hud.gd` calls `bind_player` from the same block that resolves `player_path` (`combat_hud.gd:81-89`) (MAP-02).

### Real room footprints and type icons
`room_graph_geometry.gd:99` already knows each room's size when it writes `transform`; extend the emitted room entry with `"size": {"x": float, "z": float}` and `"kind": String`. The minimap then draws each room as a rect scaled from `size` through the same projection as its center, and stamps a 8×8 type icon in the room's middle.

Room-kind icon cells (from `assets/ui/minimap_icons.png`, a 4×2 grid of 8×8 cells at 32×16 total):

| Cell (col,row) | Name | `kind` value |
|---|---|---|
| (0,0) | `combat` | `combat` |
| (1,0) | `treasure` | `treasure` |
| (2,0) | `shop` | `shop` |
| (3,0) | `key` | `key` |
| (0,1) | `boss` | `boss` |
| (1,1) | `entrance` | `entrance` |
| (2,1) | `stairs` | `stairs` |
| (3,1) | `unknown` | anything unmatched |

`kind` comes from the room-content assigner (see [`../room-content.md`](../room-content.md)); when the key is absent the `unknown` cell is used, so this lands safely before the procgen change (MAP-03, MAP-04).

### Uniform-scale projection
Replace the two independent ratios with one scale factor plus centering:

```gdscript
func _map_point(world_xz: Vector2, map_rect: Rect2) -> Vector2:
    var s := minf(map_rect.size.x / _bounds.size.x, map_rect.size.y / _bounds.size.y)
    var offset := map_rect.position + (map_rect.size - _bounds.size * s) * 0.5
    return (offset + (world_xz - _bounds.position) * s).floor()
```

The trailing `.floor()` fixes MAP-07 for every drawn primitive at once. `_recompute_bounds` seeds from the first room and no longer forces origin inclusion (MAP-06, MAP-08).

### Room-center cache
Build `_room_by_id: Dictionary[String, Dictionary]` and `_center_by_id: Dictionary[String, Vector2]` inside `configure`; `_room_center` becomes a dictionary lookup (MAP-10).

### Visibility gating and a full-map view
`combat_hud.gd` sets `Minimap.visible` from a new `has_graph()` accessor, so the empty control never occupies HUD space in the hub, waves, or arenas (MAP-05).

Add a full-screen map overlay bound to a new `map` input action (default `M` on keyboard, joypad button 6 / Back-Select): the same `minimap.gd` script instanced at `PRESET_FULL_RECT` inside a `MenuShell.build_modal`, with `mouse_filter = MOUSE_FILTER_STOP`, mouse-wheel zoom in the range `0.5`–`4.0`, middle-drag pan, and a legend row listing each icon cell with its `tr()` label. The HUD widget stays non-interactive (MAP-09).

## Work plan
1. **Projection and snapping** — uniform scale, `.floor()`, first-room bounds seeding, `_room_by_id` / `_center_by_id` caches (MAP-06, MAP-07, MAP-08, MAP-10).
2. **Reveal tiers** — add the `RevealTier` enum and `_reveal: Dictionary`; promote neighbours in `mark_visited`; gate edge drawing on both endpoints (MAP-01).
3. **Visibility gating** — add `has_graph()`; have `combat_hud.gd` bind `Minimap.visible` to it (MAP-05).
4. **Player marker** — add `bind_player`, the 10 Hz redraw, and the arrow draw; call it from `combat_hud.gd:81-89` (MAP-02).
5. **Icons and footprints** — author `assets/ui/minimap_icons.png`; draw type icons keyed on `kind` with an `unknown` fallback; draw room rects from `size` when present (MAP-03, MAP-04).
6. **Procgen data** — emit `size` and `kind` per room from `room_graph_geometry.gd` / the room-content assigner; update the dungeon-definition schema (MAP-03, MAP-04).
7. **Full map** — add the `map` input action, the overlay scene, zoom/pan, and the legend (MAP-09).

Steps 1-4 are independent of the procgen change; step 5 degrades to the `unknown` icon until step 6 lands.

## Data and schema changes
- `content/schemas/dungeon-definition.v1.json`: add to each `rooms[]` entry `"size": {"type": "object", "properties": {"x": {"type": "number"}, "z": {"type": "number"}}}` and `"kind": {"type": "string", "enum": ["combat", "treasure", "shop", "key", "boss", "entrance", "stairs"]}`. Both optional, so hand-authored dungeon files remain valid.
- `apps/game/client/project.godot`: new `map` input action (`[input] map={...}` with `physical_keycode` `M` and joypad button 6).
- `apps/game/client/translations/strings.csv`: `MAP_LEGEND_COMBAT`, `MAP_LEGEND_TREASURE`, `MAP_LEGEND_SHOP`, `MAP_LEGEND_KEY`, `MAP_LEGEND_BOSS`, `MAP_LEGEND_ENTRANCE`, `MAP_LEGEND_STAIRS`, `MAP_TITLE`.
- New asset: `apps/game/client/assets/ui/minimap_icons.png` (32×16, 4×2 grid of 8×8 cells) plus `.import` with `filter=false`, `mipmaps=false`.
- No save-format change; reveal state lives in the existing castle-run snapshot path if persisted, and no new save key is introduced by this plan. No `save_migrator.gd` bump.

## Acceptance criteria
- [ ] With one room visited, no edge whose far endpoint is `UNKNOWN` is drawn.
- [ ] Entering a room promotes each of its graph neighbours to `SEEN`, and `SEEN` rooms draw as outlines while `VISITED` rooms draw filled.
- [ ] A rotating player arrow is drawn at the player's projected position and its rotation tracks player yaw.
- [ ] A dungeon whose bounding box is `60 × 20` m draws with equal horizontal and vertical metres-per-pixel.
- [ ] Every coordinate passed to `draw_rect`, `draw_line`, `draw_circle`, and `draw_colored_polygon` is integral.
- [ ] A dungeon whose rooms all sit at `x > 100` fills the widget instead of hugging one corner.
- [ ] `Minimap.visible` is `false` in `hub.tscn`, the waves run, and both debug arenas.
- [ ] Each visited room draws the icon cell matching its `kind`, and a room with no `kind` draws the `unknown` cell.
- [ ] `_room_center` performs no array scan.
- [ ] Pressing `map` opens a full-screen map with a legend; mouse wheel changes zoom within `0.5`–`4.0`; `ui_cancel` closes it.

## Validation
Extend `apps/game/client/scripts/validation/suites/room_graph_suite.gd`:

| Test id | Assertion |
|---|---|
| `map.edge_fog` | configure a 5-room chain, `mark_visited` only room 1, and assert the drawn-edge count is 1 (the edge to the newly `SEEN` neighbour) rather than 4 |
| `map.neighbour_promotion` | after `mark_visited("r1")`, `get_reveal_tier("r2") == SEEN` and `get_reveal_tier("r3") == UNKNOWN` |
| `map.player_marker_bound` | `bind_player(node)` then moving the node 5 m changes the value returned by a new `get_player_map_point()` |
| `map.uniform_scale` | for bounds `60×20`, `_map_point(Vector2(1,0))` and `_map_point(Vector2(0,1))` differ from `_map_point(Vector2.ZERO)` by the same magnitude |
| `map.integral_coords` | every value returned by `_map_point` satisfies `is_equal_approx(v.x, floor(v.x))` |
| `map.bounds_no_origin_bias` | rooms at `x` in `[100, 160]` produce `_bounds.position.x == 100.0` |
| `map.has_graph_false_when_unconfigured` | a fresh minimap reports `has_graph() == false` |
| `map.icon_cells_present` | `assets/ui/minimap_icons.png` loads and its size is `Vector2i(32, 16)` |
| `map.kind_fallback` | a room entry with no `kind` resolves to the `unknown` cell index |
| `map.center_cache` | `minimap.gd` contains no `for room_def in _rooms` inside `_room_center` |
| `map.action_registered` | `InputMap.has_action("map")` |

## Related
- Existing behavior: [`../existing_codebase/ui/minimap.md`](../existing_codebase/ui/minimap.md)
- [`combat_hud.md`](combat_hud.md)
- [`../room-graph-procgen.md`](../room-graph-procgen.md) · [`../room-content.md`](../room-content.md) · [`../castle-run.md`](../castle-run.md)
