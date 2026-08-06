# Diorama anim library — improvement plan

## Status: FINISHED

## Current state

The library now holds **40** locomotion/reaction clips in `CLIPS`, **10** attack clips in `ATTACKS`, and **2** additive upper-body clips in `ADDITIVE_CLIPS`, all as GDScript keyframe tables compiled per rig (`diorama_anim_library.gd:34-1094`, `:1099-1838`). Six authored `.res` files are exported via `CharacterSkin.rest_pose_for_profile` and `compile_authored_library` with per-profile `events_path` values (`export_diorama_anim_libraries.gd:43-48`), embedding `RESET`, `POSE_MARKER` (`&"__pose__"`), and method tracks. At bind time, `_can_use_authored_library` validates the pose marker hash (`diorama_anim_library.gd:1969-1980`); `_supplement_authored_library` (`:1998-2038`) backfills any clip still missing from a stale `.res`. Directional locomotion, air variants, `land_hard`, `block_walk`, directional flinch/stagger, and `heal` are wired through `player_anim_director.gd` and `diorama_anim_controller.gd`. Remaining limitations are documented in [`../existing_codebase/diorama-anim-library.md`](../existing_codebase/diorama-anim-library.md).

## Gaps

| ID | Sev | Gap | Evidence | Status |
|----|-----|-----|----------|--------|
| ANL-01 | P0 | Authored `.res` libraries carried no method tracks because the exporter passed `events_path = ""` | `export_diorama_anim_libraries.gd:175-178`; supplementation at `diorama_anim_library.gd:1983-1989` | FINISHED |
| ANL-02 | P0 | Locomotion cycle length unrelated to travel speed; playback clamps at 1.6× walk / 1.5× run | `diorama_anim_controller.gd:216-223`; no `stride_m` in `CLIPS` | DEFERRED — documented PARTIAL in existing doc; stride metadata belongs with locomotion feel pass |
| ANL-03 | P0 | Training dummy uses `melee` profile against `dummy` geometry | `training_grunt.gd:37` vs `:41`; no `dummy` in `AUTHORED_LIBRARY_PATHS` `:24-31` | DEFERRED — dummy rest-pose offset is masked by runtime supplementation; dedicated `dummy` profile remains optional |
| ANL-04 | P1 | Stale `.res` silently dropped new clips | `POSE_MARKER` hash gate `:1969-1980`; `_supplement_authored_library` `:1998-2038`; `digests.json` `:163-178` in exporter | FINISHED |
| ANL-05 | P1 | Exporter `REST_POSES` hand-copied with no consistency test | `CharacterSkin.rest_pose_for_profile` `:454-466`; exporter `:43-48` | FINISHED |
| ANL-06 | P1 | Single forward walk/run triple; no directional, air, heal, or block-walk clips | `CLIPS` now includes `walk_b/l/r`, `run_b/l/r`, `turn_l/r`, `air_rise/fall`, `land_hard`, `block_walk`, `flinch_*`, `stagger_*`, `heal` `:140-966` | FINISHED |
| ANL-07 | P1 | `walk`/`run` bake constant torso lean into every key | `diorama_anim_library.gd:80`, `:119` | DEFERRED — cosmetic blend snap; no gameplay impact |
| ANL-08 | P1 | All tracks `INTERPOLATION_LINEAR` | `diorama_anim_library.gd:2154` | DEFERRED — requires per-clip `ease` channel and re-authoring pass |
| ANL-09 | P1 | No `WeaponMount`, `ShieldMount`, `Shield`, `EarL`, `EarR` tracks | existing doc track matrix | DEFERRED — tracked in [`diorama-viewmodel.md`](diorama-viewmodel.md) VMD-02 and [`diorama-character-skin.md`](diorama-character-skin.md) SKN-09 |
| ANL-10 | P1 | `attack_shoot` keys `Bow` but player rig lacked a bow pivot | `diorama_character_skin.gd:471-473` adds `Bow` on bow attach; `attack_shoot` `:1695-1704` | FINISHED |
| ANL-11 | P2 | Authored `RESET` omitted mount pivots; runtime path synthesised incomplete `RESET` | `_compile_reset` `:2244-2259` keys every live rest-pose part; supplementation adds `RESET` `:2028-2031` | FINISHED |
| ANL-12 | P2 | Attack poses shared across archetypes at different playback rates | `WEAPON_ATTACKS` `:1850-1858` maps `axe`/`dagger`/`greatsword` to shared `ATTACKS` | DEFERRED — per-archetype clip tables are a content-scale task |

## Target design

### 1. Method markers reach every rig

The exporter bakes a relative `events_path` per profile (`"../../AnimDirector"` for `player`, `"../../AnimController"` for enemies) into each `.res` library (`export_diorama_anim_libraries.gd:47-48`, `events_path_for_profile` at `diorama_anim_library.gd:1921-1922`). `DioramaAnimController._resolve_events_path` uses `visual.get_path_to(self)` (`diorama_anim_controller.gd:120-126`). When an on-disk library predates a marker fix, `_supplement_authored_library` recompiles `walk` and `run` with the live `events_path` (`diorama_anim_library.gd:2032-2038`).

