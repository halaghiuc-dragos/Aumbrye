# Diorama anim library

Holds every character animation in the game as GDScript keyframe tables and compiles them into `AnimationLibrary` resources per rig. It is on the live play path: `DioramaAnimController._finish_bind` calls `build_library()` for every player, enemy, boss, and training dummy (`diorama_anim_controller.gd:93`). There are no imported `.anim`/`.tres` animation sources â€” the six `.res` files under `apps/game/client/assets/animations/diorama/` are pre-baked output of the same tables via `scripts/tools/export_diorama_anim_libraries.gd`.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/characters/diorama_anim_library.gd` | 2260 lines: clip tables, attack tables, profile/weapon maps, compiler, pose marker |
| `apps/game/client/assets/animations/diorama/digests.json` | SHA-256 digests per profile, written by the exporter (`DIGESTS_PATH` `:34`) |
| `apps/game/client/assets/animations/diorama/player_locomotion.res` | Pre-compiled `AnimationLibrary` for the `player` profile |
| `apps/game/client/assets/animations/diorama/melee_locomotion.res` | Pre-compiled library for `melee` |
| `apps/game/client/assets/animations/diorama/ranged_locomotion.res` | Pre-compiled library for `ranged` |
| `apps/game/client/assets/animations/diorama/shield_locomotion.res` | Pre-compiled library for `shield` |
| `apps/game/client/assets/animations/diorama/brute_locomotion.res` | Pre-compiled library for `brute` |
| `apps/game/client/assets/animations/diorama/hound_locomotion.res` | Pre-compiled library for `hound` |
| `apps/game/client/assets/animations/diorama/README.md` | Regeneration command and exported profile list |
| `apps/game/client/scripts/tools/export_diorama_anim_libraries.gd` | Headless `SceneTree` exporter that writes the six `.res` files |

## Key format

Every key is `[time, x, y, z]`. A part entry may have a `"pos"` channel (meter **offset** from the part's rest position) and/or a `"rot"` channel (euler radians **offset** from the part's rest rotation). `_add_vector_track` writes `rest_value + offset` as the actual keyframe value (`diorama_anim_library.gd:2085`), so clip tables are rig-independent as long as the rest pose is supplied correctly. Locomotion/reaction clips in `CLIPS` use absolute seconds; attack clips in `ATTACKS` use normalized time `0..1` and are stretched at compile time via `build_attack` (`:1993-2019`).

## Clip inventory

### `CLIPS` (`:34-1053`) â€” 40 clips, plus a synthesised `RESET`

| Group | Clips | Loop | Method markers |
|-------|-------|------|----------------|
| Idle | `idle` (2.6 s) | yes | none |
| Forward locomotion | `walk` (0.8 s), `run` (0.56 s) | yes | `FOOTSTEP` @ walk 0.18/0.58, run 0.10/0.38 |
| Directional walk | `walk_b` (0.9 s), `walk_l` (0.85 s), `walk_r` (0.85 s) | yes | `FOOTSTEP` each |
| Directional run | `run_b`, `run_l`, `run_r` (0.62 s each) | yes | `FOOTSTEP` each |
| Turns | `turn_l`, `turn_r` (0.34 s) | no | none |
| Air | `air` (0.9 s), `air_rise`, `air_fall` | yes | none |
| Land | `land` (0.26 s), `land_hard` (0.42 s) | no | none |
| Dash | `dash_f`, `dash_b`, `dash_l`, `dash_r` (0.45 s) | no | none |
| Block | `block_start` (0.14 s), `block_hold` (1.8 s), `block_walk` (0.9 s), `block_hit` (0.24 s) | hold/walk loop | `FOOTSTEP` on `block_walk` @ 0.2/0.65 |
| Parry / guard | `parry_success` (0.36 s), `guard_break` (0.6 s) | no | `SWING_VFX` @ 0.05 on `parry_success` |
| Flinch | `flinch`, `flinch_f`, `flinch_l`, `flinch_r`, `flinch_b` (0.26 s) | no | none |
| Stagger | `stagger`, `stagger_f`, `stagger_b`, `stagger_l`, `stagger_r` (0.85 s) | no | none |
| Heal | `heal` (1.35 s) | no | `HEAL_GULP` @ 0.3/0.62, `HEAL_COMMIT` @ 0.95 |
| Death | `death` (1.0 s) | no | none |
| `RESET` | 0.1 s | no | synthesised from rest pose (`:2244-2259`) |
| `__pose__` (`POSE_MARKER`) | 0.0 s | no | rest-pose fingerprint baked into authored `.res` (`:2206-2221`, `:33`) |

`walk` and `run` key `Root` (pos), `Torso`, `Head`, `LegL`, `LegR`, `ArmL`, `ArmR`, plus quadruped-only `LegBL`, `LegBR`, `Tail` (`:61-139`). Directional walk/run clips omit arms on backpedal variants and omit quadruped pivots.

### `ADDITIVE_CLIPS` (`:1056-1094`) â€” 2 clips on a second `AnimationPlayer`

| Clip | Length (s) | Loop | Keyed parts |
|------|-----------|------|-------------|
| `breathe` | 3.4 | yes | `Torso` (pos+rot), `Head` |
| `head_look` | 0.1 | yes | `Head` (runtime yaw/pitch overwritten by `player_anim_director.gd:563-568`) |

`build_additive_library` (`:1888-1894`) compiles these without method tracks. `DioramaAnimController._setup_additive_player` (`diorama_anim_controller.gd:166-179`) autoplays `breathe`.

### `ATTACKS` (`:1099-1838`) â€” 10 clips in normalized time

| Clip | `startup_end` | `active_end` | Keyed parts | `SWING_VFX` |
|------|--------------|-------------|-------------|-------------|
| `attack_light_1` | 0.34 | 0.58 | `Root`, `Torso`, `Head`, `ArmR`, `ArmL`, `LegL`, `LegR` | 0.35 |
| `attack_light_2` | 0.32 | 0.56 | same | 0.33 |
| `attack_light_3` | 0.40 | 0.62 | same | 0.41 |
| `attack_heavy` | 0.46 | 0.66 | same | 0.47 |
| `attack_thrust` | 0.36 | 0.60 | same | 0.37 |
| `attack_thrust_2` | 0.28 | 0.50 | same | 0.29 |
| `attack_thrust_3` | 0.40 | 0.62 | same | 0.41 |
| `attack_shoot` | 0.55 | 0.70 | `Torso`, `Head`, `ArmL`, `ArmR`, `Bow` | 0.56 |
| `attack_bite` | 0.40 | 0.62 | `Root`, `Torso`, `Head`, `Tail`, `LegL`, `LegR` | 0.41 |
| `attack_shield_bash` | 0.42 | 0.62 | `Root`, `Torso`, `ArmL`, `ArmR`, `LegL`, `LegR` | 0.43 |

`build_attack` appends `HITBOX_ON` at `startup_end` and `HITBOX_OFF` at `active_end` (`:2006-2007`).

Total buildable clip names: 40 `CLIPS` + `RESET` + 10 `ATTACKS` + 2 `ADDITIVE_CLIPS` = **53** (attacks and additive clips are compiled on demand, not stored in the authored `.res` locomotion libraries).

### Method marker constants (`:16-21`)

`HITBOX_ON = &"anim_hitbox_on"`, `HITBOX_OFF = &"anim_hitbox_off"`, `SWING_VFX = &"anim_swing_vfx"`, `FOOTSTEP = &"anim_footstep"`, `HEAL_GULP = &"anim_heal_gulp"`, `HEAL_COMMIT = &"anim_heal_commit"`. All six are implemented on `DioramaAnimController` (`diorama_anim_controller.gd:488-519`).

### Clip selection maps

`PROFILE_ATTACKS` (`:1841-1848`): `player` â†’ light 1/2/3; `melee` â†’ light 1/2; `brute` â†’ heavy; `shield` â†’ shield bash; `ranged` â†’ shoot; `hound` â†’ bite. Default when the profile is unknown is `melee` (`:1864`).

`WEAPON_ATTACKS` (`:1850-1858`): `sword` â†’ light 1/2/3; `greatsword` â†’ light 3 + heavy; `dagger` â†’ light 1/2; `spear` â†’ thrust/thrust_2/thrust_3; `bow` â†’ shoot; `axe` â†’ heavy, light 3, heavy; `staff` â†’ thrust, light 2, thrust.

`attack_clips_for(profile, weapon_archetype)` (`:1861-1864`) prefers `WEAPON_ATTACKS` when the archetype is non-empty and known, else falls back to `PROFILE_ATTACKS`.

`heavy_clip_for(archetype)` (`:1867-1878`): `spear` â†’ `attack_thrust_3`, `staff` â†’ `attack_thrust`, `bow` â†’ `attack_shoot`, `axe` â†’ `attack_heavy`, default â†’ `attack_heavy`.

## Clips requested by callers versus clips defined

Every clip name any caller asks for exists in `CLIPS`, `ADDITIVE_CLIPS`, or `ATTACKS`. There are no requested-but-undefined names.

| Caller | Clips requested |
|--------|-----------------|
| `player_anim_director.gd:407-453` | `land` / `land_hard`, `air` / `air_rise` / `air_fall`, `idle`, `walk`/`run` + directional variants, `turn_l`/`turn_r` |
| `player_anim_director.gd:650-696` | `dash_f`, `dash_b`, `dash_l`, `dash_r` |
| `player_anim_director.gd:323-335`, `:726-738` | directional `flinch_*`, `stagger_*` via `DioramaAnimController` |
| `player_anim_director.gd:764` | `attack_shoot` |
| `player_anim_director.gd:760-768` | `attack_clips_for` / `heavy_clip_for` attack set |
| `player_heal.gd:92-93` | `heal` via `play_heal` |
| `player_combat_reactions.gd` | `death`, `stagger` |
| `diorama_anim_controller.gd:206-473` | block, parry, guard, flinch, stagger, heal, death, directional locomotion |
| `castle_enemy_base.gd:484-486` | `run`, `walk`, `idle` |
| `castle_enemy_base.gd` | profile attack clips, `stagger`, `death`, `flinch` |

Tracks whose part is absent from the rest pose are skipped silently (`:2038-2040`); `_compile` returns `null` when no track survived (`:2063-2064`).

## Compilation

`build_library(rest_pose, events_path, profile, force_compile)` (`:1983-1995`):

1. Unless `force_compile`, `_can_use_authored_library(rest_pose, profile)` (`:1969-1980`) returns `true` only when the rest pose has `Root`, the `.res` exists, it contains `POSE_MARKER` (`&"__pose__"`), and `_pose_hash(rest_pose)` matches the marker animation (`:2187-2241`).
2. When an authored library loads, `_supplement_authored_library` (`:1998-2038`) runs before return:
   - Compiles and adds any clip from the supplemental list (`:1952-1970`) that is missing from the loaded library.
   - Adds `RESET` from the live rest pose when absent (`:1979-1982`).
   - When `events_path != ""` and `walk`/`run` lack method tracks, recompiles those two clips with markers (`:1983-1989`).
3. On the full compile path, `compile_authored_library` (`:1954-1966`) compiles every `CLIPS` entry, then `RESET` and `POSE_MARKER`.

`events_path_for_profile(profile)` (`:1921-1922`) returns `"../../AnimDirector"` for `player` and `"../../AnimController"` for all other authored profiles.

`build_attack` caches compiled attacks in static `_attack_cache` keyed by clip name, pose hash, events path, and phase timings (`:2042-2074`, `:2077-2092`). `clear_attack_cache()` (`:1925-1926`) evicts the cache.

`_compile(spec, rest_pose, events_path, speed, phase_map)` (`:2095-2146`):
- Length is `phase_map["total"]` for attacks, else `spec["length"] / speed`, floored at 0.02 s (`:2030-2033`).
- `loop_mode` is `LOOP_LINEAR` when `spec["loop"]`, else `LOOP_NONE` (`:2034`).
- Value tracks are `INTERPOLATION_LINEAR` with `UPDATE_CONTINUOUS` (`:2154-2155`).
- A method track is added when `methods` is non-empty and `events_path != ""` (`:2140-2145`).

`build_attack` (`:2042-2074`) deep-copies the spec, appends hitbox markers, and builds a `phase_map` so `_remap_time` piecewise-linearly stretches normalized time onto weapon phases (`:2163-2175`). `total` is floored at 0.08 s (`:2063`).

## Authored `.res` libraries

`AUTHORED_LIBRARY_PATHS` (`:24-31`) maps six profiles to `res://assets/animations/diorama/<profile>_locomotion.res`. All six files are present on disk. There is **no `dummy` entry and no `dummy_locomotion.res`**.

