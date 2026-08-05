# Export tools — improvement plan

## Current state

One exporter bakes 17 locomotion clips plus `RESET` into six `AnimationLibrary` resources that every rigged character loads at runtime (see [`../existing_codebase/export-tools.md`](../existing_codebase/export-tools.md)). It cannot fail: `ResourceSaver.save` errors are pushed to the log and the script exits 0 anyway. It drops every method track, which is why footstep dust has silently stopped appearing for all six profiles. CI regenerates the libraries and throws the result away without comparing it to the committed files, and the release job does not regenerate them at all, so the artifacts that get validated and the artifacts that get shipped are never proven to be the same bytes.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| EXP-01 | P0 | Exporter exits 0 after a failed save, so the CI step cannot fail | `apps/game/client/scripts/tools/export_diorama_anim_libraries.gd:84-90` |
| EXP-02 | P0 | Authored libraries carry no method tracks; `anim_footstep` never fires and `VfxService.play_footstep` is unreachable | `export_diorama_anim_libraries.gd:81`, `apps/game/client/scripts/art/characters/diorama_anim_library.gd:550`, `apps/game/client/scripts/player/player_anim_director.gd:279-285` |
| EXP-03 | P0 | CI regenerates the libraries and discards them; nothing compares the output to the committed `.res`, and release ships the committed files unregenerated | `.github/workflows/ci.yml:117-118`, `.github/workflows/release.yml:40-58` |
| EXP-04 | P1 | `REST_POSES` is a hand-copied duplicate of the rig arithmetic with no test binding the two | `export_diorama_anim_libraries.gd:10-71` versus `apps/game/client/scripts/art/characters/diorama_character_skin.gd:32-86,365-419` |
| EXP-05 | P1 | Exported rest poses omit `WeaponMount`, `ShieldMount`, and `Shield`, so the authored `RESET` cannot restore them | `export_diorama_anim_libraries.gd:11-19` versus `diorama_character_skin.gd:404-417,462-474` |
| EXP-06 | P1 | Three of six committed libraries were last generated one commit before their sources changed | `player_locomotion.res`, `melee_locomotion.res`, `hound_locomotion.res` at `d51ac12`; `diorama_anim_library.gd` and `diorama_character_skin.gd` at `42575c2` |
| EXP-07 | P1 | `_can_use_authored_library` accepts any pose containing `Root` and never checks it against the pose baked into the resource | `diorama_anim_library.gd:453-459` |
| EXP-08 | P1 | No test loads an exported `.res`; the only assertion is `ResourceLoader.exists` | `apps/game/client/scripts/validation/suites/diorama_anim_suite.gd:16-30` |
| EXP-09 | P1 | `diorama_anim.required_clips` asserts the source dictionaries, not the exported output | `diorama_anim_suite.gd:33-50` |
| EXP-10 | P1 | Output filenames are built by string interpolation and never checked against `AUTHORED_LIBRARY_PATHS` | `export_diorama_anim_libraries.gd:82` versus `diorama_anim_library.gd:22-29` |
| EXP-11 | P2 | `diorama_anim.controller_markers` is a substring grep of the controller source | `diorama_anim_suite.gd:53-65` |
| EXP-12 | P2 | Exporter takes no arguments: no single-profile export, no output directory, no verify-only mode | `export_diorama_anim_libraries.gd:74-90` |
| EXP-13 | P2 | `diorama_character_rig_player.gd` also passes an empty `events_path`, so its compile fallback loses method tracks too | `apps/game/client/scripts/art/characters/diorama_character_rig_player.gd:34` |
| EXP-14 | P2 | 220 KB of binary `.res` committed with no `.gitattributes` entry, rewritten wholesale on every regeneration | `apps/game/client/assets/animations/diorama/`, no `.gitattributes` at repo root |
| EXP-15 | P2 | Attack clips are recompiled per character instance at bind and on every weapon change | `apps/game/client/scripts/art/characters/diorama_anim_controller.gd:295` |
| EXP-16 | P2 | No export tooling exists for textures, atlases, meshes, or content bundles | `apps/game/client/scripts/tools/` contains only this exporter and `find_graph_seed.gd` |

## Target design

### 1. An exporter that can fail

`_initialize` tracks failures and exits with a real status:

