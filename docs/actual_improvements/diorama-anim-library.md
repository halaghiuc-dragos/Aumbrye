# Diorama anim library — improvement plan

## Current state

All 27 clips in the game — 17 locomotion and reaction entries in `CLIPS` plus 10 attacks in `ATTACKS` — are keyframe tables written by hand in GDScript and compiled to `AnimationLibrary` resources at runtime (`diorama_anim_library.gd:32-407`), with a `RESET` clip synthesized from the rest pose (`:479-481`). The six `.res` files under `apps/game/client/assets/animations/diorama/` are generated from those same tables by `scripts/tools/export_diorama_anim_libraries.gd`, so there is no authored animation data in the project — only pre-baked output of the tables. Clip names match every request from `player_anim_director.gd`, `player_combat_reactions.gd`, and `castle_enemy_base.gd`; the failures are in compilation and export, not naming. See [`../existing_codebase/diorama-anim-library.md`](../existing_codebase/diorama-anim-library.md) for the complete clip inventory and track-coverage matrix.

Whether animation should stay procedural or move to authored frame data is decided in [`character-authoring.md`](character-authoring.md). This plan makes the current system correct, speed-matched, and testable, and structures the clip tables so an authored replacement can be swapped in per clip rather than all at once.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| ANL-01 | P0 | The exporter passes `events_path = ""`, so the six `.res` libraries contain no method tracks. Combined with ANC-01, no animation in the game carries a `FOOTSTEP`, `SWING_VFX`, `HITBOX_ON`, or `HITBOX_OFF` marker. | `export_diorama_anim_libraries.gd:81`; gate at `diorama_anim_library.gd:550` |
| ANL-02 | P0 | Locomotion cycle length is unrelated to travel speed. `walk` is 0.8 s with a 0.48 m biped stride while the player covers 3.6 m per cycle at `WALK_SPEED = 4.5`; playback scale clamps at 1.6x so the mismatch cannot be closed. | `:48`, `:59-60`; `diorama_anim_controller.gd:159`; `locomotion.gd:3` |
| ANL-03 | P0 | The training dummy is built from the `dummy` profile but the controller declares profile `melee`, so `melee_locomotion.res` — whose keys bake melee's absolute rest positions — drives dummy geometry. `idle` keys `Torso:position` at melee's `(0, 0.48, 0)` against the dummy's `(0, 0.46, 0)`, lifting the torso, head, and arms 0.02 m the moment idle starts. | `training_grunt.gd:37` vs `:41`; `:38` (`idle` Torso pos track), `:573`; `diorama_character_skin.gd:78-85` vs `:42-50` |
| ANL-04 | P1 | Nothing detects a stale `.res`. A clip added to `CLIPS` after the last export is silently absent for all six authored profiles, and `has_clip()` swallows the request. | `diorama_anim_suite.gd:16-30` checks `ResourceLoader.exists()` only; `diorama_anim_controller.gd:309`, `:321-322` |
| ANL-05 | P1 | `export_diorama_anim_libraries.REST_POSES` is a hand-copied duplicate of `PROFILES` with no consistency test. It currently agrees value for value, but nothing keeps it that way. | `export_diorama_anim_libraries.gd:10-71` vs `diorama_character_skin.gd:32-86` |
| ANL-06 | P1 | The clip vocabulary is a single locomotion triple and one attack per archetype. There is no strafe, backpedal, turn, cast, hover, slither, sprint-start, sprint-stop, or wake-up clip; a hound has exactly one attack (`attack_bite`) and no lunge, howl, or circle. | `CLIPS` `:32-261`, `ATTACKS` `:266-407`, `PROFILE_ATTACKS` `:410-417` |
| ANL-07 | P1 | `walk` bakes a constant `+0.06` rad torso lean into all three keys and `run` a constant `+0.2` rad, so torso pitch snaps discontinuously on entering and leaving those clips instead of easing through the 0.12 s blend. | `:56`, `:78` |
| ANL-08 | P1 | Every track is `INTERPOLATION_LINEAR` with `UPDATE_CONTINUOUS`. Anticipation, snap, and settle all read as constant-velocity ramps, which is the single largest reason the attacks feel weightless. | `:568-569` |
| ANL-09 | P1 | No clip keys `WeaponMount`, `ShieldMount`, `Shield`, `EarL`, or `EarR`, so the weapon cannot lead or trail the hand, the shield cannot brace independently of the arm, and the hound's ears never move. | full track listing in the existing-code doc; `diorama_character_skin.gd:404-417`, `:434-435` |
| ANL-10 | P1 | `attack_shoot` keys `Bow`, a pivot only the `ranged` profile owns, so a player with a bow equipped gets arm motion with no bow flex and no draw. | `:377`; `diorama_character_skin.gd:51-59`, `:407-412` |
| ANL-11 | P2 | `RESET` is synthesised only on the runtime-compiled path, and the authored `RESET` omits `WeaponMount`/`ShieldMount` because the exporter rest poses omit them. | `:479-481`, `:599-614`; `export_diorama_anim_libraries.gd:10-71` |
| ANL-12 | P2 | Attack timings are stretched from normalized time but the *poses* are not: a 0.15 s dagger swing and a 0.6 s greatsword swing use identical joint angles, just played at different rates. | `:486-512`; `WEAPON_ATTACKS` `:419-427` |