The exporter calls `CharacterSkin.rest_pose_for_profile(profile_key)` then `AnimLibrary.compile_authored_library(rest_pose, events_path, profile_key)` (`export_diorama_anim_libraries.gd:43-48`). Rest poses come from the same `_build_humanoid`/`_build_quadruped` path as runtime rigs (`diorama_character_skin.gd:454-466`), not a hand-maintained duplicate. Exported libraries include method tracks on clips that declare `methods`, plus `RESET` and `POSE_MARKER`.

After export, `digests.json` records a `library_digest` SHA-256 per profile (`export_diorama_anim_libraries.gd:163-178`, `diorama_anim_library.gd:1929-1943`). `--verify` mode recomputes digests and compares against committed `.res` files and `digests.json` (`export_diorama_anim_libraries.gd:58-71`, `:181-192`).

The on-disk `.res` files are binary and not text-readable. `diorama_anim_suite._test_required_clips` asserts the committed `player_locomotion.res` contains supplemental clip names (`heal`, `walk_b/l/r`, `block_walk`); until re-export, those clips exist only in `CLIPS` and are added at bind time by `_supplement_authored_library`.

### Which rigs load an authored library

| Consumer | `_profile` | Authored library used |
|----------|------------|----------------------|
| Player third-person body | `"player"` (`player_anim_director.gd:52`) | `player_locomotion.res` |
| Player first-person viewmodel | `"player"` (`player_anim_director.gd:76`) | no â€” viewmodel rest pose has no `Root` key, so `_can_use_authored_library` returns `false` at `:1919-1920` |
| Training dummy | `"melee"` (`training_grunt.gd:41`) despite `build_training_dummy` body (`:37`) | `melee_locomotion.res` |
| `melee`/`ranged`/`shield`/`brute`/`hound` enemies | `profile_for_enemy_data` | matching `.res` |
| Boss/miniboss definitions | `"boss"` | no â€” `AUTHORED_LIBRARY_PATHS.get("boss", "")` is `""` |

