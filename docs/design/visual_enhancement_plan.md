# VISUAL ENHANCEMENT PLAN — Agent Prompt

> **Load this file when implementing pixel-diorama / art / animation work.**  
> Dense contract. Do not re-derive. Prefer quality over shortcuts. Execute phases in order unless told otherwise.

## ROLE
Godot 4 GDScript agent for Aumbrye (`apps/game/client`). Deliver a crisp soulslike-roguelite **pixel diorama** look with 1P/3P and AnimationPlayer-on-voxel combat anims.

## GOAL
Beautiful, intentionally pixelled 3D: low-res render + nearest upscale + quantized surfaces; readable combat tells; centralized visual code; multi-biome authored kits.

## LOCKED
- Look: pixel diorama (not photoreal, not HD-2D billboards). High-contrast silhouettes.
- Anim: **AnimationPlayer on named box-mesh parts** + method markers for hit frames. No skeletal glTF characters.
- Scope: full overhaul (pipeline + anim + VFX/UI + biome art kits).
- Camera: shared-world SubViewport; **never** reparent 3D into SubViewport; **never** snap `CameraPivot` / SpringArm follow node.

## NEVER
- Reintroduce `own_world_3d=true` + reparent, or `scaling_3d_scale` bilinear soft look.
- Snap gameplay orbit pivot position.
- Use `get_viewport().get_camera_3d()` for billboards when low-res on → use `PixelDioramaViewport.get_gameplay_camera()`.
- Drive player hit/death via hidden capsule `Facing/MeshInstance3D` after migration → drive `DioramaVisual`.
- Duplicate palette colors outside `PixelDioramaStyle` / generated `.tres`.
- Force hub glow ignoring `glow_enabled`.
- Leave dual shader path (legacy `pixel_diorama.gdshader`) after Phase 0.

## ALWAYS
- Match existing GDScript style; minimal diffs; no drive-by refactors outside phase scope.
- One bootstrap per playable scene: `PixelDioramaBootstrap.attach(root)`.
- Materials via surface shader / `PixelDioramaStyle` / regen tool.
- Attack active frames: prefer AnimationPlayer method tracks; JSON timings = fallback + validation bounds.
- Anim priority: `death > stagger > attack/parry > block > dash > locomotion`.
- Update `docs/design/PIXEL_DIORAMA_PIPELINE.md` when pipeline contracts change.
- After file moves: fix preloads/class paths; no duplicate stubs.

## PATHS (current → target)

```
ROOT = apps/game/client
ART  = ROOT/scripts/art
```

| Concern | Canonical |
|---------|-----------|
| Settings | `ART/pipeline/pixel_diorama_settings.gd` |
| Viewport autoload | `ART/pipeline/pixel_diorama_viewport.gd` |
| Bootstrap | `ART/pipeline/pixel_diorama_bootstrap.gd` **NEW** |
| Mirror cam snap | `ART/pipeline/pixel_camera_snap.gd` (render-cam only) |
| Palettes/mats/geo | `ART/style/pixel_diorama_style.gd` |
| Lighting facade | `ART/lighting/visual_lighting.gd` **NEW** (wrap SceneLighting+DungeonLighting) |
| Skin | `ART/characters/diorama_character_skin.gd` |
| Anim ctrl | `ART/characters/diorama_anim_controller.gd` **NEW** |
| Floor snap | `ART/characters/character_floor_snap.gd` |
| Props/interact | `ART/props/*` |
| Dressing | `ART/dressing/*` (from hub/dungeon/debug diorama scripts) |
| VFX | `ART/vfx/vfx_service.gd` (autoload path OK) |
| Shaders | `ROOT/assets/shared/shaders/` |
| Anims | `ROOT/assets/animations/diorama/` |
| Weapons | `ROOT/assets/shared/weapons/` |
| FP viewmodel | `ROOT/scenes/art/fp_viewmodel.tscn` **NEW** |
| Rig ref | `ROOT/scenes/art/diorama_character_rig_player.tscn` **NEW** |
| Mat regen | `tools/generate_pixel_diorama_materials.py` |