## Target design

### 1. Method markers reach every rig

Fix the root cause in the controller (ANC-01, see [`diorama-anim-controller.md`](diorama-anim-controller.md)), then change the exporter to bake a **relative** events path so authored libraries carry markers too. The AnimationPlayer's `root_node` is the visual (`diorama_anim_controller.gd:94`) and the controller is a sibling of the visual's parent, so the path is deterministic per host layout. Bake `"../../AnimDirector"` for `player` and `"../AnimController"` for the enemy profiles into the exported libraries via a new `EVENTS_PATHS` table in the exporter, and assert at bind time that the baked path resolves:

```gdscript
# diorama_anim_controller._finish_bind, after add_animation_library
if _events_path != "" and _player.get_node_or_null(NodePath(_events_path)) == null:
    push_warning("DioramaAnimController: events path '%s' does not resolve" % _events_path)
```

Rejected alternative: dropping the `.res` files and always compiling at runtime. That removes ANL-01 and ANL-04 outright, but compiling 17 clips at roughly 20 tracks each for every enemy spawn is work the exporter already did once; keeping the cache and validating it is cheaper at spawn time.

### 2. Speed-matched locomotion with real stride data

Each locomotion clip declares the ground distance it covers, and the controller derives playback rate from that instead of a fixed reference speed.

```gdscript
&"walk": {
    "length": 0.8,
    "loop": true,
    "stride_m": 1.4,          # meters traveled per cycle at speed_scale 1.0
    "contacts": [0.18, 0.58], # normalized times of foot contact
    ...
}
```

`stride_m` is computed from the leg length and hip swing rather than guessed: for a profile with leg length `L` and peak hip rotations `+a` and `-b`, one step is `L * (sin a + sin b)` and a cycle is two steps. For `player` (`L = 0.46`, `a = 0.55`, `b = 0.45`) that is `2 * 0.46 * (0.522 + 0.435) = 0.88 m`. To cover 4.5 m/s at a plausible 0.8 s cycle the clip needs a `1.4 m` cycle, so the hip amplitudes must rise to about `+0.87` / `-0.72` rad **and** the run/walk speeds need a downward pass, or the root needs a 0.2 m forward lunge per step. The target is a stride:travel ratio within 15 percent at the reference speed, achieved by re-authoring amplitudes rather than by clamping playback.

New per-profile stride scaling: because `stride_m` depends on leg length, the compiler scales it by `leg_length / reference_leg_length` from the rig catalog, so a hound (0.30 m legs) reports a 0.91 m cycle and the controller picks the right rate without a hound-specific table.

`DioramaAnimController.request_locomotion` then computes `speed_scale = travel_speed * clip_length / stride_m`, clamped to `[0.5, 2.2]`, and the clamp being hit is itself a warning-worthy condition. Clip selection gains a third tier so the clamp is rarely reached: `walk` for 0-2.4 m/s, `jog` for 2.4-5.0 m/s, `run` above 5.0 m/s.

### 3. Full clip inventory

Locomotion and reaction clips to reach, with durations and loop flags. Existing entries keep their names; new entries are marked.