```gdscript
func _initialize() -> void:
    var args := _parse_args()
    var failures: PackedStringArray = []
    var written: Array[Dictionary] = []
    ...
    for profile_key in profiles:
        var err := ResourceSaver.save(library, out_path)
        if err != OK:
            failures.append("%s: %s" % [out_path, error_string(err)])
            continue
        written.append({"profile": profile_key, "path": out_path, "clips": library.get_animation_list().size()})
    if not failures.is_empty():
        for f in failures:
            printerr("export failed: %s" % f)
        quit(1)
        return
    quit(0)
```

`quit(1)` on any failure is the whole point of EXP-01. Additional hard failures, each also exiting 1:

- A profile key in `REST_POSES` with no matching entry in `AUTHORED_LIBRARY_PATHS`, or the reverse (EXP-10).
- A library that compiled fewer than a per-profile minimum clip count, so a `_compile` regression that silently returns `null` for everything cannot pass.
- A rest pose that does not match the pose derived from the live rig (EXP-04, below).

### 2. Derive rest poses from the rig, do not copy them

Delete the 62-line `REST_POSES` constant. Add to `DioramaCharacterSkin`:

```gdscript
## Builds a throwaway rig for `profile` and returns its rest pose.
## Same code path as the runtime rig, so the exporter and the game cannot diverge.
static func rest_pose_for_profile(profile: String) -> Dictionary:
    var holder := Node3D.new()
    var visual := _make_visual(holder)
    if profile == "hound":
        _build_quadruped(visual, _null_materials())
    else:
        _build_humanoid(visual, profile, _null_materials())
    var pose := collect_rest_pose(visual)
    holder.free()
    return pose
```

`_null_materials()` returns the `body`/`accent`/`theme` dictionary shape with `StandardMaterial3D.new()` placeholders, so the builder runs headless without touching `PixelStyle` shaders or `CharacterService`.

This closes EXP-04 by construction and closes EXP-05 for free, because `collect_rest_pose` already walks `WeaponMount`, `ShieldMount`, and `Shield`. The exported `RESET` then covers every pivot the runtime rig has.

The rejected alternative is keeping the hardcoded table and adding a test that compares it against `rest_pose_for_profile`. That catches drift but leaves two sources of truth and a table that must be edited by hand on every proportion change; deriving is strictly better and removes more code than it adds.

Note that `build_player_body` applies `root.scale` from `CharacterAppearance` (`diorama_character_skin.gd:96-99`). Scale is not part of the rest pose and clips do not key it, so appearance sliders do not affect the exported data.

### 3. Bake method tracks

The exporter currently passes `events_path = ""`, which discards footstep and parry markers. The controller's events path is a relative `NodePath` from the visual root to the controller node, computed at `diorama_anim_controller.gd:111-121`. It is not a constant, so it cannot be baked directly.

Make it one. The controller is always a sibling arrangement determined by `_resolve_events_path`; introduce a fixed contract instead:

```gdscript
# diorama_anim_library.gd
## Method tracks in authored libraries target this path, resolved relative to
## AnimationPlayer.root_node. DioramaAnimController reparents itself to match.
const EVENTS_NODE_PATH := "AnimEvents"
```

`DioramaAnimController._finish_bind` adds a lightweight `Node` named `AnimEvents` as a child of the visual root, forwarding `anim_footstep`, `anim_swing_vfx`, `anim_hitbox_on`, and `anim_hitbox_off` to the controller. The exporter passes `EVENTS_NODE_PATH`; the runtime compile path passes the same constant instead of the computed string, which also fixes EXP-13 and the viewmodel case in one move.

The forwarding node is four methods and costs one `Node` per character. The rejected alternative — stripping method tracks from authored libraries and re-adding them at load time — means walking every `Animation` on every bind, which is more work per character than the compile path the authored library was meant to avoid.

Acceptance for this piece is behavioral: `VfxService.play_footstep` fires twice per `walk` cycle for a bound player rig.

### 4. Verify mode and CI drift detection

Add `--verify` to the exporter. In verify mode it compiles every library, then compares against the committed resource without writing, and exits 1 on any difference.

Comparison must not depend on `ResourceSaver` byte determinism. Instead compile a canonical digest and compare that:

