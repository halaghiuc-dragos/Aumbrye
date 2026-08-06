# Export tools — improvement plan

## Status: FINISHED

## Current state

Two headless exporters live under `apps/game/client/scripts/tools/`: `export_diorama_anim_libraries.gd` bakes locomotion `AnimationLibrary` resources for six diorama profiles, and `export_voxel_meshes.gd` converts voxel mesh JSON into committed `.mesh` files. The animation exporter derives rest poses from `DioramaCharacterSkin.rest_pose_for_profile`, writes method tracks via `events_path_for_profile`, bakes `RESET` and `__pose__`, commits `digests.json`, exits non-zero on failure, supports `--verify`/`--profile`/`--out`/`--digests`, and is guarded in CI and release. `export_suite.gd` validates committed outputs. See [`../existing_codebase/export-tools.md`](../existing_codebase/export-tools.md).

## Gaps

| ID | Sev | Gap | Evidence | Status |
|----|-----|-----|----------|--------|
| EXP-01 | P0 | Exporter exits 0 after a failed save | was `export_diorama_anim_libraries.gd:84-90` | FINISHED — `export_diorama_anim_libraries.gd:73-91` |
| EXP-02 | P0 | Authored libraries dropped method tracks; footstep VFX unreachable | was `export_diorama_anim_libraries.gd:81` | FINISHED — `events_path_for_profile` at `diorama_anim_library.gd:1920-1921`, exporter `:48` |
| EXP-03 | P0 | CI regenerated and discarded libraries with no drift check | was `ci.yml:117-118` | FINISHED — `ci.yml:268-276`, `digests.json`, `--verify` |
| EXP-04 | P1 | `REST_POSES` duplicated rig arithmetic | was `export_diorama_anim_libraries.gd:10-71` | FINISHED — deleted; `rest_pose_for_profile` at `diorama_character_skin.gd:456-519` |
| EXP-05 | P1 | Exported `RESET` omitted mount pivots | was missing `WeaponMount`/`ShieldMount`/`Shield` | FINISHED — `_build_reference_humanoid` at `diorama_character_skin.gd:491-503` |
| EXP-06 | P1 | Stale committed libraries relative to sources | git history drift | FINISHED — verify mode + `digests.json` |
| EXP-07 | P1 | `_can_use_authored_library` accepted any pose with `Root` | was `diorama_anim_library.gd:453-459` | FINISHED — `__pose__` hash at `diorama_anim_library.gd:1970-1981` |
| EXP-08 | P1 | No test loaded an exported `.res` | was `diorama_anim_suite.gd:16-30` | FINISHED — `export_suite.gd` `export.resources.load` |
| EXP-09 | P1 | `required_clips` asserted source dictionaries not output | was `diorama_anim_suite.gd:33-50` | FINISHED — `diorama_anim_suite.gd:49-82` |
| EXP-10 | P1 | Output filenames never checked against `AUTHORED_LIBRARY_PATHS` | was string interpolation only | FINISHED — `_validate_profile_paths` at `export_diorama_anim_libraries.gd:127-149` |
| EXP-11 | P2 | `controller_markers` was a source grep | was `diorama_anim_suite.gd:53-65` | FINISHED — `diorama_anim.footstep_emits_vfx` at `diorama_anim_suite.gd:225-252` |
| EXP-12 | P2 | Exporter took no CLI arguments | was `export_diorama_anim_libraries.gd:74-90` | FINISHED — `--verify`, `--profile`, `--out`, `--digests` at `:95-124` |
| EXP-13 | P2 | `diorama_character_rig_player.gd` passed empty `events_path` | was `:34` | FINISHED — `events_path_for_profile("player")` at `diorama_character_rig_player.gd:34-36` |
| EXP-14 | P2 | No `.gitattributes` for binary `.res` | absent at repo root | FINISHED — `.gitattributes:1` |
| EXP-15 | P2 | Attack clips recompiled per instance | was `diorama_anim_controller.gd:295` | FINISHED — `_attack_cache` at `diorama_anim_library.gd:36`, `:2050-2093` |
| EXP-16 | P2 | No export tooling beyond diorama anim | was only `find_graph_seed.gd` besides anim exporter | PARTIAL — `export_voxel_meshes.gd` added for meshes; texture/atlas/bundle export remains `ABSENT` |

## Target design

Delivered as implemented (see existing codebase doc). Chosen approach for method tracks: bake `../../AnimDirector` / `../../AnimController` paths at export time (aligned with [`player-anim-director.md`](player-anim-director.md) PAD-01) rather than an `AnimEvents` forwarding node. Drift detection uses `library_digest` SHA-256 of canonical track content, not raw `ResourceSaver` bytes.

## Work plan

1. **Exit codes and path parity** — `export_diorama_anim_libraries.gd:73-149`. (EXP-01, EXP-10) — done
2. **CLI arguments** — `:95-124`. (EXP-12) — done
3. **`rest_pose_for_profile`** — `diorama_character_skin.gd:456-519`; delete `REST_POSES`. (EXP-04, EXP-05, EXP-06) — done
4. **`library_digest` + `digests.json`** — `diorama_anim_library.gd:1924-1937`, committed `digests.json`. (EXP-03) — done
5. **`--verify` mode** — `export_diorama_anim_libraries.gd:56-71`, `:183-195`. (EXP-03) — done
6. **CI and release guards** — `ci.yml:268-276`, `release.yml:80-82`. (EXP-03, EXP-06) — done
7. **Method tracks at export** — `events_path_for_profile`, regenerate six `.res`. (EXP-02, EXP-13) — done
8. **`__pose__` fingerprint** — `POSE_MARKER`, `_can_use_authored_library` tightening. (EXP-07) — done
9. **`export_suite.gd`** — registered `validation_runner.gd:61`. (EXP-08, EXP-09, EXP-11) — done
10. **`.gitattributes`** — repo root. (EXP-14) — done
11. **Attack cache** — `_attack_cache` in `DioramaAnimLibrary`. (EXP-15) — done
12. **Voxel mesh exporter** — `export_voxel_meshes.gd` documents mesh pipeline; broader bundle export out of scope. (EXP-16) — partial