| Clip | Length (s) | Loop | Stride (m) | Notes |
|------|-----------|------|-----------|-------|
| `idle` | 2.6 | yes | — | keep; add `Head` micro-saccade at 0.4 s intervals |
| `idle_alert` (new) | 2.0 | yes | — | weapon raised, weight forward; played when a target is locked |
| `walk` | 0.8 | yes | 1.4 | re-amplitude per section 2 |
| `jog` (new) | 0.62 | yes | 2.9 | interpolates walk and run rather than stretching either |
| `run` | 0.56 | yes | 3.9 | re-amplitude |
| `strafe_l` (new) | 0.7 | yes | 1.2 | crossover step, torso stays facing forward |
| `strafe_r` (new) | 0.7 | yes | 1.2 | mirror of `strafe_l` |
| `walk_back` (new) | 0.9 | yes | 1.1 | heel-first contacts, shorter stride |
| `turn_l` (new) | 0.4 | no | — | pivot step, played when yaw delta exceeds 100 deg while stationary |
| `turn_r` (new) | 0.4 | no | — | mirror |
| `air` | 0.9 | yes | — | keep |
| `land` | 0.26 | no | — | keep; add a `land_hard` variant at 0.45 s for falls above 4 m/s |
| `land_hard` (new) | 0.45 | no | — | knee-down absorb, `Root` drops 0.28 m |
| `dash_f` / `dash_b` / `dash_l` / `dash_r` | 0.45 | no | — | keep |
| `block_start` | 0.14 | no | — | keep |
| `block_hold` | 1.8 | yes | — | keep |
| `block_hit` | 0.24 | no | — | keep |
| `block_walk` (new) | 0.95 | yes | 1.0 | shield-forward shuffle; today blocking while moving plays `block_hold` and the legs freeze |
| `parry_success` | 0.36 | no | — | keep |
| `guard_break` | 0.6 | no | — | keep |
| `flinch` | 0.26 | no | — | keep |
| `flinch_f` / `flinch_b` / `flinch_l` / `flinch_r` (new) | 0.26 | no | — | directional variants selected from `DamageInfo.direction` |
| `stagger` | 0.85 | no | — | keep |
| `death` | 1.0 | no | — | keep |
| `death_back` (new) | 1.1 | no | — | selected when the killing blow came from the front |
| `cast_start` / `cast_hold` / `cast_release` (new) | 0.3 / 1.4 / 0.35 | no / yes / no | — | required by the `caster` rig profile |
| `hover` (new) | 1.6 | yes | — | `flyer` idle: `Root` bob plus alternating wing beat |
| `hover_move` (new) | 0.5 | yes | 2.2 | `flyer` locomotion |
| `slither` (new) | 1.1 | yes | 1.6 | `serpent` locomotion, traveling sine across the spine pivots |
| `hop` (new) | 0.7 | no | 0.9 | `blob` locomotion, squash on contact |
| `trot` (new) | 0.7 | yes | 0.91 | quadruped-specific gait replacing the borrowed biped amplitudes |
| `gallop` (new) | 0.48 | yes | 2.3 | quadruped run: front pair together, rear pair together |
| `RESET` | 0.1 | no | — | keep, extended to all rest-pose keys including mounts |

Attack clips to reach:

| Clip | `startup_end` | `active_end` | Archetype / profile |
|------|--------------|-------------|--------------------|
| `attack_light_1` / `_2` / `_3` | 0.34 / 0.32 / 0.40 | 0.58 / 0.56 / 0.62 | keep, `sword` |
| `attack_heavy` | 0.46 | 0.66 | keep |
| `attack_thrust` / `_2` / `_3` | 0.36 / 0.28 / 0.40 | 0.60 / 0.50 / 0.62 | keep, `spear` |
| `attack_shoot` | 0.55 | 0.70 | keep; retarget per ANL-10 |
| `attack_bite` | 0.40 | 0.62 | keep, `hound` |
| `attack_shield_bash` | 0.42 | 0.62 | keep, `shield` |
| `attack_axe_1` / `_2` (new) | 0.42 / 0.38 | 0.60 / 0.56 | `axe`: overhead chop and a return hook, both with a heavier `Root` commitment than `attack_light_*` |
| `attack_staff_1` / `_2` (new) | 0.34 / 0.44 | 0.56 / 0.66 | `staff`: horizontal sweep and a butt-strike |
| `attack_dagger_1` / `_2` / `_3` (new) | 0.22 / 0.20 / 0.26 | 0.38 / 0.36 / 0.46 | `dagger`: tighter arcs, so a dagger is not a fast sword |
| `attack_greatsword_1` / `_2` (new) | 0.52 / 0.48 | 0.74 / 0.70 | `greatsword`: full-body wind, `Root` steps into the swing |
| `attack_claw` (new) | 0.34 | 0.54 | `blob`, `flyer` |
| `attack_cast` (new) | 0.5 | 0.7 | `caster` |
| `attack_boss_slam` / `attack_boss_sweep` (new) | 0.58 / 0.5 | 0.76 / 0.72 | `boss_humanoid`, `construct` |

