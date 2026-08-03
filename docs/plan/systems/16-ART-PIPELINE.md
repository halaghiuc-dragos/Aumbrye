# System: Art Pipeline

## Style

Handcrafted pixel diorama: crisp pixels, low poly, chunky silhouettes, expressive lighting, handcrafted imperfections. No photoreal. No AI-looking finals.

## Formats

| Asset | Format |
|-------|--------|
| Models | glTF |
| Textures | PNG, filter Nearest |
| Icons | SVG preferred |
| Source | Blender, Aseprite/LibreSprite, Blockbench |

## Major milestones

| Major | Title | Phase |
|-------|-------|-------|
| ART-0 | Folder + placeholder policy | M0 |
| ART-2 | Castle blockout kit | M2 |
| ART-5 | Castle art pass + new themes | M5 |
| ART-6 | Fortress + Cathedral kits | M6 |

## Minor milestones

| ID | Title | Phase |
|----|-------|-------|
| ART-2.1 | Castle room kit blockout | M2 |
| THEME-5.1 | Castle art pass | M5 |

## Policy

Kenney/blockout until combat+loop proven. Replace per theme. Prefer licensed/open packs matching style over random scrapes.

## Runtime pixel pipeline

Low-res 3D render + nearest upscale + surface shaders. **Do not reparent** scene nodes into SubViewport.

| Component | Path |
|-----------|------|
| Autoload | `apps/game/client/scripts/art/pixel_diorama_viewport.gd` |
| Settings | `apps/game/client/scripts/art/pixel_diorama_settings.gd` |
| Surface shader | `apps/game/client/shaders/pixel_diorama_surface.gdshader` |
| Style helpers | `apps/game/client/scripts/art/pixel_diorama_style.gd` |

Full architecture: [visual_enhancement_plan.md](../../design/visual_enhancement_plan.md).
