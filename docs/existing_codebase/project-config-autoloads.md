# Project config and autoloads

Everything `apps/game/client/project.godot` declares: 21 autoload singletons, 35 input actions, display/rendering settings, physics layer names, GDScript warning level, and the engine feature tag. This file is loaded before any scene, so every claim here is on the live play path.

## Files

| Path | Role |
|------|------|
| `apps/game/client/project.godot` | Single Godot project settings file, `config_version=5` |
| `apps/game/client/translations/strings.csv` + `strings.en.translation` | Only registered locale |
| `apps/game/client/assets/audio/default_bus_layout.tres` | Audio bus layout referenced at `project.godot:25` |
| `apps/game/client/addons/godot_mcp/plugin.cfg` | Only enabled editor plugin (`project.godot:64`) |

## How it works

### Application

| Setting | Value | Line |
|---------|-------|------|
| `config/name` | `"Aumbrye"` | `project.godot:17` |
| `config/description` | `"Action roguelite RPG"` | `project.godot:18` |
| `run/main_scene` | `res://scenes/ui/title_screen.tscn` | `project.godot:19` |
| `config/features` | `PackedStringArray("4.7", "Forward Plus")` | `project.godot:20` |
| `config/icon` | `res://icon.svg` | `project.godot:21` |

The custom section `[aumbrye]` declares one key, `content_root=""` (`project.godot:29`). `ContentLoader` reads it to override the repo-root content path; empty means "derive from `res://`".

### Autoloads (`project.godot:33-53`, in load order)

| # | Name | Script |
|---|------|--------|
| 1 | `RunFlow` | `res://scripts/app/run_flow.gd` |
| 2 | `ApiConfig` | `res://scripts/net/api_config.gd` |
| 3 | `LocalSave` | `res://scripts/save/local_save.gd` |
| 4 | `CharacterService` | `res://scripts/save/character_service.gd` |
| 5 | `ProgressionService` | `res://scripts/progression/progression_service.gd` |
| 6 | `RunBuffs` | `res://scripts/combat/run_buffs.gd` |
| 7 | `InventoryService` | `res://scripts/inventory/inventory_service.gd` |
| 8 | `StorageService` | `res://scripts/hub/storage_service.gd` |
| 9 | `QuestService` | `res://scripts/quests/quest_service.gd` |
| 10 | `AudioDirector` | `res://scripts/audio/audio_director.gd` |
| 11 | `AchievementService` | `res://scripts/meta/achievement_service.gd` |
| 12 | `SteamService` | `res://scripts/platform/steam_service.gd` |
| 13 | `CrashLogger` | `res://scripts/platform/crash_logger.gd` |
| 14 | `WavesRunService` | `res://scripts/dungeon/waves_run_service.gd` |
| 15 | `DungeonTierService` | `res://scripts/dungeon/dungeon_tier_service.gd` |
| 16 | `VfxService` | `res://scripts/art/vfx/vfx_service.gd` |
| 17 | `PlayerControls` | `res://scripts/app/player_controls.gd` |
| 18 | `WorldState` | `res://scripts/app/world_state.gd` |
| 19 | `PixelDioramaViewport` | `res://scripts/art/pipeline/pixel_diorama_viewport.gd` |
| 20 | `AttackTokenService` | `res://scripts/combat/attack_token_service.gd` |
| 21 | `GameFacade` | `res://scripts/app/game_facade.gd` |

All 21 use the `*` prefix, so each is instantiated as a Node under `/root` rather than as a plain script singleton. Load order is the file order: `RunFlow` initializes before `LocalSave`, and `GameFacade` last.

`setup_suite.gd:26-40` asserts only eight of them exist (`RunFlow`, `LocalSave`, `WorldState`, `InventoryService`, `AudioDirector`, `ApiConfig`, `VfxService`, `PlayerControls`).

### Input actions (`project.godot:83-299`)

35 actions. Six are Godot built-ins with overridden bindings; 29 are game actions.

**Built-in UI (`deadzone 0.5`)**

| Action | Keyboard | Gamepad |
|--------|----------|---------|
| `ui_accept` | Enter (`4194309`) | button 0 |
| `ui_cancel` | Escape (`4194305`) | button 1 |
| `ui_left` | Left (`4194319`) | button 13 |
| `ui_right` | Right (`4194321`) | button 14 |
| `ui_up` | Up (`4194320`) | button 11 |
| `ui_down` | Down (`4194322`) | button 12 |