## Data and schema changes

No `content/schemas/` change. No save-format change — **no `save_migrator.gd` version bump**.

New committed file: `apps/game/client/assets/animations/diorama/digests.json` (generator, godot version, per-profile SHA-256 digests).

New committed file: `.gitattributes` at repo root.

Regenerated: all six `*_locomotion.res` under `apps/game/client/assets/animations/diorama/`.

Reserved animation name `__pose__` in each library; not playable — used only for pose fingerprinting.

Deleted: `REST_POSES` constant from `export_diorama_anim_libraries.gd`.

Updated: `apps/game/client/assets/animations/diorama/README.md` with CLI flags and digest file description.

## Acceptance criteria

- [x] `ResourceSaver.save` failure causes exporter exit 1 (`export_diorama_anim_libraries.gd:73-91`)
- [x] `AUTHORED_LIBRARY_PATHS` / exporter path mismatch causes exit 1 (`:127-149`)
- [x] `REST_POSES` removed; poses from `rest_pose_for_profile` (`diorama_character_skin.gd:456-519`)
- [x] Proportion change without regeneration fails CI verify (`ci.yml:268-276`, `digests.json`)
- [x] Exported `RESET` covers `WeaponMount`, `ShieldMount`, and `Shield` on applicable profiles (`diorama_character_skin.gd:491-503`)
- [x] `digests.json` matches fresh export (`export_diorama_anim_libraries.gd:183-195`)
- [x] CI verifies rather than regenerates (`ci.yml:268-276`)
- [x] Release fails before export when libraries are stale (`release.yml:80-82`)
- [x] Authored `walk`/`run` carry `anim_footstep` method tracks (`export_suite.gd` `export.method_tracks.footstep_present`)
- [x] Pose mismatch rejects authored library (`export_suite.gd` `export.pose_marker.rejects_mismatch`)
- [x] `__pose__` present in every library (`export_suite.gd` `export.pose_marker.present`)
- [x] `--profile player` exports one file (`export_diorama_anim_libraries.gd:115-118`)
- [x] `--verify` writes no `.res` (`export_diorama_anim_libraries.gd:56-61`)
- [x] Attack cache keyed on clip + pose + timings (`diorama_anim_library.gd:2078-2093`)
- [x] `.gitattributes` marks `*.res` binary (`.gitattributes:1`)

Manual check (once per rig proportion change): walk and sprint each profile in the debug arena; confirm limbs return to rest after `RESET` and footstep dust appears.

## Validation

`apps/game/client/scripts/validation/suites/export_suite.gd`, category `tools`, registered in `validation_runner.gd:61`, `MIN_ASSERTIONS["tools"] = 12` (`validation_runner.gd:76`):

| Test id | Asserts |
|---------|---------|
| `export.paths.match_authored_constant` | Exporter profile set equals `AUTHORED_LIBRARY_PATHS` keys |
| `export.resources.load` | All six `.res` load as `AnimationLibrary` |
| `export.resources.clip_coverage` | Clip counts and required player clips present |
| `export.resources.no_attack_clips` | No `ATTACKS` name in authored libraries |
| `export.resources.reset_covers_every_pivot` | `RESET` has position and rotation tracks per pivot |
| `export.method_tracks.footstep_present` | `walk` and `run` each have two `anim_footstep` keys |
| `export.method_tracks.parry_swing_present` | `parry_success` has `anim_swing_vfx` on humanoid profiles |
| `export.digest.matches_committed` | Loaded libraries match `digests.json` |
| `export.digest.deterministic` | Two in-process compiles yield the same digest |
| `export.pose_marker.present` | Every library has `__pose__` |
| `export.pose_marker.rejects_mismatch` | Perturbed pose fails `can_use_authored_library` |
| `export.pose_marker.accepts_match` | `rest_pose_for_profile("player")` accepts player library |
| `export.rest_pose.derives_from_rig` | Player pose includes mount pivots, no mesh names |

Extended `diorama_anim_suite.gd`: `diorama_anim.required_clips` checks loaded `player_locomotion.res`; `diorama_anim.footstep_emits_vfx` binds a player rig and checks markers.

Run exporter verify:

```powershell
powershell -File scripts/godot-bin.ps1 --headless --path apps/game/client --script res://scripts/tools/export_diorama_anim_libraries.gd --verify
```

## Related

- Existing behavior: [`../existing_codebase/export-tools.md`](../existing_codebase/export-tools.md)
- [`diorama-anim-library.md`](diorama-anim-library.md) — clip tables, `library_digest`, attack cache
- [`diorama-anim-controller.md`](diorama-anim-controller.md) — runtime consumer, `_supplement_authored_library`
- [`diorama-character-skin.md`](diorama-character-skin.md) — `rest_pose_for_profile`
- [`ci-cd.md`](ci-cd.md) — verify steps
- [`validation-suites.md`](validation-suites.md) — `export_suite.gd` registration
- [`player-anim-director.md`](player-anim-director.md) — method-track consumer
- [`vfx-service.md`](vfx-service.md) — `play_footstep`