```gdscript
static func library_digest(library: AnimationLibrary) -> String:
    var lines: PackedStringArray = []
    var names := library.get_animation_list()
    names.sort()
    for anim_name in names:
        var anim: Animation = library.get_animation(anim_name)
        lines.append("%s len=%.4f loop=%d" % [anim_name, anim.length, anim.loop_mode])
        for t in anim.get_track_count():
            lines.append("  %s type=%d" % [anim.track_get_path(t), anim.track_get_type(t)])
            for k in anim.track_get_key_count(t):
                lines.append("    %.4f %s" % [anim.track_get_key_time(t, k), anim.track_get_key_value(t, k)])
    return "\n".join(lines).sha256_text()
```

Fixed four-decimal formatting keeps the digest stable across float printing differences. The exporter writes the six digests to `apps/game/client/assets/animations/diorama/digests.json`, which is committed as text and reviewable in a diff, unlike the `.res` files themselves.

New CI step in the `godot` job of `.github/workflows/ci.yml`, replacing the current unconditional regeneration at `:117-118`:

```yaml
      - name: Verify diorama animation libraries are current
        run: godot --path . --headless --script res://scripts/tools/export_diorama_anim_libraries.gd -- --verify
      - name: Show drift on failure
        if: failure()
        working-directory: .
        run: |
          godot --path apps/game/client --headless --script res://scripts/tools/export_diorama_anim_libraries.gd
          git --no-pager diff --stat -- apps/game/client/assets/animations/diorama/
          echo "Run the exporter and commit the result." >> "$GITHUB_STEP_SUMMARY"
```

Verify rather than regenerate: a job that regenerates makes its own inputs valid and can never detect a stale commit. That is the direct fix for EXP-03 and it makes EXP-06 impossible to reintroduce.

`.github/workflows/release.yml` needs no exporter step once verification is enforced on every push, because the committed files are then provably current. Add one guard anyway, before the export at `release.yml:50-54`:

```yaml
      - name: Verify animation libraries are current
        working-directory: apps/game/client
        run: godot --headless --path . --script res://scripts/tools/export_diorama_anim_libraries.gd -- --verify
```

A release is worth the extra 20 seconds.

### 5. Rest-pose fingerprint on the resource

`_can_use_authored_library` currently accepts any pose containing `Root` (EXP-07). Bake a fingerprint and check it.

The exporter stores a `RESET`-derived pose hash in the library under the reserved animation name `__pose__`, using a zero-length `Animation` whose track paths and single key values encode the rest pose. `_can_use_authored_library` recomputes the hash from the live pose and compares:

```gdscript
static func _can_use_authored_library(rest_pose: Dictionary, profile: String) -> bool:
    if not rest_pose.has("Root"):
        return false
    var authored_path: String = AUTHORED_LIBRARY_PATHS.get(profile, "")
    if authored_path == "" or not ResourceLoader.exists(authored_path):
        return false
    var loaded := ResourceLoader.load(authored_path) as AnimationLibrary
    if loaded == null or not loaded.has_animation(POSE_MARKER):
        return false
    return _pose_hash(rest_pose) == _pose_hash_from_marker(loaded.get_animation(POSE_MARKER))
```

A mismatch falls back to compiling, which is correct and slower rather than fast and wrong. The controller must skip `__pose__` when listing playable clips.

An out-of-band `.json` sidecar was rejected: it can be deleted or edited independently of the resource, which is exactly the failure being prevented.

### 6. Command-line arguments

```
--verify                 compile and compare, write nothing, exit 1 on drift
--profile <key>          export a single profile, repeatable
--out <res:// dir>       output directory, default res://assets/animations/diorama/
--digests                write digests.json only
```

Parsed from `OS.get_cmdline_user_args()`, which is what follows `--` on the Godot command line. An unknown argument exits 1 with usage on stderr.

### 7. Attack-clip cache

`build_attack` is called per character instance and again on every weapon change (`diorama_anim_controller.gd:295`). The output depends only on the clip name, the rest pose, the events path, and the three phase durations. Add a static `Dictionary` cache in `DioramaAnimLibrary` keyed on a hash of those inputs, holding the compiled `Animation` by reference.

`Animation` resources are shared safely across `AnimationPlayer` instances as long as nobody mutates them; nothing does. Clear the cache on scene change through an existing lifecycle hook so a long session does not accumulate one entry per rest-pose variant.

This is a P2 and should land last; it is an allocation optimization, not a correctness fix.

### 8. Repository hygiene

Add `.gitattributes` at the repo root:

```
*.res binary
*.tres text eol=lf
*.tscn text eol=lf
*.gd   text eol=lf
```

