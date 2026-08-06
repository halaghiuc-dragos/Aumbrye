# Minimap — improvement plan

## Status: FINISHED

## Current state
`minimap.gd` draws the real generated room graph with three-tier fog of war (`UNKNOWN` / `SEEN` / `VISITED`), uniform-scale projection with pixel snapping, variable room footprints from procgen `size`, type icons from `kind`, a rotating player arrow, and visibility gating via `has_graph()`. `combat_hud.gd` hides the widget when unconfigured and opens a full-map overlay on the `map` input action (`M` / joypad Back-Select). Procgen emits `size` and `kind` on each room entry. See [`../existing_codebase/ui/minimap.md`](../existing_codebase/ui/minimap.md).

## Gaps

| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| MAP-01 | P0 | Edge fog of war inverted — full topology visible from frame one | FINISHED — edges gated on both endpoints `>= SEEN` |
| MAP-02 | P0 | No player marker or facing indicator | FINISHED — `bind_player` + 7 px yaw arrow |
| MAP-03 | P1 | Every room identical `9×9` square | FINISHED — rects from procgen `size` |
| MAP-04 | P1 | No room-type iconography | FINISHED — `minimap_icons.png` keyed on `kind` |
| MAP-05 | P1 | Empty minimap in hub/waves/arenas | FINISHED — `has_graph()` drives `Minimap.visible` |
| MAP-06 | P1 | Independent per-axis normalization stretches dungeons | FINISHED — single uniform scale factor |
| MAP-07 | P1 | No pixel snapping | FINISHED — `.floor()` on all draw coordinates |
| MAP-08 | P2 | Bounds seeded at origin | FINISHED — first-room seed in `_recompute_bounds` |
| MAP-09 | P2 | No legend or full-map view | FINISHED — `map` action + overlay with zoom/pan/legend |
| MAP-10 | P2 | O(rooms × edges) center lookup | FINISHED — `_center_by_id` dictionary cache |

## Validation

Extended `room_graph_suite.gd` with `map.edge_fog`, `map.neighbour_promotion`, `map.player_marker_bound`, `map.uniform_scale`, `map.integral_coords`, `map.bounds_no_origin_bias`, `map.has_graph_false_when_unconfigured`, `map.icon_cells_present`, `map.kind_fallback`, `map.center_cache`, `map.action_registered`.

## Related
- Existing behavior: [`../existing_codebase/ui/minimap.md`](../existing_codebase/ui/minimap.md)
- [`combat_hud.md`](combat_hud.md)
- [`../room-graph-procgen.md`](../room-graph-procgen.md) · [`../room-content.md`](../room-content.md) · [`../castle-run.md`](../castle-run.md)
