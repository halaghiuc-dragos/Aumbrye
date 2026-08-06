# Placeholder inventory (cross-cutting)

Evidence rollup of PLACEHOLDER / STUB / FAKE / BROKEN / ABSENT / MISSING surfaces in the current client and content trees. Detail lives in the per-system docs under this folder. Status tags are defined in [`../DOC-CONVENTIONS.md`](../DOC-CONVENTIONS.md).

## Layer snapshot

| Layer | Status (code) |
|-------|----------------|
| Hub ↔ dungeon ↔ results | Playable (`run_flow.gd`, hub, castle/waves scenes) |
| Combat mechanics | Present; lunge, guard parry stagger, heal anim/SFX, and hit feedback wired; other gaps remain (statuses, poison, backstab) |
| Combat art / audio / VFX | Mixed — authored combat SFX, 25 voxel rig manifests, 154 `.mesh` parts, 10 biome enemy silhouettes; box fallback for unmapped profiles |
| **Character art** | **IMPLEMENTED** — voxel manifests + customization; box fallback for unmapped ids ([`character-authoring.md`](character-authoring.md)) |
| Boss scripts | Mix: real phases + `boss_defeated` on frost/cathedral; final boss immunity gated in `hurtbox.gd` |
| Dungeon geometry | `MeshInstance3D` boxes + `StaticBody3D` (`castle_blockout.gd`) + procedural dressing — **not CSG** |
| Online procgen | Off — `USE_ONLINE_PROCgen := false` in `run_flow.gd` |
| Steam / cloud | Stub Steam; cloud save pull BROKEN (`get_save` wrong result key) |

## Art and characters

Player and mapped enemy archetypes load authored voxel manifests from `content/characters/` and `assets/characters/**/*.voxels.json` via `build_from_manifest()` (`diorama_character_skin.gd:512`). Unmapped profiles still fall back to runtime `BoxMesh` assembly (`_build_humanoid` at `:386`). Equipment with `"visual"` blocks can swap head meshes (`apply_equipment` at `:571`). Full inventory: [`character-authoring.md`](character-authoring.md).

| Item | Tag | Evidence |
|------|-----|----------|
| Voxel character manifests | IMPLEMENTED | `content/characters/*.json`, `assets/characters/*/*.voxels.json`; `VoxelGrid`, `VoxelMeshBuilder` |
| Box-mesh fallback bodies | PARTIAL | `_build_humanoid` still used when manifest missing (`diorama_character_skin.gd:106,186`) |
| Hardcoded `PROFILES` proportions | PARTIAL | Fallback path only; manifests use integer voxel joints |
| Bosses falling to `"boss"` profile → melee | PARTIAL | Manifest archetypes for melee/ranged/brute; other ids may still map to profiles |
| Keyframe-table anims | PLACEHOLDER | `diorama_anim_library.gd` |
| Animation method tracks (footstep / swing VFX / hitbox) | IMPLEMENTED | `diorama_anim_controller.gd:113-123` `_resolve_events_path`; `anim_hitbox_on/off` at `:378` |
| Box weapons | PARTIAL | `diorama_weapon_kit.gd` — axe/staff/unknown meshes; FP viewmodel still box |
| FP arms | PLACEHOLDER | `diorama_viewmodel.gd` |
| Room dressing props | PLACEHOLDER | `diorama_room_dressing.gd` |
| `DioramaPropFactory` | STUB | Editor-only; no gameplay call site |
| Authored character voxel meshes | IMPLEMENTED | 154 `.mesh` + 107 `.voxels.json` under `assets/characters/`; 25 manifests in `content/characters/` |
| Equipment visuals | IMPLEMENTED | `apply_equipment()` + helm `visual` meshes (`equipment/*.voxels.json`) |
| Pixel-cell alignment | IMPLEMENTED | `VoxelMeshBuilder._snap_to_palette()` + vertex-color shader path |
| Appearance scale | IMPLEMENTED | Uniform `Root.scale`; height via `position.y` on grid (`diorama_character_skin.gd:120`) |
| Default pixel preset | IMPLEMENTED | Default viewport `480×270` (`pixel_diorama_settings.gd`) |

## Audio

| Item | Tag | Evidence |
|------|-----|----------|
| Biome OGG under `assets/audio/` | IMPLEMENTED (files exist) | 22 `.ogg` ambience/boss themes |
| `_ensure_layer_streams()` after load | IMPLEMENTED | `audio_director.gd:473-477` — skips players already on file-backed streams |
| Combat / UI SFX | IMPLEMENTED | `content/audio/sfx.json` + `assets/audio/sfx/` OGG/WAV; stingers, positional loops, `audio_suite.gd` |

## Combat gaps

| Item | Tag | Evidence |
|------|-----|----------|
| Attack lunge | IMPLEMENTED | `weapon_controller.gd:247-261` `get_attack_lunge_velocity()`; `locomotion.gd:72-73,120-121` |
| Weapon `art` JSON | IMPLEMENTED | `content/weapons/*.json` `"art"` blocks; schema allows `art` |
| Stub bosses without `boss_defeated` | IMPLEMENTED | `boss_frost_warlord.gd`, `boss_cathedral_hollow.gd` emit `boss_defeated` |
| `Mana.consume` gameplay spend | MISSING | HUD reads mana; no spend callers |
| Crit / flat damage bonus | STUB | Implementations with zero call sites |
| Enemy `StatusController` | MISSING | Only `player.tscn` mounts one — player-inflicted statuses dropped |
| `burn` / `stun` statuses | STUB | Authored JSON; no gameplay applier |
| Parry stagger | IMPLEMENTED | `guard.gd:131-154` `try_parry_attack` → `_stagger_attacker` / `apply_stagger` |
| Dodge i-frame feedback | MISSING | Successful dodge returns before every feedback path |
| Poison vs Hurtbox | BROKEN | Apply + DoT bypass `receive_hit` / i-frames |
| Heal presentation | PARTIAL | Dedicated `heal` clip + SFX (`player_heal.gd`, `diorama_anim_controller.gd:225`); charge HUD may still be thin |
| Player camera hit feedback | IMPLEMENTED | `player.tscn:99` `camera_path = ../CameraPivot/SpringArm3D/Camera3D` |
| Backstab facing | BROKEN | Reads non-rotating body basis; angle rewards frontal hits |

