# Export tools

Headless Godot scripts bake authored game assets into committed binary resources. The diorama animation exporter is on the live play path: every rigged character loads its profile's `AnimationLibrary` from `AUTHORED_LIBRARY_PATHS` at bind time. A second exporter converts voxel mesh JSON intermediates into `.mesh` resources for character rigs; it is on the art pipeline path but not loaded during combat.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/tools/export_diorama_anim_libraries.gd` | Diorama animation exporter (`SceneTree`, no autoloads required) |
| `apps/game/client/scripts/tools/export_voxel_meshes.gd` | Voxel mesh JSON â†’ `.mesh` exporter |
| `apps/game/client/scripts/art/characters/diorama_anim_library.gd` | Clip tables, `AUTHORED_LIBRARY_PATHS`, `library_digest`, `compile_authored_library` |
| `apps/game/client/scripts/art/characters/diorama_character_skin.gd` | `rest_pose_for_profile` reference-rig builder |
| `apps/game/client/assets/animations/diorama/*.res` | Six committed `AnimationLibrary` outputs |
| `apps/game/client/assets/animations/diorama/digests.json` | SHA-256 digests of canonical library content for CI drift detection |
| `apps/game/client/assets/animations/diorama/README.md` | Regeneration and verify instructions |
| `apps/game/client/scripts/validation/suites/export_suite.gd` | Automated export contract tests (category `tools`) |
| `apps/game/client/scripts/validation/validation_runner.gd:61` | Registers `export_suite.gd` in `SUITE_PATHS` |
| `.github/workflows/ci.yml:268-276` | CI verify step (replaces unconditional regeneration) |
| `.github/workflows/release.yml:80-82` | Release verify guard before Windows export |
| `.gitattributes` | Marks `*.res` binary; text EOL rules for `.gd`, `.tscn`, `.tres` |
| `apps/game/client/scripts/tools/find_graph_seed.gd` | Procgen seed search utility (not an asset exporter; see [`find-graph-seed.md`](find-graph-seed.md)) |

No texture, atlas, audio, or content-bundle export tooling exists in the repo; searched `apps/game/client/scripts/tools/`, `tools/`, and `scripts/` â€” `ABSENT`.

## How it works

### Diorama animation exporter

Invocation from `apps/game/client`:

```
godot --path . --headless --script res://scripts/tools/export_diorama_anim_libraries.gd
```

Documented at `export_diorama_anim_libraries.gd:3-7` and `apps/game/client/assets/animations/diorama/README.md:10-28`.

`_initialize()` (`export_diorama_anim_libraries.gd:15`) is the entry point:

1. Parses `--verify`, `--digests`, `--profile <key>`, and `--out <dir>` from `OS.get_cmdline_user_args()`, with a fallback scan of `OS.get_cmdline_args()` for Windows headless runs (`:95-108`).
2. Validates that profile keys and output paths match `AUTHORED_LIBRARY_PATHS` (`:127-149`).
3. For each profile, calls `DioramaCharacterSkin.rest_pose_for_profile(profile)` (`diorama_character_skin.gd:456-467`) to build a pivot-only reference rig via `_build_reference_humanoid` / `_build_reference_quadruped` (`:471-519`).
4. Compiles with `DioramaAnimLibrary.compile_authored_library(rest_pose, events_path, profile)` (`diorama_anim_library.gd:1948-1961`), passing `events_path_for_profile(profile)` (`:1920-1921`): `../../AnimDirector` for `player`, `../../AnimController` for the five enemy profiles.
5. Asserts clip count â‰¥ `expected_exported_clip_count(rest_pose)` (`:1940-1945`).
6. In export mode, saves to `res://assets/animations/diorama/<profile>_locomotion.res` via `ResourceSaver.save` and writes `digests.json` (`export_diorama_anim_libraries.gd:63-78`, `:168-181`).
7. In `--verify` mode, compares `library_digest` of the compiled library against the committed `.res` and against `digests.json` without writing (`:56-61`, `:70-71`, `:183-195`).
8. Accumulates failures and calls `quit(1)` on any error; otherwise `quit(0)` (`:73-91`).

### What lands in each animation library