`WEAPON_ATTACKS` updates to `axe -> [attack_axe_1, attack_axe_2]`, `staff -> [attack_staff_1, attack_staff_2]`, `dagger -> [attack_dagger_1, attack_dagger_2, attack_dagger_3]`, `greatsword -> [attack_greatsword_1, attack_greatsword_2]`. `heavy_clip_for` gains `axe -> attack_axe_1`, `dagger -> attack_dagger_3`, `greatsword -> attack_greatsword_2`. This closes ANL-12 by giving each archetype its own poses rather than a shared pose played at a different rate.

### 4. Keyframe and pose specification

Every clip table entry gains an optional `"ease"` channel per part, parallel to `"pos"` and `"rot"`, holding one `Animation.InterpolationType` plus an optional per-key easing exponent:

```gdscript
"ArmR": {
    "rot": [[0.0, 0.0, 0.0, -0.05], [0.34, -1.5, -0.35, -0.85], [0.5, 0.55, 0.5, 0.5], [1.0, 0.0, 0.0, -0.05]],
    "ease": {"type": Animation.INTERPOLATION_CUBIC, "curve": [2.4, 0.4, 1.0, 1.0]},
},
```

`_add_vector_track` reads it and calls `track_set_interpolation_type` and `track_set_key_transition` per key. Defaults stay `INTERPOLATION_LINEAR` with transition `1.0`, so existing tables are unchanged until each clip is passed over.

Pose rules the new and re-authored clips must follow, so the tables stay reviewable:
- **Anticipation**: every attack holds a pose against the swing direction for at least 40 percent of `startup_end`, with a transition exponent above 2.0 so it accelerates late.
- **Strike**: the frame at `startup_end` is the contact pose, and it must be a single key with no neighboring key within 0.06 normalized time, so the hitbox opening frame is unambiguous.
- **Overshoot**: the key immediately after `active_end` overshoots the rest pose on the primary joint by 15-25 percent of the swing arc, then settles.
- **Weight shift**: any clip with a `Root` position track keys `LegL` and `LegR` in opposition, so the body never translates without a supporting foot moving.
- **Contact keys**: locomotion clips key foot contact times in `contacts` and must have the corresponding leg at its extreme rotation within 0.02 s of each contact time.
- **Torso lean** is keyed from `0.0` at cycle start rather than baked as a constant, closing ANL-07.

### 5. Rig contract as data, checked by the compiler

`_compile` stops silently dropping tracks. Add an optional `"requires"` array per clip listing the parts without which the clip is meaningless:

```gdscript
&"attack_shoot": { "requires": ["ArmL", "ArmR", "Bow"], ... }
&"trot": { "requires": ["LegL", "LegR", "LegBL", "LegBR"], ... }
```

`build_library` skips a clip whose `requires` are not all present and records the skip in a returned diagnostics array; `build_attack` returns `null` with a `push_warning`. This is what makes ANL-10 detectable rather than invisible.

### 6. Export correctness

- `REST_POSES` is deleted from the exporter and replaced by a call into `DioramaCharacterSkin`/`CharacterRigCatalog`, building each rig into a detached `Node3D` and calling `collect_rest_pose`. Closes ANL-05 and, as a side effect, adds the missing `WeaponMount`/`ShieldMount`/`Shield` keys so the authored `RESET` becomes complete (ANL-11).
- The exporter writes a sidecar `content/characters/anim_manifest.json` recording, per profile, the clip names, clip count, total track count, and a hash of the clip tables. `build_library` compares the manifest hash against a hash computed from `CLIPS` at load time and falls back to runtime compilation with a `push_warning` on mismatch. Closes ANL-04.
- A `dummy` entry is added so `dummy_locomotion.res` exists, and `training_grunt.gd:41` is changed to `set_profile("dummy")`. Closes ANL-03.

