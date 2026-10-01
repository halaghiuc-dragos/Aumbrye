---
name: aumbrye-backlog
description: Implement items from docs/BUGS_AND_ENHANCEMENTS.md (Aumbrye, Godot 4.7 GDScript roguelite). Use when working on an AUDIO-, REL-, V-, A-, AN-, G-, SIM- or FUN- item, or when touching combat, enemy AI, dungeon generation and building, audio, saves or balance in this repo.
---

# Implementing the Aumbrye backlog

The backlog is `docs/BUGS_AND_ENHANCEMENTS.md`: each item has Problem / Action / Location / How /
Links, and the table at the top groups the open items by area. Read the item and its Links before
editing.

Product aim: a simple, fun roguelite with soulslike combat. Prefer deleting or simplifying over
adding machinery.

## Hard repo rules (from CLAUDE.md, the owner's standing decisions)

- **No tests.** No test files, runners or `tests/` dirs in any language. No GitHub Actions and no Dependabot.
- Verification is manual: the diagnostics under `apps/game/client/scenes/debug/*.tscn` that `CLAUDE.md` lists, plus temporary probes (see `probes.md`).
- **No git commands unless the user asks.** Don't commit.
- **GDScript warnings are errors** (`project.godot` `[debug]` sets them to 2). The common traps:
  - unused variables and parameters (prefix with `_`)
  - integer division (use `int(a / float(b))` or `@warning_ignore("integer_division")`)
  - shadowed variables
  - narrowing conversions
  - un-inferable `:=` from untyped values (declare the type: `var x: int = ...`)
- Match the surrounding style: static typing, `##` doc comments that explain *why the current code is this way*. No history comments ("used to…", ticket ids), no dead code, no stray files.
- When an item is fully implemented, delete it from the backlog; when it is partly done, trim its text to what is left.
- Remove files by naming them; never with a generic delete.

## Running things

```bash
# from the repo root
godot --headless --path apps/game/client res://scenes/debug/lint_scripts.tscn        # every script compiles
godot --headless --path apps/game/client res://scenes/debug/scene_sweep.tscn         # every scene loads
godot --headless --path apps/game/client res://scenes/debug/definition_health.tscn   # 1000 generated floors
godot --headless --path apps/game/client res://scenes/debug/floor_connectivity_audit.tscn -- --seeds=6
node scripts/balance/balance-cli.mjs --summary   # rewrites reports/balance_export.json
node scripts/validate.mjs --layer content        # rewrites reports/validation-summary.json
node scripts/check-doc-paths.mjs                 # every path a doc cites exists
```

- Godot 4.7.2 is at `~/.local/bin/godot`. The Godot MCP server may not be connected; use headless runs.
- After adding a `class_name` script or an asset, run `godot --headless --import --path apps/game/client`, or the lint scene fails with "could not resolve class".
- Diagnostics that start runs or call `LocalSave` write the real saves in `~/.local/share/godot/app_userdata/Aumbrye`: `playable_run_audit`, `behavior_integration_audit`, `floor_definition_persistence_audit`, `phase_walk`, `perf_audit`, `probe_creation_flow`, `capture_world_screens`, `capture_hub_tents`. Windowed captures can be pointed at a scratch folder with `XDG_DATA_HOME=/tmp/<dir>`.
- `balance-cli` and `validate.mjs` modify tracked files under `reports/`. Say so when you report.

## Architecture map (where things live)

The client is under `apps/game/client/`. Paths below are relative to `scripts/` unless they start with a top-level folder.