`compile_authored_library` compiles every `CLIPS` entry the rest pose supports, plus synthesized `RESET` and the reserved `__pose__` fingerprint marker (`diorama_anim_library.gd:1948-1961`, `POSE_MARKER` at `:33`).

| Bucket | Count | Exported |
|--------|-------|----------|
| `CLIPS` (`diorama_anim_library.gd:38-1057`) | 38 locomotion/reaction clips (humanoid profiles compile all; `hound` skips arm-only tracks) | Yes |
| `RESET` (`_compile_reset`, `:2226-2241`) | 1; one position and one rotation key per rest-pose pivot | Yes |
| `__pose__` (`_compile_pose_marker`, `:2184-2200`) | 1; encodes the rest pose for `_can_use_authored_library` | Yes |
| `ATTACKS` (`diorama_anim_library.gd:1103-1883`) | 10 weapon-timed clips | No â€” compiled per instance via `build_attack` |

Attack clips are excluded by design: `build_attack` (`:2042-2075`) stretches normalized attack timelines onto per-weapon startup/active/recovery through `_remap_time` (`:2189-2203`). Results are cached in `_attack_cache` keyed on clip name, pose hash, events path, and phase durations (`:36`, `:2050-2075`, `:2078-2093`); `clear_attack_cache()` is called from `DioramaAnimController._teardown` (`diorama_anim_controller.gd:557`).

Method tracks are written when `events_path != ""` (`diorama_anim_library.gd:2118-2124`). Exported libraries bake footstep and parry markers:

| Clip | Method keys | Source |
|------|-------------|--------|
| `walk` | `anim_footstep` at 0.18 and 0.58 | `diorama_anim_library.gd:98` |
| `run` | `anim_footstep` at 0.1 and 0.38 | `:139` |
| `parry_success` | `anim_swing_vfx` at 0.05 | `:623` |

### Rest poses

`rest_pose_for_profile` builds pivot-only reference rigs from `PROFILES` (`diorama_character_skin.gd:52-113`) without meshes or autoload dependencies. Humanoid profiles include `WeaponMount`, `ShieldMount`, and profile `extras` (`Bow` on `ranged`, `Shield` on `shield`) at `:471-503`. Runtime rigs use the same pivot names via `collect_rest_pose` (`:531-538`).

`_can_use_authored_library` (`diorama_anim_library.gd:1970-1981`) requires a `Root` key, a committed file, a `__pose__` marker, and a pose hash match via `_pose_hash` / `_pose_hash_from_marker` (`:2168-2213`). A mismatch falls back to runtime compilation.

### Voxel mesh exporter

```
godot --path apps/game/client --headless --script res://scripts/tools/export_voxel_meshes.gd
```

`_initialize()` (`export_voxel_meshes.gd:10`) walks `res://assets/characters/_intermediate/` (and `equipment/`), converts each `.mesh.json` to a committed `.mesh` under `res://assets/characters/`, prints the count, and exits 0. It has no `--verify` mode, no digest file, and no validation suite (`export_voxel_meshes.gd:10-15`).

### CI and release

`.github/workflows/ci.yml:268-276` runs `--verify` instead of regenerating libraries. On failure, a follow-up step regenerates and prints `git diff --stat` for `assets/animations/diorama/`.

`.github/workflows/release.yml:80-82` runs the same verify guard before `godot --export-release`.

### Validation

`export_suite.gd` (category `tools`, 13 tests) loads committed `.res` files, checks clip coverage, method tracks, `RESET` pivot coverage, `digests.json` parity, pose-marker acceptance/rejection, and `rest_pose_for_profile` pivot sets. Registered at `validation_runner.gd:61` with `MIN_ASSERTIONS["tools"] = 12` (`:76`).

`diorama_anim_suite.gd` asserts required clips are present in loaded `player_locomotion.res` (`:49-82`), method tracks on authored libraries (`:114-138`), and footstep marker exposure on a bound player rig (`:225-252`).

## Contracts