## Work plan

1. **Fix the dummy profile** — `training_grunt.gd:41` becomes `set_profile("dummy")`. Until step 6 adds `dummy_locomotion.res`, this makes the dummy compile at runtime against its own rest pose, which is already correct. Closes ANL-03.
2. **Bake and validate the events path** — add `EVENTS_PATHS` to the exporter, re-export the six `.res` files, add the resolve warning in `_finish_bind`. Depends on ANC-01. Closes ANL-01.
3. **Add `requires` to every clip and enforce it in `_compile` / `build_attack`** — returns diagnostics, warns on skip. Closes ANL-10's invisibility; retargeting the bow itself follows in step 8.
4. **Add the `ease` channel and `_add_vector_track` support** — no behavior change until clips opt in. Closes ANL-08's mechanism.
5. **Add `stride_m` and `contacts` to `walk`/`run`; rewrite `request_locomotion` to derive `speed_scale` from stride** — add the `jog` clip. Closes ANL-02.
6. **Replace exporter `REST_POSES` with catalog-driven rest poses; add the `dummy` profile; write `anim_manifest.json` and the staleness check** — closes ANL-05, ANL-04, ANL-11.
7. **Re-author `walk`, `run`, `jog` amplitudes to the computed strides, keying torso lean from zero and adding `ease` curves** — closes ANL-07 and the locomotion half of ANL-08.
8. **Add per-archetype attack clips (`axe`, `staff`, `dagger`, `greatsword`) and repoint `WEAPON_ATTACKS` / `heavy_clip_for`; give the player rig a `Bow` pivot so `attack_shoot` keys resolve** — closes ANL-12 and ANL-10. The `Bow` pivot change lands in `diorama_character_skin.gd:407-412` alongside [`diorama-character-skin.md`](diorama-character-skin.md) step 6.
9. **Add directional and stance clips** — `strafe_l`, `strafe_r`, `walk_back`, `turn_l`, `turn_r`, `block_walk`, `land_hard`, `flinch_f/b/l/r`, `death_back`, `idle_alert`. Closes the humanoid half of ANL-06.
10. **Add non-humanoid clip sets** — `trot`, `gallop`, `hover`, `hover_move`, `slither`, `hop`, `cast_*`, `attack_claw`, `attack_cast`, `attack_boss_slam`, `attack_boss_sweep`, plus `EarL`/`EarR`, `WeaponMount`, `ShieldMount`, and `Shield` tracks. Closes ANL-06 and ANL-09.

Steps 1-6 are independently landable and leave the game runnable. Steps 7-10 each add clips without removing any, so a partially landed inventory degrades to the current behavior rather than breaking.

## Data and schema changes

- New file `content/characters/anim_manifest.json`: `{ "<profile>": { "clips": [...], "clip_count": int, "track_count": int, "tables_hash": "<hex>" } }`. New schema `content/schemas/anim_manifest.schema.json`.
- New `.res` file `apps/game/client/assets/animations/diorama/dummy_locomotion.res`, plus re-exported versions of the existing six once step 2 lands.
- `AUTHORED_LIBRARY_PATHS` gains a `dummy` entry (`diorama_anim_library.gd:22-29`).
- `apps/game/client/assets/animations/diorama/README.md` needs its profile list updated from six to seven and a note that the libraries now carry method tracks. That file is outside this topic's edit scope and is listed here as a follow-up.
- No save-format change; no `save_migrator.gd` version bump.

## Acceptance criteria