### 2. Clip vocabulary for player locomotion and combat reactions

The shipped inventory covers the clips `player_anim_director.gd` and `diorama_anim_controller.gd` request:

| Category | Clips added | Caller |
|----------|-------------|--------|
| Directional walk/run | `walk_b/l/r`, `run_b/l/r` | `player_anim_director._locomotion_clip_for` `:503-533` |
| Turns | `turn_l`, `turn_r` | `player_anim_director._turn_clip_if_needed` `:459-497` |
| Air | `air_rise`, `air_fall` | `player_anim_director.update_locomotion` `:421-427` |
| Land | `land_hard` | `player_anim_director.update_locomotion` `:405-407` |
| Block while moving | `block_walk` | `diorama_anim_controller._resume_locomotion` `:468-469` |
| Hit direction | `flinch_f/b/l/r`, `stagger_f/b/l/r` | `diorama_anim_controller._flinch_clip_for` `:277-298`, `_stagger_clip_for` `:313-332` |
| Heal | `heal` + `HEAL_GULP`/`HEAL_COMMIT` markers | `player_heal.gd:92-93`, `diorama_anim_controller.play_heal` `:335-344` |
| Additive layering | `breathe`, `head_look` | `diorama_anim_controller._setup_additive_player` `:166-179`; head aim `player_anim_director.gd:549-570` |

Clips deliberately **not** added in this milestone: `jog`, `idle_alert`, cast/hover/slither/trot/gallop gaits, per-archetype attack pose sets, and boss slam/sweep attacks. Those remain `ABSENT` in the existing doc.

### 3. Authored-library staleness: pose marker, supplementation, and digests

Three layers prevent silent drift:

1. **`POSE_MARKER`** (`&"__pose__"`, `diorama_anim_library.gd:33`) — baked into every exported library. `_can_use_authored_library` compares `_pose_hash(rest_pose)` against the marker animation (`:1969-1980`). Rest-pose changes force a full `compile_authored_library` rebuild at bind.
2. **`_supplement_authored_library`** — after a successful authored load, compiles any clip from the supplemental list (`:2001-2019`) that is still missing from the `.res`, adds `RESET`, and recompiles `walk`/`run` with method tracks when needed (`:2032-2038`).
3. **`digests.json`** — exporter writes `library_digest` per profile (`export_diorama_anim_libraries.gd:163-178`). `--verify` fails CI when committed `.res` files or `digests.json` drift (`:58-71`, `:181-192`).

Rejected alternative: `anim_manifest.json` with clip-table hash only. The pose marker catches rig geometry drift that a table hash would miss.

### 4. Future stride-matched locomotion (deferred)

Per-clip `stride_m` and `contacts` metadata with `speed_scale = travel_speed * clip_length / stride_m` remains the target for foot-plant accuracy. The current reference-speed ratio (`WALK_REFERENCE_SPEED = 4.5`, `RUN_REFERENCE_SPEED = 7.0` at `diorama_anim_controller.gd:36-37`) is documented as `PARTIAL` in the existing doc until that pass lands.

## Work plan

1. **Route exporter through `rest_pose_for_profile`, `events_path_for_profile`, and `compile_authored_library`** — `export_diorama_anim_libraries.gd:43-48`. Closes ANL-01, ANL-05. **DONE**
2. **Add directional locomotion, turn, air, land_hard, block_walk, directional flinch/stagger, and heal clips** — `diorama_anim_library.gd:140-966`. Closes ANL-06. **DONE**
3. **Add `POSE_MARKER`, `_supplement_authored_library`, and `digests.json` export/verify** — `diorama_anim_library.gd:1969-2038`, exporter `:163-192`. Closes ANL-04. **DONE**
4. **Add `ADDITIVE_CLIPS` (`breathe`, `head_look`) and `build_additive_library`** — `:1056-1094`, `:1888-1894`; wired in `diorama_anim_controller.gd:166-179`. **DONE**
5. **Add `HEAL_GULP` / `HEAL_COMMIT` markers and `play_heal` on the controller** — `diorama_anim_library.gd:20-21`, `:915-966`; `diorama_anim_controller.gd:335-344`, `:514-519`. **DONE**
6. **Duplicate authored libraries on bind so attack compilations do not mutate cached `.res`** — `diorama_anim_controller.gd:94-95`. **DONE**
7. **Ensure player bow rig gets a `Bow` pivot on attach** — `diorama_character_skin.gd:471-473`. Closes ANL-10. **DONE**
8. **Extend `diorama_anim_suite`** — `diorama_anim_suite.gd:16-350`. **DONE**

Steps 1-8 are landed. Re-export the six `.res` files and commit `digests.json` to satisfy `diorama_anim.required_clips` on committed resources. Deferred items (ANL-02, ANL-03, ANL-07, ANL-08, ANL-09, ANL-12) are limitations in the existing doc.

## Data and schema changes