Biome mats: `ROOT/assets/{biome}/materials/mat_{floor,wall,accent}.tres`  
Consumers to rewire: `hub.gd`, `castle_run.gd`, `waves_run.gd`, combat arena, `biome_registry.gd` (data only for lighting colors).

## BASELINE (do not break)
- SubViewport ~480×270, `own_world_3d=false`, root `disable_3d` when active, nearest upscale.
- Autoload `PixelDioramaViewport`; settings persisted LocalSave meta `pixel_diorama`.
- Skin builds parts: `Torso Head ArmL ArmR LegL LegR` (+ `Visor Shield Bow Tail`); add `WeaponMount ShieldMount Weapon`.
- Combat timers live in `weapon_controller.gd` / enemy JSON; signals `attack_started`/`attack_ended` exist—wire to anim.
- Player anim today: locomotion/dash only. Enemy: windup/attack/block/stagger via sine animator—replace.

---

## P0 — CENTRALIZE
**Done when:** one attach API; one palette authority; legacy shader unused; art scripts under `ART/{pipeline,style,lighting,characters,props,dressing,vfx}`.

1. Create dirs; move files; update `class_name`/preloads/`project.godot` autoloads.
2. `PixelDioramaBootstrap.attach(scene)` = load settings + `apply_rendering_project_settings` + `apply_to_scene` + `PixelDioramaViewport.attach_to_scene`; replace copies in hub/castle/waves/arena.
3. `VisualLighting`: `apply_outdoor|indoor|arena|hub(biome_profile)`; BiomeRegistry supplies profile dict only.
4. Style defaults read Settings; delete duplicate consts.
5. Migrate accents → `pixel_diorama_surface.gdshader`; remove legacy shader usage; regen all `mat_*.tres` from palettes.
6. Fix doc paths (`16-ART-PIPELINE.md` still says `shaders/` wrongly).

## P1 — CRISP PIPELINE
**Done when:** presets in UI; mirror-cam snap works; no forced hub glow; emissives quantized; 1P viewmodel hooks exist (clips can be stub).

1. Settings UI presets: `320x180 | 480x270 | 640x360` (+ effective scale label). Persist w/h.
2. Wire `camera_snap_enabled` → snap **PixelRenderCamera** translation only (use `camera_snap_step()`); never pivot.
3. `make_emissive_material()` (or shader variant); convert water/emissive StandardMaterials.
4. Optional CanvasItem finish on SubViewportContainer: dither+contrast; default subtle/off.
5. Tune directional shadow bias/distance for low-res chunky geo.
6. Hub/outdoor: respect `glow_enabled`.
7. FP: `scenes/art/fp_viewmodel.tscn` (voxel arms+weapon under cam); `orbit_camera.gd` show/hide with `apply_first_person()`; 3P shows full body.
8. Floor-snap player + all enemy spawns.

## P2 — ANIMATIONPLAYER VOXEL
**Done when:** player+enemies use `DioramaAnimController`; attacks use method markers; sine animator retired/shimmed; weapons mount.

### API (implement exactly)
```gdscript
# DioramaAnimController
func bind(visual: Node3D) -> void
func set_profile(profile: String) -> void
func set_weapon(weapon_id: String) -> void
func request_locomotion(state: StringName, params: Dictionary = {}) -> void
func play_oneshot(clip: StringName, force := false) -> void
func play_attack(clip: StringName) -> void  # emits/calls enable_hitbox|disable_hitbox|play_swing_vfx via tracks
func set_blocking(holding: bool) -> void
```

### Clip set (min)
`idle walk run air land dash_f dash_b dash_l dash_r`  
`attack_light_1 attack_light_2 attack_light_3 attack_heavy`  
`block_start block_hold block_hit parry_success guard_break`  
`flinch stagger death`  
Enemy: `windup attack recover` (+ profile variants as needed)