- **Output paths**: exporter filenames must match `AUTHORED_LIBRARY_PATHS` (`diorama_anim_library.gd:24-31`); enforced in `_validate_profile_paths` (`export_diorama_anim_libraries.gd:127-149`).
- **Events path**: method tracks target `../../AnimDirector` (player) or `../../AnimController` (enemies), resolved relative to `AnimationPlayer.root_node` (`diorama_anim_library.gd:1920-1921`).
- **Pose fingerprint**: `__pose__` must match `rest_pose_for_profile(profile)` or the authored library is rejected (`diorama_anim_library.gd:1970-1981`).
- **Digest parity**: `digests.json` profiles map must match `library_digest` of committed `.res` files (`export_diorama_anim_libraries.gd:183-195`, `export_suite.gd:186-206`).
- **Exit code**: `quit(1)` on save failure, path mismatch, clip-count regression, or verify drift (`export_diorama_anim_libraries.gd:73-91`).
- **Node-name contract**: clip track paths key pivots by name (`Root`, `Torso`, `Head`, `ArmL`, `ArmR`, `LegL`, `LegR`, `WeaponMount`, `ShieldMount`, `Bow`, `Shield`, quadruped pivots) per `diorama_character_skin.gd:8-14`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Diorama locomotion export for six profiles | IMPLEMENTED | `export_diorama_anim_libraries.gd:42-78`, `diorama_anim_library.gd:1948-1961` |
| Committed `.res` outputs loaded at runtime | IMPLEMENTED | `diorama_anim_library.gd:1989-1995`, `diorama_anim_controller.gd:93-97` |
| Exporter exit code on failure | IMPLEMENTED | `export_diorama_anim_libraries.gd:73-91` |
| Method tracks in authored libraries | IMPLEMENTED | `events_path_for_profile`, `_compile` at `diorama_anim_library.gd:2118-2124` |
| `rest_pose_for_profile` (no duplicated `REST_POSES`) | IMPLEMENTED | `diorama_character_skin.gd:456-519` |
| `WeaponMount`, `ShieldMount`, `Shield` in exported `RESET` | IMPLEMENTED | `_build_reference_humanoid` at `diorama_character_skin.gd:491-503` |
| `__pose__` fingerprint on authored libraries | IMPLEMENTED | `diorama_anim_library.gd:33`, `:1958-1960`, `:1970-1981` |
| `digests.json` committed drift detection | IMPLEMENTED | `apps/game/client/assets/animations/diorama/digests.json`, `DIGESTS_PATH` at `diorama_anim_library.gd:34` |
| CI verify (no blind regeneration) | IMPLEMENTED | `.github/workflows/ci.yml:268-276` |
| Release verify guard | IMPLEMENTED | `.github/workflows/release.yml:80-82` |
| `--verify`, `--profile`, `--out`, `--digests` CLI | IMPLEMENTED | `export_diorama_anim_libraries.gd:95-124` |
| `export_suite.gd` | IMPLEMENTED | `apps/game/client/scripts/validation/suites/export_suite.gd`, `validation_runner.gd:61` |
| Attack-clip static cache | IMPLEMENTED | `diorama_anim_library.gd:36`, `:2050-2093` |
| `.gitattributes` for `.res` | IMPLEMENTED | `.gitattributes:1` |
| Voxel mesh export | IMPLEMENTED | `export_voxel_meshes.gd:10-73` (no verify suite) |
| Texture/atlas/audio/content-bundle export | ABSENT | searched `apps/game/client/scripts/tools/`, `tools/`, `scripts/` |

## Related

- Improvement plan: [`../actual_improvements/export-tools.md`](../actual_improvements/export-tools.md) - **FINISHED**
- [`diorama-anim-library.md`](diorama-anim-library.md) â€” clip tables, `library_digest`, attack cache
- [`diorama-anim-controller.md`](diorama-anim-controller.md) â€” runtime consumer and `_supplement_authored_library`
- [`diorama-character-skin.md`](diorama-character-skin.md) â€” `rest_pose_for_profile`, `PROFILES`
- [`ci-cd.md`](ci-cd.md) â€” verify workflow steps
- [`validation-suites.md`](validation-suites.md) â€” `export_suite.gd`
- [`find-graph-seed.md`](find-graph-seed.md) â€” the other script under `scripts/tools/`
- [`player-anim-director.md`](player-anim-director.md) â€” method-track consumer for the player rig