`DioramaAnimController._finish_bind` duplicates the loaded library when authored (`diorama_anim_controller.gd:94-95`) so per-instance attack compilations do not mutate the cached `.res` resource.

## Locomotion speed scaling

Playback rate is **not** derived from per-clip stride metadata â€” `CLIPS` has no `stride_m` or `contacts` keys. `DioramaAnimController.request_locomotion` scales `walk`/`walk_*`/`block_walk` by `speed / 4.5` clamped to `[0.45, 1.6]` and `run`/`run_*` by `speed / 7.0` clamped to `[0.6, 1.5]` (`diorama_anim_controller.gd:36-37`, `:216-223`). At `WALK_SPEED = 4.5` (`locomotion.gd:3`) the player travels 3.6 m per 0.8 s `walk` cycle against roughly 0.48 m of hip-swing stride for a 0.46 m leg â€” feet slide when the clamp is hit.

`walk` bakes a constant `+0.06` rad forward torso pitch at every key (`diorama_anim_library.gd:80`); `run` bakes `+0.2` rad (`:119`), so torso pitch snaps on blend in/out.

Quadruped `walk`/`run` reuse biped leg amplitudes (`:84-96`, `:123-136`). A hound leg is 0.30 m (`diorama_character_skin.gd:426`); `content/enemies/frost_hound.json:8` sets `move_speed: 5.5`, so foot sliding is worse than on bipeds at the same playback clamp.

