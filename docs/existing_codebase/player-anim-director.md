# Player animation director

`PlayerAnimDirector` is the single translation layer from player gameplay state to player animation. It subclasses `DioramaAnimController`, drives the third-person voxel rig, builds and mirrors the first-person viewmodel, and is created in code (not in `player.tscn`). It is on the live play path everywhere the player scene is.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/player/player_anim_director.gd` | `class_name PlayerAnimDirector extends DioramaAnimController` |
| `apps/game/client/scripts/art/characters/diorama_anim_controller.gd` | Base class: priority stack, `AnimationPlayer`, mirrors. See [`diorama-anim-controller.md`](diorama-anim-controller.md) |
| `apps/game/client/scripts/art/characters/diorama_anim_library.gd` | Clip tables. See [`diorama-anim-library.md`](diorama-anim-library.md) |
| `apps/game/client/scripts/art/characters/diorama_viewmodel.gd` | First-person arms. See [`diorama-viewmodel.md`](diorama-viewmodel.md) |
| `apps/game/client/assets/animations/diorama/player_locomotion.res` | Prebuilt `AnimationLibrary` loaded in preference to runtime compilation |

## How it works

`locomotion.gd:40-43` instantiates the script, names the node `AnimDirector`, adds it under the `Player` root, and calls `bind(visual)` with `Facing/DioramaVisual`.

`_ready()` (`player_anim_director.gd:42`) caches `Dodge`, `Guard`, `WeaponController`, `CombatReactions`, `Health`, and `CameraPivot/SpringArm3D`, calls `set_profile("player")`, connects signals, connects its own `footstep_frame` and `swing_frame`, builds the viewmodel, and calls `sync_camera_mode()`.

### Signals consumed

| Source node | Signal | Handler | Effect |
|-------------|--------|---------|--------|
| `Dodge` | `dash_started` | `_on_dash_started` | `play_dash(dir)` with the clip chosen from the dash vector in the rig's own frame (`:217-230`) |
| `Guard` | `block_state_changed(bool)` | `_on_block_state_changed` | `set_blocking` |
| `Guard` | `parry_success(Node)` | `_on_parry_success` | `play_parry` |
| `Guard` | `guard_broken` | `_on_guard_broken` | `play_guard_break` |
| `WeaponController` | `attack_started(String)` | `_on_attack_started` | `play_heavy_attack` for `heavy*`, `play_attack(..., &"attack_shoot")` for `bow*`, else `play_attack` (`:249-261`) |
| `WeaponController` | `weapon_changed(String)` | `_on_weapon_changed` | `set_weapon(archetype, archetype)` |
| `CombatReactions` | `stagger_started` | `_on_stagger_started` | `play_stagger(DEFAULT_STAGGER)` = `0.85` s |
| `CombatReactions` | `player_died` | `play_death` | death clip, `Priority.DEATH` |
| `Health` | `health_changed` | `_on_health_changed` | tracks `_last_health` only; reactions come from `Hurtbox.damaged` (`:291-305`) |
| `Hurtbox` | `damaged` | `_on_hurtbox_damaged` | single `_arbitrate_hit_reaction` picks one clip per hit (`:311-335`) |

Locomotion is pushed, not pulled: `update_locomotion(on_floor, velocity, sprinting, fall_height, local_dir)` (`:379`) is called once per physics frame after `move_and_slide()`. It returns early while `Dodge.is_dodging`. State selection: not on floor → `air_rise`/`air_fall`; landing uses `fall_height` thresholds; horizontal speed `<= 0.2` → `idle` or turn-in-place; else directional `walk`/`run` from `local_dir` via `_locomotion_clip_for`.

### Clip coverage

Every clip name this director can request, and whether `DioramaAnimLibrary` provides it:

| Requested clip | Requested from | In library |
|----------------|----------------|------------|
| `idle`, `walk`, `walk_l`, `walk_r`, `walk_b`, `run`, `run_b`, `air`, `air_rise`, `air_fall` | `player_anim_director.gd:421-453` | yes |
| `land`, `land_hard` | `:405-411` | yes |
| `turn_l`, `turn_r` | `:459-497` | yes |
| `dash_f`, `dash_b`, `dash_l`, `dash_r` | `:650-696` | yes |
| `block_start`, `block_hold`, `block_walk`, `block_hit` | `diorama_anim_controller.gd:468-469` | yes |
| `parry_success`, `guard_break` | base class | yes |
| `flinch`, `flinch_l`, `flinch_r`, `flinch_b` | `_arbitrate_hit_reaction` | yes |
| `stagger` | `:322-323` | yes |
| `death` | `play_death` | yes |
| `heal` | `diorama_anim_controller.gd:335-344` | yes |
| `attack_light_*`, `attack_heavy`, `attack_thrust_*`, `attack_shoot` | weapon routing | yes; bow keys `Bow` pivot built lazily in `diorama_character_skin.gd:470-477` |

### Method-track markers

`DioramaAnimLibrary` defines method markers including `anim_hitbox_on`, `anim_hitbox_off`, `anim_swing_vfx`, `anim_footstep`, `anim_heal_gulp`, and `anim_heal_commit`. The exporter writes `events_path: "../../AnimDirector"` per profile (`export_diorama_anim_libraries.gd:13`), and `_resolve_events_path` uses `visual.get_path_to(self)` (`diorama_anim_controller.gd:120-126`). `has_footstep_markers()` and `has_marker_tracks()` guard validation. Footsteps and swing VFX route through `footstep_frame` / `swing_frame` handlers at `player_anim_director.gd:790-813`.

### Viewmodel and camera modes

`_build_viewmodel()` (`:143`) requires `CameraPivot/SpringArm3D/Camera3D`, builds `DioramaViewmodel` under it with `CharacterService.appearance_theme` (`:119-121`), creates a mirrored `ViewmodelAnim` child, and registers it with `add_mirror`. `set_viewmodel_theme(theme)` retints on biome change (`:187-201`; called from `castle_run.gd` and `hub.gd`).

`sync_camera_mode()` (`:86`) sets the viewmodel holder visible only in first person and always leaves `_visual.visible = true`. `_process` runs `_update_viewmodel_sway` every frame (`:164-204`): camera yaw/pitch deltas are scaled by `1.6` and `1.4`, clamped to `SWAY_YAW_LIMIT = 0.09` and `SWAY_PITCH_LIMIT = 0.07` rad, smoothed with `SWAY_RESPONSE = 9.0`, and applied as `rotation = (sway.y, sway.x, sway.x * 0.4)`; a walk bob of `BOB_HEIGHT = 0.014` m advances at `delta * speed * 2.2`.

First person hides the upper body by switching the `Torso` subtree to `SHADOW_CASTING_SETTING_SHADOWS_ONLY` — the legs stay fully visible under the camera (`diorama_character_skin.gd:23`, `:283-289`). Third-person weapon and shield mounts get `cast_shadow = OFF` in first person (`:296-302`), re-applied on weapon swap by `_sync_first_person_weapon_shadows` (`player_anim_director.gd:300-305`).

## Contracts

- Node name `AnimDirector` under the player body. Looked up by `player_combat_reactions.gd:81`, `hit_feedback.gd:34`, `player_heal.gd:66`, `orbit_camera.gd:272`.
- Public API beyond the base class: `play_heal(duration)`, `sync_camera_mode()`, `update_locomotion(bool, Vector3, bool)`, overridden `set_weapon(weapon_id, archetype)` and `revive()`.
- Requires the rig pivot names `Root`, `Torso`, `Head`, `ArmL`, `ArmR`, `LegL`, `LegR`, `WeaponMount`, `ShieldMount` — the shared contract with `DioramaAnimLibrary` (`diorama_character_skin.gd:11-14`).
- Priority stack (highest wins): `DEATH` > `STAGGER` > `ATTACK` > `BLOCK` > `DASH` > `LOCOMOTION` (`diorama_anim_controller.gd:16-23`).
- Blend times: `LOCOMOTION_BLEND = 0.12` s, `ACTION_BLEND = 0.06` s, `block_hit` uses `0.03` s (`diorama_anim_controller.gd:28-29`, `:194`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Locomotion state machine and speed-scaled playback | IMPLEMENTED | `player_anim_director.gd:379-453`, `diorama_anim_controller.gd:206-216` |
| Directional walk/run and turn-in-place | IMPLEMENTED | `_locomotion_clip_for`, `_turn_clip_if_needed` |
| Dash direction clip selection | IMPLEMENTED | `player_anim_director.gd:650-696` |
| Attack clips stretched onto real weapon phase timings | IMPLEMENTED | `diorama_anim_library.gd` `compile_attack` |
| Animation method markers (footstep, swing, hitbox, heal) | IMPLEMENTED | `export_diorama_anim_libraries.gd:13`, `diorama_anim_controller.gd:120-145` |
| Heal animation with marker-timed commit | IMPLEMENTED | `diorama_anim_controller.gd:335-344`, `player_heal.gd:119-122` |
| Bow draw motion on the player rig | IMPLEMENTED | `diorama_character_skin.gd:470-477`, re-bind on weapon change |
| Hitstop on the player rig | IMPLEMENTED | `hit_feedback.gd:46-50` lazy `_director()` |
| Viewmodel palette from biome | IMPLEMENTED | `set_viewmodel_theme`, `castle_run.gd`, `hub.gd` |
| `RESET` clip and `revive()` blend | IMPLEMENTED | `diorama_anim_controller.gd:367-368` |
| Blocking locomotion (`block_walk`) | IMPLEMENTED | `diorama_anim_controller.gd:468-469` |
| Single-reaction arbitration per hit | IMPLEMENTED | `_arbitrate_hit_reaction` via `Hurtbox.damaged` |
| Air rise/fall clips | IMPLEMENTED | `player_anim_director.gd:421-427` |
| Per-instance attack library copy | IMPLEMENTED | `diorama_anim_controller.gd:95` `duplicate(true)` |
| Additive breathe/head-look layer | IMPLEMENTED | `DioramaAdditivePlayer` at `diorama_anim_controller.gd:166-179` |

## Related
- Improvement plan: [`../actual_improvements/player-anim-director.md`](../actual_improvements/player-anim-director.md) — **FINISHED**
- [`locomotion.md`](locomotion.md), [`player-combat.md`](player-combat.md), [`player-combat-reactions.md`](player-combat-reactions.md), [`player-heal.md`](player-heal.md)
- [`diorama-anim-controller.md`](diorama-anim-controller.md), [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md)