## Loop honesty (P0)

| Item | Tag | Evidence |
|------|-----|----------|
| Waves results presentation | IMPLEMENTED | `results_screen.gd:88-91,104-107` branches `waves_complete` / `waves_failed` |
| Waves `levels_gained` | FAKE | Hardcoded `0` after real XP grant (`run_flow.gd`) |
| Escape quest on any `run_ended` | IMPLEMENTED | `quest_service.gd:95-96` `register_run_outcome`; escape completes only on `OUTCOME_ESCAPED` |
| Fetch quests never register | IMPLEMENTED | `inventory_service.gd` calls `QuestService.register_fetch` on successful `add_item` |
| Affix `tiers` / `itemTypes` / `weight` | IMPLEMENTED | `affix_roller.gd:128-196` filters `itemTypes`, weighted pick, `_roll_tier_value` |
| Castle affix rolls | MISSING | `AffixRoller` / `add_rolled_item` unused on castle loot path |
| Skip-floor items | BROKEN | Consume return discarded — skip is free/repeatable |
| Floor-transition stair spawn | BROKEN | `run_snapshot` meta removed before stair spawn reads it |
| Stub bosses without `boss_defeated` | IMPLEMENTED | `boss_frost_warlord.gd`, `boss_cathedral_hollow.gd` emit `boss_defeated` |
| Final-boss `is_immune()` | IMPLEMENTED | `hurtbox.gd:41` gates damage when `owner_body.is_immune()` |

## Dungeon builder / procgen

| Item | Tag | Evidence |
|------|-----|----------|
| Height transitions | IMPLEMENTED | `_build_height_transitions()` builds stairs or asserts flat when `maxHeightLevel=0` (`dungeon_builder.gd:275`) |
| Shortcut corridors | IMPLEMENTED | Loop edges emit `kind: "shortcut"`; `_wire_shortcut_edges()` opens doors and nav-links (`dungeon_builder.gd:100,187`) |
| Treasure room assignment | BROKEN | Dead ends computed before door masks |
| Exit portal without `Props` | BROKEN | Orphaned — final floor can be incompletable |
| Doorway nav links | BROKEN | Degenerate (both ends same point) |
| Floor 10 layout | IMPLEMENTED | `_generate_final_floor()` reads biome `finalFloor` + entrance→arena→boss layout (`dungeon_procgen.gd:114-159`) |
| C# CLI fallback definition | PARTIAL | Missing `roomContent` / `locks` / `puzzles` |
| 63/90 room scenes vs `KIND_SPECS` | BROKEN | Wrong footprints / disabled doors |

## Meta / UI / accessibility

| Item | Tag | Evidence |
|------|-----|----------|
| Colorblind setting | FAKE | No gameplay consumer |
| Most achievements | STUB | 19 catalog ids never unlock |
| Aptitude talents | STUB | `lootQuality` / `xpGain` / `goldFind` / `cooldownReduction` inert |
| XP curve economy keys | IMPLEMENTED | `xp_curve.json` keys match `ProgressionService.calculate_run_xp` |
| Inventory / status icons | IMPLEMENTED | `item_icon_atlas.gd`, `status_icon_atlas.gd`, `assets/ui/*.png`; `inventory_ui.gd` `TextureRect` cells |
| Skies / Cathedral portals | STUB | Dressed then `visible = false` in `hub.gd` |

## Platform

| Item | Tag | Evidence |
|------|-----|----------|
| Online runs | STUB (off) | `USE_ONLINE_PROCgen := false` |
| Dockerfile for API | IMPLEMENTED | `services/backend/Dockerfile`; CI `api-image` + GHCR release |
| Cloud save pull | BROKEN | `ApiClient.get_save()` reads wrong result key |
| CrashLogger logging API | STUB | No callers |
| Multiplayer | ABSENT | No peer/RPC game server under client scripts |
| CI Godot version | IMPLEMENTED | `ci.yml` / `release.yml` pin `4.7.0`; matches `project.godot` features `4.7` |
| Content strict CI | IMPLEMENTED | `npm run validate:strict` hard gate in `ci.yml` |
| gdlint coverage | IMPLEMENTED | All `apps/game/client/scripts/**/*.gd` (excludes addons) |
| Steam auth ticket exchange | ABSENT | Client returns `""`; no backend route |
| Validation suites vs deleted docs | IMPLEMENTED | `docs_suite.gd` validates current doc tree links |
| Web ↔ API browser path | BROKEN | No CORS, no Vite proxy; Account reads `save.state` vs `stateJson` |

## Related

- Architecture: [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
- Game loop: [`00-GAME-LOOP.md`](00-GAME-LOOP.md)
- Improvements twin: [`../actual_improvements/`](../actual_improvements/README.md)
- Character authoring: [`character-authoring.md`](character-authoring.md)
- Player-impact priority: [`../actual_improvements/00-ADDICTION-AND-FUN.md`](../actual_improvements/00-ADDICTION-AND-FUN.md)