**Locomotion (`deadzone 0.2`)**

| Action | Keyboard | Gamepad |
|--------|----------|---------|
| `move_forward` | `W` (`87`) | axis 1 at `-1.0` |
| `move_back` | `S` (`83`) | axis 1 at `+1.0` |
| `move_left` | `A` (`65`) | axis 0 at `-1.0` |
| `move_right` | `D` (`68`) | axis 0 at `+1.0` |

**Camera look (`deadzone 0.15`, gamepad only)**

`look_left` axis 2 `-1.0`, `look_right` axis 2 `+1.0`, `look_up` axis 3 `-1.0`, `look_down` axis 3 `+1.0` (`project.godot:204-223`). There is no keyboard or mouse-motion binding for look; mouse look is handled in camera scripts, not through the InputMap.

**Combat and movement verbs (`deadzone 0.5`)**

| Action | Keyboard / mouse | Gamepad | Line |
|--------|------------------|---------|------|
| `sprint` | Shift (`4194325`) | button 8 | `project.godot:143` |
| `jump` | `F` (`70`) | button 0 | `project.godot:149` |
| `dodge` | Space (`32`) | button 1 | `project.godot:155` |
| `light_attack` | mouse button 1 | axis 5 at `+1.0` (right trigger) | `project.godot:161` |
| `heavy_attack` | mouse button 2 | button 3 | `project.godot:167` |
| `block` | `Q` (`81`) | axis 4 at `+1.0` (left trigger) | `project.godot:173` |
| `lock_on` | Enter (`4194309`), mouse button 3 | button 5 | `project.godot:179` |
| `heal` | `H` (`72`) | button 7 | `project.godot:283` |
| `two_hand` | `V` (`86`) | — | `project.godot:289` |
| `weapon_art` | `C` (`67`) | button 10 | `project.godot:294` |

**UI and meta**

| Action | Keyboard / mouse | Gamepad | Line |
|--------|------------------|---------|------|
| `pause` | Escape (`4194305`) | button 6 | `project.godot:186` |
| `inventory` | Tab (`4194306`) | button 4 | `project.godot:250` |
| `talents` | `K` (`75`) | button 7 | `project.godot:271` |
| `interact` | `E` (`69`) | button 2 | `project.godot:277` |
| `quick_slot_1` | `1` (`49`) | — | `project.godot:256` |
| `quick_slot_2` | `2` (`50`) | — | `project.godot:261` |
| `quick_slot_3` | `3` (`51`) | — | `project.godot:266` |
| `zoom_in` | mouse button 4 | button 11 | `project.godot:192` |
| `zoom_out` | mouse button 5 | button 12 | `project.godot:198` |
| `toggle_camera` | `P` (`80`) | — | `project.godot:245` |

**Debug**

| Action | Keyboard | Line |
|--------|----------|------|
| `debug_toggle` | F1 (`4194332`) | `project.godot:224` |
| `debug_hitboxes` | F2 (`4194333`) | `project.godot:229` |
| `toggle_damage_numbers` | F3 (`4194334`) | `project.godot:240` |
| `reset_duel` | `R` (`82`), gamepad button 9 | `project.godot:234` |

All keyboard bindings use `physical_keycode`, so they follow physical key position rather than layout.

### Display and rendering

| Setting | Value | Line |
|---------|-------|------|
| `window/size/viewport_width` | `1920` | `project.godot:57` |
| `window/size/viewport_height` | `1080` | `project.godot:58` |
| `window/stretch/mode` | `"canvas_items"` | `project.godot:59` |
| `window/stretch/scale_mode` | `"integer"` | `project.godot:60` |
| `textures/canvas_textures/default_texture_filter` | `0` (nearest) | `project.godot:314` |
| `textures/default_filters/anisotropic_filtering_level` | `0` | `project.godot:315` |
| `textures/default_filters/texture_filter` | `0` (nearest) | `project.godot:316` |

There is no `window/size/mode`, `window/vsync/vsync_mode`, or `rendering/anti_aliasing/*` entry, so those keep Godot defaults (windowed, vsync enabled, no MSAA).

`[importer_defaults] texture` (`project.godot:72-79`) disables compression (`compress/mode: 0`), disables mipmaps, and enables `process/fix_alpha_border` — the import defaults that keep pixel art crisp.