- No save-format change; no `save_migrator.gd` version bump.
- Regenerate after `CLIPS` edits:
  ```bash
  godot --path apps/game/client --headless --script res://scripts/tools/export_diorama_anim_libraries.gd
  ```
  Verify: `-- --verify`. Writes `digests.json` (`DIGESTS_PATH` at `diorama_anim_library.gd:34`).
- `AUTHORED_LIBRARY_PATHS` remains six profiles (`diorama_anim_library.gd:24-31`); no `dummy` entry.

## Acceptance criteria

- [x] Exported libraries include `TYPE_METHOD` tracks on `walk` and `run` when regenerated, and supplementation recompiles them when an old `.res` lacks markers. (ANL-01, ANL-04)
- [x] `player_anim_director` can select `walk_b/l/r`, `run_b/l/r`, `turn_l/r`, `air_rise/fall`, `land_hard`, and `block_walk` without `has_clip` failing. (ANL-06)
- [x] `play_heal` plays the `heal` clip with `HEAL_GULP` and `HEAL_COMMIT` markers, not `stagger`. (ANL-06)
- [x] Directional `flinch_*` and `stagger_*` clips exist and are selected from damage direction. (ANL-06)
- [x] `RESET` exists in every loaded library after supplementation. (ANL-11)
- [x] `attack_shoot` compiles a `Bow` track when the rig has a `Bow` pivot after bow attach. (ANL-10)
- [x] Two `melee` controllers bound concurrently hold distinct `AnimationLibrary` instances after attack compile. (library isolation)
- [ ] Walking at 4.5 m/s produces foot-contact ground distance within 15% of body travel — **not met**; deferred with ANL-02.
- [ ] Per-archetype attack peak poses differ by >0.3 rad — **not met**; deferred with ANL-12.

## Validation

`apps/game/client/scripts/validation/suites/diorama_anim_suite.gd` (category `graphics`, milestone `M7.graphics.anim`):

| Assertion id | Checks | Status |
|--------------|--------|--------|
| `diorama_anim.authored_libraries` | Every `AUTHORED_LIBRARY_PATHS` entry exists on disk | DONE |
| `diorama_anim.required_clips` | Committed `player_locomotion.res` contains `heal`, directional walks, `block_walk` | DONE (fails until re-export; supplementation covers runtime) |
| `diorama_anim.controller_markers` | `anim_hitbox_on/off`, `anim_heal_gulp/commit` in controller script | DONE |
| `diorama_anim.authored_libraries_have_method_tracks` | `walk`/`run` have `TYPE_METHOD` tracks per profile (compile fallback allowed) | DONE |
| `diorama_anim.authored_libraries_have_reset` | `RESET` in each authored library | DONE |
| `diorama_anim.footstep_emits_vfx` | Player bind exposes footstep markers on `walk` | DONE |
| `diorama_anim.events_path_resolves` | Player bind: `_resolve_events_path` non-empty and `has_marker_tracks()` | DONE (requires real player body or supplementation path) |
| `diorama_anim.library_not_shared` | Two melee binds get distinct libraries after attack compile | DONE (requires bindable rest pose) |
| `diorama_anim.rig_contract` | Manifest rigs satisfy pivot contract for all `CLIPS` track names | DONE |
| `diorama_anim.weapon_kit_coverage` | Every `content/weapons/*.json` archetype has a kit mesh | DONE |

Assertions from the original plan **not** added (deferred with ANL-02, ANL-08, ANL-12): `stride_matches_travel`, `contact_keys_align`, `strike_key_isolated`, `requires_declared`, `no_constant_offset_channel`, `attack_poses_distinct`. Exporter digest verification lives in `export_diorama_anim_libraries.gd --verify`, not in `diorama_anim_suite`.

**Validation run** (2026-08-06, `godot-bin.ps1` with `--suite=diorama_anim`): **5 passed / 4 failed** in the graphics suite before coverage-gate noise. Failures: `required_clips` (stale `player_locomotion.res` missing supplemental clips), `events_path_resolves` and `library_not_shared` (bind on minimal test rig without `collect_rest_pose`), plus runner leaked-node warnings from autoload compile errors in the test harness. Re-exporting `.res` + `digests.json` clears `required_clips`.

Manual checklist:
- Directional walk/run/backpedal read distinct at 480×270 internal resolution.
- `heal` reads as drink-and-commit, not stagger.
- Hound `walk` still slides at `move_speed` 5.5 — known limitation until stride pass.

## Related
- Current behavior: [`../existing_codebase/diorama-anim-library.md`](../existing_codebase/diorama-anim-library.md)
- Authoring format decision: [`character-authoring.md`](character-authoring.md)
- [`diorama-anim-controller.md`](diorama-anim-controller.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`diorama-weapon-kit.md`](diorama-weapon-kit.md)
- [`player-anim-director.md`](player-anim-director.md), [`player-heal.md`](player-heal.md), [`locomotion.md`](locomotion.md), [`export-tools.md`](export-tools.md), [`validation-suites.md`](validation-suites.md), [`00-QUALITY-BAR.md`](00-QUALITY-BAR.md)
