# Portal ellipse shader — improvement plan

## Status: FINISHED

## Current state

`PixelDioramaStyle.build_portal()` is the single archway + layered interior builder; hub, arena, and in-run portals all use it with `content/art/portals.json` definitions via `PortalCatalog.resolve()`. Portal shader receives `color_levels` and scaled `pixel_scale` from settings. Merchant stalls use `build_merchant_stall()`. Enter burst and ambient hum are data-driven. See [`../existing_codebase/portal-ellipse-shader.md`](../existing_codebase/portal-ellipse-shader.md).

## Gaps

| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| POR-01 | P0 | Shader only on hub portals | FINISHED — `build_portal()` everywhere |
| POR-02 | P0 | `glow.emission` runtime error | FINISHED — palette colour passed to `_add_orb()` |
| POR-03 | P1 | Settings skip portal shader | FINISHED — `PORTAL_SHADER_SUFFIX` branch |
| POR-04 | P1 | Fourth portal colour table | FINISHED — `portals.json` |
| POR-05 | P1 | Hub-only theme strings | FINISHED — biome entries + aliases |
| POR-06 | P1 | Duplicate archway builders | FINISHED — unified `build_portal()` |
| POR-07 | P2 | Flat quad interior | FINISHED — three-layer depth stack |
| POR-08 | P2 | Uncached materials | FINISHED — `_portal_material_cache` |
| POR-09 | P2 | No portal audio/VFX | FINISHED — `sfx` keys + enter burst |
| POR-10 | P2 | No shader validation | FINISHED — `portal_shader_suite.gd` |

## Validation

`portal_shader_suite.gd` (category `graphics`): JSON load, biome coverage, aliases, unknown-id fallback, colour bounds, uniform coverage, settings reach, cache, single builder source, child names, interior layers, exit portal shader, merchant stall, sfx keys.

Run: `powershell -File scripts/godot-bin.ps1 --headless --path apps/game/client --script res://scripts/validation/validation_main.gd -- --suite=portal_shader_suite`

## Acceptance criteria

- [x] Castle exit portal shows spiral interior. (POR-01)
- [x] No `Invalid get index 'emission'` when skinning portals. (POR-02)
- [x] Colour levels and pixel scale affect portal interior. (POR-03)
- [x] `portals.json` retints portal and glow without code. (POR-04)
- [x] All ten biomes have distinct portal colours. (POR-05)
- [x] No duplicate archway literals in hub/arena. (POR-06)
- [x] Three interior layers show parallax. (POR-07)
- [x] Hub portals share cached materials per id. (POR-08)
- [x] Portal hum and enter burst on approach/traversal. (POR-09)
- [x] Merchant stall is not a portal shape. (POR-01)

## Related

- Existing behaviour: [`../existing_codebase/portal-ellipse-shader.md`](../existing_codebase/portal-ellipse-shader.md)
- [`pixel-style.md`](pixel-style.md) · [`vfx-service.md`](vfx-service.md) · [`audio-director.md`](audio-director.md)