- [ ] Every animation in every loaded library, for every profile including the six authored ones, contains a `TYPE_METHOD` track when its clip table declares `methods`.
- [ ] Walking the player at 4.5 m/s produces a foot-contact-to-foot-contact ground distance within 15 percent of the distance the body actually travels between those two contacts.
- [ ] `speed_scale` never hits either end of its clamp during normal walk, jog, or run at any speed the player or any enemy can reach.
- [ ] The training dummy's `Torso`, `Head`, `ArmL`, and `ArmR` local positions are unchanged between the rest pose and the first frame of `idle`.
- [ ] Loading a library whose manifest hash does not match the compiled clip tables emits a warning and falls back to runtime compilation, verified by editing one keyframe and re-running.
- [ ] `attack_shoot` compiles with a `Bow` track for both the `ranged` and `player` profiles.
- [ ] `axe`, `staff`, `dagger`, and `greatsword` each play attack clips whose peak `ArmR` rotation differs from `attack_light_1` by more than 0.3 rad on at least one axis.
- [ ] `trot` and `gallop` compile only for rigs that have all four leg pivots, and a biped requesting them is warned rather than silently given a partial clip.
- [ ] Backpedalling plays `walk_back`, strafing plays `strafe_l`/`strafe_r`, and blocking while moving plays `block_walk`.
- [ ] The hound's `EarL`/`EarR` rotate in `trot`, `gallop`, and `attack_bite`.
- [ ] `RESET` for every authored profile keys every pivot the rig has, including `WeaponMount` and `ShieldMount`.
- [ ] No clip has a `Root` position track without opposing `LegL`/`LegR` rotation keys.

## Validation

Extend `apps/game/client/scripts/validation/suites/diorama_anim_suite.gd` (category `graphics`, existing milestone tag `M7.graphics.anim`). Keep the three existing assertions and add:

- `diorama_anim.method_tracks_present` — for each profile in `AUTHORED_LIBRARY_PATHS`, load the library and assert that `walk`, `run`, and `parry_success` each contain at least one track with `Animation.TYPE_METHOD`. Fails today for all six.
- `diorama_anim.manifest_matches_tables` — recompute the clip-table hash and assert it equals `anim_manifest.json`'s `tables_hash` for every profile. Fails whenever the `.res` files are stale.
- `diorama_anim.authored_clip_names` — assert every authored library's `get_animation_list()` equals the full `CLIPS` key set plus `RESET`, per profile.
- `diorama_anim.exporter_rest_pose_parity` — build each profile's rig and assert `collect_rest_pose` matches the rest pose the exporter used, position and rotation, to 1e-4. Replaces the hand-maintained duplicate check.
- `diorama_anim.stride_matches_travel` — for each of `walk`, `jog`, `run`, and each profile, assert `abs(stride_m - reference_speed * length) / stride_m <= 0.15` using the reference speed band the clip is selected for.
- `diorama_anim.contact_keys_align` — for each locomotion clip, assert that at each `contacts` time the corresponding leg track's interpolated rotation is within 10 percent of that track's extreme value.
- `diorama_anim.strike_key_isolated` — for each `ATTACKS` entry, assert the primary arm track has a key exactly at `startup_end` and no other key within 0.06 normalized time.
- `diorama_anim.requires_declared` — for every clip, assert that every part named in a track appears either in `requires` or in the set of parts the base humanoid rig always has. Catches a new clip keying a pivot no rig owns.
- `diorama_anim.no_constant_offset_channel` — for every clip, assert no `rot` or `pos` channel has an identical non-zero value at every key, which is exactly the `walk`/`run` torso-lean defect.
- `diorama_anim.attack_poses_distinct` — for each pair of attack clips assigned to different archetypes, assert their `ArmR` peak rotations differ by more than 0.3 rad on at least one axis.
- `diorama_anim.profile_attack_coverage` — for every archetype in `content/weapons/*.json` and every `rig_profile` in `content/enemies/` and `content/bosses/`, assert `attack_clips_for` returns a non-empty list of clips that all exist in `ATTACKS`.
- `diorama_anim.root_motion_has_support` — for every clip with a `Root` position track, assert `LegL` and `LegR` tracks exist and are in opposition at the extreme `Root` key.

Manual checklist:
- Attacks read as anticipate, strike, settle at the 480x270 internal resolution.
- `trot` and `gallop` read as animal gaits rather than a biped walk on four legs.

## Related
- Current behavior: [`../existing_codebase/diorama-anim-library.md`](../existing_codebase/diorama-anim-library.md)
- Authoring format and animation-data decision: [`character-authoring.md`](character-authoring.md)
- [`diorama-anim-controller.md`](diorama-anim-controller.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`diorama-weapon-kit.md`](diorama-weapon-kit.md)
- [`player-anim-director.md`](player-anim-director.md), [`export-tools.md`](export-tools.md), [`validation-suites.md`](validation-suites.md), [`vfx-service.md`](vfx-service.md), [`00-QUALITY-BAR.md`](00-QUALITY-BAR.md)