Explicit is better than relying on git's NUL heuristic, and it documents the intent for the `digests.json` reviewer.

## Work plan

1. **Exit codes** — rewrite `_initialize` in `export_diorama_anim_libraries.gd` to accumulate failures and call `quit(1)`. Add the path-parity check against `AUTHORED_LIBRARY_PATHS` and the minimum-clip-count check. (EXP-01, EXP-10)
2. **Argument parsing** — add `--verify`, `--profile`, `--out`, `--digests` via `OS.get_cmdline_user_args()`. (EXP-12)
3. **Derive rest poses** — add `DioramaCharacterSkin.rest_pose_for_profile` and `_null_materials`, delete `REST_POSES` from the exporter, regenerate all six libraries. `RESET` now covers `WeaponMount`, `ShieldMount`, and `Shield`. (EXP-04, EXP-05, EXP-06)
4. **Digests** — add `DioramaAnimLibrary.library_digest`, write `assets/animations/diorama/digests.json`, commit it. (EXP-03)
5. **Verify mode** — implement the compare-and-exit path. (EXP-03)
6. **CI** — replace the regenerate step in `ci.yml` with the verify step plus the failure-diff step; add the verify guard to `release.yml`. (EXP-03, EXP-06)
7. **`AnimEvents` node** — add `DioramaAnimLibrary.EVENTS_NODE_PATH`, the forwarding node in `DioramaAnimController._finish_bind`, and pass the constant from the exporter, the controller, and `diorama_character_rig_player.gd:34`. Regenerate. (EXP-02, EXP-13)
8. **Pose fingerprint** — bake `__pose__`, tighten `_can_use_authored_library`, filter the marker out of clip listings. Regenerate. (EXP-07)
9. **`export_suite.gd`** — the assertions below. (EXP-08, EXP-09, EXP-11)
10. **`.gitattributes`.** (EXP-14)
11. **Attack cache** — static cache in `DioramaAnimLibrary` keyed on clip, pose hash, events path, and phase durations. (EXP-15)
12. **Scope note** — no further export tooling is planned; if an atlas or content-bundle exporter is added later it belongs under `apps/game/client/scripts/tools/` with the same verify-mode contract. (EXP-16)

Steps 1 through 6 are independently landable and leave the game runnable; the libraries do not change content until step 3, and step 3's regeneration is a pure addition of `RESET` tracks. Steps 7 and 8 each change the resource contents and must regenerate and re-digest in the same commit as the code change, or CI verification fails.

## Data and schema changes

No `content/schemas/` change. No save-format change, so **no `save_migrator.gd` version bump**.

New committed file: `apps/game/client/assets/animations/diorama/digests.json`, an object mapping profile key to the SHA-256 of the canonical library digest, plus a `generator` field naming the exporter and a `godot` field recording `Engine.get_version_info()["string"]`. Reviewable as text; it is the human-readable proxy for the six binary blobs.

New committed file: `.gitattributes` at the repo root.

Regenerated on steps 3, 7, and 8: all six `.res` files under `apps/game/client/assets/animations/diorama/`.

New reserved animation name `__pose__` inside each library, which `DioramaAnimController` must exclude wherever it enumerates clips.

Deleted: the `REST_POSES` constant, `export_diorama_anim_libraries.gd:10-71`.

`apps/game/client/assets/animations/diorama/README.md` needs the new arguments and the digests file described. It is owned by this topic.

## Acceptance criteria

- [ ] Making `ResourceSaver.save` fail for one profile causes the exporter to exit 1 and the CI step to fail.
- [ ] Renaming a key in `AUTHORED_LIBRARY_PATHS` without renaming the exporter output causes exit 1.
- [ ] `REST_POSES` no longer exists; the exporter obtains poses from `DioramaCharacterSkin.rest_pose_for_profile`.
- [ ] Changing `PROFILES["player"]["torso"].y` and not regenerating causes the CI verify step to fail with a named profile.
- [ ] Every exported `RESET` contains tracks for `WeaponMount` and `ShieldMount`, and the `shield` library also for `Shield`.
- [ ] `digests.json` is committed and its six digests match a fresh export on a clean checkout.
- [ ] The `godot` CI job verifies rather than regenerates; the working tree is unchanged after a successful run.
- [ ] `release.yml` fails before exporting if the committed libraries are not current.
- [ ] A bound player rig walking on the floor emits `footstep_frame` twice per `walk` cycle and `VfxService.play_footstep` is called.
- [ ] Binding a rig whose rest pose differs from the baked one compiles instead of loading the authored resource.
- [ ] `__pose__` never appears in the controller's playable clip list.
- [ ] `--profile player` writes exactly one file.
- [ ] `--verify` writes no file, verified by an unchanged directory mtime set.
- [ ] Binding 50 characters with the same weapon compiles each attack clip once.
- [ ] `.gitattributes` marks `*.res` binary.

