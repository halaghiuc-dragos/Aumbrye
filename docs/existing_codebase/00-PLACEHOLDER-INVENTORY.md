# Placeholder inventory (cross-cutting)

Evidence rollup of PLACEHOLDER / STUB / FAKE / BROKEN / ABSENT / MISSING surfaces in the current client and content trees. Detail lives in the per-system docs under this folder. Status tags are defined in [`../DOC-CONVENTIONS.md`](../DOC-CONVENTIONS.md).

## Layer snapshot

| Layer | Status (code) |
|-------|----------------|
| Hub ↔ dungeon ↔ results | Playable (`run_flow.gd`, hub, castle/waves scenes) |
| Combat mechanics | Present, with major dead/unwired features (see Combat below) |
| Combat art / audio / VFX | Mostly PLACEHOLDER / BROKEN (box diorama, generator audio, thin VFX, dead anim events) |
| **Character art** | **PLACEHOLDER — runtime `BoxMesh` assemblies; zero authored character assets** ([`character-authoring.md`](character-authoring.md)) |
| Boss scripts | Mix: real phases (knight/hydra/sovereign/final) + stubs lacking `boss_defeated` |
| Dungeon geometry | `MeshInstance3D` boxes + `StaticBody3D` (`castle_blockout.gd`) + procedural dressing — **not CSG** |
| Online procgen | Off — `USE_ONLINE_PROCgen := false` in `run_flow.gd` |
| Steam / cloud | Stub Steam; cloud save pull BROKEN (`get_save` wrong result key) |

## Art and characters (largest gap)

Characters are not authored art. They are assembled at runtime from 6–9 `BoxMesh` primitives sized by a hardcoded `PROFILES` dictionary, and the "pixel" look is a procedural shader pattern plus an optional low-res SubViewport. Searching `apps/game/client/` for `*.png` / `*.vox` / `*.glb` / `*.gltf` / `*.obj` / `*.fbx` outside `.godot/` returns **zero** files. Full inventory: [`character-authoring.md`](character-authoring.md). Plan: [`../actual_improvements/character-authoring.md`](../actual_improvements/character-authoring.md).

| Item | Tag | Evidence |
|------|-----|----------|
| Box-mesh character bodies | PLACEHOLDER | `diorama_character_skin.gd:365-451` |
| Hardcoded body proportions | PLACEHOLDER | `diorama_character_skin.gd:32-86` `PROFILES` |
| Bosses falling to `"boss"` profile → melee | PLACEHOLDER | `profile_for_enemy_data` / `PROFILES` miss |
| Keyframe-table anims | PLACEHOLDER | `diorama_anim_library.gd` |
| Animation method tracks (footstep / swing VFX / hitbox) | BROKEN | Exporter `events_path = ""`; controller `_resolve_events_path` always empty |
| Box weapons | PLACEHOLDER | `diorama_weapon_kit.gd` — `axe`/`staff` fall through to sword |
| FP arms | PLACEHOLDER | `diorama_viewmodel.gd` |
| Room dressing props | PLACEHOLDER | `diorama_room_dressing.gd` |
| `DioramaPropFactory` | STUB | Editor-only; no gameplay call site |
| Authored character art (any format) | ABSENT | Zero raster/model/voxel files under `apps/game/client/` |
| Equipment visuals | ABSENT | Body never changes when gear changes |
| Pixel-cell alignment across body parts | BROKEN | Object-space pattern per box (`pixel_diorama_surface.gdshader:43-48`) |
| Appearance `Root.scale` vs cell size | BROKEN | `diorama_character_skin.gd:107` |
| Default pixel preset | PARTIAL | Native 1080p — chunky look opt-in (`pixel_diorama_settings.gd`) |

## Audio

| Item | Tag | Evidence |
|------|-----|----------|
| Biome OGG under `assets/audio/` | IMPLEMENTED (files exist) | 22 `.ogg` ambience/boss themes |
| `_restore_generator_streams()` after load | BROKEN | `audio_director.gd:471-476` — unconditionally replaces loaded streams with `AudioStreamGenerator` |
| Combat / UI SFX | PLACEHOLDER | Generator sine tones only; no file-backed combat SFX path |

## Combat gaps

