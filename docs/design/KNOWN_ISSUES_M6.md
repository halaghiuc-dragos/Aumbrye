# Known Issues (M6)

## AUTH-6.1 — OAuth deferred

Google and Discord OAuth are **not implemented** in M6. Email/password auth works via `/api/v1/auth`. Website account page notes the deferral. Track for post-EA polish per DEC-B06.

## Content ID aliases

Boss roster IDs (`boss_castle_knight`, etc.) alias to existing scenes where noted. Legacy enemy IDs (`crystal_slime`, `swamp_hydra`) remain on disk for M5 compatibility but biomes use roster IDs.

## Item catalog

Catalog is the validation source of truth (73 equipment/consumables/materials on disk; 79 total with relics). Relic defs in `content/relics/` use `relic-definition` schema (not item-instance).

## UTF-8 BOM on generated assets (fixed)

M6 batch-generated `.tscn` / `.gd` files initially had UTF-8 BOM, causing Godot `Parse Error: Expected '['` at line 1. Fixed 2026-07-31. When generating Godot files from PowerShell, use `[System.IO.File]::WriteAllText(..., (New-Object System.Text.UTF8Encoding $false))` — not `Out-File -Encoding UTF8`.

## Performance

1080p60 target documented in `docs/design/performance_m6.md`; not CI-gated.

## Godot MCP editor tools

Headless validation passes without the editor GUI. Editor-dependent MCP tools (`editor_status`, `scene_management`, `scene_hierarchy`, `scene_run`) require Godot 4.7 open with the `godot_mcp` plugin connected.

**Fixed 2026-08-03:** `scene_run` no longer crashes on Godot 4.7 — `EditorInterface` is cached from the plugin instead of `Engine.get_singleton`. See [PROCgen_PIXEL_CHANGELOG_2026-08.md](PROCgen_PIXEL_CHANGELOG_2026-08.md).

Runtime probes (`project_info`, `filesystem_file`, `debug_log`) work without the editor.

## Partial carry-over to M7

- Input remapping UI
- Mythic per-item unique behavior
- Status HUD icon art
- Final OGG audio + diorama room art