## Validation

New suite `apps/game/client/scripts/validation/suites/export_suite.gd`, category `tools`, registered in `SUITE_PATHS`:

| Test id | Asserts |
|---------|---------|
| `export.paths.match_authored_constant` | The set of profiles the exporter writes equals the key set of `AUTHORED_LIBRARY_PATHS` |
| `export.resources.load` | All six `.res` load as `AnimationLibrary` |
| `export.resources.clip_coverage` | Each library contains all 17 `CLIPS` names its rest pose supports, plus `RESET`; `hound` is asserted against its reduced expected set explicitly, not by exception |
| `export.resources.no_attack_clips` | No `ATTACKS` name appears in any exported library |
| `export.resources.reset_covers_every_pivot` | Every key of `rest_pose_for_profile(profile)` has a position and a rotation track in that library's `RESET` |
| `export.resources.track_paths_resolve` | Every track path in every clip names a pivot present in that profile's rest pose |
| `export.resources.first_key_matches_rest` | For each clip, the value of the first key of each position track equals the rest position plus the authored offset |
| `export.method_tracks.footstep_present` | `walk` and `run` each contain a method track with two `anim_footstep` keys |
| `export.method_tracks.parry_swing_present` | `parry_success` contains one `anim_swing_vfx` key |
| `export.digest.matches_committed` | `library_digest` of each loaded resource equals its entry in `digests.json` |
| `export.digest.deterministic` | Compiling the same profile twice in-process yields the same digest |
| `export.pose_marker.present` | Every library has `__pose__` |
| `export.pose_marker.rejects_mismatch` | `_can_use_authored_library` returns `false` for a rest pose with a perturbed `Torso` position |
| `export.pose_marker.accepts_match` | It returns `true` for the pose from `rest_pose_for_profile` |
| `export.rest_pose.derives_from_rig` | `rest_pose_for_profile("player")` contains `Root`, `Torso`, `Head`, `ArmL`, `ArmR`, `LegL`, `LegR`, `WeaponMount`, `ShieldMount` and no `MeshInstance3D` names |

Extend `apps/game/client/scripts/validation/suites/diorama_anim_suite.gd`:

- `diorama_anim.required_clips` moves from asserting the source dictionaries to asserting the nine required names are present in the loaded `player_locomotion.res`, which is what EXP-09 is about.
- `diorama_anim.controller_markers` is replaced by `diorama_anim.controller_hitbox_toggles`: bind a controller to a rig, call `anim_hitbox_on`, and assert the weapon controller's hitbox became enabled. That converts the grep at `diorama_anim_suite.gd:53-65` into behavior (EXP-11).
- Add `diorama_anim.footstep_emits_vfx`: bind a player rig, play `walk` to 0.2 s, and assert `footstep_frame` was emitted.

Manual check, once per art change to the rigs, because a visual regression is not machine-checkable: load the debug arena, walk and sprint each of the six profiles, and confirm the limbs return to rest after `RESET` and that dust puffs appear under the feet.

## Related

- Existing behavior: [`../existing_codebase/export-tools.md`](../existing_codebase/export-tools.md)
- [`diorama-anim-library.md`](diorama-anim-library.md) — clip tables, `library_digest`, `EVENTS_NODE_PATH`, the attack cache
- [`diorama-anim-controller.md`](diorama-anim-controller.md) — the `AnimEvents` forwarding node and `__pose__` filtering
- [`diorama-character-skin.md`](diorama-character-skin.md) — `rest_pose_for_profile`
- [`ci-cd.md`](ci-cd.md) — the verify step, the failure summary, and the untracked `export_presets.cfg` that blocks `release.yml`
- [`validation-suites.md`](validation-suites.md) — `export_suite.gd` registration
- [`vfx-service.md`](vfx-service.md) — `play_footstep`, dead until EXP-02 is fixed