## Contracts

- **Part names keyed by clips** â€” `Root`, `Torso`, `Head`, `ArmL`, `ArmR`, `LegL`, `LegR`, `LegBL`, `LegBR`, `Tail`, `Bow`. `WeaponMount`, `ShieldMount`, `Shield`, `EarL`, and `EarR` are never keyed by any clip.
- **Rest-pose shape** â€” `{ part_name: { "path": String, "position": Vector3, "rotation": Vector3 } }`, from `DioramaCharacterSkin.collect_rest_pose` (`diorama_character_skin.gd:222-227`).
- **Method names** the host must implement: `anim_hitbox_on`, `anim_hitbox_off`, `anim_swing_vfx`, `anim_footstep`, `anim_heal_gulp`, `anim_heal_commit`.
- **Consumers** â€” `DioramaAnimController` (`diorama_anim_controller.gd:93`, `:414-430`), `diorama_character_rig_player.gd:34`, `export_diorama_anim_libraries.gd:178`, `diorama_anim_suite.gd:16-366`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| All clips are procedurally keyframed in GDScript; `.res` files are generated output | PLACEHOLDER | `:34-1838`; `export_diorama_anim_libraries.gd:178` |
| Directional locomotion, air variants, `land_hard`, `block_walk`, directional flinch/stagger, `heal` | IMPLEMENTED | `:140-966`; callers in `player_anim_director.gd:407-738` |
| Additive `breathe` / `head_look` layering | IMPLEMENTED | `:1056-1094`, `diorama_anim_controller.gd:166-179` |
| Authored libraries export with method tracks, `RESET`, and `POSE_MARKER` | IMPLEMENTED | `export_diorama_anim_libraries.gd:43-48`, `compile_authored_library` `:1954-1966` |
| Rest-pose drift detected via `POSE_MARKER` hash; falls back to full compile | IMPLEMENTED | `_can_use_authored_library` `:1969-1980` |
| Runtime supplementation backfills clip/marker gaps in stale `.res` | IMPLEMENTED | `_supplement_authored_library` `:1998-2038` |
| `digests.json` records per-profile library SHA-256 | IMPLEMENTED | `export_diorama_anim_libraries.gd:163-178`; file `ABSENT` on disk until next export |
| Attack phase remapping matches weapon JSON timings | IMPLEMENTED | `:1993-2019`, `:2090-2102` |
| Locomotion playback uses reference-speed ratio, not stride metadata | PARTIAL | `diorama_anim_controller.gd:216-223`; no `stride_m` in `CLIPS` |
| No `dummy` authored library; dummy driven by `melee` library against `dummy` geometry | BROKEN | `AUTHORED_LIBRARY_PATHS` `:24-31`, `training_grunt.gd:37` vs `:41` |
| Committed `player_locomotion.res` missing supplemental clips until re-export | PARTIAL | `diorama_anim_suite.gd:50-84` checks on-disk `.res`; supplementation at bind masks runtime |
| `walk`/`run` bake constant torso lean into every key | PARTIAL | `diorama_anim_library.gd:80`, `:119` |
| Every value track is `INTERPOLATION_LINEAR`; no per-key ease | PARTIAL | `:2081` |
| Quadruped reuses biped leg amplitudes | PLACEHOLDER | `:84-96` vs `diorama_character_skin.gd:426` |
| `attack_shoot` keys `Bow`; player gets a `Bow` pivot only when a bow is attached | PARTIAL | `:1695-1704`, `diorama_character_skin.gd:471-473` |
| No per-archetype attack pose sets (`axe`, `dagger`, `greatsword` reuse sword/thrust poses) | PLACEHOLDER | `WEAPON_ATTACKS` `:1850-1858` maps to shared `ATTACKS` entries |
| No `jog`, `idle_alert`, cast, hover, trot, gallop, or boss attack clips | ABSENT | `CLIPS` / `ATTACKS` inventories above |
| No clip keys `WeaponMount`, `ShieldMount`, `Shield`, `EarL`, `EarR` | ABSENT | track listings above; `diorama_character_skin.gd:671` builds `EarL` on hounds |

## Related
- Improvement plan: [`../actual_improvements/diorama-anim-library.md`](../actual_improvements/diorama-anim-library.md) - **FINISHED**
- Cross-cutting decision on authored characters and animation data: [`character-authoring.md`](character-authoring.md)
- [`diorama-anim-controller.md`](diorama-anim-controller.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`player-anim-director.md`](player-anim-director.md)
- [`export-tools.md`](export-tools.md), [`validation-suites.md`](validation-suites.md), [`vfx-service.md`](vfx-service.md)
