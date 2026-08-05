# Export tools

One export tool exists: a headless Godot script that bakes the diorama locomotion clip tables into six `AnimationLibrary` resources. Its output is committed to the repository and loaded at runtime by every rigged character, so it is on the live play path. CI regenerates the libraries on every push but never compares the result against the committed files.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/tools/export_diorama_anim_libraries.gd` | The exporter. `SceneTree` script, 91 lines, no autoloads required |
| `apps/game/client/scripts/art/characters/diorama_anim_library.gd` | Source of the clip data and of `AUTHORED_LIBRARY_PATHS` |
| `apps/game/client/scripts/art/characters/diorama_character_skin.gd` | Builds the runtime rigs whose rest poses the exporter hardcodes |
| `apps/game/client/assets/animations/diorama/*.res` | Six committed outputs, 30-38 KB each, binary `RSRC` format |
| `apps/game/client/assets/animations/diorama/README.md` | Regeneration instructions |
| `.github/workflows/ci.yml:117-118` | The CI step that runs the exporter |
| `apps/game/client/scripts/validation/suites/diorama_anim_suite.gd` | The only automated coverage, three assertions |

`apps/game/client/scripts/tools/` contains exactly two scripts: this exporter and `find_graph_seed.gd`, which is a procgen search utility documented in [`find-graph-seed.md`](find-graph-seed.md), not an export tool. No texture, atlas, mesh, audio, or content-bundle export tooling exists anywhere in the repo; searched `apps/game/client/scripts/tools/`, `tools/`, and `scripts/` — `ABSENT`.

## How it works

### Invocation

```
godot --path . --headless --script res://scripts/tools/export_diorama_anim_libraries.gd
```

from `apps/game/client`, as documented at `apps/game/client/scripts/tools/export_diorama_anim_libraries.gd:4` and `apps/game/client/assets/animations/diorama/README.md:11`.

### Control flow

`_initialize()` (`export_diorama_anim_libraries.gd:74`) is the entry point:

1. Globalizes `res://assets/animations/diorama` and creates it recursively if missing (`:75-77`).
2. Iterates the six keys of the `REST_POSES` constant (`:79`): `player`, `melee`, `hound`, `shield`, `brute`, `ranged`.
3. Calls `AnimLibrary.build_library(rest_pose, "", profile_key, true)` (`:81`). The fourth argument is `force_compile`, which makes `build_library` skip the authored-library shortcut at `diorama_anim_library.gd:468` and recompile from the clip tables. Without it the exporter would reload and re-save its own previous output.
4. Saves to `res://assets/animations/diorama/<profile>_locomotion.res` via `ResourceSaver.save` (`:82-83`).
5. On a non-`OK` return, calls `push_error` (`:85`); otherwise prints the path and clip count (`:87`).
6. Prints `Diorama anim export complete.` and calls `quit()` with no argument (`:89-90`), which exits with status 0 regardless of how many saves failed.

### What lands in each library

`build_library` (`diorama_anim_library.gd:462-482`) compiles every entry of `CLIPS` plus a synthesized `RESET`:

| Bucket | Count | Exported |
|--------|-------|----------|
| `CLIPS` (`diorama_anim_library.gd:32-264`) | 17: `idle`, `walk`, `run`, `air`, `land`, `dash_f`, `dash_b`, `dash_l`, `dash_r`, `block_start`, `block_hold`, `block_hit`, `parry_success`, `guard_break`, `flinch`, `stagger`, `death` | Yes |
| `RESET` (`_compile_reset`, `:599-614`) | 1, one position and one rotation key per rest-pose pivot | Yes |
| `ATTACKS` (`diorama_anim_library.gd:266-407`) | 10: `attack_light_1..3`, `attack_heavy`, `attack_thrust`, `attack_thrust_2`, `attack_thrust_3`, `attack_shoot`, `attack_bite`, `attack_shield_bash` | No |

Attacks are excluded by design: `build_attack` (`:486-512`) stretches a normalized attack timeline onto the real startup, active, and recovery times of the equipped weapon through `_remap_time` (`:577-589`), so the clip cannot be baked ahead of time. `diorama_anim_controller.gd:295` compiles them per character instance.

`_compile` (`:515-556`) skips any track whose part name is absent from the rest pose (`:530-531`) and returns `null` when no track was written (`:546-547`). The `hound` rest pose has no `ArmL`/`ArmR`, so arm-only clips are dropped from `hound_locomotion.res`; its file is 30791 bytes against 37738 for the four humanoid profiles that share a topology.

Track values are absolute, not additive: `_add_vector_track` (`:559-573`) writes `rest_value + offset` at every key (`:573`). A library is therefore only valid for the exact rest pose it was compiled against.

### Method tracks are dropped

`_compile` writes the method track only when `events_path != ""` (`:550`). The exporter passes `""` (`export_diorama_anim_libraries.gd:81`), so every `methods` entry in `CLIPS` is discarded:

| Clip | Method keys | Source |
|------|-------------|--------|
| `walk` | `anim_footstep` at 0.18 and 0.58 | `diorama_anim_library.gd:68` |
| `run` | `anim_footstep` at 0.1 and 0.38 | `diorama_anim_library.gd:89` |
| `parry_success` | `anim_swing_vfx` at 0.05 | `diorama_anim_library.gd:206` |

### Rest poses

The exporter's `REST_POSES` constant (`:10-71`) hardcodes the pivot layout for each profile. The runtime equivalent is `DioramaCharacterSkin.collect_rest_pose` (`diorama_character_skin.gd:222-227`), which walks the built rig and records every non-`MeshInstance3D` `Node3D` child (`:462-474`).

The hardcoded numbers are a manual derivation of the arithmetic in `_build_humanoid` (`diorama_character_skin.gd:365-419`) applied to the `PROFILES` table (`:32-86`):

- `LegL`/`LegR` at `(±hip_x, leg.y, 0)` (`:381`)
- `Torso` at `(0, leg.y, 0)` (`:384`)
- `Head` at `(0, torso.y, 0)` (`:387`)
- `ArmL`/`ArmR` at `(±shoulder_x, torso.y * 0.88, 0)` (`:399-402`)

Checked against `PROFILES` for all six profiles, the hardcoded values currently match. Example: `player` has `leg.y = 0.46` and `torso.y = 0.62` (`:34-35`), giving a shoulder height of `0.62 * 0.88 = 0.5456`, which is what `export_diorama_anim_libraries.gd:17` records. The `hound` values match `_build_quadruped` (`:422-451`) the same way.

The exporter's tables are nonetheless incomplete relative to `collect_rest_pose`. Every humanoid rig also contains `WeaponMount` and `ShieldMount` pivots (`diorama_character_skin.gd:404-405`), the `shield` profile adds a `Shield` pivot (`:413-417`), and none of the three appear in `REST_POSES`. The runtime pose for `player` has nine entries where the exporter's table has seven. Since no clip keys those names, only `RESET` differs: the authored `RESET` cannot restore a mount that a future clip moves.

### Runtime consumption

`DioramaAnimController._finish_bind` (`diorama_anim_controller.gd:81-104`) collects the live rest pose (`:85`), resolves the method-track target path (`:88`), and calls `build_library(_rest_pose, _events_path, _profile)` (`:89`). `build_library` prefers the authored resource when `_can_use_authored_library` returns true (`diorama_anim_library.gd:468`).

`_can_use_authored_library` (`:453-459`) requires only that the rest pose contains a `Root` key and that the file for the profile exists. It does not compare the pose against the one baked into the resource. The `Root` check exists to route the first-person viewmodel to the compile path, because that rig names its root `ViewRoot` (`diorama_viewmodel.gd:16`).

When the authored resource is used, the `_events_path` computed at `:88` is discarded along with it. `anim_footstep` (`diorama_anim_controller.gd:360-361`) therefore never fires for any of the six rigged profiles, and `PlayerAnimDirector._on_footstep_frame` (`player_anim_director.gd:279-285`), which calls `VfxService.play_footstep`, is unreachable during locomotion. `anim_swing_vfx` still fires during attacks, because attack clips are compiled at runtime with a real `events_path` (`diorama_anim_controller.gd:295`); the consumer at `castle_enemy_base.gd:135` works.

`diorama_character_rig_player.gd:34` calls `build_library(rest_pose, "", "player")` with an empty `events_path` as well, so even its compile fallback produces method-free clips.

### CI

`.github/workflows/ci.yml:117-118` runs the exporter in the `godot` job, immediately before the validation run at `:119-120`. The regenerated `.res` files stay in the runner's working tree, are not uploaded as artifacts, and are not compared against the committed versions. The job then validates against files that no reviewer will ever see.

`.github/workflows/release.yml:40-58` does not run the exporter. `godot --export-release "Windows Desktop"` at `:54` packages whatever is committed under `assets/animations/diorama/`. Two different sets of animation data can therefore be validated and shipped. That job also cannot currently succeed on a clean checkout for an unrelated reason: `export_presets.cfg` is excluded by `.gitignore:135`, covered in [`ci-cd.md`](ci-cd.md).

Committed output is stale relative to its inputs. `player_locomotion.res`, `melee_locomotion.res`, and `hound_locomotion.res` were last written in commit `d51ac12`; `diorama_anim_library.gd` and `diorama_character_skin.gd` were both modified again in `42575c2`, the current `HEAD`, which added `shield_locomotion.res`, `brute_locomotion.res`, and `ranged_locomotion.res` without regenerating the other three. The `HEAD` edits happened to touch only `ATTACKS` and `AUTHORED_LIBRARY_PATHS`, not `CLIPS`, so the three stale files are still correct by luck. No check in the repository establishes that.

## Contracts

- **Output paths**: the six filenames the exporter writes must match `AUTHORED_LIBRARY_PATHS` (`diorama_anim_library.gd:22-29`) exactly. The exporter builds them by string interpolation (`export_diorama_anim_libraries.gd:82`); nothing verifies the two agree.
- **Rest-pose parity**: `REST_POSES` (`export_diorama_anim_libraries.gd:10-71`) must stay consistent with `PROFILES` (`diorama_character_skin.gd:32-86`) and with the placement arithmetic in `_build_humanoid` and `_build_quadruped`. Enforced by nothing.
- **Node-name contract**: clip track paths key pivots by name (`Root`, `Torso`, `Head`, `ArmL`, `ArmR`, `LegL`, `LegR`, `Tail`, `LegBL`, `LegBR`, `Bow`), stated at `diorama_character_skin.gd:8-14`.
- **Library name**: the controller registers the resource under `LIBRARY_NAME` (`diorama_anim_controller.gd:95`); clip lookups are unprefixed inside the library.
- **Exit code**: always 0 (`export_diorama_anim_libraries.gd:90`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Locomotion clip export for six profiles | IMPLEMENTED | `export_diorama_anim_libraries.gd:79-87` |
| Committed `.res` outputs loaded at runtime | IMPLEMENTED | `diorama_anim_library.gd:468-472`, `diorama_anim_controller.gd:89` |
| Exporter exit code on save failure | BROKEN | `export_diorama_anim_libraries.gd:84-90` — `push_error` then `quit()` with status 0 |
| Footstep and parry method tracks in authored libraries | BROKEN | `export_diorama_anim_libraries.gd:81` passes `events_path = ""`; `diorama_anim_library.gd:550` |
| `VfxService.play_footstep` on the play path | BROKEN | `player_anim_director.gd:279-285` unreachable while an authored library is bound |
| CI regeneration | PARTIAL | `ci.yml:117-118` regenerates and discards; no diff against committed files |
| Release-time regeneration | ABSENT | `release.yml:40-58` has no exporter step |
| Committed outputs current with sources | PARTIAL | Three of six last regenerated one commit before their sources changed |
| `REST_POSES` parity with the real rig | PARTIAL | Values match today; duplication at `export_diorama_anim_libraries.gd:10-71` versus `diorama_character_skin.gd:32-86` has no guard |
| `WeaponMount`, `ShieldMount`, `Shield` in exported `RESET` | ABSENT | Absent from `REST_POSES`; present in the runtime pose per `diorama_character_skin.gd:404-417,462-474` |
| Rest-pose validation when loading an authored library | ABSENT | `diorama_anim_library.gd:453-459` checks only for a `Root` key and file existence |
| Attack-clip export | ABSENT by design | `build_attack` needs per-weapon timing, `diorama_anim_library.gd:486-512` |
| Test that loads an exported `.res` | ABSENT | `diorama_anim_suite.gd:16-30` checks `ResourceLoader.exists` only |
| Test of clip content in the exported resource | ABSENT | `diorama_anim_suite.gd:33-50` asserts the source dictionaries, not the output |
| `diorama_anim.controller_markers` assertion | FAKE | `diorama_anim_suite.gd:53-65` greps the controller source for two substrings |
| Exporter command-line arguments | ABSENT | `export_diorama_anim_libraries.gd:74-90` takes none |
| Any other export tool | ABSENT | `apps/game/client/scripts/tools/` holds only this script and `find_graph_seed.gd` |

## Related

- Improvement plan: [`../actual_improvements/export-tools.md`](../actual_improvements/export-tools.md)
- [`diorama-anim-library.md`](diorama-anim-library.md) — the clip tables this tool bakes
- [`diorama-anim-controller.md`](diorama-anim-controller.md) — the runtime consumer
- [`diorama-character-skin.md`](diorama-character-skin.md) — the rigs whose rest poses are duplicated here
- [`ci-cd.md`](ci-cd.md) — the workflow step and the untracked `export_presets.cfg`
- [`validation-suites.md`](validation-suites.md) — `diorama_anim_suite`
- [`find-graph-seed.md`](find-graph-seed.md) — the other script under `scripts/tools/`
