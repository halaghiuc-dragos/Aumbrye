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
| `Health` | `health_changed` | `_on_health_changed` | on any decrease: `play_block_impact()` while blocking, else `play_flinch()` (`:268-276`) |
| `Poise` | `poise_damaged(amount, remaining)` | `_on_poise_damaged` | `>= 20.0` → `play_stagger(0.45)`; `>= 8.0` → `play_flinch()` (`:132-136`) |

Locomotion is pushed, not pulled: `update_locomotion(on_floor, velocity, sprinting)` (`:141`) is called once per physics frame after `move_and_slide()`. It returns early while `Dodge.is_dodging`. State selection: not on floor → `air` (with an unused `vertical_speed` param); first frame back on floor → one-shot `land` at `Priority.DASH`; horizontal speed `<= 0.2` → `idle`; else `run` when sprinting, `walk` otherwise, both passing `speed` so the base class scales `AnimationPlayer.speed_scale`.

### Clip coverage

Every clip name this director can request, and whether `DioramaAnimLibrary` provides it:

| Requested clip | Requested from | In library |
|----------------|----------------|------------|
| `idle`, `walk`, `run`, `air` | `player_anim_director.gd:149-161` | yes, `diorama_anim_library.gd:33`, `:48`, `:70`, `:91` |
| `land` | `:153` | yes, `:103` |
| `dash_f`, `dash_b`, `dash_l`, `dash_r` | `:208-230` | yes, `:114`, `:126`, `:138`, `:150` |
| `block_start`, `block_hold`, `block_hit` | `diorama_anim_controller.gd:183-195` | yes, `:162`, `:174`, `:187` |
| `parry_success` | `diorama_anim_controller.gd:200` | yes, `:197` |
| `guard_break` | `diorama_anim_controller.gd:205` | yes, `:208` |
| `flinch` | `:136`, `:276` | yes, `:220` |
| `stagger` | `:129`, `:134`, `:246` | yes, `:230` |
| `death` | `:119` | yes, `:246` |
| `attack_light_1`, `attack_light_2`, `attack_light_3` | `PROFILE_ATTACKS["player"]`, `WEAPON_ATTACKS["sword"]` | yes, `:267`, `:281`, `:295` |
| `attack_heavy` | `heavy_clip_for` default, `WEAPON_ATTACKS["greatsword"]`/`["axe"]` | yes, `:309` |
| `attack_thrust`, `attack_thrust_2`, `attack_thrust_3` | `WEAPON_ATTACKS["spear"]`, `["staff"]`, `heavy_clip_for("spear")` | yes, `:325`, `:339`, `:353` |
| `attack_shoot` | `:259`, `WEAPON_ATTACKS["bow"]` | yes, `:369`, but its only weapon track keys a `Bow` pivot the player rig does not have — `PROFILES["player"]` declares no `extras` (`diorama_character_skin.gd:32-41`); only `"ranged"` adds a `Bow` pivot (`:58`, `:408-412`). The track is dropped by `_compile` (`diorama_anim_library.gd:530-531`) |
| heal | `play_heal(duration)` at `:128` | **no heal clip exists.** `play_heal` calls `play_stagger(duration)`, so drinking plays the hurt animation |

No clip name is requested that the library lacks. Two clips are effectively unavailable in practice: `attack_shoot`'s bow motion (missing pivot) and any heal pose (missing clip).

### Method-track markers

`DioramaAnimLibrary` defines four `AnimationPlayer` method markers: `anim_hitbox_on`, `anim_hitbox_off`, `anim_swing_vfx`, `anim_footstep` (`diorama_anim_library.gd:16-19`). `walk` and `run` carry two `FOOTSTEP` keys each (`:68`, `:89`); every attack carries a `SWING_VFX` key plus injected `HITBOX_ON`/`HITBOX_OFF` at the phase boundaries (`:499-500`).

None of them fire for the player:

- The prebuilt libraries are exported with `events_path = ""` (`apps/game/client/scripts/tools/export_diorama_anim_libraries.gd:81`), and `_compile` skips the method track when the path is empty (`diorama_anim_library.gd:550`). `player_locomotion.res` therefore contains no method tracks.
- The runtime path is also empty: `_resolve_events_path` returns `""` unless `visual.is_ancestor_of(self)` (`diorama_anim_controller.gd:116`). The visual is `Player/Facing/DioramaVisual` and the controller is `Player/AnimDirector`, so the guard rejects it.

Consequences: no `footstep_frame` (see [`locomotion.md`](locomotion.md)), no `swing_frame`-driven weapon trail, and no animation-driven hitbox. Hitboxes are opened by `WeaponController`'s own phase timer instead (`weapon_controller.gd:320-329`), and the swing trail is emitted from `_enable_hitbox_for_attack` (`weapon_controller.gd:356-357`), so combat works but the visual strike frame and the hitbox frame are only as aligned as the phase-stretch math makes them.

### Viewmodel and camera modes

`_build_viewmodel()` (`:62`) requires `CameraPivot/SpringArm3D/Camera3D`, builds `DioramaViewmodel` under it, creates a second plain `DioramaAnimController` named `ViewmodelAnim` as a child of the director, sets its profile and weapon, binds it to `ViewRoot`, and registers it with `add_mirror` so one gameplay call drives both rigs (`:73-81`). The palette theme is hardcoded to `PixelStyle.PaletteTheme.HUB` (`:66`).

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
| Locomotion state machine and speed-scaled playback | IMPLEMENTED | `player_anim_director.gd:141-161`, `diorama_anim_controller.gd:156-164` |
| Dash direction clip selection | IMPLEMENTED | `player_anim_director.gd:217-230` |
| Attack clips stretched onto real weapon phase timings | IMPLEMENTED | `diorama_anim_library.gd:486-512` |
| Animation method markers (footstep, swing, hitbox) | BROKEN | `export_diorama_anim_libraries.gd:81` exports with no events path; `diorama_anim_controller.gd:116` rejects the runtime path |
| Heal animation | PLACEHOLDER | `play_heal` reuses `stagger` (`player_anim_director.gd:128-129`) |
| Bow draw motion on the player rig | BROKEN | `attack_shoot` keys a `Bow` pivot absent from `PROFILES["player"]` (`diorama_character_skin.gd:32-41`) |
| Hitstop on the player rig | BROKEN | `hit_feedback.gd:32-34` resolves `AnimDirector` in its own `_ready`, which Godot runs before the parent `_ready` that creates the node, so `set_speed_scale` is never called |
| Viewmodel palette | FAKE | Hardcoded `PaletteTheme.HUB` regardless of biome (`player_anim_director.gd:66`) |
| `RESET` clip | ABSENT from the prebuilt libraries | Added only on the compile path (`diorama_anim_library.gd:479-481`); the authored `.res` is returned before that (`:468-472`) |
| Turn-in-place, strafe-specific, and blocking-locomotion clips | ABSENT | `CLIPS` has no `walk_l`/`walk_r`/`walk_b`/`turn_*`/`block_walk` entries (`diorama_anim_library.gd:32-261`) |
| Additive upper-body layering | ABSENT | One `AnimationPlayer`, one clip at a time; no `AnimationTree` or blend tree anywhere under `scripts/art/characters/` |

## Related
- Improvement plan: [`../actual_improvements/player-anim-director.md`](../actual_improvements/player-anim-director.md)
- [`locomotion.md`](locomotion.md), [`player-combat.md`](player-combat.md), [`player-combat-reactions.md`](player-combat-reactions.md), [`player-heal.md`](player-heal.md)
- [`diorama-anim-controller.md`](diorama-anim-controller.md), [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md)