| Area | Key files | Notes |
|---|---|---|
| Run lifecycle | `app/run_flow.gd` (autoload RunFlow) | start, continue, death, bonfire respawn, floor transition, finish; XP through `ProgressionService.calculate_run_xp` |
| Castle floor scene | `dungeon/castle_run.gd` | builds the floor, room tracking, boss intro, snapshot persistence, player death |
| Floor build | `dungeon/dungeon_builder.gd` | door sync, enemy/boss/loot/trap spawn, `_apply_floor_scaling`, `respawn_enemies`, `reveal_secret`, `register_chest` |
| Room geometry | `dungeon/castle/castle_blockout.gd`, `dungeon/castle/castle_room_scene.gd`, `dungeon/room_template.gd` | one door flag per wall (`door_north` …); the readers of those flags are listed under "Engine and code facts" |
| Generation | `dungeon/local_procgen.gd` → `dungeon/procgen/dungeon_procgen.gd` → `room_graph_generator.gd`, `room_graph_layout.gd`, `room_graph_assigner.gd`, `room_content_assigner.gd`, `room_lock_placer.gd`, `procgen_placements.gd` | returns a wrapper whose `definition` holds rooms, edges, placements, locks and roomContent |
| Floor recipes and encounters | `content/progression/floor_recipes.json`, `content/encounters/encounters.json`, `content/progression/room_pacing.json` | the recipe decides what each room holds; encounter templates fill pack rooms by role |
| Room content | `dungeon/room_content/*.gd`, `dungeon/floor_keyring.gd`, `dungeon/traps/*.gd` | reward (cursed and timed caches), trap (no-hit gauntlet), rest, lore, merchant, shrine, vault, arena gate |
| Enemies | `enemies/castle_enemy_base.gd`, `enemies/enemy_blackboard.gd`, `enemies/elite_affixes.gd`, `combat/attack_token_service.gd`, `enemies/attack_scheduler.gd` | subclasses in `enemies/` and `bosses/` (`arena_boss.gd` base, `boss_phase_controller.gd`) |
| Player combat | `combat/weapon_controller.gd`, `combat/guard.gd`, `player/dodge.gd`, `player/player_heal.gd`, `player/player_combat_reactions.gd`, `player/locomotion.gd` | |
| Damage pipeline | `combat/hitbox.gd` → `combat/hurtbox.gd` | `combat/hit_feedback.gd` handles the local hit-stop, camera punch and hit sounds |
| Statuses and rules | `combat/statuses/status_controller.gd`, `combat/combat_events.gd`, `combat/run_buffs.gd` | relic rules and synergies register with `CombatEvents` |
| Animation | `art/characters/diorama_anim_controller.gd` (Priority enum, `AnimationPlayer` only), `art/characters/diorama_anim_library.gd`, `player/player_anim_director.gd` | |
| Camera | `camera/orbit_camera.gd`, `camera/lock_on.gd`, `player/lock_on_movement.gd` | |
| Audio | `audio/audio_director.gd` (autoload AudioDirector), `content/audio/sfx.json`, `content/audio_profiles/*.json`, `assets/audio/` | `sfx.json` is the single cue table |
| VFX | `art/vfx/vfx_service.gd` (autoload VfxService; also owns `Engine.time_scale` through `push_time_scale`) | |
| Models | `tools/blender/*.py` build every `.glb`; `art/props/prop_library.gd` loads props | rebuild commands are in `CLAUDE.md` |
| Saves | `save/local_save.gd` (autoload LocalSave), `save/save_migrator.gd`, `save/save_validator.gd` | |
| Content | `app/content_loader.gd` (`load_json` returns a deep copy), `content/enemy_catalog.gd` (`get_definition` returns the shared dictionary) | the top-level `content/` folder holds the JSON data and `schemas/` |
| Player stat refresh | `inventory/inventory_service.gd` `apply_equipment_to_player_node()` | merges gear, class, talents, run buffs and statuses on every status, inventory or buff change |
| Inventory | `inventory/grid_inventory.gd`, `ui/inventory_ui.gd` | an ordered list with a fixed capacity; a slot's cell is its position |
| Meta progression | `meta/` (vault, hub growth, mode unlocks, achievements, bestiary, challenge, run history), `progression/progression_service.gd` | most records are character flags through `CharacterService.set_flag` |
| Modes | `content/modes/catalog.json`, `content/modes/unlocks.json`, `meta/mode_unlock_service.gd` | a `parked` flag hides a mode's hub portal |
| Training arena | `practice/combat_arena.gd`, `scenes/combat/combat_arena.tscn` | practice exercises and boss rematches |
| UI and input | `ui/combat_hud.gd`, `ui/menu_stack.gd` (autoload MenuStack: `show_modal` / `hide_modal`), `app/player_controls.gd`, `project.godot [input]` | |
| Backend | `services/backend/src/...` (.NET 10), `packages/procedural` (C# generator, diverged from GDScript) | frozen: the game does not call it (`ApiConfig.ONLINE_ENABLED`) |

Autoloads: 34, listed in `project.godot [autoload]`.

## Engine and code facts (don't repeat these bugs)

1. **Dictionaries and arrays are references.** `var x := dict` then `dict.clear()` clears `x` too. `EnemyCatalog.get_definition()` is shared by every instance: never write into `_data`; duplicate before writing.
2. **Build order in `DungeonBuilder`:** rooms `_ready` (dressing reads the template's default doors) → `_sync_blockout_doors_from_edges` (close all, then reopen per edge) → `_finalize_all_blockouts` (geometry and nav rebuild) → enemies, loot, traps, room content → boss → stair levers → boss door. Bosses exist at floor build, so anything in a boss `_ready()` runs at floor load.
3. **Sockets:** use `_socket_for_edge(from_room, to_room, edge)`, which resolves by the edge's direction, never by room facing or centre delta.
4. **Door flags are read in several places.** A change to the door model must update `castle_blockout.gd`, `dungeon_builder.gd`, `diorama_room_dressing.gd`, `castle_room_scene.gd`, `room_content/room_arena_gate_content.gd`, `scripts/tools/split_room_elevation_audit.gd`, `scripts/tools/navigation_cache_audit.gd` and `scripts/tools/floor_connectivity_audit.gd` together.
5. **One respawn path:** `CastleRun.persist_bonfire_checkpoint()` and `DungeonBuilder.respawn_enemies()`. `RunFlow.rest_at_bonfire()` only restores the player.
6. **Dead enemies are not freed.** Placement enemies stay in the tree (hidden and frozen) because respawn and snapshots restore them by placement id. Adds and splits are not placements, so free them.
7. **Elite affixes** are chosen in `procgen_placements.gd` and applied in `dungeon_builder.gd._apply_floor_scaling` through `apply_phase_modifiers`; a new affix is one entry in `content/combat/elite_affixes.json`.
8. **Animation priority:** `_begin_action` refuses lower priorities, and `play_attack()` bypasses priority. Flinch uses the STAGGER priority.
9. **Determinism:** generation depends only on the seed, tier, floor, mode and the captured `GenerationInputs` (`lootQuality`, `lockedItems`). Never read the clock, the save or the day/night cycle during generation.
10. **Saves:** `LocalSave.set_active_run(data, true)` is a synchronous full write with a read-back; pass `flush=false` for frequent events. `request_autosave(DEFERRED)` waits two seconds, so flush with `LocalSave.autosave()` before any `reload_active_into_services()`.
11. **The save validator is all-or-nothing:** any unexpected field quarantines the file and restores a backup. Removing a slot, an item id or a field needs a `SaveMigrator` step in the same change (and the `schema_versions.json` fixture bumped with `CURRENT_VERSION`).
12. **The player stat refresh reloads the weapon** only when the weapon's data path changed (`applied_weapon_key`); keep it that way, since a reload cancels a swing.
13. **`LocalProcgen.generate()` returns a wrapper** (`{ok, definition, run_id, warnings, …}`); the floor is `result.definition`. Pass `0` as the final-floor index, since any other value builds a short final-floor arena.
14. **Physics interpolation is on.** After setting `global_position` for a jump (respawn, stairs), call `reset_physics_interpolation()` on the body. Set `global_position` only after `add_child`.
15. **Stat units differ by source.** On items, `physicalDamage` is flat and folds into `bonusDamage`; on classes and talents it is a fraction read by `damage_multiplier()`. `goldFind`, `lootQuality` and `xpGain` come from talents. Check the consumer before adding content that uses a stat.
16. **CombatEvents rules act on `ctx.actor`,** and not every event's actor is the player (`onStatusApplied` passes the instigator). Make sure the actor is the player when adding a rule or an event.
17. **`extends SceneTree` tools run with `--script` have no autoloads,** so anything touching procgen fails. Write diagnostics as `scenes/debug/*.tscn` plus `scripts/tools/*_audit.gd` that exit non-zero on failure.
18. **`String.format([...])` replaces `{0}`, not `%s`.** Use `"%s" % [x]`; strings in `translations/strings.csv` use `%s`.
19. **One interaction system.** New interactables register with `DungeonInteractionService`, and always call `set_input_as_handled()` after acting.
20. **Items are 1×1.** `ItemCatalog` flattens footprints at load, so don't build features on grid sizes.
21. **Room-content chests** must register with the builder (`register_chest`) so they are saved and restored.
22. **Every authored content name needs translation keys.** `validate.mjs` fails on a `name` or `description` in content without `CONTENT_<ID>_NAME` / `_DESCRIPTION` rows in `translations/strings.csv` (English and Romanian).

## Workflow per item

1. Read the item and its Links in the backlog.
2. `grep` every consumer of what you change (function, flag, signal, content key) before editing.
3. Make the smallest correct change. If the item is under section 6 (Simplification), delete code rather than wrap it.
4. Verify:
   - `lint_scripts.tscn` passes.
   - The relevant audits pass: floor and room items → `floor_connectivity_audit`, `definition_health`, `soft_lock_audit`, `room_content_placement_audit`; combat → `combat_state_audit`, `combat_stats_audit`, `enemy_attack_audit`, `balance-cli`; items and saves → `inventory_audit`, `icon_atlas_audit`, `node scripts/validate.mjs`.
5. Update the backlog: delete a finished item, trim a partly done one, and run `node scripts/check-doc-paths.mjs`.
6. Report what changed, how it was verified, and which tracked files the tools rewrote.

## Don'ts

- Don't add tests, CI or Dependabot.
- Don't reintroduce synthesised audio fallbacks for missing audio: a missing asset is a debug warning and silence.
- Don't scale `CharacterBody3D` nodes; use `configure_physical_size()`.
- Don't place gates or doors by room facing or centre delta; use edges.
- Don't run save-writing audits against a save folder you care about without backing it up.