| Item | Tag | Evidence |
|------|-----|----------|
| Attack lunge | STUB | `get_attack_lunge_velocity()` → `Vector3.ZERO` |
| Weapon `art` JSON | ABSENT + schema-blocked | No `"art"` in `content/weapons/`; `weapon-definition.v1.json` `additionalProperties: false` |
| `Mana.consume` gameplay spend | MISSING | HUD reads mana; no spend callers |
| Crit / flat damage bonus | STUB | Implementations with zero call sites |
| Enemy `StatusController` | MISSING | Only `player.tscn` mounts one — player-inflicted statuses dropped |
| `burn` / `stun` statuses | STUB | Authored JSON; no gameplay applier |
| Parry stagger | STUB | `get_parry_stagger_duration()` has no caller |
| Dodge i-frame feedback | MISSING | Successful dodge returns before every feedback path |
| Poison vs Hurtbox | BROKEN | Apply + DoT bypass `receive_hit` / i-frames |
| Heal presentation | PLACEHOLDER | `play_heal()` aliases stagger; no charge HUD |
| Player camera hit feedback | BROKEN | Wrong `camera_path`; AnimDirector cached too early |
| Backstab facing | BROKEN | Reads non-rotating body basis; angle rewards frontal hits |

## Loop honesty (P0)

| Item | Tag | Evidence |
|------|-----|----------|
| Waves results presentation | BROKEN | `results_screen.gd` only special-cases `"died"` — `waves_failed` reads as success |
| Waves `levels_gained` | FAKE | Hardcoded `0` after real XP grant (`run_flow.gd`) |
| Escape quest on any `run_ended` | BROKEN | `quest_service.gd` — death completes escape quests |
| Fetch quests never register | BROKEN | `register_fetch` has no call site from inventory/loot |
| Castle affix rolls | MISSING | `AffixRoller` / `add_rolled_item` unused on castle loot path |
| Affix `tiers` / `itemTypes` / `weight` | FAKE | Authored; roller ignores them (flat 1–3) |
| Skip-floor items | BROKEN | Consume return discarded — skip is free/repeatable |
| Floor-transition stair spawn | BROKEN | `run_snapshot` meta removed before stair spawn reads it |
| Stub bosses without `boss_defeated` | BROKEN | Frost / cathedral — kill does not unlock stairs/portal |
| Final-boss `is_immune()` | FAKE | Cosmetic after `Health.take_damage` already applied |

## Dungeon builder / procgen

| Item | Tag | Evidence |
|------|-----|----------|
| Height transitions | STUB | `_build_height_transitions()` → `pass` |
| Shortcut corridors | STUB | Implemented, no call site |
| Treasure room assignment | BROKEN | Dead ends computed before door masks |
| Exit portal without `Props` | BROKEN | Orphaned — final floor can be incompletable |
| Doorway nav links | BROKEN | Degenerate (both ends same point) |
| Floor 10 layout | FAKE | Hardcoded Forgotten Sovereign layout |
| C# CLI fallback definition | PARTIAL | Missing `roomContent` / `locks` / `puzzles` |
| 63/90 room scenes vs `KIND_SPECS` | BROKEN | Wrong footprints / disabled doors |

## Meta / UI / accessibility

| Item | Tag | Evidence |
|------|-----|----------|
| Colorblind setting | FAKE | No gameplay consumer |
| Most achievements | STUB | 19 catalog ids never unlock |
| Aptitude talents | STUB | `lootQuality` / `xpGain` / `goldFind` / `cooldownReduction` inert |
| XP curve economy keys | FAKE | Schema keys ≠ `calculate_run_xp` readers |
| Inventory / status icons | PLACEHOLDER | Unicode / missing `iconPath` |
| Skies / Cathedral portals | STUB | Dressed then `visible = false` in `hub.gd` |

## Platform

| Item | Tag | Evidence |
|------|-----|----------|
| Online runs | STUB (off) | `USE_ONLINE_PROCgen := false` |
| Dockerfile for API | ABSENT | Also makes `release.yml` BROKEN |
| Cloud save pull | BROKEN | `ApiClient.get_save()` reads wrong result key |
| CrashLogger logging API | STUB | No callers |
| Multiplayer | ABSENT | No peer/RPC game server under client scripts |
| CI Godot version | BROKEN skew | CI/release 4.4.0 vs project features 4.7 |
| Content strict CI | FAKE | `continue-on-error: true` |
| gdlint coverage | PARTIAL | ~8 of ~271 `.gd` files |
| Steam auth ticket exchange | ABSENT | Client returns `""`; no backend route |
| Validation suites vs deleted docs | BROKEN | Assertions require removed documentation paths |
| Web ↔ API browser path | BROKEN | No CORS, no Vite proxy; Account reads `save.state` vs `stateJson` |

## Related

- Architecture: [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
- Game loop: [`00-GAME-LOOP.md`](00-GAME-LOOP.md)
- Improvements twin: [`../actual_improvements/`](../actual_improvements/README.md)
- Character authoring: [`character-authoring.md`](character-authoring.md)
- Player-impact priority: [`../actual_improvements/00-ADDICTION-AND-FUN.md`](../actual_improvements/00-ADDICTION-AND-FUN.md)