`[animation] compatibility/default_parent_skeleton_in_mesh_instance_3d=true` (`project.godot:13`) is a Godot 4.x compatibility flag.

### Physics layers (`project.godot:307-310`)

| Layer | Name |
|-------|------|
| 1 | `world` |
| 2 | `player_body` |
| 3 | `hitbox` |
| 4 | `hurtbox` |

Layers 5-32 are unnamed.

### Other sections

- `[gdscript] warnings/untyped_declaration=1` (`project.godot:68`) — untyped declarations warn but do not error.
- `[internationalization] locale/translations` lists exactly one file: `res://translations/strings.en.translation` (`project.godot:303`).
- `[editor_plugins] enabled` lists exactly one plugin: `res://addons/godot_mcp/plugin.cfg` (`project.godot:64`).

## Contracts

- **Autoload names are global identifiers.** Scripts call `RunFlow`, `LocalSave`, `WorldState`, `InventoryService`, `AudioDirector`, `ApiConfig`, `VfxService`, `PlayerControls`, `WavesRunService`, `AttackTokenService`, `GameFacade` by bare name. Renaming an autoload breaks every call site.
- **`TestContext.REQUIRED_INPUT_ACTIONS`** (`apps/game/client/scripts/validation/test_context.gd:13-17`) is the contract the validation harness enforces: `interact`, `toggle_camera`, `lock_on`, `sprint`, `inventory`, `pause`, `move_forward`, `move_back`, `move_left`, `move_right`, `debug_toggle`, `zoom_in`, `zoom_out`. All 13 are present.
- **Layer names 1-4** are the contract combat code relies on; `hitbox`/`hurtbox` separation is assumed by `Hitbox` and `Hurtbox` scripts.
- **`config/features` "4.7"** is what the Godot editor writes into the project file. Any editor older than 4.7 refuses to open the project without a downgrade warning.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| 21 autoloads registered and instantiated | IMPLEMENTED | `project.godot:33-53` |
| 35 input actions with keyboard + gamepad bindings | IMPLEMENTED | `project.godot:83-299` |
| Engine version pin vs CI | BROKEN | `project.godot:20` declares `"4.7"`; `.github/workflows/ci.yml:115` and `release.yml:48` pin `version: 4.4.0` |
| Input rebinding at runtime | ABSENT | Repo-wide grep of `apps/game/client/scripts` for `InputMap.action_erase_events`, `InputMap.action_add_event`, `InputMap.add_action`, `keybind`, `remap` finds no input-remapping code; the only `remap` hits are animation time remapping in `diorama_anim_library.gd:554,571,577` |
| `talents` and `heal` share gamepad button 7 | BROKEN | `project.godot:274` and `project.godot:286` |
| `lock_on` and `ui_accept` share Enter (`4194309`) | BROKEN | `project.godot:85` and `project.godot:181` |
| `zoom_in`/`ui_up` share button 11; `zoom_out`/`ui_down` share button 12 | BROKEN | `project.godot:110,116,195,201` |
| `jump` / `ui_accept` share button 0; `dodge` / `ui_cancel` share button 1 | PARTIAL | `project.godot:86,92,152,158` — intended overlap for gameplay vs menu context, but nothing disambiguates them |
| Localization beyond English | ABSENT | `project.godot:303` registers one translation; `apps/game/client/translations/` contains only `strings.csv` and `strings.en.translation` |
| Explicit vsync / window mode / MSAA settings | ABSENT | No `window/vsync/*`, `window/size/mode`, or `rendering/anti_aliasing/*` keys in `project.godot` |
| Named physics layers 5-32 | ABSENT | `project.godot:305-310` names only layers 1-4 |
| `godot_mcp` editor plugin enabled in the shipped project file | PARTIAL | `project.godot:64` — a development tool enabled in the committed project settings |

## Related

- Improvement plan: [`../actual_improvements/project-config-autoloads.md`](../actual_improvements/project-config-autoloads.md)
- [`ci-cd.md`](ci-cd.md) — the 4.4.0 versus 4.7 pin
- [`validation-suites.md`](validation-suites.md) — `setup_suite.gd` autoload and input assertions
- [`platform-and-net.md`](platform-and-net.md) — `SteamService` and `CrashLogger` autoloads
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) section 2