### Wire
| File | Action |
|------|--------|
| `locomotion.gd` | request_locomotion |
| `dodge.gd` | dash_* by dir |
| `weapon_controller.gd` | play_attack on start; hitbox from markers (JSON fallback) |
| `guard.gd` | block/parry clips |
| `player_combat_reactions.gd` | flinch/stagger/death on DioramaVisual |
| `castle_enemy_base.gd` + `training_grunt.gd` | AI → controller |
| `diorama_character_skin.gd` | WeaponMount/ShieldMount; spawn weapon mesh by id |
| Libraries | `assets/animations/diorama/{profile}[_weapon].res` |

Author via rig scene → AnimationPlayer tracks on part transforms → save library. Quality bar: readable windup, clear strike arc, distinct block/parry, weighty death—not sine wobble.

## P3 — VFX
**Done when:** VFX nearest + pixel-scaled; slash follows weapon; telegraphs pose+glyph not orange sphere; billboards use gameplay cam.

1. VfxService: `texture_filter_mode()`; chunky low-segment meshes; size ∝ `pixel_scale`; biome tint optional.
2. Swing: voxel arc/ribbon from WeaponMount.
3. Hit/block/parry: fewer longer-lived chunky sparks.
4. Enemy telegraph: windup pose + floor glyph/rim.
5. `hit_feedback.gd` SFX stub → real placeholder calls.
6. Damage numbers / HP bars: gameplay cam + pixel-friendly scale.

## P4 — UI
**Done when:** all major menus/HUD use GameUISkin; beauty preset exists.

1. Skin: `waves_run_ui`, `dialogue_ui`, `results_screen`, combat HUD, status icons (no colored squares).
2. Settings: beauty defaults preset (recommended crisp pack).
3. Document CanvasLayer vs SubViewport order.

## P5 — ART KITS (full overhaul)
**Done when:** Hub+Castle feel shipped; kit-first dressing; Umbral has own mats; other biomes have distinct prop language.

Rules: grid `0.25–0.5m`; silhouette OK at 480×270; identity = palette + props (not fog alone); nearest/procedural only.

Per biome: `assets/{biome}/{materials,props,rooms,characters}/`  
Shared: `assets/shared/{props,weapons}/`  
Dressing: authored prop if slot exists else `DioramaPropFactory`. Blockout accepts modular pieces over time.

| Pass | Focus |
|------|--------|
| A | Hub + Forgotten Castle (hero look) |
| B | Arena + Waves outdoor + FP polish |
| C | Crystal / Swamp / Frozen |
| D | Cathedral / Vault / Prism |
| E | Mire / Hollow / **Umbral dedicated** |

Refine body proportions per profile; bosses = extra named parts still on AnimationPlayer.

## P6 — VALIDATE + DOCS
1. Suites: `pixel_pipeline_suite` (bootstrap, nearest, viewport); `diorama_anim_suite` (libs load, markers, attack plays).
2. Respect `docs/design/performance_m6.md` light/prop budgets.
3. Playtest: crispness, 1P/3P, attack readability, biome blind-ID, Umbral.
4. Expand `PIXEL_DIORAMA_PIPELINE.md`: Pipeline / Lighting / Animation / Kits / FP-TP / Checklist.

---

## EXEC ORDER
`P0 → P1 → P2 → P3/P4 (parallel OK) → P5A → P5B→E → P6`

## QUALITY BAR
- Default 480×270 looks intentional pixels, not mush.
- Attack/block/parry/dodge/hit/death phase-accurate.
- 1P has voxel arms+weapon; 3P full body.
- Single bootstrap, palette, lighting facade.
- Hub+Castle diorama-grade; procgen unbroken.

## IMPL HEURISTICS (token-saving)
- Read only files for the active phase + this doc.
- Search symbols before broad explore.
- Prefer edit-in-place after moves; delete dead sine paths once controller ships.
- No new markdown except updates listed in P0/P6.
- Commit only if user asks.
