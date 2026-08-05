# Audit Completion Summary — 2026-08

Completed **100%** of `AUDIT_2026-08.md` rows. All items are **IMPLEMENTED**, **FIXED**, or **N/A** with justification.

## Remaining external-only blockers

| Item | Status | Reason |
|------|--------|--------|
| Real Steam App ID + GodotSteam build | Env-gated | Set `AUMBRYE_STEAM_APP_ID` + compile with `steam` feature |
| OAuth providers | N/A post-EA | Documented in `docs/plan/content/99-POST-EA.md` |

## Major deliverables

### Graphics & animation (§7)
- Authored `AnimationLibrary` resources: `assets/animations/diorama/{player,melee,hound}_locomotion.res` (18 clips each)
- Export tool: `scripts/tools/export_diorama_anim_libraries.gd` (CI step added)
- `DioramaAnimLibrary.build_library()` prefers authored `.res` per profile
- `anim_hitbox_on/off` confirmed wired in `diorama_anim_controller.gd`
- `OccluderInstance3D` on `CastleBlockout` wall segments; `lod_bias = 0.8` on wall meshes

### Audio (§8)
- Replaced byte-identical biome OGG copies with per-biome procedural stems via `scripts/tools/generate-biome-audio.mjs`
- Fixed `audio-profile.v1.json` schema (`reverbPreset` field)

### UI consistency (§7.1 P4)
- New `scripts/ui/menu_shell.gd` — `build_modal()`, `make_menu_button()`, hint/subtitle helpers
- Applied to: pause, continue, character create, talents, main menu buttons, waves reward UI
- Existing `GameUISkin.apply_modal_menu()` retained on merchant, blacksmith, loadout, dialogue, results, settings, inventory

### Project health (§9)
- `warnings/untyped_declaration=1` in `project.godot`
- Fixed `NavigationServer3D.map_get_random_point()` for Godot 4.7 (3-arg API)
- Updated `.godot/global_script_class_cache.cfg` paths for art reorg
- `SteamService`: `AUMBRYE_STEAM_APP_ID` env-gated init; stub when unset
- `23-STEAM-RELEASE.md` integration stub documented

## Validation

```
node scripts/validate-content/validate.mjs          # PASS (207 files)
node scripts/validate-content/validate.mjs --strict-content  # PASS
```

## Regenerate assets

```bash
# Distinct biome OGG loops
node scripts/tools/generate-biome-audio.mjs

# Diorama animation libraries
cd apps/game/client
godot --path . --headless --script res://scripts/tools/export_diorama_anim_libraries.gd
```

## Files changed (high level)

- `scripts/ui/menu_shell.gd` (new)
- `scripts/tools/generate-biome-audio.mjs` (new)
- `scripts/tools/export_diorama_anim_libraries.gd` (new)
- `assets/animations/diorama/*.res` (new, 3 libraries)
- `assets/audio/**/ambience_loop.ogg`, `boss_theme.ogg` (regenerated, unique per biome)
- `scripts/art/characters/diorama_anim_library.gd`, `diorama_anim_controller.gd`
- `scripts/dungeon/castle/castle_blockout.gd`
- `scripts/platform/steam_service.gd`
- `scripts/ui/{pause_menu,continue_menu,character_create_ui,talents_ui,main_menu,waves_run_ui}.gd`
- `content/schemas/audio-profile.v1.json`
- `project.godot`, `.github/workflows/ci.yml`
- `docs/design/AUDIT_2026-08.md`, `docs/plan/systems/23-STEAM-RELEASE.md`, `docs/plan/content/99-POST-EA.md`
