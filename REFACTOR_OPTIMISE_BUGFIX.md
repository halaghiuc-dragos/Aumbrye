# Aumbrye — Refactor / Optimise / Bugfix Backlog

**Generated:** 2026-08-06
**Revised:** 2026-08-06 (r3) — section 5A now carries the complete per-file sweep
(`BUG-13`…`BUG-53`, `PERF-16`…`PERF-24`, `REF-09`…`REF-15`); section 13 holds 43 `IMP-` improvement items
measured against the design target; section 14 is new and holds 22 `EXT-` content-extension plans for the
item, NPC, quest, story, class and customization bases. Sections 1, 2 and 15 were updated to match, and
`IMP-A05` carries an inline correction. Nothing from earlier revisions was removed.
**Target engine:** Godot **4.7.1** (repo currently pins 4.7.0)
**Basis:** Static analysis of the working tree at commit `3e22117`. **The `docs/` tree was treated as
obsolete and was not used as a source of truth** — every item below is derived from the code, scenes,
content JSON, project settings, CI workflows and project files as they exist on disk. Where `docs/`
appears, it appears only as a *subject* of remediation.

---

## 0. How to read this document

Every item follows the same four-field shape:

- **Problem** — what is wrong, stated as an observable fact about the code.
- **Action** — what to do about it (the verb, the scope).
- **Location** — file path(s) and line numbers where known.
- **Solution Hint** — concrete implementation direction, not a full patch.

Items carry an ID (`BUG-nn`, `PERF-nn`, `REF-nn`, `DEAD-nn`, `QA-nn`, `DEP-nn`, `BE-nn`, `WEB-nn`,
`DOC-nn`, `FEAT-nn`, `IMP-xnn`, `EXT-xnn`) so they can be cross-referenced in issues and commits.

There are **five solution categories** in this document, and every one of them uses the same four-field shape:

| Category | Sections | Question it answers | Items |
|---|---|---|---|
| **Bugfixing** | 3, 5, 5A | What is broken and how do I fix it? | 53 |
| **Optimisation** | 4, 5A (`PERF-16`+) | What is slow and how do I make it fast? | 25 |
| **Refactoring** | 6, 7, 5A (`REF-09`+) | What is badly shaped or unnecessary and how do I reshape or delete it? | 20 |
| **Improvement** | 13 (`IMP-xnn`) | What already works but does not yet make this the game it is meant to be? | 43 |
| **Extension** | 14 (`EXT-xnn`) | What content and systems must be *built* to reach high replayability? | 22 |

Sections 13 and 14 are written against an explicit design target: **a roguelite + Soulslike action RPG with
snappy combat, hand-feeling pixel-diorama presentation, a 10-tier replayable dungeon ladder, an endless mode
that rotates biomes every 10–20 floors and accepts floor-skip consumables, a Dark Souls × Diablo item and
inventory system, and enough NPCs, story, quests, buffs, traps and mechanics to be addictive and replayable
at Soulslike-but-fair difficulty.** Section 13 states the gap between what the code does today and what that
target requires; section 14 states what to build to close it, with scale targets per content base.

Severity legend:

| Tag | Meaning |
|---|---|
| 🔴 **P0** | Ships broken / data loss / makes the build unshippable. Fix before anything else. |
| 🟠 **P1** | Major performance or correctness defect that players will feel every session. |
| 🟡 **P2** | Real defect or cost, but survivable; schedule into normal sprints. |
| 🔵 **P3** | Hygiene, maintainability, future-proofing. |

Confidence legend:

| Tag | Meaning |
|---|---|
| **Verified** | Read directly in the source; the claim is a restatement of what the file does. |
| **Inferred** | Follows from engine semantics applied to verified code, but was not executed/profiled. |

---

## 1. Codebase inventory (measured, not documented)

| Metric | Value |
|---|---|
| GDScript files (total, incl. addons) | 406 |
| GDScript files (game code, excl. addons + validation) | 304 |
| GDScript LOC — game code | ~57,100 |
| GDScript LOC — validation suites | ~27,700 |
| GDScript LOC — vendored `addons/godot_mcp` | ~23,400 |
| Godot scenes (`.tscn`) | 227 |
| Content JSON files (`content/`) | 323 |
| Voxel source files (`art-source/*.vox`) | 262 |
| Exported meshes (`assets/characters/*.mesh`) | 262 (**222 orphaned**) |
| Runtime voxel JSON (`*.voxels.json`) | 115 |
| C# source files (backend + packages + tools) | 106 |
| Autoload singletons | **27** |
| Markdown files in `docs/` | 241 |
| Files tracked by git | 2,910 |

Two numbers stand out and drive several items below: **27 autoloads** (REF-01) and **~23,400 lines of
validation code whose assertions are largely `grep`-on-source** (QA-01).

Content census (measured from `content/`, and the basis for most of section 13):

| Content | Count | Note |
|---|---|---|
| Items | 90 | 21 weapon, 36 armour, 7 accessory, 9 consumable, 17 material |
| — by rarity | 40 common, 14 magic, 21 rare, 8 epic, 3 legendary, 4 aumbral | |
| — by grid footprint | **64 are 2×2**, 15 are 1×1, 5 are 1×2, 4 are 2×3, 1 is 2×4, 1 is 1×4 | grid is 6×4 = 24 cells (`IMP-F01`) |
| Affixes | **14** (7 prefix + 7 suffix) | across 6 rarity tiers (`IMP-F02`) |
| Enemies | 29 | **0 define an `attacks` array** (`IMP-B01`) |
| Bosses | 11 | **0 define phases**; 5 distinct bosses shared across 10 dungeons (`IMP-B02`, `IMP-B04`) |
| Weapons | 8 | one archetype each (`IMP-A06`) |
| Biomes | 10 | 9 declare 6–10 rooms; 0 declare `maxHeightLevel`; 2 declare a `grade` profile |
| Dungeons | 10 | 3 `difficultyTiers` each (`IMP-C01`) |
| Statuses | 5 | all debuffs, no build-up meters (`IMP-H01`) |
| Traps | 5 | 2 per biome (`IMP-H02`) |
| Relics | 11 | flat stats only (`IMP-H03`) |
| Talent branches | 3 | |
| Recipes | 5 | |
| NPCs / dialogue trees / quests | 3 / 5 / 4 | trees are 1–3 nodes each (`IMP-G01`) |
| Item icons in atlas | 109 cells @ 16×16 | covers 88 of 90 items |

The pattern across that table is consistent and is the core finding of section 13: **the engine supports
substantially more than the content uses.** Move sets, boss phases, per-attack damage types, room height
levels, per-biome colour grading, per-shield block profiles and per-tier run modifiers are all implemented,
wired and unused.

---

## 2. Executive summary — the ten things that matter most

| # | ID | Severity | One-line statement |
|---|---|---|---|
| 1 | BUG-01 | 🔴 P0 | All game content is loaded from a path *outside* `res://`; the exported build cannot find any of it. |
| 2 | BUG-02 | 🔴 P0 | Character voxel meshes are loaded with `globalize_path()` + `FileAccess`, which cannot read out of a `.pck`. |
| 3 | BUG-13 | 🔴 P0 | **Any inventory change full-heals the player and resets poise** — picking up an item mid-fight restores full HP. |
| 4 | BUG-39 / BUG-40 | 🔴 P0 | Hit-stop measures itself on the clock it just slowed, so a 0.09 s freeze lasts ~1.13 s; and a **second hit inside the window locks the whole game at 8 % speed permanently**. |
| 5 | IMP-B01 | 🔴 P0 | **Every enemy and boss in the game has exactly one attack.** The move-set system is fully built and used by zero of 40 enemy/boss files. |
| 6 | BUG-33 | 🟠 P1 | Endless mode hardcodes one biome, so nine biomes, five enemy families and five bosses are unreachable in the mode meant to be played longest. |
| 7 | IMP-F01 | 🟠 P1 | The inventory is 6×4 = 24 cells and 64 of 90 items are 2×2 — the bag is full after **six** equipment drops. |
| 8 | BUG-52 / BUG-53 | 🟠 P1 | Class perks are authored, named and localised but **read by no code**; class weapon restrictions are enforced in one UI screen and bypassed by every real equip path. |
| 9 | PERF-01 / PERF-02 / PERF-03 / PERF-04 | 🟠 P1 | Hitboxes raycast per candidate per frame; enemies raycast 2–3× per frame with no LOD; dungeon builds are synchronous (the gate *permits* a 1500 ms hitch); characters are unbatched. |
| 10 | QA-01 / DEP-01 / REF-01 | 🟠 P1 | 145 validation assertions test source *text*, not behaviour; backend targets .NET 8 while pulling 10.0.x packages; 27 autoloads form a global mutable graph. |

Items 3–8 are not costs — they are the game not working as designed, and they outrank most of the original
performance list. `BUG-13` invalidates any combat or economy tuning done before it is fixed; `BUG-39` and
`BUG-40` mean nobody has yet experienced the combat feel the code was written to produce.

Two more that are cheap to fix and disproportionately damaging: **`BUG-42`** — the `goldFind` talent is
applied to *refunds*, so repeatedly failing a purchase with a full inventory prints money — and **`BUG-45`**,
where crit rolls, enemy attack selection and the entire waves-mode seed use the unseeded global RNG, which
makes the seed-sharing feature unachievable.

---

## 3. 🔴 P0 — Shipping blockers

### BUG-01 — Content root resolves outside `res://`, so exported builds load zero content

- **Problem** — `ContentLoader.content_root()` returns
  `ProjectSettings.globalize_path("res://").path_join("../../..")`. In the editor `res://` globalises to
  `D:/Proiecte/Aumbrye/apps/game/client/`, so `../../..` lands on the repo root and `content/` is found.
  In an **exported build**, `globalize_path("res://")` returns the directory containing the executable,
  so the loader walks three levels *above the install directory* and finds nothing. `aumbrye/content_root`
  is `""` in `project.godot`, and neither `export_presets.cfg` nor `.github/workflows/release.yml` copies
  `content/` next to the binary. Every enemy, item, class, relic, quest, dialogue, biome, loot table,
  weapon and audio profile therefore resolves to `{}` in the shipped game.
  *(Verified — read the loader, the project settings, the export preset and the release workflow.)*
- **Action** — Move authoritative content into `res://content/` (or embed it at export time) and make
  `content_root()` `res://`-native. Add an export smoke test that boots the packaged binary headless and
  asserts a non-empty catalogue.
- **Location** — `apps/game/client/scripts/app/content_loader.gd:10-36`; `apps/game/client/project.godot`
  (`[aumbrye] content_root=""`); `apps/game/client/export_presets.cfg`; `.github/workflows/release.yml:66-95`
- **Solution Hint** — Two viable shapes:
  1. *Preferred:* make `content/` a directory inside the Godot project (symlink or a build step that mirrors
     the repo `content/` into `res://content/`), and replace `FileAccess.open(abs_path)` with
     `FileAccess.get_file_as_string("res://content/...")`. Directory walks in `ContentDirLoader` must then use
     `DirAccess.open("res://content/enemies")`, which works inside a `.pck`.
  2. *Fallback:* keep the external directory but resolve it as
     `OS.get_executable_path().get_base_dir().path_join("content")` in release builds, and add
     `content/` to the export `include_filter` / a post-export copy step.
  Either way, add a hard boot assertion: `assert(not EnemyCatalog.get_definition("castle_grunt").is_empty())`
  behind a startup self-check that fails loudly instead of degrading silently.

### BUG-02 — Voxel meshes are read through `globalize_path()`, which cannot read from a `.pck`

- **Problem** — `VoxelMeshBuilder.load_mesh()` converts a `res://…voxels.json` path to an absolute OS path
  and opens it with `FileAccess`. In an export, the `.voxels.json` files live inside `game.pck`, not on the
  filesystem at that absolute path, so the open fails, `_build_from_voxels` is never reached, and `load_mesh`
  returns `null`. `DioramaCharacterSkin` treats a `null` mesh as fatal (`push_error` + `return null`), so
  **every character built from a rig manifest fails to construct** in the shipped build.
  *(Verified — read the builder and both call sites in the skin.)*
- **Action** — Drop the `globalize_path` round-trip and read the resource through the virtual filesystem.
- **Location** — `apps/game/client/scripts/art/characters/voxel_mesh_builder.gd:14-22`;
  consumers at `scripts/art/characters/diorama_character_skin.gd:251, 888, 937, 1023`
- **Solution Hint** — Replace lines 15-21 with
  `var text := FileAccess.get_file_as_string(path)` (works for both `res://` and `user://` and inside a `.pck`),
  then `JSON.parse_string(text)`. Same fix applies to `pixel_diorama_style.gd:142,153` (`Image.load_from_file`
  on a globalised path — use `Image.load_from_file` only for `user://`, otherwise `load()` the imported texture)
  and `vfx_service.gd:750`.

### BUG-03 — Save verification reads the temp file before the write handle is flushed

- **Problem** — `_write_save()` opens the temp file, calls `file.store_string(...)`, then immediately calls
  `_read_raw_text(temp_path)` through a **second** `FileAccess` handle to verify the JSON — while the first
  handle is still open and unflushed. Godot buffers writes; the verify read can observe a truncated or empty
  file. On the failure path the code *deletes the temp file and returns `false`*, so a perfectly good save is
  discarded. The same unflushed-write pattern appears in `_save_roster` and the legacy-migration writer.
  *(Verified — read `_write_save`; no `flush()` or `close()` call exists between store and read.)*
- **Action** — Flush and close the write handle before verification, on every write path.
- **Location** — `apps/game/client/scripts/save/local_save.gd:952-985` (write+verify), `:1186`, `:1264`
- **Solution Hint** — Insert `file.close()` (or `file.flush()`; `close()` is clearer) immediately after
  `file.store_string(...)` and before `var verified = JSON.parse_string(...)`. Consider setting `file = null`
  as well to make the release explicit. Add a regression test in `save_suite.gd` that writes a large payload
  (> 64 KiB, to exceed any buffer) and asserts the verify step succeeds.

### BUG-04 — `EnemyPool.release()` dereferences a null parent; the pool is dead code either way

- **Problem** — `EnemyPool.release()` calls `node.get_parent().remove_child(node)` with no null guard; any
  node already detached from the tree crashes the caller. It is moot in practice because **`EnemyPool` is never
  called from game code** — the only references in the repository are two validation assertions that check the
  file contains the string `class_name EnemyPool`. Pooled nodes are also never freed on scene change (they sit
  outside the tree holding their signal connections and groups), so if it were wired up it would leak.
  *(Verified — grepped every reference; the only hits are `m6_suite.gd:726` and `m7_suite.gd:691`.)*
- **Action** — Decide: either wire pooling into `DungeonBuilder._spawn_enemy` / `WavesRun` properly, or delete
  the file and the two assertions that pretend it is in use.
- **Location** — `apps/game/client/scripts/combat/enemy_pool.gd:24-31`;
  fake assertions at `scripts/validation/suites/m6_suite.gd:726-731` and `m7_suite.gd:691`
- **Solution Hint** — If keeping it: guard with `if node.get_parent(): node.get_parent().remove_child(node)`,
  implement `reset_for_pool()` on `CastleEnemyBase` (reset state machine, re-enable collision, clear `_hit_times`,
  reconnect nothing), call `EnemyPool.clear_all()` from `RunFlow` on run teardown, and cap pool size per id.
  If deleting: remove the file *and* the two suite assertions in the same commit, otherwise CI will still be
  green on a lie.

### BUG-05 — `LightFlicker` disables itself permanently the first time a torch leaves view

- **Problem** — `_process()` culls itself with `set_process(visible)`. Once `visible` is `false`, `set_process(false)`
  stops `_process` from ever running again — so nothing can re-evaluate visibility and the light stays frozen at
  base energy for the rest of the scene's life. Every torch the player walks past loses its flicker permanently.
  *(Verified — read the whole file; there is no external re-enable path.)*
- **Action** — Move the visibility check off the `_process` callback so it can recover.
- **Location** — `apps/game/client/scripts/art/lighting/light_flicker.gd:26-45`
- **Solution Hint** — Use `VisibleOnScreenNotifier3D` on the parent, or connect to the light's
  `visibility_changed` signal, and drive `set_process()` from that signal. Simplest fix that keeps the current
  shape: never call `set_process(false)`; instead keep processing but `return` early when hidden, and throttle the
  visibility test to every 0.25 s as it already does. (A `_process` that early-returns costs ~nothing compared to
  a permanently broken effect; the real win is moving flicker to a shader or `AnimationPlayer` — see PERF-12.)

---

## 4. 🟠 P1 — Runtime performance

> **Measure before you cut.** None of the numbers below were profiled on this machine; they are structural
> costs read out of the source. Start every fix in this section by capturing a baseline with
> `--profiler` / the Godot debugger's *Monitors* + *Profiler* tabs in a 20-enemy arena, and record the
> baseline into `user://perf_baseline.json` so QA-02 stops skipping.

### PERF-01 — Hitboxes run a shape query *and* a raycast per candidate, every physics frame

- **Problem** — `Hitbox` connects `area_entered` **and** runs `_scan_overlaps()` from `_physics_process` while
  active. Each scan allocates a fresh `PhysicsShapeQueryParameters3D`, a fresh `exclude` array and a fresh result
  array, then for every overlapping area calls `_try_hit()`, which itself performs:
  a `get_tree().get_first_node_in_group("castle_run")` tree search (`_is_cross_boss_boundary`), **and** a full
  `intersect_ray` line-of-sight test (`_has_clear_line_to`) with two more allocations. With a 0.15 s active window
  at 60 Hz and 4 overlapping hurtboxes, one swing costs ~9 shape queries and ~36 raycasts plus ~90 short-lived
  allocations. Multiply by every attacking enemy in the room.
  *(Verified — read `hitbox.gd` end to end.)*
- **Action** — Make hit detection event-driven and cache the per-swing invariants.
- **Location** — `apps/game/client/scripts/combat/hitbox.gd:26-36, 91-120, 122-160, 178-215`
- **Solution Hint** —
  1. Delete the `_physics_process` polling entirely and rely on `area_entered` + a single `_scan_overlaps()` at
     `enable()` (already done) to catch pre-existing overlaps. Polling exists to catch fast sweeps — if that is
     the real requirement, keep polling but drop it to every *other* physics frame and skip it when
     `get_overlapping_areas().is_empty()`.
  2. Hoist `PhysicsShapeQueryParameters3D` into a member allocated once in `_ready()`; only `transform` changes
     per call.
  3. Resolve the `castle_run` node **once** in `_ready()` into a weak reference instead of a group search per hit.
  4. Cache the LOS result per `(target_id, swing)` in `_hit_times` — a target already validated this swing does
     not need a second raycast.
  5. `_hit_times` currently only clears on `reset_swing()`; make `disable()` clear it too so long-lived hitboxes
     do not accumulate dead instance ids.

### PERF-02 — Enemy AI raycasts 2–3× per physics frame per enemy, with no LOD

- **Problem** — `CastleEnemyBase._physics_process` calls `_update_ai`, which calls `_has_aggro()`, which calls
  `_has_line_of_sight_to_player()` (a `PhysicsRayQueryParameters3D` allocation + `intersect_ray` + result
  Dictionary). In the CHASE state, `_process_chase` calls `_has_aggro()` *and then* `_can_attack()`, which
  raycasts **again**; `_can_attack()` additionally calls `_is_cross_boss_boundary_with_player()`, which does a
  `get_tree().get_first_node_in_group("castle_run")` tree walk every frame. `_end_attack()` calls `_has_aggro()`
  a third time. There is no distance gate, no visibility gate, and no tick-rate reduction for far-away enemies —
  a 30-enemy floor pays ~60–90 raycasts + 30 group searches + ~200 Variant dictionary lookups per physics frame.
  *(Verified — traced every call path in `castle_enemy_base.gd:460-694`.)*
- **Action** — Introduce an AI LOD scheme and memoise per-frame queries.
- **Location** — `apps/game/client/scripts/enemies/castle_enemy_base.gd:460-484, 555-569, 625-694`
- **Solution Hint** —
  1. **Memoise per tick:** cache the LOS result and the player distance in `_physics_process` before
     `_update_ai`, stored with a frame stamp (`Engine.get_physics_frames()`); `_has_aggro`, `_can_attack` and
     `_end_attack` read the cache.
  2. **LOD bands:** near (< 20 m) = full rate; mid (20–40 m) = AI every 4th physics tick; far (> 40 m) or
     `not is_visible_in_tree()` = every 16th tick and skip LOS entirely. Stagger the phase per enemy with
     `get_instance_id() % N` so ticks do not align into a spike.
  3. **Hoist `_data` lookups:** `_data.get("move_speed", 3.5)`, `attack_range`, `aggro_range` etc. are Variant
     dictionary reads inside the hot path. Unpack them into typed floats once in `_ready()`
     (`var _move_speed: float`, `var _attack_range_sq: float`, …) and compare squared distances to drop the
     `sqrt` in `distance_to`.
  4. Resolve `castle_run` once in `_ready()` (same fix as PERF-01.3).

### PERF-03 — Dungeon build and scene changes are fully synchronous; the perf gate *permits* a 1.5 s hitch

- **Problem** — `DungeonBuilder` contains **zero `await`s**. `build_from_source()` instantiates every room scene,
  every enemy, every chest, every trap, every prop, every doorway bridge and the whole floor shell in a single
  frame. All scene navigation goes through `get_tree().change_scene_to_file()` (synchronous) — there is **no
  `ResourceLoader.load_threaded_request` anywhere in the project**. The `loading_screen.tscn` exists but is only
  used as a static interstitial from the main menu, not as a progress host. And the perf gate that is supposed to
  catch this sets `BUDGET_DUNGEON_BUILD_MS := 1500` — a 1.5-second freeze is a *passing* result.
  *(Verified — `grep -c await` on the builder returns 0; grepped for `load_threaded` across all scripts: no hits.)*
- **Action** — Convert floor construction to a chunked/threaded pipeline behind the loading screen, and tighten
  the budget.
- **Location** — `apps/game/client/scripts/dungeon/dungeon_builder.gd:76-144` and its `_build_*`/`_place_*`
  helpers; `scripts/app/run_scene_router.gd:14`; `scripts/ui/loading_screen.gd`;
  budget at `scripts/validation/suites/perf_gate_suite.gd:6`
- **Solution Hint** —
  1. Make `build_from_source` a coroutine: `await get_tree().process_frame` after each room instantiation and
     after every N placements, emitting a `build_progress(ratio)` signal.
  2. Pre-warm the room `PackedScene`s with `ResourceLoader.load_threaded_request()` at the *start* of the floor
     transition (in `RunFlow._transition_floor`), then `load_threaded_get()` when the builder needs them.
  3. Route every `change_scene_to_file` through a single `SceneTransition` service that shows the loading screen,
     polls `load_threaded_get_status`, and swaps with `change_scene_to_packed`.
  4. Drop `BUDGET_DUNGEON_BUILD_MS` to something a player would tolerate as a *frame* cost once chunked —
     e.g. keep a 1500 ms wall-clock budget for the whole build but add a **per-frame** budget of 8 ms and assert
     no single frame exceeds it.

### PERF-04 — Characters are dozens of separate `MeshInstance3D`s with per-instance materials

- **Problem** — `DioramaCharacterSkin` builds each body as a pivot hierarchy where every part (LegL, LegR, Torso,
  Head, ArmL, ArmR, Visor, Hood, BeltTrim, Pauldron, PauldronR, hair, face accents, class armour, equipment
  visuals, weapon, shield) is its own `Node3D` pivot with its own child `MeshInstance3D` and its own
  `material_override`. That is ~12–20 draw calls and ~12–20 unique material instances **per character**, with no
  possibility of batching or instancing. `_make_voxel_material()` is called per equipment piece and per hair
  mesh rather than shared. On a 20-enemy floor this is 250–400 draw calls of character geometry alone, before
  props, rooms, VFX and UI.
  *(Verified — read the builder paths at `diorama_character_skin.gd:870-1035`.)*
- **Action** — Collapse each character to one skinned mesh with a shared material, or at minimum share materials
  across instances.
- **Location** — `apps/game/client/scripts/art/characters/diorama_character_skin.gd` (whole build path, esp.
  `:870-950`, `:1010-1035`); `scripts/art/characters/voxel_mesh_builder.gd`
- **Solution Hint** — Ordered by effort:
  1. **Cheap, immediate:** cache materials by `(theme, slot)` in a static dictionary so all enemies of a theme
     share one `ShaderMaterial` resource. Per-instance colour variation moves to
     `MeshInstance3D.set_instance_shader_parameter()`, which does not break batching.
  2. **Medium:** merge all static parts of a body into one `ArrayMesh` with surfaces grouped by material, keeping
     only the animated pivots (arms, legs, head) as separate instances. Cuts ~15 draw calls to ~4.
  3. **Proper:** author the rigs as real skinned meshes (`Skeleton3D` + `MeshInstance3D` with a `Skin`) built
     offline by `export_voxel_meshes.gd`, so a character is **one** draw call and animation is GPU skinning
     rather than per-pivot transform writes. This also removes the need for the runtime hierarchy builder
     entirely (see REF-05).

### PERF-05 — Enemy health bars CPU-billboard every frame and rebuild a GPU texture on every hit

- **Problem** — Two independent wastes in the same file:
  1. `_build_sprites()` sets `billboard = BaseMaterial3D.BILLBOARD_ENABLED` on all four sprites — the GPU already
     faces them at the camera. Then `_process()` runs **every frame for every enemy**, calls
     `PixelDioramaViewport.get_gameplay_camera()` (which falls back to `get_tree().root.get_camera_3d()`), does
     vector math and calls `look_at()`. The entire callback is redundant work that fights the GPU billboard.
  2. `_on_health_changed()` calls `_make_bar_texture()`, which allocates a new `Image`, runs a
     **128-iteration nested `set_pixel` loop**, and creates a brand-new `ImageTexture` — i.e. a GPU texture
     upload — on *every damage event*. The same function then also sets `_fill_sprite.scale.x = ratio`, which
     already produces the visual result on its own. The texture regeneration is pure churn.
  *(Verified — read `enemy_health_bar.gd` end to end.)*
- **Action** — Delete the `_process` billboard, and replace per-hit texture generation with a scaled static
  texture.
- **Location** — `apps/game/client/scripts/ui/enemy_health_bar.gd:34-118` (build), `:110-131` (`_make_bar_texture`),
  `:134-142` (`_process`), `:145-158` (`_on_health_changed`)
- **Solution Hint** — Remove `_process()` entirely (the sprites are already billboarded; if the *pixel-snapped*
  look demands Y-only billboarding, use `BILLBOARD_FIXED_Y` instead of CPU `look_at`). Build the fill texture
  **once** as a solid 1×1 or 2×2 colour and drive the bar purely with `scale.x` + `position.x`. Additionally,
  gate the whole node on distance/visibility: connect a `VisibleOnScreenNotifier3D` and hide bars beyond ~25 m.

### PERF-06 — `AudioDirector._process` runs every frame to do nothing once stems are loaded

> **Corrected 2026-08-06.** An earlier revision of this item claimed the director synthesises four sine
> streams on the main thread every frame and ranked it P1. That was wrong. `_process()` only fills a layer
> whose `stream is AudioStreamGenerator`, and a successfully loaded `.ogg` **replaces** the generator, so
> synthesis does not run in normal play. All ten biomes have all four stems on disk, and
> `audio_suite.gd` asserts this behaviourally (`audio.no_process_synthesis_with_stems` starts a dungeon and
> asserts no layer is still an `AudioStreamGenerator`). The residual cost is small; the item is now P3.

- **Problem** — `_process()` runs every frame for the life of the process, performing four `playing`
  reads and four `is AudioStreamGenerator` type checks that are all false once stems are loaded. The
  autoload is `PROCESS_MODE_ALWAYS`, so this also ticks on the title screen and in menus. Cheap per frame,
  but it is one of 27 autoloads and the pattern repeats (see PERF-11).
  *(Verified — read `audio_director.gd:127-136`; confirmed every biome directory under
  `apps/game/client/assets/audio/` contains `ambience_loop.ogg`, `explore_loop.ogg`, `combat_loop.ogg` and
  `boss_theme.ogg`.)*
- **Action** — Disable processing while no layer is generator-backed.
- **Location** — `apps/game/client/scripts/audio/audio_director.gd:127-136`, `:138-163` (`set_biome`), `:518-522`
- **Solution Hint** — Track `_generator_active: bool`, recomputed whenever a layer's stream is assigned
  (`_try_load_file_stream()` and the generator-restore path), and call `set_process(_generator_active)`.
  Separately, add a validation assertion that every path declared in `content/audio_profiles/*.json`
  resolves via `ResourceLoader.exists()` — `audio_suite.gd` currently checks the filesystem through
  `globalize_path`, which will not work in an export (same class of bug as BUG-02).

### PERF-06b — Dead audio assets: legacy `castle/` folder and 24 duplicate `.wav` sources

- **Problem** — `apps/game/client/assets/audio/castle/` holds `ambience_loop` and `boss_theme` in **both**
  `.ogg` and `.wav`, plus a `README.md`. Nothing references it: `BiomeRegistry.BIOME_CASTLE` resolves to
  `"forgotten_castle"`, which has its own complete four-stem folder. Across `assets/audio/` there are 24
  `.wav` files sitting next to their imported `.ogg` counterparts. All of it is exported into the shipped
  build under `export_filter="all_resources"`.
  *(Verified — grepped `content/` and `scripts/` for `audio/castle`: no hits; read
  `biome_registry.gd:8`.)*
- **Action** — Delete the legacy folder and the redundant `.wav` sources.
- **Location** — `apps/game/client/assets/audio/castle/`; `apps/game/client/assets/audio/**/*.wav`
- **Solution Hint** — Keep `.wav` masters in `art-source/` (or out of the repo) if they are still needed for
  re-encoding; the Godot project only needs the `.ogg` plus its `.import`. Add an assertion that every
  file under `assets/audio/` is reachable from some `content/audio_profiles/*.json` or `content/audio/sfx.json`
  entry, mirroring the character-asset check proposed in DEAD-02.

### PERF-07 — Content catalogues re-walk and re-parse the entire content directory when a load fails

- **Problem** — Every catalogue guards with `if not _definitions.is_empty(): return`. When loading genuinely
  fails — which is exactly the BUG-01 export case, but also any transient I/O failure — `_definitions` stays
  empty, so **every subsequent call re-runs the full directory walk and JSON parse**. `EnemyCatalog.get_definition()`
  is called from `CastleEnemyBase._ready()`, `CombatHUD.bind_boss()`, `DungeonBuilder._spawn_enemy()` and
  more. In the failure case, spawning 30 enemies re-parses `content/enemies/` + `content/bosses/` 30 times.
  Separately, `ContentLoader.load_json()` has **no cache at all** and additionally runs
  `ContentSchemaValidator.validate_loaded()` on every call in debug builds.
  *(Verified — read `enemy_catalog.gd`, `content_dir_loader.gd`, `content_loader.gd`.)*
- **Action** — Add a `_load_attempted` flag distinct from `_definitions.is_empty()`, and memoise `load_json`.
- **Location** — `apps/game/client/scripts/content/enemy_catalog.gd:57-62` and the identical pattern in
  `item_catalog.gd`, `class_catalog.gd`, `relic_catalog.gd`, `quest_catalog.gd`, `dialogue_catalog.gd`,
  `trap_catalog.gd`, `portal_catalog.gd`, `aspect_catalog.gd`;
  `scripts/app/content_loader.gd:20-36`; `scripts/content/content_dir_loader.gd`
- **Solution Hint** — Pull the flag into `ContentDirLoader` so it is fixed once:
  a `static var _loaded_dirs: Dictionary` keyed by the directory list. In `ContentLoader.load_json`, add
  `static var _json_cache: Dictionary` keyed by relative path, cleared from `clear_all_caches()`. Run
  `ContentSchemaValidator` **once per unique path** rather than per call. Make a failed load `push_error` once
  and mark the catalogue permanently failed rather than retrying forever.

### PERF-08 — Hot paths use string-based dynamic dispatch (`has_method` + `call`) every physics frame

- **Problem** — The codebase contains **282 `has_method()` calls and 290 `.call()` calls** outside the validation
  suites, and they cluster in exactly the wrong places: `locomotion.gd` has 11, `player_anim_director.gd` 11,
  `combat_hud.gd` 16, `lock_on.gd` 11, `weapon_controller.gd` 9 — all inside per-frame callbacks.
  `Locomotion._physics_process` alone performs `has_method` + `call` for `is_movement_locked`,
  `get_attack_lunge_velocity`, `process_dash_physics`, `process_dodge_physics`, `get_move_speed_multiplier` and
  `get_rotation_cap_multiplier` on **every physics tick**. Each pair is a `StringName` hash lookup plus a
  `Variant`-boxed dynamic call — one to two orders of magnitude slower than a typed method call.
  *(Verified — counted with grep; read `locomotion.gd:117-200`.)*
- **Action** — Replace duck-typed sibling access with typed cached references resolved once in `_ready()`.
- **Location** — `apps/game/client/scripts/player/locomotion.gd:117-200`;
  `scripts/combat/weapon_controller.gd:123-153`; `scripts/player/player_anim_director.gd`;
  `scripts/ui/combat_hud.gd:216-224`; `scripts/camera/lock_on.gd`; `scripts/combat/hurtbox.gd:44-90`
- **Solution Hint** — These components are all siblings under the player node with fixed names. Declare typed
  members (`var _dodge: Dodge`, `var _weapon: WeaponController`, `var _combat_reactions: PlayerCombatReactions`)
  and resolve them once in `_ready()` with `get_node_or_null(...) as Type`. Where a genuine optional/plugin
  boundary exists, keep the check but **hoist it out of the loop**: resolve
  `var _has_lunge := _weapon != null and _weapon.has_method("get_attack_lunge_velocity")` in `_ready()` and test
  the bool per frame. Prefer signals or a small typed interface (`class_name MovementModifier`) over
  `has_method` probing.

### PERF-09 — `VfxService._process` allocates a fresh array every frame and never sleeps

- **Problem** — `_sweep_pools()` builds a brand-new `Array[Dictionary] remaining` every frame and reassigns
  `_sweep_entries`, even when the list is empty. `_process` also runs `_update_hitstop()`, a `lerpf` on
  `_shake_amount` and iterates `_free_nodes` unconditionally. The service is an autoload with
  `set_process(true)` permanently on, so this runs on the title screen and in menus too.
  *(Verified — read `vfx_service.gd:58-66, 662-687`.)*
- **Action** — Make the sweep allocation-free and idle-aware.
- **Location** — `apps/game/client/scripts/art/vfx/vfx_service.gd:58-66, 662-679`
- **Solution Hint** — Sweep in place with a reverse loop and `remove_at()` instead of rebuilding the array.
  Early-return from `_process` when `_sweep_entries.is_empty() and _free_nodes.is_empty() and
  _hitstop_until_ms == 0 and is_zero_approx(_shake_amount)`. Better: call `set_process(false)` when the service
  goes idle and re-enable it from `play()` / `request_hitstop()` / `request_shake()`.

### PERF-10 — `CombatHUD._process` runs six unthrottled update passes every frame

- **Problem** — `_process` calls `_update_lock_reticle`, `_update_guard_indicators`, `_update_objective_marker`,
  `_update_attack_bar`, `_update_status_timers` and `_update_controls_hint_visibility` every frame. Only
  `_update_status_timers` is throttled (via `STATUS_REFRESH_INTERVAL`). The objective marker and lock reticle
  involve 3D→2D projection and node lookups; the guard indicators use `has_method`/`call` (see PERF-08).
  *(Verified — read `combat_hud.gd:216-224` and the update helpers.)*
- **Action** — Throttle the non-reticle passes and make the rest signal-driven.
- **Location** — `apps/game/client/scripts/ui/combat_hud.gd:216-224`
- **Solution Hint** — Keep `_update_lock_reticle` and `_update_attack_bar` at frame rate (they track motion);
  move `_update_objective_marker` and `_update_controls_hint_visibility` to a 10 Hz accumulator. Guard indicators
  should be driven by `Guard` signals (`guard_started` / `guard_broken`) rather than polled.

### PERF-11 — `SteamService._process` runs every frame even in stub mode

- **Problem** — `_process` checks `if not is_stub_mode and Engine.has_singleton("Steam")` every frame.
  `_init_stub()` sets `is_stub_mode = true` but never calls `set_process(false)`, so the callback is dispatched
  60× per second forever to do nothing. Trivial individually, but it is one of 27 autoloads and the pattern
  repeats.
  *(Verified — read `steam_service.gd:33-35, 114-122`.)*
- **Action** — Disable processing in stub mode; audit all autoloads for the same pattern.
- **Location** — `apps/game/client/scripts/platform/steam_service.gd:33-35, 114-122`
- **Solution Hint** — Add `set_process(false)` at the end of `_init_stub()` and `set_process(true)` on successful
  real init. Then sweep every autoload in `project.godot` and assert each one either has no `_process`/
  `_physics_process` or explicitly disables it when idle. Worth a validation assertion.

### PERF-12 — Camera updates in `_process` while bodies move in `_physics_process`, with interpolation off

- **Problem** — `OrbitCamera` splits its work: `_physics_process` handles stick look, mode blend and spring-arm
  length; `_process` handles camera effects, shoulder offset, optics and the pixel snap. The player moves in
  `_physics_process`. Godot's `physics_interpolation` is **not enabled** in `project.godot`. Reading a
  physics-driven transform from a render-rate callback without interpolation produces the classic
  physics/render beat — visible as sub-pixel camera judder, which the nearest-neighbour pixel pipeline
  (PERF-13) will *amplify* into full-pixel crawl.
  *(Verified — read `orbit_camera.gd:105-131`; grepped `project.godot` for `physics_interpolation` — absent.)*
- **Action** — Enable 3D physics interpolation and consolidate camera work into one callback.
- **Location** — `apps/game/client/scripts/camera/orbit_camera.gd:105-131`;
  `apps/game/client/project.godot` (`[physics]` section absent)
- **Solution Hint** — Add `physics/common/physics_interpolation=true` to `project.godot` (Godot 4.4+ supports 3D
  interpolation), and set `physics/common/physics_ticks_per_second=60`. Then move *all* camera transform writes
  into `_process` and read the player's interpolated transform, or move all of them into `_physics_process` and
  let interpolation smooth the result. Do not split. Verify with the pixel-snap path in
  `pixel_camera_snap.gd` — snapping must happen *after* interpolation, on the render camera only (which
  `PixelDioramaViewport._mirrored_transform()` already does correctly).

### PERF-13 — The low-res SubViewport runs `UPDATE_ALWAYS` with the root 3D disabled

- **Problem** — `PixelDioramaViewport` sets `render_target_update_mode = SubViewport.UPDATE_ALWAYS` and
  `root.disable_3d = true`, mirroring the gameplay camera into a low-res SubViewport. The design is sound, but:
  (a) `UPDATE_ALWAYS` renders the 3D world even when a full-screen opaque menu is on top; (b) the autoload
  connects to `get_tree().root.child_entered_tree`, firing a deferred `_try_auto_attach` for **every** node that
  enters the root; (c) `_process` runs with `PROCESS_MODE_ALWAYS` so it ticks while paused.
  *(Verified — read `pixel_diorama_viewport.gd:57-64, 111-137, 139-158.)*
- **Action** — Switch the SubViewport to `UPDATE_WHEN_VISIBLE` and gate rendering behind menu state.
- **Location** — `apps/game/client/scripts/art/pipeline/pixel_diorama_viewport.gd:130`, `:57-64`, `:402-419`
- **Solution Hint** — Use `SubViewport.UPDATE_WHEN_VISIBLE` and toggle `_layer.visible` from `MenuStack` when a
  full-screen modal opens. For (b), only auto-attach when the entering node *is* `get_tree().current_scene`
  (the deferred handler already checks this — move the check earlier, before `call_deferred`, to avoid the
  per-node deferred allocation). For (c), `PROCESS_MODE_ALWAYS` is needed so the mirror keeps up during a paused
  pause-menu render — keep it, but early-return when `_layer.visible == false`.

### PERF-14 — Voxel meshing is advertised as greedy but emits two triangles per exposed face

- **Problem** — `voxel_mesh_builder.gd`'s docstring says "Builds greedy-merged voxel ArrayMeshes". There is **no
  greedy meshing** — `_build_from_voxels` iterates every solid cell and emits 2 unindexed triangles for each of
  the 6 faces that has no solid neighbour. There is no `SurfaceTool.index()` call, so the vertex buffer carries
  6 vertices per quad instead of 4, and no vertex sharing at all. For a 16×16×16-ish character part this is
  several thousand redundant triangles that a real greedy mesher would collapse into a handful of quads.
  *(Verified — read the whole builder; the docstring is at line 4 and contradicts lines 39-77.)*
- **Action** — Implement actual greedy meshing (or move meshing offline entirely), and fix the docstring.
- **Location** — `apps/game/client/scripts/art/characters/voxel_mesh_builder.gd:4, 39-77`
- **Solution Hint** — Two-stage: (1) immediate — call `st.index()` before `st.commit()` to at least dedupe
  vertices; (2) proper — implement the standard binary-plane greedy algorithm (sweep each of the 6 axis
  directions, build a 2D mask per slice, merge maximal rectangles). Since the input is authored art that never
  changes at runtime, the *right* answer is to run this in `export_voxel_meshes.gd` at build time and ship
  `.mesh` resources — which is what the (currently orphaned, see DEAD-02) `.mesh` files were presumably for.
  Also: `_snap_to_palette` runs an 8-way colour-distance search per mesh; hoist the palette into a
  precomputed array.

### PERF-15 — Deep-copy + pretty-print + full re-read + full re-validate on every autosave

- **Problem** — `_write_save()` performs, synchronously on the main thread: `data.duplicate(true)` (deep copy of
  the whole save state), `_normalize_save_integers`, `_build_item_instances`, `JSON.stringify(normalized, "\t")`
  (pretty-printed, so noticeably larger and slower than compact), a full file write, a **full file re-read**, a
  **full re-parse**, a **full `SaveValidator.validate`**, then a rename. `request_autosave` is called from many
  gameplay events. The perf gate's own budget for this is 50 ms — a 50 ms main-thread stall is a visible hitch.
  *(Verified — read `local_save.gd:952-985` and `perf_gate_suite.gd:9`.)*
- **Action** — Slim the write path and move it off the critical frame.
- **Location** — `apps/game/client/scripts/save/local_save.gd:498-527, 952-985`
- **Solution Hint** — Use compact `JSON.stringify(normalized)` (pretty-print only under
  `OS.is_debug_build()`). Skip the re-read entirely — validate the in-memory `normalized` dictionary before
  writing, then write once and trust the atomic rename. If the read-back is a deliberate corruption guard, keep
  it but only on `SavePriority.IMMEDIATE`. For deferred autosaves, serialise on a `WorkerThreadPool` task and
  do the rename on the main thread when it completes. Also fix BUG-03 (missing flush) in the same change.

---

## 5. 🟡 P2 — Correctness bugs

### BUG-06 — Buffered attack fires regardless of the buffer window

- **Problem** — `WeaponController._physics_process` contains two consecutive blocks:
  ```gdscript
  if _post_dodge_attack_buffer > 0.0 and _buffered_attack != "" and not is_attacking:
      _try_attack(_buffered_attack); _buffered_attack = ""
  if _buffered_attack != "" and not is_attacking:
      _try_attack(_buffered_attack); _buffered_attack = ""
  ```
  The second block is a strict superset of the first, so the first is dead code — **and** the second ignores
  `_post_dodge_attack_buffer` entirely. The buffer timer therefore has no gameplay effect: an input buffered
  seconds ago still fires the instant the current attack ends. This is a felt input-responsiveness bug, not just
  a tidiness issue.
  *(Verified — read `weapon_controller.gd:123-153`.)*
- **Action** — Delete the redundant block and gate the buffer on the window; clear `_buffered_attack` when the
  window expires.
- **Location** — `apps/game/client/scripts/combat/weapon_controller.gd:147-153`
- **Solution Hint** — Keep one block, gated on the timer, and clear the buffer in the decrement:
  ```gdscript
  if _post_dodge_attack_buffer > 0.0:
      _post_dodge_attack_buffer -= delta
      if _post_dodge_attack_buffer <= 0.0:
          _buffered_attack = ""
  ...
  if _buffered_attack != "" and not is_attacking and _post_dodge_attack_buffer > 0.0:
      _try_attack(_buffered_attack)
      _buffered_attack = ""
  ```
  Add a combat-suite test that buffers an input, advances 1 s of simulated time, and asserts no attack fires.

### BUG-07 — `ApiConfig.acquire_http()` can spin forever with no timeout

- **Problem** — `acquire_http()` is a `while true` loop that scans the HTTP pool for a free request node and
  `await get_tree().process_frame` when none is available. If a caller ever fails to call `release_http()` — an
  early `return` on an error path, an exception, a scene change mid-request — the pool is permanently exhausted
  and every subsequent network call hangs forever, silently. The `return _http_pool[0]` after the loop is
  unreachable.
  *(Verified — read `api_config.gd:95-114`.)*
- **Action** — Add a timeout and a leak guard.
- **Location** — `apps/game/client/scripts/net/api_config.gd:95-114`
- **Solution Hint** — Bound the wait (e.g. 10 s worth of frames) and return `null`, with all callers handling
  `null` as a transport failure. Add a watchdog that force-releases any handle busy for longer than the request
  timeout. Better still: wrap acquire/release so callers cannot forget —
  `func with_http(fn: Callable) -> Variant` that acquires, `await`s the callable, and releases in all paths.

### BUG-08 — 318 signal connections against 28 disconnections

- **Problem** — The game scripts contain 318 `.connect(` calls and only 28 `.disconnect(` calls. Several
  connections target autoloads (`AudioDirector`, `RunFlow`, `PixelDioramaViewport.world_attached`,
  `VfxService`) from scene-local nodes. When those nodes are freed, Godot cleans up connections *from* the freed
  node, but connections *whose target is the freed node* are only cleaned automatically if the node itself is
  the receiver — a lambda or bound callable capturing a freed node produces "Attempt to call function on
  previously freed instance" at runtime. `CombatHUD` is the only place with a rigorous `_unbind_*` pattern.
  *(Verified — counted with grep; read `combat_hud.gd:243-297` as the counter-example of doing it right.)*
- **Action** — Audit connections to long-lived objects and add symmetric teardown.
- **Location** — Repo-wide; highest risk: `apps/game/client/scripts/ui/*.gd`,
  `scripts/enemies/castle_enemy_base.gd:115-125`, `scripts/camera/lock_on.gd:_set_lock`,
  `scripts/art/vfx/vfx_service.gd:54-55`
- **Solution Hint** — Rule of thumb to enforce in review: *if the emitter outlives the receiver, disconnect in
  `_exit_tree()`.* Mechanically, prefer `signal.connect(callable, CONNECT_ONE_SHOT)` where applicable, and use
  `Object.connect` with a `Callable` bound to `self` (auto-cleaned) rather than lambdas capturing nodes. Add a
  validation assertion that walks a torn-down gameplay scene and asserts
  `AudioDirector.get_signal_connection_list(...)` is empty.

### BUG-09 — `CastleEnemyBase` reaches into the animation controller's private state

- **Problem** — `_start_windup()` reads `_animator._events_path` — a private member of `DioramaAnimController` —
  to decide whether hitbox timing comes from animation events. This silently breaks if the controller is
  refactored, and it is not covered by any interface contract.
  *(Verified — `castle_enemy_base.gd:714-716`.)*
- **Action** — Expose a public predicate on the controller.
- **Location** — `apps/game/client/scripts/enemies/castle_enemy_base.gd:714-716`;
  `scripts/art/characters/diorama_anim_controller.gd`
- **Solution Hint** — Add `func drives_hitbox_events() -> bool: return not _events_path.is_empty()` to
  `DioramaAnimController` and call that. While there, `_on_hit_resolved(res)` at `castle_enemy_base.gd:863` is
  the **only** untyped function parameter in the game scripts despite `warnings/untyped_declaration=1` — type it
  as `DamageResolution`.

### BUG-10 — Godot version pin (4.7.0) does not match the stated target (4.7.1)

- **Problem** — `apps/game/client/.godot-version` contains `4.7.0`, and `project.godot` declares
  `config/features=PackedStringArray("4.7", "Forward Plus")`. Both CI and the release export read
  `.godot-version`, so local development on 4.7.1 and CI on 4.7.0 can diverge on engine-behaviour changes.
  *(Verified — read the version file, the project file, and both workflows.)*
- **Action** — Pin `.godot-version` to `4.7.1` and re-run the full validation + export path once.
- **Location** — `apps/game/client/.godot-version`; `.github/workflows/ci.yml:260-267`;
  `.github/workflows/release.yml:72-78`
- **Solution Hint** — Bump the file, open the project once in 4.7.1 so `.godot/` and `*.import` regenerate,
  commit any `.import` churn separately from code changes, and re-run `godot --headless --script
  res://scripts/validation/validation_main.gd`. Also review the 4.7 API surface for deprecations touching this
  codebase: `SubViewport` sizing while `SubViewportContainer.stretch` is on (already commented at
  `pixel_diorama_viewport.gd:263`), `Viewport.disable_3d`, and `physics_interpolation` semantics (PERF-12).

### BUG-11 — `Hitbox._try_hit` assumes `_owner_node` is alive

- **Problem** — `_try_hit` dereferences `_owner_node.get_node_or_null("HitFeedback")` without an
  `is_instance_valid` check. `_owner_node` is resolved once in `_ready()` by walking up to the first
  `CharacterBody3D`. If the owner is freed while a swing is in flight (enemy killed by a simultaneous hit,
  scene teardown mid-frame), this is a use-after-free.
  *(Inferred — the null path is reachable; not reproduced.)*
- **Action** — Guard the owner dereference.
- **Location** — `apps/game/client/scripts/combat/hitbox.gd:141-160`
- **Solution Hint** — Early-return from `_try_hit` when `not is_instance_valid(_owner_node)`, and call
  `disable()` from the owner's `tree_exiting`. Same audit applies to `_find_combat_owner()` results held across
  frames elsewhere in `scripts/combat/`.

### BUG-12 — `Hurtbox.receive_hit` allocates and re-searches the node tree on every hit

- **Problem** — Each hit constructs a fresh `DamageResolution` `RefCounted`, then calls `_find_dodge()`,
  `_find_character_body()` and `_find_guard()` — node-tree searches — before any damage math runs. Combined with
  PERF-01 (hitboxes polling every frame), a sustained multi-enemy fight produces a steady stream of allocations
  and tree walks.
  *(Verified — read `hurtbox.gd:44-90`.)*
- **Action** — Cache the sibling references and pool or flatten the resolution object.
- **Location** — `apps/game/client/scripts/combat/hurtbox.gd:44-90`
- **Solution Hint** — Resolve `_dodge`, `_guard` and `_character_body` once in `_ready()` (typed) and refresh
  only on `tree_entered`. Replace the `DamageResolution` `RefCounted` with a reusable member instance that is
  reset per hit, or with a plain `Dictionary`/`struct`-shaped typed class if the signal contract permits.

---

## 5A. Per-file sweep — additional defects, costs and shape problems

This section is the result of walking the gameplay source file by file rather than by symptom. It adds
bugs (`BUG-13`…`BUG-53`), optimisations (`PERF-16`…`PERF-24`) and refactors (`REF-09`…`REF-15`) that the
first pass did not reach. Everything here was read in the file named under **Location**.

The sweep covers the whole of `apps/game/client/scripts/` — combat, player, camera, inventory, items, loot,
dungeon (including `procgen/`, `room_content/`, `traps/`, `castle/`), enemies, bosses, hub, quests, dialogue,
npc, save, net, app, content, platform, ui, art and debug — plus `content/**` and the backend and web
sources. See section 16 for what "covered" does and does not warrant.

### 🔴 P0 / 🟠 P1 — Bugs

### BUG-13 — Any inventory change full-heals the player, mid-run, for free

- **Problem** — `Health.configure()` unconditionally sets `current = max_hp`. `InventoryService` calls
  `health.configure(Health.MAX_HEALTH + bonus_hp)` from `apply_equipment_to_player_node()`, which is called
  from `_apply_equipment_to_player()`, which is wired to `inventory.changed`, `RunBuffs.buffs_changed` and
  `ProgressionService.progression_changed`. `GridInventory` emits `changed` on **every** add, remove, move,
  equip, unequip, split, sort and consume. The net effect is that picking an item off the floor, dragging an
  item one cell, or splitting a stack restores the player to full health. The same call path also resets
  `Poise.current` to max (`Poise.configure` does the same thing), so it clears an in-progress stagger build-up.
  This single defect removes the resource-attrition pressure that a Soulslike run economy is built on.
- **Action** — Separate "change the maximum" from "refill to the maximum" on every combat resource, and make
  the equipment path use the non-refilling variant.
- **Location** — `apps/game/client/scripts/combat/health.gd` (`configure`);
  `apps/game/client/scripts/combat/poise.gd` (`configure`);
  `apps/game/client/scripts/inventory/inventory_service.gd` (`apply_equipment_to_player_node`,
  `_on_inventory_changed`, `_on_run_buffs_changed`, `_on_progression_changed`)
- **Solution Hint** — Give `Health.configure()` the signature `Stamina.configure()` already has:
  `configure(max_hp: float, preserve_ratio: bool = false)`. When `preserve_ratio` is true, scale `current` by
  `new_max / old_max` and clamp; when the max **shrinks** below `current`, clamp down. Do the same for `Poise`.
  Then call `configure(..., true)` from the equipment path and keep the refilling form for `respawn`,
  `reset_after_revive` and bonfire rest. Add a regression assertion in the combat validation suite:
  damage the player, emit `inventory.changed`, assert `Health.current` is unchanged.

### BUG-14 — Every copy of an item dropped in one run rolls identical affixes and a colliding instance ID

- **Problem** — `InventoryService._loot_roll_seed()` returns `RunFlow.current_seed + hash(item_id) & 0x7fffffff`,
  which is constant for a given `(run, item_id)` pair. `AffixRoller.roll_instance()` seeds its RNG with that
  value and derives the instance identity from it via
  `_make_instance_id(item_id, roll_seed)` → `"%s_%d" % [item_id, seed]`. Two `iron_greatsword` drops in the
  same run therefore receive the same rarity, the same affixes, the same values **and the same
  `instanceId`**. `GridInventory.find_instance_index()` returns the first match, so quick-slot bindings,
  `RunFlow.get_loot_claimed_instance_ids()` and `strip_equipped_run_loot()` all act on the wrong copy.
  A loot game whose drops are not independent is not a loot game.
- **Action** — Make the roll seed unique per drop and derive instance IDs from a monotonic counter rather
  than from the seed.
- **Location** — `apps/game/client/scripts/inventory/inventory_service.gd` (`_loot_roll_seed`);
  `apps/game/client/scripts/loot/affix_roller.gd` (`roll_instance`, `_make_instance_id`)
- **Solution Hint** — Mix a per-run drop ordinal into the seed:
  `RunFlow.current_seed ^ (hash(item_id) * 2654435761) ^ (drop_index * 40503)`, where `drop_index` is an
  integer that `RunFlow` increments on every drop and persists in the active-run snapshot (so it survives
  save/load and stays deterministic for a given seed). For identity, keep `instanceId` opaque: a run-scoped
  counter (`"%s#%d" % [item_id, next_instance_ordinal()]`) is sufficient and is never expected to collide.
  `AffixRoller.roll_identical(item_id, seed)` stays as the explicit reproduce-this-exact-roll entry point.

### BUG-15 — `AffixRoller` records the RNG's *post-roll* state as `rollSeed`, so rolls are not reproducible

- **Problem** — When `roll_seed < 0` the roller calls `rng.randomize()`, consumes numbers for rarity, affix
  count, affix picks and tier values, and then stores `"rollSeed": rng.seed`. `RandomNumberGenerator.seed`
  reads back the generator's **current** state, not the value it was seeded with, so replaying
  `roll_identical(item_id, stored_seed)` produces a different item. Anything that re-derives an item from its
  saved `rollSeed` — save reload, item comparison tooltips, blacksmith preview — can silently disagree with
  what the player was shown.
- **Action** — Capture the seed before consuming any randomness, and store that.
- **Location** — `apps/game/client/scripts/loot/affix_roller.gd` (`roll_instance`)
- **Solution Hint** — `var effective_seed := roll_seed if roll_seed >= 0 else randi() & 0x7fffffff`, then
  `rng.seed = effective_seed` and store `effective_seed` in both `rollSeed` and `_make_instance_id`. This also
  removes the branchy `roll_seed if roll_seed >= 0 else rng.…` expressions that appear three times in the
  function. Add a validation assertion: roll twice from a stored `rollSeed` and assert affix equality.

### BUG-16 — `GridInventory.add_item()` mutates the grid and then reports failure

- **Problem** — The placement loop appends slots as it goes and only checks `if quantity > 0: return false`
  **after** the loop. When a stack partially fits, the fitting portion is already appended to `slots` and the
  stacking pre-pass has already incremented existing stacks, but the function returns `false` **without
  emitting `changed`**. `InventoryService.add_item()` then reports `inventory_rejected("full")` to the UI. The
  player is told the pickup failed while the items are in fact in the grid, and no listener refreshes, so the
  UI does not draw them until some other event fires.
- **Action** — Make `add_item` transactional: compute placement fully, then commit, or roll back.
- **Location** — `apps/game/client/scripts/inventory/grid_inventory.gd` (`add_item`)
- **Solution Hint** — Snapshot `slots` (a shallow copy of the array plus a copy of any stack dictionaries the
  pre-pass will touch) before mutating; on the failure path restore the snapshot and return `false`. If partial
  pickup is the desired behaviour instead, return the number actually placed and emit `changed`, and have
  `InventoryService` report `"partial"` rather than `"full"`. Either is defensible; the current mixture is not.
  Note the same latent shape in `_repack_slots()`, which silently **drops** any slot that no longer fits after
  a sort — a sort that deletes items is worse than a sort that refuses.

### BUG-17 — Equipment cannot be swapped when the grid is full

- **Problem** — `equip_from_index()` calls `_return_equipped_to_grid(target_slot)` to place the currently
  equipped item **before** removing the incoming item from the grid. With a full grid `_find_first_fit()`
  returns `(-1, -1)`, `_return_equipped_to_grid` returns `false`, and the equip is refused — even though the
  swap is space-neutral, because the incoming item is about to vacate its own cells.
- **Action** — Reorder the swap so the incoming item's cells are freed before the outgoing item looks for space.
- **Location** — `apps/game/client/scripts/inventory/grid_inventory.gd` (`equip_from_index`,
  `_return_equipped_to_grid`)
- **Solution Hint** — Lift the incoming instance out of `slots` first, then attempt to place the previously
  equipped item; if that placement fails, put the incoming instance back at its original `(x, y)` and return
  `false`. Since the incoming item's rectangle was just vacated, a same-size or smaller outgoing item is
  guaranteed to fit, which is the common case.

### BUG-18 — Default `instanceId` collides for identically named items

- **Problem** — `_normalize_slot()` synthesises a missing `instanceId` as
  `"%s_%d" % [item_id, int(slot.get("rollSeed", slot.get("x", 0) + slot.get("y", 0)))]`. For any item without a
  roll seed the discriminator is `x + y`, so two `estus_flask` stacks at `(0,2)` and `(2,0)` receive
  `estus_flask_2` twice. `split_stack()` compounds this by minting `"%s_%d" % [instanceId, Time.get_ticks_msec()]`,
  which collides whenever two splits land in the same millisecond. Quick slots resolve by `instanceId`, so a
  collision silently rebinds the hotbar to a different stack.
- **Action** — Mint instance IDs from a single non-colliding source.
- **Location** — `apps/game/client/scripts/inventory/grid_inventory.gd` (`_normalize_slot`, `split_stack`)
- **Solution Hint** — Add a `static var _next_instance_ordinal := 1` to `GridInventory` and a
  `_mint_instance_id(item_id)` helper used by `_normalize_slot`, `split_stack` and `AffixRoller` alike.
  Persist the high-water mark in the save so IDs stay unique across sessions, and bump the save schema
  version with a migration step that re-mints duplicates found in existing saves (see `DOC-03` for the
  migration table that must be updated at the same time).

### BUG-19 — Shield stats are never applied: `Guard` is configured with two of three arguments

- **Problem** — `Guard.set_combat_stat_modifiers(equipment_stats, talent_stats, block_data)` reads
  `block_data["stability"]` and `block_data["reduction"]` to derive `_block_stability` and the shield's own
  damage reduction. The only caller,
  `InventoryService.apply_equipment_to_player_node()`, invokes it as
  `guard.set_combat_stat_modifiers(equip_stats, talent_stats)` — `block_data` defaults to `{}`. Every shield in
  the game therefore blocks at exactly the hardcoded `BLOCK_DAMAGE_REDUCTION = 0.55` with
  `_block_stability = 1.0`. Shield choice has no mechanical effect, which removes a whole axis of Soulslike
  build-crafting. Contrast the weapon path immediately above it, which *does* pass a third argument.
- **Action** — Resolve the equipped `secondary`/shield instance and pass its block profile.
- **Location** — `apps/game/client/scripts/inventory/inventory_service.gd`
  (`apply_equipment_to_player_node`); `apps/game/client/scripts/combat/guard.gd`
  (`set_combat_stat_modifiers`)
- **Solution Hint** — `var shield := inventory.get_equipped_instance("secondary")`, look its definition up in
  `ItemCatalog`, and pass `def.get("block", {})`. Author `stability` and `reduction` on the shield items in
  `content/items/equipment/` (only one item currently uses the `secondary` slot at all — see `IMP-F02`).
  While there, note that `set_combat_stat_modifiers` ignores its `equipment_stats` parameter entirely; either
  use it for a `blockReduction` equipment stat or drop the parameter.

### BUG-20 — Two contradictory "forward" conventions, in the same file

- **Problem** — `Locomotion.get_facing_direction()` returns `_facing.global_transform.basis.z`, i.e. this
  project treats the `Facing` node's **+Z** as forward. `Dodge._get_attack_backstep_direction()` and
  `DamageInfo.classify_arc()` follow that convention. But
  `PlayerCombatReactions._stagger_clip_for()` computes `var forward := -facing.global_transform.basis.z` —
  the opposite — while `_get_facing_forward()` **in the same file** goes through
  `get_facing_direction()` and gets +Z. Directional stagger animations are therefore played mirrored: a hit
  from behind plays `stagger_f`, a hit from the front plays `stagger_b`. The same `-basis.z` fallback appears in
  `Guard._get_block_facing()`, `WeaponController.get_attack_lunge_velocity()` and
  `PlayerCombatReactions._get_facing_forward()`; those are dormant only because `get_facing_direction()`
  always exists on the player and wins.
- **Action** — Pick one convention, state it once, and delete every ad-hoc fallback that contradicts it.
- **Location** — `apps/game/client/scripts/player/player_combat_reactions.gd` (`_stagger_clip_for`,
  `_get_facing_forward`); `apps/game/client/scripts/player/locomotion.gd` (`get_facing_direction`);
  `apps/game/client/scripts/combat/guard.gd` (`_get_block_facing`);
  `apps/game/client/scripts/combat/weapon_controller.gd` (`get_attack_lunge_velocity`);
  `apps/game/client/scripts/player/dodge.gd` (`_get_facing_forward`)
- **Solution Hint** — Add `static func forward_of(facing: Node3D) -> Vector3` to a small `CombatFacing`
  helper, document the +Z choice in one comment there, and route all five sites through it. This is a
  prerequisite for `IMP-A03` (backstab/riposte readability): directional reactions cannot be tuned while two
  conventions are live.

### BUG-21 — Blocking does not prevent a backstab multiplier

- **Problem** — `Hurtbox.receive_hit()` runs `_apply_arc_multipliers()` **after** `Guard.modify_incoming_hit()`
  and unconditionally. `Guard._is_frontal_hit()` decides frontality from `info.direction` (the attack's travel
  vector), while `DamageInfo.classify_arc()` decides it from `info.source.global_position` (the attacker's
  location). These disagree whenever the attacker's position and its attack vector diverge — a sweeping arc,
  a lunging attack, a projectile fired while strafing. The result is a hit that `Guard` accepts as frontal and
  reduces by 55 %, then `classify_arc` re-classifies as `BACK` and multiplies by `BACKSTAB_DAMAGE_MULT = 1.6`
  and `BACKSTAB_POISE_MULT = 2.0`. Players see blocked hits that stagger them.
- **Action** — Classify the hit arc once, before guard resolution, and feed the same arc to both.
- **Location** — `apps/game/client/scripts/combat/hurtbox.gd` (`receive_hit`, `_apply_arc_multipliers`);
  `apps/game/client/scripts/combat/guard.gd` (`_is_frontal_hit`);
  `apps/game/client/scripts/combat/damage_info.gd` (`classify_arc`)
- **Solution Hint** — Compute `var arc := DamageInfo.classify_arc(body, info.source.global_position)` at the
  top of `receive_hit`, store it on the `DamageResolution`, pass it into `modify_incoming_hit(info, arc)`, and
  have `_apply_arc_multipliers` consume the stored value. Then make the rule explicit: a successful block
  suppresses `SIDE`/`BACK` multipliers (you cannot be backstabbed through a raised shield) — or, if you want
  backstabs to beat shields, make that a deliberate design statement rather than an emergent disagreement.

### BUG-22 — Parry has no whiff cost, so tapping block is strictly better than holding it

- **Problem** — `Guard` opens a `PARRY_WINDOW = 0.18` s window on **entering** guard, and closes it on the
  timer. There is no cooldown, no stamina cost and no recovery on a failed parry: `_enter_guard()` is reachable
  the very next frame `PlayerInput.just_pressed(&"block")` fires. Mashing the block button therefore produces a
  near-continuous parry window at zero cost, while *holding* block — the intended defensive posture — has a
  parry window only in its first 0.18 s. The dominant strategy in the current build is to never hold guard.
  Meanwhile `try_parry_attack()` checks neither stamina nor exhaustion.
- **Action** — Give the parry attempt a cost and a recovery, and decouple it from guard entry.
- **Location** — `apps/game/client/scripts/combat/guard.gd` (`_enter_guard`, `try_parry_attack`,
  `_physics_process`)
- **Solution Hint** — Two viable shapes. (a) Souls-classic: bind parry to its own action, charge stamina on
  the attempt, and lock out guard for a whiff-recovery window (~0.4 s) if no attack lands inside the window.
  (b) Keep the tap-to-parry gesture but add `_parry_cooldown_timer` set on every `_enter_guard()`, plus a
  stamina charge, so mashing drains the bar. Either way, gate on `_stamina.consume()` so a parry attempt at
  low stamina is a real risk. See `IMP-A04` for how this interacts with the riposte window.

### BUG-23 — Hyperarmor only exists once the hitbox opens, so heavy attacks are always interrupted

- **Problem** — `WeaponController._hyperarmor_active` is assigned in `_enable_hitbox_for_attack()`, which runs
  at the **start of the ACTIVE phase**, and is cleared in `_disable_hitbox()` and `_end_attack()`. During
  `STARTUP` — the entire wind-up of a heavy attack or weapon art, 0.35 s for the fallback heavy — the player
  has no hyperarmor. In every Soulslike, poise on a committed heavy swing exists precisely to let it survive a
  chip hit during the wind-up. As written, any enemy that touches the player during wind-up staggers them and
  the heavy never comes out, which makes heavy attacks unusable against more than one enemy.
- **Action** — Arm hyperarmor when the attack starts, not when the hitbox opens.
- **Location** — `apps/game/client/scripts/combat/weapon_controller.gd` (`_start_attack`,
  `_enable_hitbox_for_attack`, `_disable_hitbox`, `_end_attack`)
- **Solution Hint** — Move the `_hyperarmor_active = bool(_current_attack.get("hyperarmor", false))` assignment
  into `_start_attack()`, and clear it at the start of `RECOVERY` rather than on hitbox close. Better still,
  express it as a window (`hyperarmor_start` / `hyperarmor_end` fractions of the attack, defaulting to
  "startup through active") so `content/weapons/*.json` can tune poise frames per swing — that is the same
  data-driven treatment `IMP-B01` asks for on the enemy side.

### BUG-24 — A staggered or dead enemy freezes in mid-air

- **Problem** — `CastleEnemyBase._physics_process()` returns early on both `is_dead()` and
  `_stagger_timer > 0.0`, **before** the `if not is_on_floor(): velocity += get_gravity() * delta` /
  `move_and_slide()` block at the bottom. An enemy staggered while airborne — knocked off a ledge, hit during
  a hop, spawned above the floor — stops in place and hangs there for the stagger duration. On death it hangs
  permanently until the corpse is freed.
- **Action** — Always integrate gravity and call `move_and_slide()`; gate only the AI on those states.
- **Location** — `apps/game/client/scripts/enemies/castle_enemy_base.gd` (`_physics_process`)
- **Solution Hint** — Restructure to a single exit: compute `var ai_enabled := not is_dead() and _stagger_timer <= 0.0`,
  run `_update_ai(delta)` and facing only when `ai_enabled`, zero the horizontal velocity when staggered, and
  fall through to gravity + `move_and_slide()` + `_update_diorama_animation()` in all cases.

### BUG-25 — Enemy combo follow-ups have no telegraph and bypass the attack-token budget

- **Problem** — `_end_attack()` chains into `combo_followups` by setting `_state = State.WINDUP` and
  `_state_timer` directly. It does not call `_show_attack_telegraph()`, does not call
  `AudioDirector.play_sfx("windup", …)`, and does not re-request an attack token — but it *does* call
  `_release_attack_token()` immediately before. A combo's second and third swings therefore arrive with no
  visual or audio tell (the one affordance a Soulslike owes the player) and are invisible to
  `AttackTokenService`, so three enemies can all be mid-combo while the budget believes two are attacking.
- **Action** — Route combo follow-ups through the same entry point as the first swing.
- **Location** — `apps/game/client/scripts/enemies/castle_enemy_base.gd` (`_end_attack`, `_start_windup`)
- **Solution Hint** — Extract the body of `_start_windup()` after attack selection into
  `_enter_windup(attack_data: Dictionary)` and call it from both places; keep the token held for the duration
  of the whole combo (release in `_process_recovery` when the chain actually ends) rather than per swing.
  Note this bug is currently *latent for content reasons*: no enemy JSON defines `combo_followups` at all
  (see `IMP-B01`), so the code path never runs. Fix it before authoring combos, not after.

### BUG-26 — Token-starved enemies re-request an attack token every physics frame

- **Problem** — `_start_windup()` calls `_select_attack_data()`, then `AttackTokenService.request_token()`, and
  `return`s if the token is refused — without setting `_cooldown` or changing `_state`. The enemy is still in
  `CHASE`, `_can_attack()` is still true next frame, so `_process_chase` calls `_start_windup()` again
  immediately. With four enemies around the player and a two-token budget, two enemies re-run attack selection
  and a dictionary lookup 60 times a second, indefinitely, and stand perfectly still while doing it (see
  `IMP-B03`).
- **Action** — Back off on refusal.
- **Location** — `apps/game/client/scripts/enemies/castle_enemy_base.gd` (`_start_windup`,
  `_process_chase`); `apps/game/client/scripts/combat/attack_token_service.gd`
- **Solution Hint** — On refusal set `_cooldown = randf_range(0.25, 0.6)` (jittered so the queue does not
  synchronise) and switch to a `CIRCLE`/`REPOSITION` state rather than standing at `stop_range`. Move the
  `_select_attack_data()` call to *after* the token is granted so a refused attempt costs nothing.

### BUG-27 — `Engine.time_scale` and screen saturation can be left permanently modified by the death sequence

- **Problem** — `PlayerCombatReactions._run_death_sequence()` sets `Engine.time_scale = DEATH_SLOW_SCALE`
  (0.35) and then `await`s three `get_tree().create_timer(...)` calls before restoring it and before setting
  `PixelDioramaSettings.screen_saturation`. `SceneTreeTimer` is itself scaled by `Engine.time_scale`, so the
  0.60 s slow-motion beat actually lasts ~1.7 s of wall time and the full sequence ~6 s. More seriously, if the
  scene changes during any of those awaits — the player opens the pause menu and quits to hub, a floor
  transition is in flight, `RunFlow` force-ends the run — the coroutine's node is freed, the restore lines
  never execute, and the **entire game** stays at 0.35 speed and 0.25 saturation until the process restarts.
  `reset_combat_state()` restores both, but it is only called on revive, not on quit.
- **Action** — Make the restore unconditional, and make the timers ignore the time scale they set.
- **Location** — `apps/game/client/scripts/player/player_combat_reactions.gd` (`_run_death_sequence`,
  `reset_combat_state`)
- **Solution Hint** — Use `get_tree().create_timer(t, true, false, true)` (the fourth argument is
  `ignore_time_scale`) so the beats have the intended wall-clock length. Wrap the restore in
  `_exit_tree()` / a `tree_exiting` connection so `Engine.time_scale = 1.0` and the saved saturation are
  reapplied on teardown no matter how the sequence is interrupted. Best of all, drive the sequence from a
  `Tween` owned by the node — Godot cancels a node's tweens when it leaves the tree, which converts this from
  a manual-cleanup problem into a structural guarantee.

### BUG-28 — `DialogueRunner` recurses without a visited set, so a cyclic tree overflows the stack

- **Problem** — `_advance_to_node()` calls itself for `fallback` nodes and for `auto` nodes with a `next`
  target. Nothing tracks which nodes have been visited during a single advance. A dialogue whose `next` chain
  loops (`a → b → a`, both `auto`), or whose `fallback` chain loops, recurses until GDScript's stack limit is
  hit and the game crashes. Authored content is the only thing preventing this today, and content authoring is
  exactly what `IMP-G02` asks to scale up.
- **Action** — Convert the recursion to a bounded loop with a visited set.
- **Location** — `apps/game/client/scripts/dialogue/dialogue_runner.gd` (`_advance_to_node`)
- **Solution Hint** — `while true:` with `var visited: Dictionary = {}`; `if visited.has(node_id): push_error(...)
  ; end_dialogue(); return`. Add a content-validation rule in `scripts/validate-content` that walks each
  dialogue graph and fails the build on an auto-cycle, so the error is caught at authoring time rather than at
  runtime.

### BUG-29 — An unrecognised dialogue condition key silently hides content

- **Problem** — `DialogueConditions.evaluate()` ends with `push_warning(...)` and `return false`. A misspelled
  key (`"minLvl"`, `"questState"`, `"hasItem"` — the last of which is not implemented at all) makes the
  condition evaluate to **false**, so the node or choice simply does not appear. The warning goes to the Godot
  log, which players never see and which CI does not fail on. The failure mode is "a quest branch quietly does
  not exist", which is the hardest possible content bug to notice.
- **Action** — Fail loudly at authoring time and fail *open* at runtime.
- **Location** — `apps/game/client/scripts/dialogue/dialogue_conditions.gd` (`evaluate`)
- **Solution Hint** — Keep a `const KNOWN_KEYS` set; in a debug build `assert()` on an unknown key, in a
  release build return `true` with a warning so content degrades to visible rather than invisible. Add the
  same key whitelist to the content JSON schema in `content/schemas/` so `npm run validate` rejects typos
  before they ship. The condition vocabulary is also thin for the quest design in `IMP-G03` — there is no
  item-possession, no biome, no dungeon-cleared and no difficulty-tier predicate.

### BUG-30 — `DungeonBuilder`'s static floor cache is never trimmed, so endless runs leak

- **Problem** — `RunFlow._stash_current_floor_in_cache()` and `_set_current_floor_cache()` both write to two
  caches: the instance-level `floor_definitions`, which `_trim_floor_cache()` bounds to `MAX_CACHED_FLOORS`,
  and the **static** `DungeonBuilder._floor_definition_cache`, which has no eviction at all — only
  `clear_floor_cache()`, called at run start and run end. An endless run holds every floor definition it has
  ever generated in memory. `_persist_active_run()` compounds this: `_cleared_floors`, `_loot_collected` and
  `_loot_claimed_instance_ids` are unbounded arrays that are `duplicate()`d into the active-run snapshot and
  written to disk on every autosave, so both RAM and save size grow linearly with floor count in the one mode
  designed to be played forever.
- **Action** — Bound the static cache the same way the instance cache is bounded, and bound the run-history
  arrays.
- **Location** — `apps/game/client/scripts/app/run_flow.gd` (`_stash_current_floor_in_cache`,
  `_set_current_floor_cache`, `_trim_floor_cache`, `_persist_active_run`);
  `apps/game/client/scripts/dungeon/dungeon_builder.gd` (`store_floor_cache`, `_floor_definition_cache`)
- **Solution Hint** — Move the eviction policy into `DungeonBuilder.store_floor_cache()` so there is exactly
  one place that decides what is cached, and have `RunFlow` stop keeping a parallel dictionary (this is also
  `REF-11`). For run history, `_cleared_floors` can be a high-water integer in endless mode rather than a set,
  and `_loot_collected` / `_loot_claimed_instance_ids` should be capped ring buffers — the results screen only
  reads the tail. Measure with a scripted 500-floor endless run before and after.

### BUG-31 — `Poise`, `Stamina`, `Health` and `StatusController` regenerate in `_process`, so balance is frame-rate dependent

- **Problem** — `Poise._process()` and `Stamina._process()` advance regeneration timers and integrate regen
  rates using the **render** delta, while all damage, stamina consumption and poise damage are applied from
  `_physics_process` at a fixed 60 Hz. On a 144 Hz display the regen loop runs 2.4× more often with
  proportionally smaller deltas — which is mathematically equivalent for a linear rate, but *not* for the
  threshold logic layered on top: `_regen_timer > 0.0: return` means the delay consumes a variable number of
  frames, `_exhausted and current >= EXHAUSTION_RECOVERY` flips at a different point in the frame relative to
  `consume()`, and the `poise_changed` / `stamina_changed` signals fire at display rate rather than tick rate,
  driving `PERF-10`'s HUD work. During slow-motion (`Engine.time_scale = 0.35` in the death sequence) the two
  clocks diverge outright.
- **Action** — Move all combat-resource simulation to `_physics_process`.
- **Location** — `apps/game/client/scripts/combat/poise.gd` (`_process`);
  `apps/game/client/scripts/combat/stamina.gd` (`_process`);
  `apps/game/client/scripts/combat/statuses/status_controller.gd`
- **Solution Hint** — Rename to `_physics_process` and call `set_process(false)` in `_ready`. Then throttle the
  change signals: emit at most once per tick and only when the value crosses a visible threshold, which
  removes most of the HUD churn in `PERF-10`. A validation test that runs 600 fixed ticks and asserts an exact
  stamina total is cheap to write once the loop is deterministic.

### BUG-32 — `Stamina.insufficient` fires every frame while sprinting on empty

- **Problem** — `Locomotion._physics_process()` calls `_stamina.drain(SPRINT_STAMINA_DRAIN * delta)` every
  frame the sprint key is held. `drain()` emits `insufficient` on every refusal. Holding sprint with an empty
  bar therefore emits 60 signals a second; any HUD element or audio cue bound to `insufficient` flashes or
  stutters continuously.
- **Action** — Rate-limit the signal, and stop asking once the answer is known.
- **Location** — `apps/game/client/scripts/combat/stamina.gd` (`drain`, `consume`);
  `apps/game/client/scripts/player/locomotion.gd` (`_physics_process`)
- **Solution Hint** — Guard the emit with a short `_insufficient_cooldown` (0.4 s is enough to read as one
  cue), or emit only on the transition into insufficiency. Separately: `drain()` and `consume()` are
  byte-identical duplicates — see `REF-09`.

### BUG-33 — Endless mode never changes biome

- **Problem** — `RunFlow.start_endless_run()` calls `_start_mode_run(RM.MODE_ENDLESS, BiomeRegistry.BIOME_UMBRAL, …)`
  and `_resolve_floor_definition()` generates every subsequent floor with the unchanged `current_biome_id`.
  There is no rotation, no biome schedule and no biome-change transition anywhere in the endless path. An
  endless run is therefore floor 1 to floor 999,999 in `umbral_chapel`, with the same enemy pool, the same
  boss pool, the same trap pool, the same materials, the same lighting and the same audio profile, forever.
  This is a direct contradiction of the intended design (10–20 floors per biome, rotating endlessly), and it
  is also the single largest replayability loss in the build.
- **Action** — Introduce a seeded biome schedule for endless runs.
- **Location** — `apps/game/client/scripts/app/run_flow.gd` (`start_endless_run`,
  `_resolve_floor_definition`, `_transition_floor`); `apps/game/client/scripts/dungeon/biome_registry.gd`
- **Solution Hint** — See `IMP-D01` for the full design. Minimally: a
  `static func biome_for_floor(run_seed: int, floor_index: int) -> String` that partitions the floor axis into
  seeded 10–20-floor segments and draws biomes without immediate repeats, called from `_resolve_floor_definition`
  instead of reading `current_biome_id`. Because it is a pure function of `(seed, floor)` it stays deterministic
  across save/load and across a floor skip that jumps straight to floor 501.

### BUG-34 — The 250-floor skip does not exist

- **Problem** — `SkipFloorService.SKIP_ITEMS` defines exactly four entries — `skip_10_floors` (start 11),
  `skip_50_floors` (51), `skip_100_floors` (101) and `skip_500_floors` (501). The intended ladder is
  10 / 50 / 100 / **250** / 500. `content/loot/global_drops.json` and the endless menu are both driven off this
  dictionary, so the missing tier leaves a 5× gap between the 100 and 500 rungs — the point in the curve where
  a player who has ground out a few hundred floors has nothing to spend.
- **Action** — Add the missing rung end to end.
- **Location** — `apps/game/client/scripts/dungeon/skip_floor_service.gd` (`SKIP_ITEMS`);
  `content/loot/global_drops.json`; `content/items/consumables/`
- **Solution Hint** — Add `"skip_250_floors": 251`, author the consumable item JSON alongside the existing four
  (it must carry `consumableEffect.kind = "skipFloors"` so `ConsumableService.can_use` keeps routing it to the
  portal rather than to direct use), and give it a drop chance between the 100 and 500 entries. Also
  fix the presentation bug in the same feature: `umbral_endless_menu._build_skip_buttons()` labels buttons with
  the raw item id (`"Use skip_10_floors → floor 11"`) instead of `ItemCatalog.get_definition(id).name`.

### BUG-35 — Enemy patrol and wind-up variance use the global RNG, breaking seed determinism

- **Problem** — `CastleEnemyBase._process_patrol()` calls `randf_range(1.0, 2.5)` for patrol waits and
  `_start_windup()` calls `randf_range(-windup_variance, windup_variance)`. Both use Godot's global RNG, which
  is not seeded from the run seed. Two players entering the same seed get identical layouts and identical
  spawns but different enemy behaviour, and the same is true for a save reloaded mid-floor. This undermines the
  seed-sharing promise the dungeon seed service is built around (`DungeonSeedService`, `FloorSeedMix`) and makes
  `FEAT-06` (deterministic replay) unimplementable.
- **Action** — Give every enemy a run-derived RNG stream.
- **Location** — `apps/game/client/scripts/enemies/castle_enemy_base.gd` (`_process_patrol`,
  `_start_windup`); `apps/game/client/scripts/dungeon/procgen/procgen_rng.gd`
- **Solution Hint** — Seed a per-enemy `RandomNumberGenerator` in `_ready()` from
  `FloorSeedMix.mix(RunFlow.current_seed, floor) ^ hash(spawn_anchor_id)` and use it for every gameplay roll.
  Reserve the global RNG strictly for cosmetics (VFX jitter, particle lifetimes) and say so in a comment, so the
  distinction survives future edits.

### BUG-36 — `RunFloorConfig.max_secrets_for_biome()` re-reads and re-parses a JSON file on every call

- **Problem** — `max_secrets_for_biome()` calls `ContentLoader.load_json("content/biomes/%s.json" % biome_id)`
  directly rather than going through `BiomeRegistry.get_biome()`, which is the cached accessor. It therefore
  bypasses `BiomeRegistry._cache` and hits `PERF-07`'s uncached-load path. The same pattern appears in
  `DungeonCatalog.get_display_name()`, which loads the biome JSON on every call just to read `name` — and that
  function is called once per dropdown row every time the castle entry menu is opened.
- **Action** — Route every biome read through the cached registry.
- **Location** — `apps/game/client/scripts/dungeon/run_floor_config.gd` (`max_secrets_for_biome`);
  `apps/game/client/scripts/dungeon/dungeon_catalog.gd` (`get_display_name`)
- **Solution Hint** — Replace both with `BiomeRegistry.get_biome(biome_id)`. Then grep for
  `load_json("content/biomes` across the tree and eliminate the rest; the registry should be the only caller.

### BUG-37 — `_m6_strict_orphan_item` is a test fixture shipped in production content

- **Problem** — `content/items/equipment/_m6_strict_orphan_item.json` exists solely so
  `scripts/validation/suites/m6_suite.gd` can assert that the strict catalog check notices an item that is not
  registered in `content/items/catalog.json`. It is the only item file absent from the catalog. It is inside
  the exported content tree, so it ships to players, and any code that enumerates the equipment directory
  (rather than the catalog) will pick it up as a real item.
- **Action** — Move the fixture out of the shipping content root.
- **Location** — `content/items/equipment/_m6_strict_orphan_item.json`;
  `apps/game/client/scripts/validation/suites/m6_suite.gd`
- **Solution Hint** — `content/fixtures/` already exists for exactly this purpose and already holds eleven
  files. Move it there, point the suite at the new path, and add an export `exclude_filter` for
  `content/fixtures/*` (see `PERF-06b`, which proposes the same mechanism for stale audio).

### BUG-38 — The castle entry menu discards the player's dungeon selection every time it opens

- **Problem** — `CastleEntryMenu.open_menu()` calls `_build_dungeon_dropdown()`, which ends with
  `_dungeon_dropdown.select(0)` and `_selected_dungeon = <first entry>`. A player who has unlocked all ten
  dungeons and wants to re-run the ninth must re-select it every single time they walk up to the portal,
  including immediately after finishing a run in it. `_build_difficulty_dropdown()` has the same reset.
- **Action** — Persist and restore the last selection.
- **Location** — `apps/game/client/scripts/ui/castle_entry_menu.gd` (`_build_dungeon_dropdown`,
  `_build_difficulty_dropdown`, `open_menu`)
- **Solution Hint** — Store the last chosen `(dungeon_id, difficulty_tier)` in `CharacterService` flags, and
  after rebuilding the dropdown select the matching index if it is still unlocked, falling back to index 0
  otherwise. This is small, but it is felt on literally every run start — see `IMP-C03` for the wider
  tier-selection redesign it belongs to.

### BUG-39 — A second hit during hit-stop locks the whole game at 8 % speed, permanently

- **Problem** — `HitFeedback._apply_hitstop()` caches the scale to restore with
  `if Engine.time_scale >= HITSTOP_TIME_SCALE: _hitstop_restore_scale = Engine.time_scale`, then sets
  `Engine.time_scale = HITSTOP_TIME_SCALE` (0.08). The comparison is `>=`, not `>`. On the **first** hit
  `Engine.time_scale` is 1.0, so 1.0 is cached and the restore is correct. On a **second** hit that lands
  while the first hit-stop is still running, `Engine.time_scale` is already 0.08, `0.08 >= 0.08` is true, and
  the frozen value is cached as the restore target. When the timer expires, `_process()` sets
  `Engine.time_scale = 0.08` — and every subsequent hit re-caches 0.08. The entire game runs at 8 % speed for
  the rest of the session. The only code that ever resets it is
  `PlayerCombatReactions.reset_combat_state()`, which runs on revive. Two hits in a 0.09 s window is not an
  edge case: it is a combo, a multi-enemy fight, or a single swing that hits two enemies.
- **Action** — Change the comparison to `>`, and make the restore target a single owned value rather than a
  re-read of the global.
- **Location** — `apps/game/client/scripts/combat/hit_feedback.gd` (`_apply_hitstop`, `_process`,
  `_hitstop_restore_scale`, `HITSTOP_TIME_SCALE`)
- **Solution Hint** — The immediate fix is `if Engine.time_scale > HITSTOP_TIME_SCALE:`. The durable fix is
  `BUG-41`: one owner for `Engine.time_scale`, which cannot be corrupted by a nested request because nesting
  becomes refcounted rather than save/restore. `VfxService.request_hitstop()` already has the correct guard
  shape (`if _hitstop_until_ms <= now_ms`) — it caches only when no hit-stop is in flight — so the two
  implementations disagree about the same problem, which is itself the argument for consolidating them.

### BUG-40 — Hit-stop lasts twelve times longer than authored, because its timer runs on scaled time

- **Problem** — `HitFeedback._process(delta)` decrements `_hitstop_timer` by `delta`, and `_process`'s delta
  **is scaled by `Engine.time_scale`**. Hit-stop sets the scale to 0.08 and then measures its own duration in
  that slowed clock, so the authored `DEFAULT_HITSTOP = 0.09` s elapses after `0.09 / 0.08 ≈ 1.13` s of real
  time. Every connecting hit freezes the game for over a second. The same applies to `_anim_hitstop_timer`.
  `preview_hitstop_duration()` returns the authored value, so anything that reasons about the length — tests,
  tuning, the accessibility slider — sees 0.09 while the player experiences 1.13.
- **Action** — Measure hit-stop in unscaled wall time.
- **Location** — `apps/game/client/scripts/combat/hit_feedback.gd` (`_process`, `_apply_hitstop`,
  `preview_hitstop_duration`); `apps/game/client/scripts/art/vfx/vfx_service.gd` (`request_hitstop`,
  `_update_hitstop`)
- **Solution Hint** — Use `Time.get_ticks_msec()` deadlines exactly as `VfxService._update_hitstop()` already
  does, or divide the decrement by `Engine.time_scale`. Then re-tune: with the bug fixed, 0.09 s of true
  hit-stop at 0.08 scale is a strong, snappy impact, and the weight curve
  (`clampf(damage / 20.0, 0.85, 1.35)`) becomes meaningful instead of scaling an already-broken duration.
  This is the single change that will most alter how the game *feels* — see the correction note in `IMP-A05`.

### BUG-41 — Three components own `Engine.time_scale` independently, with three restore caches

- **Problem** — `HitFeedback` (per character, so one instance per player *and* per enemy),
  `VfxService` (autoload, `request_hitstop`) and `PlayerCombatReactions` (`_run_death_sequence`, sets 0.35)
  all write `Engine.time_scale` and all keep their own idea of what to restore it to. There is no arbitration.
  A hit-stop that begins during the death slow-motion captures 0.35 as "normal"; a `VfxService` hit-stop that
  ends while a `HitFeedback` hit-stop is still running restores full speed mid-freeze; an enemy's
  `HitFeedback` and the player's `HitFeedback` race each other every time a trade happens. `BUG-39` and
  `BUG-27` are both symptoms of this one structural problem.
- **Action** — Give `Engine.time_scale` exactly one owner with a stacked/refcounted request API.
- **Location** — `apps/game/client/scripts/combat/hit_feedback.gd` (`_apply_hitstop`, `_process`);
  `apps/game/client/scripts/art/vfx/vfx_service.gd` (`request_hitstop`, `_update_hitstop`);
  `apps/game/client/scripts/player/player_combat_reactions.gd` (`_run_death_sequence`,
  `reset_combat_state`)
- **Solution Hint** — `VfxService` is already an autoload and already has the better implementation; make it
  the sole owner. Expose `push_time_scale(id: StringName, scale: float, duration_ms: int)` and
  `release_time_scale(id)`, apply the **minimum** of all active requests, and restore to 1.0 when the stack
  empties. `HitFeedback` and the death sequence become callers. A `_notification(NOTIFICATION_WM_CLOSE_REQUEST)`
  and a scene-change hook that clears the stack removes the "left permanently slow" class of failure entirely.

### BUG-42 — `goldFind` is applied to refunds, which makes failed purchases a money printer

- **Problem** — `CharacterService.add_gold()` multiplies every incoming amount by the player's `goldFind`
  talent bonus. It is the only way to add gold, so it is also used for **refunds**:
  `MerchantService.buy_item()` calls `CharacterService.add_gold(price)` on all three failure paths
  (out of stock, inventory full, item not sold here), and `BlacksmithService.unlock_item()` calls
  `add_coins(cost)` (which forwards to `add_gold`) when the inventory is full. With any `goldFind` invested,
  a player who fills their inventory and then repeatedly attempts to buy the most expensive stocked item
  gains `price * goldFind` every attempt, indefinitely. Given `IMP-F01` (the bag fills after six items), the
  precondition is not obscure — it is the default state.
- **Action** — Separate "earn gold" from "credit gold", and apply the bonus only to the former.
- **Location** — `apps/game/client/scripts/save/character_service.gd` (`add_gold`, `add_coins`);
  `apps/game/client/scripts/hub/merchant_service.gd` (`buy_item`);
  `apps/game/client/scripts/hub/blacksmith_service.gd` (`unlock_item`)
- **Solution Hint** — `add_gold(amount, apply_bonus: bool = true)`, with every refund and every save-restore
  path passing `false`. Better still, invert the responsibility: have the *earning* sites
  (`_award_kill_coins`, quest rewards, sell) call `award_gold()` which applies the bonus, and make
  `add_gold()` a plain credit. The transactional shape in `BUG-43` fixes the refunds at the same time.

### BUG-43 — A failed unlock refunds the gold but keeps the recipe

- **Problem** — `BlacksmithService.unlock_item()` performs four steps in order: `spend_coins(cost)`,
  `LocalSave.add_owned_recipe(recipe_id)`, `InventoryService.add_item(item_id, 1)`, and — if the add fails —
  `CharacterService.add_coins(cost)` plus an error return. The recipe is **not** rolled back. The player gets
  their gold back (plus the `goldFind` bonus, per `BUG-42`) and keeps the permanent unlock, so
  `is_unlocked()` now returns true for an item they never received and can never buy again through this path.
  The same non-transactional shape appears in `MerchantService.buy_item()`, which spends gold before checking
  stock and inventory space.
- **Action** — Validate everything, then commit; never partially commit and refund.
- **Location** — `apps/game/client/scripts/hub/blacksmith_service.gd` (`unlock_item`, `can_unlock`);
  `apps/game/client/scripts/hub/merchant_service.gd` (`buy_item`)
- **Solution Hint** — Reorder to: check affordability → check `has_space_for(item_id)` → check stock →
  perform the add → spend the gold → record the recipe/purchase. Every check is already implemented
  (`GridInventory.has_space_for`, `get_available_stock`), they are just called in the wrong order. Note that
  `can_unlock()` already runs the affordability and level checks, so `unlock_item()` re-running them is
  cheap; the missing check is the inventory-space one.

### BUG-44 — Closing the map overlay unpauses the game underneath any other open menu

- **Problem** — `CombatHUD._open_map_overlay()` sets `get_tree().paused = true` and
  `Input.mouse_mode = MOUSE_MODE_VISIBLE`; `_close_map_overlay()` sets `paused = false` and
  `mouse_mode = MOUSE_MODE_CAPTURED` **unconditionally**, without recording what the state was on entry.
  `StairMenu` in the same codebase does this correctly (`_was_paused = get_tree().paused` on open,
  `get_tree().paused = _was_paused` on close). So opening the map from the stair menu — or from any state that
  was already paused — and then closing it resumes the game and captures the mouse while a modal is still up.
  `PauseMenu.close_menu()` has the same unconditional `paused = false`. Four components write
  `get_tree().paused` and 33 sites write `Input.mouse_mode`.
- **Action** — Route pause and mouse-mode ownership through `MenuStack`, which already tracks modal depth.
- **Location** — `apps/game/client/scripts/ui/combat_hud.gd` (`_open_map_overlay`, `_close_map_overlay`);
  `apps/game/client/scripts/ui/pause_menu.gd` (`open_menu`, `close_menu`);
  `apps/game/client/scripts/ui/stair_menu.gd` (`open_menu`, `close_menu`);
  `apps/game/client/scripts/ui/menu_stack.gd` (`push`, `pop`, `depth`)
- **Solution Hint** — `MenuStack` already saves and restores `Input.mouse_mode` around the first push and
  the last pop; extend it to own `get_tree().paused` the same way, and have every modal — including the map
  overlay, which currently bypasses `MenuStack` entirely — push and pop instead of writing the globals. This
  is the concrete, player-visible instance of `REF-08`.

### BUG-45 — Crit rolls, enemy attack selection and waves seeds all use the unseeded global RNG

- **Problem** — Extending `BUG-35`, four more gameplay-affecting rolls bypass any seeded stream:
  `Hitbox._try_hit` rolls crits with `randf() < _crit_chance`;
  `CastleEnemyBase._select_attack_data()` picks `attacks[randi() % attacks.size()]`;
  `CastleEnemyBase._pick_patrol_target()` offsets with `randf_range`;
  `FinalBossForgottenCastle` places arena traps with `randf_range`; and
  `WavesRunService` seeds an entire run with `_run_seed = randi_range(1, 2_147_483_646)`, so waves runs
  cannot be reproduced or shared at all. Crit damage in particular means two players on the same seed take
  and deal different damage, which makes the seed-sharing feature (`DungeonSeedService`, `FloorSeedMix`) and
  `FEAT-06` (deterministic replay) unachievable.
- **Action** — Route every gameplay roll through a run-derived stream; reserve the global RNG for cosmetics.
- **Location** — `apps/game/client/scripts/combat/hitbox.gd` (`_try_hit`);
  `apps/game/client/scripts/enemies/castle_enemy_base.gd` (`_select_attack_data`, `_pick_patrol_target`);
  `apps/game/client/scripts/enemies/final_boss_forgotten_castle.gd`;
  `apps/game/client/scripts/dungeon/waves_run_service.gd`;
  `apps/game/client/scripts/dungeon/procgen/procgen_rng.gd`
- **Solution Hint** — `procgen_rng.gd` already exists as the seeded-stream helper. Add a
  `RunRng.stream(name: StringName) -> RandomNumberGenerator` that derives a substream from
  `RunFlow.current_seed` per concern (`&"crit"`, `&"enemy_ai"`, `&"loot"`) so consuming one does not shift
  the others. For waves, take the seed from `RunFlow` like the other modes rather than minting a fresh one.
  Add a validation assertion that greps for bare `randf(`/`randi(` outside `scripts/art/` and fails —
  this is the rare case where `QA-01`'s source-text assertion style is the right tool.

### BUG-46 — Sell price adds raw affix values, so pricing is scale-blind and exploitable

- **Problem** — `MerchantService.get_slot_unit_sell_price()` finishes with
  `for affix in slot.get("affixes", []): price += int(round(float(affix.get("value", 0.0))))`. Affix values
  are in the unit of whatever stat they modify: `critChance` is a fraction (`0.05` → `+0`), `maxHealth` is
  points (`40` → `+40`), `staminaRegen` is a multiplier (`0.15` → `+0`). So a legendary with three
  percentage-based affixes sells for less than a common with one flat-health affix, and any affix with a
  large raw value inflates price without regard to rarity or usefulness. The rarity multiplier and upgrade
  multiplier applied just above it are the parts that were designed; this line is not.
- **Action** — Price affixes from their rarity tier, not from their raw numeric value.
- **Location** — `apps/game/client/scripts/hub/merchant_service.gd` (`get_slot_unit_sell_price`);
  `apps/game/client/scripts/loot/affix_roller.gd` (`_roll_tier_value`); `content/affixes/*.json`
- **Solution Hint** — Give each affix a `value` band per rarity in its definition (the `tiers` object already
  exists) and price a rolled affix by `tier_index(rarity) * base_affix_price`, optionally scaled by where in
  the band the roll landed. That makes an item's price a function of how good the roll was, which is what a
  player expects, and removes the unit mismatch entirely. Fold this into `IMP-F02`'s affix expansion.

### BUG-47 — `crystal_sovereign.json` is an orphan duplicate of `boss_crystal_sovereign.json`

- **Problem** — `content/bosses/` holds both `boss_crystal_sovereign` (hp 580) and `crystal_sovereign`
  (hp 650), two definitions of the same fight with different numbers. No biome's `bossPool` or `enemyPool`
  references `crystal_sovereign`; only `boss_crystal_sovereign` is reachable. `EnemyCatalog.LEGACY_ALIASES`
  documents exactly this pattern for a third case (`castle_knight` → `boss_castle_knight`) but does not
  cover this one, so the orphan is loaded into `_definitions` and is live to anything that resolves by id.
  `scripts/bosses/crystal_sovereign.gd` exists alongside it, making it unclear which is authoritative.
- **Action** — Delete the orphan or alias it, and add a validation rule that every boss definition is
  referenced by at least one pool.
- **Location** — `content/bosses/crystal_sovereign.json`; `content/bosses/swamp_hydra.json`;
  `apps/game/client/scripts/content/enemy_catalog.gd` (`LEGACY_ALIASES`);
  `apps/game/client/scripts/bosses/crystal_sovereign.gd`
- **Solution Hint** — Confirm which of the two is the tuned one, keep it, and add
  `"crystal_sovereign": "boss_crystal_sovereign"` to `LEGACY_ALIASES` so any existing save or content
  reference still resolves. Then extend `scripts/validate-content` with a reachability check across
  `enemyPool` / `bossPool` / `trapPool` — the same check would have caught `BUG-37`.

### BUG-48 — `CharacterService` restores gold as `max(gold, coins)` from two save fields

- **Problem** — `apply_save()` reads `saved_gold = data.get("gold", …)` and
  `saved_coins = data.get("coins", saved_gold)`, then sets `gold = maxi(saved_gold, int(saved_coins))`.
  Two fields describe one quantity, and the reconciliation rule is "whichever is larger wins". A save written
  by an older build with a stale `coins` field, or any partial write that leaves the two out of step, silently
  grants the player the higher balance. There is no migration step that collapses the two (see the
  `SaveMigrator.STEPS` table), so both keep being read forever.
- **Action** — Collapse to one field with a migration, and stop writing the other.
- **Location** — `apps/game/client/scripts/save/character_service.gd` (`apply_save`, `to_save`);
  `apps/game/client/scripts/save/save_migrator.gd` (`STEPS`, `CURRENT_VERSION`)
- **Solution Hint** — Add a migration step that sets `gold = coins` when only `coins` is present, erases
  `coins`, and bumps `CURRENT_VERSION`. Then read `gold` alone. `REF-15` removes the duplicate runtime API
  that made two fields plausible in the first place.

### BUG-49 — The backend returns raw exception messages to API clients

- **Problem** — `RunService.CreateRunAsync()` wraps generation in
  `catch (Exception ex) { return new CreateRunResult(false, Error: ex.Message); }`, and the endpoint surfaces
  `Error` to the caller. Any generator failure — a null reference, a key-not-found, a path in a stack-derived
  message — is returned verbatim over HTTP. This leaks internal structure to unauthenticated-adjacent callers
  and produces error strings no client can branch on.
- **Action** — Return a stable error code, log the exception server-side.
- **Location** — `services/backend/src/Aumbrye.Application/Services/RunService.cs` (`CreateRunAsync`);
  `services/backend/src/Aumbrye.Api/ProblemResults.cs`
- **Solution Hint** — `ProblemResults.cs` already exists as the shared error shape. Return a
  `generation_failed` problem with a correlation id, and `ILogger.LogError(ex, …)` the detail. Catch the
  specific exception types the generator can throw rather than `Exception`, so genuinely unexpected failures
  still surface as 500s rather than being flattened into a 400-shaped result.

### BUG-50 — `MenuStack`'s focus stack desynchronises when modals close out of order

- **Problem** — `push()` appends the current focus owner to `_focus_stack` and `pop()` pops the **last**
  entry regardless of which modal was removed: `pop()` finds the modal by index in `_stack`, removes it from
  there, and then unconditionally does `_focus_stack.pop_back()`. If a modal lower in the stack closes first
  — which `PauseMenu._on_closed()` and the various `close_menu()` paths make reachable, since they call
  `MenuStack.pop(self)` without checking they are on top — focus is restored to the wrong control, and the
  two arrays drift apart for the remainder of the session.
- **Action** — Key the saved focus to the modal, not to stack position.
- **Location** — `apps/game/client/scripts/ui/menu_stack.gd` (`push`, `pop`, `_focus_stack`)
- **Solution Hint** — Replace the parallel array with a `Dictionary` keyed by the modal's instance id, or
  store the focus owner as an entry on a single stack of `{modal, focus}` records and remove by index.
  Combine with `BUG-44`: once `MenuStack` also owns pause and mouse mode, all three pieces of restore state
  live in one record and cannot drift independently.

### BUG-51 — The online generator has no concept of floors, so it can only ever produce floor 1

- **Problem** — `RunService.GenerationSeedFor(run)` is
  `DungeonSeedDeriver.GenerationSeed(run.Seed, run.Tier, 1)` — the floor argument is the literal `1`, and the
  `Run` entity has no floor column. `GetDungeonDefinitionAsync()` therefore regenerates floor 1 for every
  request, whatever floor the client is on. The client models 10 floors in castle mode and unbounded floors in
  endless mode (`RunFloorConfig`), and mixes the floor into its own seed via `FloorSeedMix`. The two
  generators are not merely duplicated (`REF-02`) — their **contracts disagree**. This is currently masked
  because `RunFlow.USE_ONLINE_PROCGEN` is `false`, so the online path is dead in the shipped client.
- **Action** — Either add floors to the server contract or delete the server generator.
- **Location** — `services/backend/src/Aumbrye.Application/Services/RunService.cs` (`GenerationSeedFor`,
  `CreateRunAsync`, `GetDungeonDefinitionAsync`); `services/backend/src/Aumbrye.Domain/Entities/Run.cs`;
  `packages/procedural/`; `apps/game/client/scripts/app/run_flow.gd` (`USE_ONLINE_PROCGEN`)
- **Solution Hint** — This is the decision `REF-02` asks for, made concrete. If the server generator stays,
  add `floor` to the route (`GET /runs/{id}/dungeon?floor=N`), persist the reached floor on `Run`, and mirror
  `FloorSeedMix` exactly — with a cross-language parity test, because a silent divergence here desynchronises
  every client. If it goes, deleting `packages/procedural` and the run endpoints removes an entire language's
  worth of duplicated logic and the parity burden with it. Given the client ships offline-first and the flag
  has been false, deleting is the cheaper answer.

### BUG-52 — Class perks are authored, named, localised — and never read by any code

- **Problem** — Each of the five class definitions declares `perk` (`bloodrage`, `steadfast`, `shadowstep`,
  `bulwark`, `arcane_focus`), `perkName` and `perkDescription`, with translation keys for all of them. A grep
  for `perk`, and for each of the five perk ids, across every non-validation script returns **nothing** —
  `ClassCatalog` does not expose a `get_perk()`, and no consumer looks one up. The classes are presented to
  the player with a named signature ability that does not exist. Mechanically, the five classes differ only by
  `statBonuses` (two stats each), `startingWeaponItemId` and `allowedWeapons` — and `allowedWeapons` is
  effectively unenforced (`BUG-53`). Choosing a class at character creation is close to choosing a starting
  weapon and a hat.
- **Action** — Implement the five perks, or remove the promise from the UI until they exist.
- **Location** — `content/classes/*.json` (`perk`, `perkName`, `perkDescription`);
  `apps/game/client/scripts/content/class_catalog.gd`;
  `apps/game/client/scripts/ui/class_card.gd`; `apps/game/client/scripts/ui/character_create_ui.gd`;
  `apps/game/client/scripts/combat/run_buffs.gd`
- **Solution Hint** — Perks are the same shape as the event-hooked relics proposed in `IMP-H03`
  (`onKill`, `onParry`, `onLowHealth`, `onRoomClear`), so build one dispatcher and let both use it:
  `bloodrage` = damage scaling as health drops; `steadfast` = poise regen while guarding; `shadowstep` =
  extended i-frames on a backstep; `bulwark` = block stability bonus (which needs `BUG-19` fixed first);
  `arcane_focus` = mana regen on hit. Add `ClassCatalog.get_perk(class_id)` and register the hook in
  `RunBuffs` when a run starts. See `EXT-E01` for the wider class-identity design.

### BUG-53 — Class weapon restrictions are enforced in one UI screen and bypassed everywhere else

- **Problem** — `ClassCatalog.is_weapon_allowed(class_id, item_id)` has exactly one caller in the entire
  codebase: `loadout_ui.gd`. The actual equip paths — `GridInventory.equip_from_index()`,
  `GridInventory.equip_weapon()`, `InventoryService._use_or_equip_index()` (reached from the inventory screen
  and from quick slots) — never consult it. A Scholar can therefore equip a greatsword by double-clicking it
  in the inventory, and the restriction only appears in the pre-run loadout screen. Either the restriction is
  a real rule, in which case it is unenforced, or it is not, in which case the loadout screen is lying.
- **Action** — Enforce the rule at the single choke point where equipping actually happens.
- **Location** — `apps/game/client/scripts/content/class_catalog.gd` (`is_weapon_allowed`);
  `apps/game/client/scripts/inventory/grid_inventory.gd` (`equip_from_index`, `equip_weapon`);
  `apps/game/client/scripts/inventory/inventory_service.gd` (`_use_or_equip_index`);
  `apps/game/client/scripts/ui/loadout_ui.gd`
- **Solution Hint** — `GridInventory.equip_from_index()` is the choke point — `equip_weapon`,
  `_use_or_equip_index` and the loadout screen all funnel through it. Add the check there and emit a rejection
  reason so the UI can explain *why*. `GridInventory` currently has no dependency on `CharacterService`, so
  either inject the class id or pass a `Callable` validator from `InventoryService`, which already owns that
  coupling. Consider softening the rule to a scaling penalty rather than a hard block, which is the Souls
  convention and preserves the experimentation `EXT-E01` argues for.

### 🟠 P1 / 🟡 P2 — Optimisations

### PERF-16 — `PlayerCombatReactions.is_movement_locked()` performs four node lookups per physics frame

- **Problem** — `is_movement_locked()` iterates the `LOCK_SOURCES` table and, for each of the four entries,
  runs `_body.get_node_or_null(name)`, `has_method(...)` and `call(...)`. `Locomotion._physics_process()` calls
  it first thing on every tick, so the player performs 4 string-keyed node lookups, 4 method-table lookups and
  4 dynamic dispatches, 60 times a second, forever — to read four booleans that are already fields on nodes
  resolved and cached in `_ready()`. `get_lock_sources()` duplicates the same loop for the debug overlay.
- **Action** — Cache the four nodes once and call typed methods.
- **Location** — `apps/game/client/scripts/player/player_combat_reactions.gd` (`is_movement_locked`,
  `get_lock_sources`, `LOCK_SOURCES`, `_ready`)
- **Solution Hint** — `_ready()` already resolves `_dodge`, `_guard` and `_stamina`; add `_weapon` and
  `_heal`, and rewrite `is_movement_locked()` as four direct `and`/`or` reads. Keep `LOCK_SOURCES` only as the
  data the debug overlay iterates, or delete it and have the overlay ask for a `PackedStringArray` the
  fast path fills. This is the same fix shape as `PERF-08`/`REF-03`, applied to the single hottest caller.

### PERF-17 — `WeaponController._is_action_blocked()` re-resolves `Dodge` and `StatusController` every frame

- **Problem** — `_is_action_blocked()` is the first thing `WeaponController._physics_process()` does, and it
  calls `_body.get_node_or_null("Dodge")` and `_body.get_node_or_null("StatusController")` on every tick even
  though `_ready()` already caches `_guard`, `_combat_reactions` and `_lock_on` from the same parent. It then
  reads `dodge.get("is_dodging")` and `_guard.get("is_guard_active")` as **string-keyed Variant property
  lookups**, which is the slowest way GDScript can read a boolean.
- **Action** — Cache the nodes in `_ready()` and read typed fields.
- **Location** — `apps/game/client/scripts/combat/weapon_controller.gd` (`_is_action_blocked`, `_ready`,
  `_start_attack`)
- **Solution Hint** — Add `_dodge` and `_status` to the `_ready()` block next to the three that are already
  cached, and replace `.get("name")` with direct field access once `Dodge` and `Guard` are typed
  (`class_name Dodge`, `class_name Guard` — neither declares one today, which is why the call sites use
  duck typing; see `REF-03`). `_start_attack()` also re-resolves `AnimDirector` on every swing for the same
  reason.

### PERF-18 — `Locomotion` resolves `StatusController` and dispatches four weapon methods per physics frame

- **Problem** — `Locomotion._physics_process()` contains
  `var status_ctrl := get_node_or_null("StatusController") as StatusController` inline, plus four
  `_weapon.has_method(...)` / `_weapon.call(...)` pairs (`get_move_speed_multiplier`,
  `get_rotation_cap_multiplier`, `get_attack_lunge_velocity` twice) and two `_dodge.get("is_dodging")` Variant
  reads. That is one node lookup and ten dynamic dispatches per tick on the player's hottest function.
- **Action** — Cache `StatusController` alongside the other `_ready()` lookups and convert the weapon calls
  to typed access.
- **Location** — `apps/game/client/scripts/player/locomotion.gd` (`_physics_process`, `_ready`)
- **Solution Hint** — `_ready()` already caches `_stamina`, `_dodge`, `_combat_reactions`, `_lock_on` and
  `_weapon`; add `_status`. Then give `WeaponController` a `class_name` so `_weapon` can be typed and the
  `has_method` guards disappear. Also note `get_attack_lunge_velocity()` is called twice per frame on two
  different code paths — hoist it to a single local.

### PERF-19 — `GridInventory` placement is O(cells × slots) and `_repack_slots()` is O(n²) on every sort

- **Problem** — `can_place()` scans every existing slot to test one candidate cell. `_find_first_fit()` calls
  it for every cell in the grid. `add_item()` calls `_find_first_fit()`-equivalent logic inside a nested
  `for y / for x` loop. `_repack_slots()` — which runs on every sort, and therefore on every click of the sort
  button — clears the array and re-runs `_find_first_fit()` for each item in turn, making it
  O(items² × width × height). At the current 6×4 grid with a handful of items this is invisible; at the grid
  size `IMP-F01` requires (and with the stash in `storage_ui.gd`) it will not be.
- **Action** — Maintain an occupancy bitmap instead of rescanning the slot list.
- **Location** — `apps/game/client/scripts/inventory/grid_inventory.gd` (`can_place`, `_find_first_fit`,
  `add_item`, `_repack_slots`, `find_slot_at`)
- **Solution Hint** — Keep a `PackedByteArray` of `grid_width * grid_height` holding the slot index occupying
  each cell (`-1` for empty), updated on add/remove/move. `can_place` becomes a rectangle scan of the bitmap,
  `find_slot_at` becomes a single index, and `_repack_slots` becomes a sort plus a single sweep. Also fix the
  dead `if quantity <= 0: break` in `add_item`, which breaks only the inner loop and lets the outer loop spin
  through every remaining row.

### PERF-20 — `GlobalDropService` re-reads and re-parses `global_drops.json` on every enemy death

- **Problem** — `roll_enemy_drop()` opens with `var data: Dictionary = ContentLoader.load_json(DROPS_PATH)`.
  It is called from `CastleEnemyBase._try_roll_global_drop()` on every kill. In a wave or a dense room that is
  a file read plus a JSON parse per corpse, on the frame the corpse spawns its death VFX — exactly the frame
  that is already the most expensive one in combat.
- **Action** — Load once into a static, like `AffixRoller` and `DungeonCatalog` already do.
- **Location** — `apps/game/client/scripts/loot/global_drop_service.gd` (`roll_enemy_drop`)
- **Solution Hint** — `static var _entries: Array` + `static var _loaded: bool` with an `_ensure_loaded()`,
  matching the pattern in `affix_roller.gd`. While there, note the roll semantics: the function iterates
  entries in file order and returns the **first** one whose independent `randf()` succeeds, so the earlier an
  item appears in the JSON the more likely it is to drop, regardless of its authored `chance`. If that is not
  intentional (it reads as accidental), convert to a single weighted draw.

### PERF-21 — `WorldItemPickup` runs a full `_process` per dropped item to bob a mesh and poll a key

- **Problem** — Every dropped or spawned pickup runs `_process()` every frame: a `Time.get_ticks_msec()` call,
  a `sin()`, a `get_meta()` string lookup and a `Vector3` write for the bob, plus
  `Input.is_action_just_pressed("interact")` polling even when no player is nearby (the `_player == null`
  early-out happens *after* the bob). A cleared room can leave a dozen of these alive.
- **Action** — Move the bob to a shader or a shared tween, and move interaction to event-driven input.
- **Location** — `apps/game/client/scripts/inventory/world_item_pickup.gd` (`_process`, `_ready`,
  `_on_body_entered`, `_on_body_exited`)
- **Solution Hint** — The bob is a pure function of time and a constant offset — put it in the pickup's
  material as a vertex offset and delete the CPU loop entirely, which also makes it free at any count. Replace
  the input poll with `_unhandled_input()` and `set_process_unhandled_input(_player != null)` toggled in
  `_on_body_entered` / `_on_body_exited`, so an idle pickup costs nothing. `xp_shard_pickup.gd` and
  `loot_chest.gd` should get the same treatment.

### PERF-22 — `Hurtbox` walks the node tree six or more times per hit

- **Problem** — `receive_hit()` and its helpers call `_find_character_body()` from `_apply_arc_multipliers`,
  `_apply_defense`, `_get_resistances`, `_emit_victim_feedback`, `_is_hyperarmor_active` and the i-frame
  branch, plus `_find_guard()` and `_find_dodge()` — each of which is a `while node: get_node_or_null(...)`
  walk from the hurtbox up to the scene root. A single sword swing that connects therefore performs eight or
  more upward tree walks with a string lookup at every level. This is `BUG-12` measured properly: the cost is
  not "an allocation", it is a repeated O(depth) search on the frame the player most wants to be smooth.
- **Action** — Resolve the owner, guard and dodge once in `_ready()` and cache them.
- **Location** — `apps/game/client/scripts/combat/hurtbox.gd` (`_find_character_body`, `_find_guard`,
  `_find_dodge`, `receive_hit`)
- **Solution Hint** — `_ready()` already caches `_health`, `_poise` and `_status_controller` — add `_body`,
  `_guard` and `_dodge` using the same walk, executed once. Re-resolve lazily only if
  `is_instance_valid()` fails (which covers re-parenting and pooled enemies). Then pass the resolved body into
  the helpers as a parameter instead of having each one re-derive it.

### PERF-23 — `QuestService` scans every quest definition on every kill and every pickup

- **Problem** — `register_kill()` and `register_fetch()` both loop `QuestCatalog.get_all_ids()`, and for each
  id call `CharacterService.get_quest_state()` and `QuestCatalog.get_definition()` — a dictionary lookup and a
  definition fetch per quest, per kill. `InventoryService._on_item_added_success()` calls `register_fetch()`
  on every item added. With four quests this is free; the quest counts in `IMP-G03` (dozens of quests, some
  repeatable) make it a per-kill linear scan.
- **Action** — Index active quests by trigger type when quest state changes, not when the trigger fires.
- **Location** — `apps/game/client/scripts/quests/quest_service.gd` (`register_kill`, `register_fetch`,
  `_check_escape_quests`, `accept_quest`, `complete_quest`)
- **Solution Hint** — Maintain `_active_by_type: Dictionary` (`"kill"` → array of quest ids, `"fetch"` → …)
  rebuilt only in `accept_quest` / `complete_quest` / save load. `register_kill(enemy_id)` then touches only
  the kill quests, and a second level of indexing by `targetId` makes the common case O(1).

### PERF-24 — `RoomGraphGenerator._creates_2x2_block()` runs a 16-cell scan per placement candidate

- **Problem** — `_can_place_room()` is called for every direction of every walk step and every branch
  frontier expansion. For each call, `_creates_2x2_block()` performs a 2×2 sweep of 2×2 blocks — sixteen
  dictionary lookups plus up to sixteen `get_slot_at()` calls. With `max_walk_attempts = 8192` and
  `max_generation_attempts = 256` for the larger biome, a worst-case generation performs on the order of a
  million dictionary probes, synchronously, on the main thread during the loading screen (`PERF-03`).
- **Action** — Track block occupancy incrementally instead of re-deriving it.
- **Location** — `apps/game/client/scripts/dungeon/procgen/room_graph_generator.gd` (`_creates_2x2_block`,
  `_can_place_room`, `_grow_branches`)
- **Solution Hint** — Because rooms are only ever *added* during a single attempt, maintain a
  `Dictionary` of 2×2 anchor → occupied-count updated on each `add_slot()`; `_creates_2x2_block(cell)` then
  tests four anchors against the count. Combine with `PERF-03` (move generation off the main thread) so the
  cost stops being a visible hitch regardless.

### 🔵 P3 — Refactoring

### REF-09 — `Stamina.consume()` and `Stamina.drain()` are byte-identical

- **Problem** — Both functions have the same body: exhaustion check, sufficiency check, subtract, set regen
  delay, emit `stamina_changed`, flip `_exhausted`, emit `depleted`, return `true`. Two names for one
  behaviour means call sites carry an implied distinction that does not exist — `WeaponController` uses
  `consume`, `Locomotion` uses `drain` for sprint, `Dodge` uses `consume` — and any future change has to be
  made twice or the two silently diverge.
- **Action** — Keep one, and if the distinction is wanted, make it real.
- **Location** — `apps/game/client/scripts/combat/stamina.gd` (`consume`, `drain`)
- **Solution Hint** — There *is* a real distinction worth encoding: `consume` is a discrete cost (a swing, a
  roll) that should fail atomically and trigger the "insufficient" cue, while `drain` is a continuous
  per-second cost (sprinting) that should be allowed to run the bar to zero and simply stop the action. Give
  `drain` those continuous semantics — no `insufficient` emit (`BUG-32`), clamp at zero rather than refuse —
  and the two names earn their keep. Otherwise delete `drain` and update the one caller.

### REF-10 — `EndlessDifficulty`, `CastleTierDifficulty` and `WavesDifficulty` are three unrelated scaling formulas

- **Problem** — Three files implement "how much stronger are enemies here", with three different shapes:
  `CastleTierDifficulty` multiplies a catalog tier multiplier by a linear per-floor growth read from the
  dungeon JSON; `EndlessDifficulty` uses a hardcoded per-10-floor step with a logarithmic knee and a soft cap;
  `WavesDifficulty` uses a flat linear per-wave rate with no cap. None share an interface, so every consumer
  (`DungeonBuilder`, `CastleRun`, `WavesRun`, `GlobalDropService`) branches on run mode to pick one. Adding a
  fourth mode, or retuning "difficulty" globally, means touching all of them.
- **Action** — Define one `DifficultyProfile` interface and implement the three curves behind it.
- **Location** — `apps/game/client/scripts/dungeon/endless_difficulty.gd`;
  `apps/game/client/scripts/dungeon/castle_tier_difficulty.gd`;
  `apps/game/client/scripts/dungeon/waves_difficulty.gd`;
  `apps/game/client/scripts/dungeon/run_modifier_service.gd`
- **Solution Hint** — A `RefCounted` with `hp_multiplier(progress: int) -> float`,
  `damage_multiplier(progress) -> float`, `rare_drop_bonus(progress) -> float` and
  `modifiers(progress) -> Array[String]`, plus a factory `DifficultyProfile.for_run(run_mode, dungeon_id, tier)`.
  Move the constants into `content/` so they are tunable without a code change — which is a hard prerequisite
  for `IMP-I01`, since difficulty tuning that requires recompiling is difficulty tuning that will not happen.

### REF-11 — Floor definitions are cached in two places with two different policies

- **Problem** — `RunFlow.floor_definitions` (instance, LRU-trimmed by distance from the current floor) and
  `DungeonBuilder._floor_definition_cache` (static, unbounded) hold the same data. `_stash_current_floor_in_cache`
  and `_set_current_floor_cache` write both; `_get_cached_floor_definition` reads `RunFlow`'s first and falls
  back to `DungeonBuilder`'s. Two caches with different lifetimes over the same key space is a correctness
  hazard as well as the leak in `BUG-30`: after a trim, the two disagree about what floor 7 looks like, and
  which one wins depends on read order.
- **Action** — One cache, owned by one component.
- **Location** — `apps/game/client/scripts/app/run_flow.gd` (`floor_definitions`,
  `_stash_current_floor_in_cache`, `_set_current_floor_cache`, `_get_cached_floor_definition`,
  `_trim_floor_cache`, `_clear_floor_cache`); `apps/game/client/scripts/dungeon/dungeon_builder.gd`
- **Solution Hint** — `DungeonBuilder` is the right owner (it is what regenerates on a miss). Give it
  `store/get/clear` plus the eviction policy, delete `RunFlow.floor_definitions` entirely, and make the
  eviction distance-aware by passing the current floor into `store_floor_cache`.

### REF-12 — `SkipFloorService` re-implements inventory counting instead of asking the inventory

- **Problem** — `SkipFloorService._count_item()` iterates `inventory.slots` summing quantities — which is
  exactly what `InventoryService.count_item()` already does, and what
  `InventoryService.consume_boss_sigil()` / `consume_dungeon_key()` do again with slightly different loops.
  Four hand-rolled scans of the same array, in three files, each with its own idea of how to read `quantity`.
- **Action** — Consolidate onto `GridInventory` as the single owner of slot iteration.
- **Location** — `apps/game/client/scripts/dungeon/skip_floor_service.gd` (`_count_item`,
  `get_available_skips`); `apps/game/client/scripts/inventory/inventory_service.gd` (`count_item`,
  `consume_boss_sigil`, `consume_dungeon_key`, `has_dungeon_key`, `dungeon_keys_for_floor`)
- **Solution Hint** — Add `count_by_id(item_id) -> int` and `find_slots_where(predicate: Callable) -> Array[int]`
  to `GridInventory` and express all five call sites in terms of them. `remove_items_by_id` already exists and
  already handles partial stacks correctly, so `consume_boss_sigil` and `consume_dungeon_key` collapse to one
  line each.

### REF-13 — Bosses are ordinary enemies with larger numbers, structurally

- **Problem** — Every file in `content/bosses/` carries the same ten keys as a regular enemy
  (`health`, `attack_damage`, `attack_range`, `attack_cooldown`, `windup`/`active`/`recovery` durations,
  `aggro_range`, `deaggro_range`, `enemy_type`). None declares phases, phase transitions, arena mechanics,
  adds, or a second move set. `CastleEnemyBase._is_boss_enemy()` decides boss-ness by testing whether the id
  string **contains** `"boss"` or `"miniboss"`, and uses that only to pick a lock-on orbit radius. There is no
  boss controller and no boss state machine; `scripts/bosses/` contains presentation and arena scripts, not
  behaviour.
- **Action** — Introduce a boss layer above the shared enemy base rather than encoding boss-ness in a string.
- **Location** — `content/bosses/*.json`; `apps/game/client/scripts/enemies/castle_enemy_base.gd`
  (`_is_boss_enemy`, `get_lock_orbit_radius`); `apps/game/client/scripts/bosses/`
- **Solution Hint** — See `IMP-B02` for the design. Structurally: add `"isBoss": true` and a `"phases"` array
  to the boss schema, and a `BossController` that owns phase thresholds, phase-entry cinematics, move-set
  swaps and add-spawns while delegating locomotion and hit resolution to `CastleEnemyBase`. Replace the
  substring test with the data flag — `_is_boss_enemy()` currently also returns `true` for any future enemy
  whose id happens to contain "boss".

### REF-14 — `WeaponController._process_bow_input()` is a second, divergent attack state machine

- **Problem** — The bow branch returns early from `_physics_process()` before the two-hand and weapon-art
  handling, so bow users can never toggle stance or use a weapon art. It maintains its own `DRAWING` phase
  outside the `AttackPhase` progression, sets `is_attacking = true` without populating `_current_attack` or
  `_phase_timer`, and `_fire_bow_shot()` fakes a projectile by resizing the melee hitbox to
  `Vector3(0.6, 0.6, 8.0)` offset 4 m forward — an 8-metre box that is attached to the player and travels with
  them for the duration of the "shot". Arrows do not exist as entities, cannot miss, cannot be dodged after
  release, and cannot hit anything the player has since turned away from.
- **Action** — Make ranged attacks projectiles, and fold the draw into the shared phase machine.
- **Location** — `apps/game/client/scripts/combat/weapon_controller.gd` (`_process_bow_input`,
  `_fire_bow_shot`, `_reset_bow`, `_apply_hitbox_profile`);
  `apps/game/client/scripts/combat/enemy_projectile.gd`
- **Solution Hint** — `enemy_projectile.gd` already implements a travelling damage source with a `Hitbox`;
  generalise it to `Projectile` with a `team` field and spawn one from `_fire_bow_shot()` with velocity scaled
  by `_draw_charge`. Then `DRAWING` becomes a normal phase with a charge value, and the bow branch collapses
  into `_try_attack("heavy")` with a charge-up modifier — which also un-blocks two-handing and weapon arts for
  bows.

### REF-15 — `coins` is a complete duplicate API for `gold`, and every change emits two signals

- **Problem** — `CharacterService` exposes `gold`, `add_gold`, `spend_gold`, `can_afford` and `gold_changed`
  **and** `get_coins`, `add_coins`, `spend_coins`, `can_afford_coins` and `coins_changed`. The second set is a
  pure alias of the first: `get_coins()` returns `gold`, `add_coins()` calls `add_gold()`, and `add_gold()`
  emits **both** `gold_changed` and `coins_changed` on every mutation, so every listener bound to either
  signal fires twice per transaction. Callers pick arbitrarily — `MerchantService.buy_item()` uses
  `spend_gold`, `BlacksmithService.upgrade_item()` uses `spend_coins`, and `BlacksmithService.can_upgrade()`
  checks `can_afford` while `upgrade_item()` spends via `spend_coins`. The save format carries both fields,
  which is what produces `BUG-48`.
- **Action** — Delete the alias set and the second signal.
- **Location** — `apps/game/client/scripts/save/character_service.gd` (`get_coins`, `add_coins`,
  `spend_coins`, `can_afford_coins`, `coins_changed`, `add_gold`, `spend_gold`, `apply_save`, `to_save`);
  `apps/game/client/scripts/hub/blacksmith_service.gd`; `apps/game/client/scripts/hub/merchant_service.gd`;
  `apps/game/client/scripts/ui/` (any `coins_changed` listeners)
- **Solution Hint** — Grep for `coins` across `scripts/` and `content/`, rename every call site to the gold
  form, then remove the aliases and `coins_changed`. Pair the change with the save migration in `BUG-48` so
  the runtime and the save format collapse to one field in the same commit. If the intent was ever two
  distinct currencies (a soft currency and a premium/meta currency — which `IMP-D04` argues the game
  actually needs), implement that deliberately as a second balance rather than resurrecting the alias.

---

## 6. 🟡 P2 / 🔵 P3 — Refactoring

### REF-01 — 27 autoloads form an unbounded global mutable graph

- **Problem** — `project.godot` registers 27 autoload singletons: `RunFlow`, `ApiConfig`, `LocalSave`,
  `CharacterService`, `ProgressionService`, `RunBuffs`, `InventoryService`, `StorageService`, `QuestService`,
  `AudioDirector`, `AchievementService`, `SteamService`, `CrashLogger`, `WavesRunService`, `DungeonTierService`,
  `VfxService`, `DisplayService`, `PlayerControls`, `MenuStack`, `WorldState`, `PixelDioramaViewport`,
  `AttackTokenService`, `GameFacade`, `InputRebindService`, `DebugConsole`, `InputGlyphWatcher`, `UISymbolBus`.
  Every one is globally reachable and mutable from every script, several have `_process` callbacks
  (PERF-06/09/11/13), initialisation order is implicit, and there is no dependency graph — `RunFlow` alone is
  1,320 lines and touches saves, scene routing, procgen, cloud API, leaderboards, achievements, buffs and
  respawn rules. A `GameFacade` autoload exists, which suggests the consolidation was started and abandoned.
  *(Verified — read the `[autoload]` block and `run_flow.gd`'s function list.)*
- **Action** — Group autoloads into a small number of owned subsystems behind explicit facades, and split
  `RunFlow`.
- **Location** — `apps/game/client/project.godot` (`[autoload]`); `scripts/app/run_flow.gd`;
  `scripts/app/game_facade.gd`
- **Solution Hint** — Target 6–8 autoloads:
  `Services` (save/character/progression/inventory/storage/quests), `Platform` (steam/crash/api),
  `Presentation` (audio/vfx/display/pixel pipeline), `Input` (controls/rebind/glyphs), `Run` (run flow/waves/tier),
  `UI` (menu stack/symbol bus). Each becomes a thin container that owns child service nodes, so initialisation
  order is explicit and testable. Split `RunFlow` along the seams already visible in its own function names:
  `RunLifecycle` (start/enter/abandon/complete), `FloorTransition` (ascend/descend/cache), `RunPersistence`
  (snapshot/restore/cloud), `RunStats` (kills/loot/elapsed). Note `scripts/app/run_lifecycle.gd` and
  `scripts/app/run_scene_router.gd` already exist — finish moving into them rather than adding new files.

### REF-02 — The dungeon generator is implemented twice, in two languages

- **Problem** — There is a full C# procedural generator in `packages/procedural/` (LayoutGraphGenerator,
  RoomTypeAssigner, EnemyPlacer, LootPlacer, AffixRoller, DungeonSeedDeriver, FinalFloorGenerator, SeededRandom)
  **and** a full GDScript generator in `apps/game/client/scripts/dungeon/procgen/` (room_graph_generator,
  room_content_assigner, procgen_placements, procgen_loot_roller, procgen_rng, floor_seed_mix). They must produce
  byte-identical output for a given seed, and the only thing holding them together is
  `cross_stack_parity_suite.gd`, which spot-checks seed mixing, kind specs and biome catalogue parity. Every
  balance or layout change has to be made twice, correctly, in two languages.
  *(Verified — listed both trees; read the parity suite.)*
- **Action** — Pick one authority and make the other a consumer.
- **Location** — `packages/procedural/**`; `apps/game/client/scripts/dungeon/procgen/**`;
  `apps/game/client/scripts/validation/suites/cross_stack_parity_suite.gd`
- **Solution Hint** — Given `RunFlow._try_online_generate` already prefers the server and falls back to local,
  the cleanest resolution is: **C# is authoritative**; the client ships a *generated artefact* rather than a
  reimplementation. Concretely, extend `tools/procgen-cli` to emit a compact deterministic layout format, run it
  at build time for the seed space the game can reach offline, or compile `Aumbrye.Procedural` to a GDExtension
  / WASM module the client calls. If keeping two implementations is a deliberate offline-play requirement, then
  at minimum expand the parity suite to fuzz N=1000 seeds × 10 biomes and diff the *entire* `DungeonDefinition`,
  not just three properties — otherwise the guarantee is nominal.

### REF-03 — `has_method`/`call` duck typing used where typed interfaces are available

- **Problem** — Beyond the per-frame cost (PERF-08), the 282 `has_method` sites make the component contracts
  invisible: nothing declares that a player node *must* have a `Dodge` exposing `process_dash_physics`, so a
  rename silently degrades to a no-op instead of failing. Note that `dodge.gd` is probed for **two different**
  method names (`process_dash_physics` and `process_dodge_physics`) in `locomotion.gd`, which is a fossil of a
  rename that was never completed.
  *(Verified — `locomotion.gd:149-159`.)*
- **Action** — Introduce typed component base classes and delete the duck-typed probes.
- **Location** — `apps/game/client/scripts/player/locomotion.gd:149-159`; repo-wide `has_method` sites
- **Solution Hint** — Define `class_name` bases for the player component slots (`Dodge`, `WeaponController`,
  `Guard`, `Stamina`, `Mana`, `Poise`, `PlayerCombatReactions`) — most already have `class_name`. Then use
  `@onready var _dodge := $Dodge as Dodge` and call directly. Resolve the `process_dash_physics` /
  `process_dodge_physics` duplication to a single name in the same commit.

### REF-04 — `_data.get(...)` Variant lookups in physics loops

- **Problem** — Enemy tuning is read from an untyped `Dictionary` inside the hot path:
  `velocity = to_target.normalized() * _data.get("move_speed", 3.0)` performs a hash lookup returning a `Variant`,
  then a `Variant`-boxed multiply, every physics frame per enemy. The same pattern covers `attack_range`,
  `aggro_range`, `deaggro_range`, `patrol_radius`, `attack_cooldown`, `retreat_threshold`.
  *(Verified — `castle_enemy_base.gd:534, 551, 579, 596, 618, 620, 628, 630, 663, 848`.)*
- **Action** — Unpack content data into typed fields once at spawn.
- **Location** — `apps/game/client/scripts/enemies/castle_enemy_base.gd:503-694, 847-851`
- **Solution Hint** — Add a small `EnemyTuning` `RefCounted` (or plain typed members) populated in `_ready()`
  from `_data`, with squared-distance variants precomputed (`_aggro_range_sq`, `_attack_range_sq`). This pairs
  naturally with PERF-02 and should be done as one change.

### REF-05 — Three parallel representations of the same character art

- **Problem** — Character geometry exists as `.vox` (262 files in `art-source/`), `.mesh` (262 files in
  `assets/characters/`) and `.voxels.json` (115 files in `assets/characters/`). Rig manifests in
  `content/characters/` reference **both** `.mesh` (36 entries) and `.voxels.json` (133 entries), so both
  loaders are live. `assets/characters/*/` contains both `arml.mesh` and `arm_l.mesh` — two naming conventions
  for the same part. The `.mesh` exporter (`scripts/tools/export_voxel_meshes.gd`) is not referenced by any
  workflow, so the `.mesh` files are hand-generated and can silently drift from their `.vox` sources.
  *(Verified — counted files on disk and references in `content/characters/*.json`.)*
- **Action** — Collapse to one runtime representation with a build-time exporter under CI verification.
- **Location** — `art-source/characters/**`; `apps/game/client/assets/characters/**`;
  `content/characters/*.json`; `apps/game/client/scripts/tools/export_voxel_meshes.gd`
- **Solution Hint** — `.vox` is the source; ship `.mesh` (or better, a single skinned mesh per rig — see
  PERF-04). Regenerate all `.mesh` from `.vox` with the exporter, rewrite every manifest to reference `.mesh`,
  delete `.voxels.json` and the runtime `VoxelMeshBuilder` JSON branch, and add a CI job mirroring the existing
  `export_diorama_anim_libraries.gd -- --verify` pattern that fails on drift. Standardise on one naming
  convention (`arm_l` or `arml`, not both) and delete the losers.

### REF-06 — `MaterialFlash`/`MaterialDissolve` duplicate materials per instance

- **Problem** — `_apply_mesh_tint` in `CastleEnemyBase` duplicates the surface material on every tint change;
  `MaterialDissolve` and `MaterialFlash` operate per-instance across the whole diorama hierarchy. With
  PERF-04's 12–20 mesh instances per character, a single hit-flash duplicates a material per part.
  *(Verified — `castle_enemy_base.gd:290-306`; `scripts/art/characters/material_flash.gd`,
  `material_dissolve.gd`.)*
- **Action** — Move flash/dissolve to instance shader uniforms.
- **Location** — `apps/game/client/scripts/enemies/castle_enemy_base.gd:290-306`;
  `scripts/art/characters/material_flash.gd`; `scripts/art/characters/material_dissolve.gd`
- **Solution Hint** — Add `instance uniform float flash_amount;` and `instance uniform float dissolve;` to the
  shared pixel-diorama shader, and drive them with `MeshInstance3D.set_instance_shader_parameter()`. This keeps
  one material resource for all characters (enabling PERF-04.1) and makes flash/dissolve allocation-free.

### REF-07 — `PixelDioramaStyle` at 1,471 lines mixes palette, geometry and material concerns

- **Problem** — `scripts/art/style/pixel_diorama_style.gd` is the second-largest game file and holds palette
  tables, `add_box` geometry helpers, material factories, legacy-mesh hiding and texture loading (including a
  `globalize_path` call at `:142` that shares BUG-02's export problem). It is imported by the character skin,
  the prop kits, the weapon kit and the room dressing — a hub with no seams.
  *(Verified — read the file's structure and its `globalize_path` usages.)*
- **Action** — Split into `PixelPalette` (data), `PixelGeometry` (box/pivot builders) and `PixelMaterials`
  (factory + cache).
- **Location** — `apps/game/client/scripts/art/style/pixel_diorama_style.gd`
- **Solution Hint** — Do the split mechanically first (three files, re-export the old names as thin
  `const` aliases so callers keep compiling), then migrate call sites file-by-file. Fix the two `globalize_path`
  texture loads while the file is open.

### REF-08 — `MenuStack` / `PlayerControls` / pause ownership is spread across five files

- **Problem** — `get_tree().paused` is written from `RunFlow` (2 sites), `CombatHUD` (2 sites), `PauseMenu`
  (2 sites) and `StairMenu` (2 sites, with its own `_was_paused` restore). `PlayerControls.is_gameplay_blocked()`
  independently consults `is_player_meta_ui_open()` *and* `get_tree().paused`. There is no single owner of pause
  state, which is exactly the kind of thing that produces "the game stayed paused after closing the menu" bugs.
  *(Verified — grepped every `get_tree().paused` write.)*
- **Action** — Make `MenuStack` the sole owner of pause.
- **Location** — `apps/game/client/scripts/ui/menu_stack.gd`; `scripts/app/run_flow.gd:893, 922`;
  `scripts/ui/combat_hud.gd:580, 588`; `scripts/ui/pause_menu.gd:63, 77`; `scripts/ui/stair_menu.gd:34-51`
- **Solution Hint** — `MenuStack.push(menu, {pauses = true})` / `MenuStack.pop()` computes
  `get_tree().paused = _stack.any(func(e): return e.pauses)`. No other file writes `paused`. Add a validation
  assertion that opening and closing each menu in sequence leaves `paused == false`.

---

## 7. 🔵 P3 — Files that are not needed

### DEAD-01 — Unreferenced scripts

- **Problem** — Eleven `.gd` files are referenced by nothing in the project (no `preload`, no `load`, no
  `class_name` use, no scene, no `project.godot` entry, no content JSON):
  `scripts/content/aspect_catalog.gd`, `scripts/debug/mcp_validation.gd`,
  `scripts/dungeon/procgen/procgen_biome_loader.gd`, `scripts/dungeon/procgen/procgen_loot_tables.gd`,
  `scripts/tools/build_ui_theme.gd`, `scripts/tools/export_voxel_meshes.gd`,
  `scripts/tools/run_pixel_style_main.gd`, `scripts/tools/strip_mat_tres_px_s.gd`,
  `scripts/ui/appearance_cycle_row.gd`, `scripts/ui/waves_inventory_ui.gd`,
  `scripts/validation/assertions.gd`. Plus `scripts/combat/enemy_pool.gd` (BUG-04).
  *(Verified — full-tree reference scan across `.gd`, `.tscn`, `.tres`, `.cfg`, `.json`, `.gdshader`,
  `project.godot` and `export_presets.cfg`.)*
- **Action** — Delete, with two exceptions.
- **Location** — as listed above
- **Solution Hint** — Keep `export_voxel_meshes.gd` — it is the missing half of REF-05 and should be **wired into
  CI**, not deleted. Keep `strip_mat_tres_px_s.gd` only if it is a documented one-shot migration tool; otherwise
  delete. Everything else goes. `mcp_validation.gd` is suspicious: `scenes/debug/mcp_validation.tscn` **is** the
  CI validation entry point, so confirm the scene's script reference before deleting the `.gd`.

### DEAD-02 — 222 of 262 exported `.mesh` files are orphaned

- **Problem** — Only 40 `.mesh` paths are referenced from `content/characters/*.json`; 222 files on disk are
  referenced by nothing. Many are duplicates under a second naming convention (`arm_l.mesh` alongside
  `arml.mesh`). They are tracked in git and inflate every clone and every export (`export_filter="all_resources"`).
  *(Verified — set difference between referenced paths and files on disk.)*
- **Action** — Delete the orphans as part of REF-05.
- **Location** — `apps/game/client/assets/characters/**/*.mesh`
- **Solution Hint** — Do REF-05 first (decide the single representation), then regenerate cleanly from
  `art-source/` and commit only what the manifests reference. Add a validation assertion that every file under
  `assets/characters/` is referenced by some manifest, so this cannot silently recur.

### DEAD-03 — Vendored `addons/godot_mcp` ships ~23,400 lines of editor tooling into the game project

- **Problem** — `addons/godot_mcp` is a third-party MCP server plugin (v1.0.0, author "LIDAXIAN") vendored into
  the game project. It is ~23,400 lines — roughly 41% of the game's own script volume — including
  `node_tools.gd` (2,461 lines), `animation_tools.gd` (2,276), `physics_tools.gd` (1,334). It is an *editor*
  tool but lives inside the exported project tree. It is also excluded from the CI `gdlint`/`gdformat` step, so
  it is unlinted, unversioned against upstream, and unaudited.
  *(Verified — read `plugin.cfg`, counted lines, read the CI lint step's `-not -path '*/addons/*'` filter.)*
- **Action** — Confirm it is excluded from exports, and decide whether to keep it vendored.
- **Location** — `apps/game/client/addons/godot_mcp/**`; `apps/game/client/export_presets.cfg`
  (`export_filter="all_resources"`, `exclude_filter=""`)
- **Solution Hint** — `exclude_filter` is empty and `export_filter="all_resources"`, so this **is** currently
  being packaged into the shipped build. Set `exclude_filter="addons/godot_mcp/*"` (and audit the export size
  before/after). Longer term, move it out of the game project into a developer-only overlay, or pin it as a
  git submodule so upstream fixes are trackable.

### DEAD-04 — Stray files at the repository root and in the client

- **Problem** — `debug-d7fbce.log`, `seed1.json`, `seed99999.json` sit at the repo root; nine `.godot_*.log`
  files sit in `apps/game/client/`. All are gitignored (so they are not in history) but they clutter the working
  tree and the seed JSONs look like they were meant to be fixtures.
  *(Verified — `git status --ignored`.)*
- **Action** — Delete the logs; move the seed files to `content/fixtures/` if they are fixtures, else delete.
- **Location** — repo root; `apps/game/client/.godot_*.log`
- **Solution Hint** — `content/fixtures/` already exists. If `seed1.json` / `seed99999.json` are procgen golden
  outputs, move them there and reference them from `procgen_suite.gd`; otherwise remove. Add
  `apps/game/client/.godot_*.log` and `debug-*.log` to `.gitignore` if not already covered (they are — the point
  is to actually delete them).

### DEAD-05 — Dead functions and placeholder branches in gameplay code

- **Problem** — `CastleEnemyBase._try_parry_check()` is an empty `pass` function with a comment saying the logic
  lives elsewhere; `get_lock_priority()` returns a constant `0.0` for every enemy (so the lock-on priority system
  it feeds is inert); `PixelDioramaViewport._dbg_dump` / `_dbg_walk` / `dump_render_state` walk the entire scene
  tree and exist only for an env-var-gated debug print.
  *(Verified — `castle_enemy_base.gd:74-75, 823-825`; `pixel_diorama_viewport.gd:66-108`.)*
- **Action** — Delete `_try_parry_check`; either implement `get_lock_priority` per archetype or remove it from
  the lock-on scoring; move the debug dump behind `OS.is_debug_build()` or into the debug console.
- **Location** — `apps/game/client/scripts/enemies/castle_enemy_base.gd:74-75, 823-825`;
  `scripts/art/pipeline/pixel_diorama_viewport.gd:66-108`
- **Solution Hint** — `get_lock_priority` is the more interesting one: a working implementation (bosses > elites
  > trash, attackers > idle) would materially improve lock-on feel. See FEAT-04.

---

## 8. 🟠 P1 / 🟡 P2 — Test, validation and CI quality

### QA-01 — 145 validation assertions test source text, not behaviour

- **Problem** — The validation harness contains **145 calls to `ctx.file_contains(path, "some literal source
  text")`** against only ~54 behavioural `ctx.check`-style assertions. `m7_suite.gd` and `m6_suite.gd` have 24
  each; `quality_bar_suite.gd` has 20. These assertions pass whenever a string appears in a file — for example
  `m6_suite.gd:726` asserts that `enemy_pool.gd` contains `class_name EnemyPool`, which is green even though
  `EnemyPool` is never called (BUG-04). This is ~27,700 lines of test code that largely cannot detect a
  regression, while creating strong resistance to refactoring (renaming a function breaks "tests").
  *(Verified — counted with grep; read the `enemy_pool` assertions.)*
- **Action** — Convert `file_contains` assertions into behavioural assertions, and delete the ones that cannot be.
- **Location** — `apps/game/client/scripts/validation/suites/m6_suite.gd`, `m7_suite.gd`,
  `quality_bar_suite.gd`, `pause_menu_suite.gd`, `m5_suite.gd`, `flow_suite.gd`, `hub_m4_suite.gd`, and 10 others
- **Solution Hint** — Triage each of the 145 into three buckets:
  (a) *convertible* — instantiate the thing and assert its observable behaviour (most of them);
  (b) *architectural invariant* — keep, but implement as a real structural check (e.g. "six catalogues share
  `ContentDirLoader`" becomes "call each catalogue's loader and assert the returned map is non-empty and keyed
  by `id`"); (c) *meaningless* — delete. Budget this as a real project: it is ~30% of the client's script
  volume. Prioritise the suites that gate the P0/P1 items above so the fixes land with genuine coverage.

### QA-02 — The frame-budget gate silently skips in CI

- **Problem** — `perf_gate_suite._test_frame_budget()` returns `skip(...)` when `user://perf_baseline.json` is
  absent. CI runs headless on a fresh runner, so that file never exists — **the frame-budget assertion has never
  run in CI**. The other budgets are permissive to the point of being useless: `BUDGET_DUNGEON_BUILD_MS = 1500`
  accepts a 1.5-second freeze, `BUDGET_NODE_COUNT = 8000`, `BUDGET_STATIC_MEMORY_BYTES = 512 MiB`.
  *(Verified — read `perf_gate_suite.gd:1-70`.)*
- **Action** — Commit a baseline, fail (not skip) when it is missing, and tighten the budgets.
- **Location** — `apps/game/client/scripts/validation/suites/perf_gate_suite.gd:6-11, 55-70`
- **Solution Hint** — Check a baseline JSON into `content/fixtures/perf_baseline.json` and load it from there
  rather than `user://`. Change `skip(...)` to a failure. Set targets that reflect the quality bar you want:
  p95 frame ≤ 13.9 ms (72 fps headroom for a 60 fps target), per-frame build cost ≤ 8 ms, node count ≤ 4000 for
  a standard floor. Record the *current* numbers first so the tightening is staged, not aspirational.

### QA-03 — `gdformat` pre-commit covers 8 files; CI covers all of `scripts/`

- **Problem** — `.pre-commit-config.yaml` runs `gdformat --check` against a hand-listed regex of 8 specific
  files, while `.github/workflows/ci.yml` runs `gdlint` + `gdformat --check` over **every** `.gd` under
  `apps/game/client/scripts`. Contributors get a green pre-commit and a red CI.
  *(Verified — read both files.)*
- **Action** — Make the pre-commit hook match CI's scope.
- **Location** — `.pre-commit-config.yaml:26-32`; `.github/workflows/ci.yml:240-249`
- **Solution Hint** — Replace the file regex with `files: ^apps/game/client/scripts/.*\.gd$` and add the
  `gdlint` hook too. Keep `pass_filenames: true` so it only checks staged files (fast).

### QA-04 — Godot validation reports success ambiguously

- **Problem** — The CI summary step parses failures with
  `jq -r '.tests[] | select(.status == "fail" or .pass == false)'` — accepting **two different schemas** for the
  same report, which means the report format is not pinned. If `validation_runner` emits neither key on a
  crashed suite, the failure is invisible in the summary.
  *(Verified — read `ci.yml:296-300` and `validation_main.gd`.)*
- **Action** — Pin the report schema and assert on it.
- **Location** — `.github/workflows/ci.yml:296-300`;
  `apps/game/client/scripts/validation/validation_runner.gd`
- **Solution Hint** — Emit exactly one shape (`status: "pass"|"fail"|"skip"`), add a top-level
  `{total, passed, failed, skipped}` block, and have the CI step assert `failed == 0 && total > 0` so an empty
  or malformed report fails rather than passing vacuously.

### QA-05 — No automated test boots the *exported* build

- **Problem** — CI validates the project in the editor's headless mode, where `res://` maps to the source
  directory. That is precisely the environment in which BUG-01 and BUG-02 are invisible. The release workflow
  exports a `.exe` and uploads it without ever running it.
  *(Verified — read both workflows.)*
- **Action** — Add an export smoke test.
- **Location** — `.github/workflows/release.yml:66-95`; new job in `.github/workflows/ci.yml`
- **Solution Hint** — Export a Linux headless build in CI, run it with a `--smoke-test` command-line flag that
  boots the autoloads, asserts every catalogue is non-empty, builds one character rig, generates one dungeon
  floor, writes and re-reads a save, then quits with a status code. This single job would have caught both P0s.

### QA-06 — CI has no dependency-vulnerability or license gate

- **Problem** — CodeQL runs (`.github/workflows/codeql.yml`), and Dependabot is clearly active (the recent
  commit history is dominated by Dependabot merges), but there is no `dotnet list package --vulnerable`,
  no `npm audit`, and no SBOM step. `SECURITY.md` exists but nothing enforces it.
  *(Verified — listed `.github/workflows/`; read the git log.)*
- **Action** — Add vulnerability scanning to CI.
- **Location** — `.github/workflows/ci.yml`
- **Solution Hint** — Add to the backend job:
  `dotnet list Aumbrye.sln package --vulnerable --include-transitive` (fail on any hit), and to the web job:
  `npm audit --audit-level=high`. Optionally emit a CycloneDX SBOM for release builds.

---

## 9. 🟠 P1 — Dependency updates

> Versions below were resolved live from npmjs.com and api.nuget.org on **2026-08-06**. Re-verify before
> executing; treat every major bump as its own PR with the full test suite green.

### DEP-01 — Backend targets .NET 8 while already consuming 10.0.x packages

- **Problem** — All six C# projects declare `<TargetFramework>net8.0</TargetFramework>`, yet
  `Aumbrye.Infrastructure.csproj` already references `Microsoft.Extensions.Configuration.Binder` **10.0.10** —
  a package built for .NET 10. Mixing a 10.x framework package into a net8.0 target relies on netstandard
  fallbacks and can surface as runtime `MissingMethodException`. CI pins `dotnet-version: 8.0.x` and the
  OpenAPI drift check hardcodes `bin/Release/net8.0/` paths in two places.
  *(Verified — read all six `.csproj` files and `ci.yml`.)*
- **Action** — Move the entire backend to **.NET 10** and unify every Microsoft package on 10.0.x.
- **Location** — `services/backend/src/*/**.csproj`; `packages/shared/Aumbrye.Shared.csproj`;
  `packages/procedural/Aumbrye.Procedural.csproj`; `services/backend/tests/*/**.csproj`;
  `tools/procgen-cli/ProcgenCli.csproj`; `.github/workflows/ci.yml:14-45, 100-125`;
  `services/backend/Dockerfile`
- **Solution Hint** — Add a `Directory.Build.props` at the repo root with
  `<TargetFramework>net10.0</TargetFramework>`, `<Nullable>enable</Nullable>`, `<ImplicitUsings>enable</ImplicitUsings>`
  and `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`, then strip those from the individual `.csproj`
  files — this also removes the current inconsistency where only `Shared` and `Procedural` treat warnings as
  errors. Add a `global.json` pinning the SDK. Update the two hardcoded `net8.0` paths in `ci.yml` to `net10.0`,
  bump `setup-dotnet` to `10.0.x`, and rebase the Dockerfile onto the .NET 10 runtime image.

### DEP-02 — NuGet package versions

| Package | Current | Latest (2026-08-06) | Notes |
|---|---|---|---|
| `Microsoft.EntityFrameworkCore` | 9.0.18 | **10.0.10** | Major; review query-translation changes. |
| `Microsoft.EntityFrameworkCore.Design` | 9.0.18 | **10.0.10** | |
| `Microsoft.EntityFrameworkCore.Sqlite` | 9.0.18 | **10.0.10** | |
| `Npgsql.EntityFrameworkCore.PostgreSQL` | 8.0.11 | **10.0.3** | **Two majors behind.** Highest-risk bump. |
| `Npgsql.OpenTelemetry` | 8.0.6 | **10.0.3** | |
| `Microsoft.AspNetCore.Authentication.JwtBearer` | 8.0.11 | **10.0.10** | Ties to DEP-01. |
| `Microsoft.AspNetCore.Mvc.Testing` | 8.0.11 | **10.0.10** | |
| `Microsoft.Extensions.Hosting.Abstractions` | 8.0.1 | **10.0.10** | |
| `Microsoft.Extensions.Http` | 8.0.1 | **10.0.10** | |
| `Microsoft.Extensions.Configuration.Binder` | 10.0.10 | 10.0.10 | ✅ already current — but see DEP-01. |
| `Microsoft.IdentityModel.Tokens` | 8.3.0 | **8.22.0** | Security-relevant; prioritise. |
| `System.IdentityModel.Tokens.Jwt` | 8.3.0 | **8.22.0** | Security-relevant; prioritise. |
| `StackExchange.Redis` | 2.8.16 | **3.1.3** | Major; review connection/multiplexer API. |
| `Swashbuckle.AspNetCore` | 6.9.0 | **10.2.3** | **Four majors behind.** Will change generated OpenAPI — expect drift-check churn. |
| `AspNetCore.HealthChecks.NpgSql` | 8.0.2 | **9.0.0** | |
| `AspNetCore.HealthChecks.Redis` | 8.0.1 | **9.0.0** | |
| `OpenTelemetry.Exporter.OpenTelemetryProtocol` | 1.10.0 | **1.17.0** | |
| `OpenTelemetry.Extensions.Hosting` | 1.10.0 | **1.17.0** | |
| `OpenTelemetry.Instrumentation.AspNetCore` | 1.10.1 | **1.17.0** | |
| `OpenTelemetry.Instrumentation.Http` | 1.10.0 | **1.17.0** | |
| `BCrypt.Net-Next` | 4.0.3 | **4.2.1** | Security-relevant; prioritise. |
| `Microsoft.NET.Test.Sdk` | 17.11.1 | **18.8.1** | Major. |
| `xunit` | 2.9.2 | **2.9.3** | Patch. Consider evaluating xunit v3 separately. |
| `xunit.runner.visualstudio` | 2.8.2 | **3.1.5** | Major; pairs with the Test.Sdk bump. |
| `coverlet.collector` | 6.0.2 | **10.0.1** | Major. |

- **Action** — Sequence the bumps: (1) security packages (`IdentityModel*`, `BCrypt`) on net8.0 immediately;
  (2) framework retarget to net10.0 + all Microsoft/EF/Npgsql packages together; (3) `Swashbuckle` alone,
  because it will regenerate `packages/shared/openapi/aumbrye-api.v1.yaml` and trip the contract job;
  (4) test tooling (`Test.Sdk`, `xunit.runner.visualstudio`, `coverlet`) together; (5) `StackExchange.Redis`.
- **Location** — all `.csproj` files listed in DEP-01
- **Solution Hint** — Introduce `Directory.Packages.props` with `<ManagePackageVersionsCentrally>true</...>` so
  versions live in one file and cannot drift between projects (this is what allowed the 8.0/9.0/10.0 mix). Run
  `dotnet list package --outdated` after each step. For Swashbuckle, expect to regenerate the spec and the web
  client types in the same PR (`npm run generate:api`), since the `contract` CI job diffs both.

### DEP-03 — npm package versions (`apps/web`)

| Package | Current | Latest (2026-08-06) | Notes |
|---|---|---|---|
| `vite` | ^6.2.0 | **8.2.0** | **Two majors.** Do 6→7→8 in steps. |
| `vitest` | ^3.0.9 | **4.1.10** | Major; pairs with `@vitest/coverage-v8`. |
| `@vitest/coverage-v8` | ^3.0.9 | **4.1.10** | Must match `vitest` major. |
| `eslint` | ^9.22.0 | **10.8.0** | Major; flat-config changes. |
| `@eslint/js` | ^9.22.0 | **10.0.1** | Must match `eslint` major. |
| `typescript` | ~5.7.2 | **7.0.2** | **Do not bump blindly** — TS 7 is the native rewrite. Move to latest 5.x first, then evaluate 7 on a branch. |
| `typescript-eslint` | ^8.26.0 | **8.66.0** | Minor within v8. Safe. |
| `@vitejs/plugin-react` | ^4.3.4 | **6.0.5** | Two majors; pairs with the `vite` bump. |
| `react` / `react-dom` | ^19.0.0 | **19.2.8** | Minor. Safe. |
| `@types/react` | ^19.0.10 | **19.2.18** | Safe. |
| `@types/react-dom` | ^19.0.4 | **19.2.4** | Safe. |
| `react-router-dom` | ^7.4.0 | **7.18.2** | Minor. Safe. |
| `@tanstack/react-query` | ^5.69.0 | **5.101.4** | Minor. Safe. |
| `react-helmet-async` | ^2.0.5 | **3.0.0** | Major. |
| `@playwright/test` | ^1.51.0 | **1.62.1** | Minor; requires `npx playwright install` refresh. |
| `jsdom` | ^26.0.0 | **30.0.1** | **Four majors.** |
| `msw` | ^2.7.3 | **2.15.0** | Minor. Safe. |
| `@testing-library/react` | ^16.2.0 | **16.3.2** | Safe. |
| `@testing-library/jest-dom` | ^6.6.3 | **7.0.0** | Major. |
| `@testing-library/user-event` | ^14.6.1 | **14.6.3** | Safe. |
| `eslint-plugin-react-hooks` | ^5.2.0 | **7.1.1** | Two majors; new rules will fire. |
| `eslint-plugin-jsx-a11y` | ^6.10.2 | 6.10.2 | ✅ current. |
| `globals` | ^16.0.0 | **17.9.0** | Major. |
| `openapi-typescript` | ^7.6.1 | **7.13.0** | Minor. Safe. |
| `gray-matter` | ^4.0.3 | 4.0.3 | ✅ current. |
| `@prerenderer/rollup-plugin` | ^0.3.12 | 0.3.12 | ✅ current — but 0.x and Puppeteer-based; see WEB-01. |
| `@prerenderer/renderer-puppeteer` | ^1.2.4 | 1.2.4 | ✅ current. |

- **Action** — Three PRs: (1) all "safe" minors together; (2) tooling majors (`vite`, `@vitejs/plugin-react`,
  `vitest`, `@vitest/coverage-v8`, `jsdom`) together, since they interlock; (3) lint majors (`eslint`,
  `@eslint/js`, `globals`, `eslint-plugin-react-hooks`) together, expecting new lint failures.
  Hold TypeScript 7 for its own evaluation branch.
- **Location** — `apps/web/package.json`; `apps/web/package-lock.json`; `apps/web/eslint.config.js`;
  `apps/web/vite.config.ts`; `apps/web/vitest.config.ts`
- **Solution Hint** — `npm run lint && npm test && npm run build && npm run test:e2e` must be green after each
  PR. The `contract` CI job asserts `apps/web/package.json` `version` matches
  `packages/shared/Contracts/ApiVersions.cs` `ExpectedClientVersion` — bumping the web version requires the C#
  constant to move in the same commit.

### DEP-04 — Godot, GodotSteam and GitHub Actions

- **Problem** — Several toolchain pins are stale or broken:
  - `.godot-version` = `4.7.0` against a stated 4.7.1 target (BUG-10).
  - `addons/godotsteam/godotsteam.gdextension` declares `compatibility_minimum = "4.4"` and points at
    `win64/` and `linux64/` directories that **do not exist** — only `README.md`, the `.gdextension` and its
    `.uid` are present. The game therefore always runs in `SteamService` stub mode, and any Steam release is
    blocked on supplying binaries.
  - `.github/workflows/ci.yml` uses `lychee-action@v2` for the docs link check — that is not a valid action
    reference (the published action is `lycheeverse/lychee-action`), so that job cannot be resolving.
  - `chickensoft-games/setup-godot@v1` is used in both workflows; verify it still supports 4.7.x.
  - Local dev Node is **v22.15.0** while `apps/web/package.json` declares `"engines": {"node": ">=24"}` and CI
    uses Node 24 — a local/CI mismatch.
  *(Verified — read `.godot-version`, the `.gdextension`, `addons/godotsteam/` contents, both workflows, and
  `node -v`.)*
- **Action** — Pin Godot 4.7.1; supply or remove GodotSteam; fix the lychee action reference; align local Node.
- **Location** — `apps/game/client/.godot-version`; `apps/game/client/addons/godotsteam/godotsteam.gdextension`;
  `.github/workflows/ci.yml` (docs-link-check job, `setup-godot` steps); `apps/web/package.json`
- **Solution Hint** — For GodotSteam, download the 4.7-compatible release, place the `.dll`/`.so` under
  `win64/`/`linux64/`, and raise `compatibility_minimum` to `"4.7"`. If Steam is not a near-term target, delete
  the addon and keep `SteamService`'s stub path as the only path — the current half-state is worse than either.
  For lychee, use `lycheeverse/lychee-action@v2`. Add `.nvmrc` with `24` so local shells match CI.

---

## 10. 🟡 P2 — Backend and web

### BE-01 — No central package/framework version management

- **Problem** — Covered mechanically in DEP-01/DEP-02, but the root cause is structural: six `.csproj` files
  each declare their own `TargetFramework`, their own `Nullable`/`ImplicitUsings`, and their own package
  versions. Only `Shared` and `Procedural` set `TreatWarningsAsErrors`. This is how EF 9.0.18 and Binder 10.0.10
  ended up in the same project.
- **Action** — Introduce `Directory.Build.props` + `Directory.Packages.props` + `global.json`.
- **Location** — repo root (new files); all `.csproj` files
- **Solution Hint** — See DEP-01. Also apply `TreatWarningsAsErrors` uniformly — the API and Infrastructure
  projects currently do not have it, which is where most of the code lives.

### BE-02 — Two migrations share the same timestamp prefix

- **Problem** — `20260805120000_AddAccountSteamId.cs` and `20260805120000_InitialCreate.cs` carry the **same**
  `20260805120000` prefix. EF orders migrations lexicographically by id; two migrations with an identical
  timestamp have undefined relative order, and `AddAccountSteamId` depends on `InitialCreate` having run.
  *(Verified — listed the migrations directory. Note `AddAccountSteamId` has no `.Designer.cs` while the other
  three migrations do, which suggests it was hand-authored.)*
- **Action** — Regenerate the migration with a correct, later timestamp; confirm applied-migration history on
  any existing database before doing so.
- **Location** — `services/backend/src/Aumbrye.Infrastructure/Persistence/Migrations/`
- **Solution Hint** — If no production database exists yet, squash to a single `InitialCreate`. If one does,
  do **not** rename the applied migration — instead verify `__EFMigrationsHistory` ordering and add a
  `MigrationTests` case (the test file already exists) that applies migrations from empty and asserts the final
  schema. The missing `.Designer.cs` should be regenerated either way, since EF uses it for model snapshots.

### BE-03 — CI hardcodes `net8.0` build output paths in two places

- **Problem** — The OpenAPI verification steps in both the `backend` and `contract` jobs reference
  `src/Aumbrye.Api/bin/Release/net8.0/Aumbrye.Api.dll`. Any framework retarget silently breaks the drift check
  — or worse, the job fails in a way that looks like a spec mismatch.
  *(Verified — `ci.yml:33-40, 113-120`.)*
- **Action** — Derive the path from the target framework.
- **Location** — `.github/workflows/ci.yml:33-40, 113-120`
- **Solution Hint** — Set a workflow-level `env: TFM: net10.0` and interpolate, or use
  `dotnet build -o ./publish` and reference `./publish/Aumbrye.Api.dll`.

### WEB-01 — Prerendering depends on a 0.x plugin driving Puppeteer at build time

- **Problem** — `vite.config.ts` runs `@prerenderer/rollup-plugin` (v0.3.12 — pre-1.0) with a Puppeteer renderer
  and a fixed `renderAfterTime: 1000` heuristic across five routes. This makes every production build depend on
  downloading and launching Chromium, adds ~5 s of fixed wait, and silently produces empty prerendered HTML if a
  route takes longer than 1 s to settle.
  *(Verified — read `apps/web/vite.config.ts`.)*
- **Action** — Replace the time-based wait with an explicit readiness signal, or move to a first-party SSG path.
- **Location** — `apps/web/vite.config.ts:30-45`
- **Solution Hint** — Short term: switch `renderAfterTime` to `renderAfterElementExists: '[data-prerender-ready]'`
  and have each page set that attribute when its data has resolved. Medium term, given React 19 + React Router 7
  are already in place, evaluate React Router's framework mode (or `vite-plugin-ssr`/`vike`) for real SSG and
  drop the Puppeteer dependency from the build entirely.

### WEB-02 — Web app is small enough that its risk is concentrated in the API contract

- **Problem** — `apps/web/src` is 27 files. The meaningful failure mode is not app complexity but the
  hand-maintained parity between three artefacts: the C# `ExpectedClientVersion` constant, `package.json`
  `version`, and the generated `src/api/schema.d.ts`. CI asserts all three, which is good — but the assertion is
  a `jq` + `grep -oP` shell one-liner that will break on any formatting change to `ApiVersions.cs`.
  *(Verified — `ci.yml:126-129`.)*
- **Action** — Replace the shell parity check with a typed check.
- **Location** — `.github/workflows/ci.yml:126-129`; `packages/shared/Contracts/ApiVersions.cs`;
  `apps/web/package.json`
- **Solution Hint** — Add a unit test in `Aumbrye.UnitTests` that reads `apps/web/package.json` and asserts
  `ApiVersions.ExpectedClientVersion` matches, so the check lives in the test suite rather than in YAML.

### WEB-03 — Nested `<BrowserRouter>`, imported from two different packages

- **Problem** — `main.tsx` wraps `<App/>` in a `<BrowserRouter>` imported from **`react-router`**, and
  `App.tsx` renders a second `<BrowserRouter>` imported from **`react-router-dom`**. Nesting two routers
  means the inner one owns history and the outer one is inert; anything rendered between them that expects
  router context (or any future `useNavigate` call in `main.tsx`'s tree) talks to a router that does not
  drive the URL. Using two package specifiers for the same library also risks two copies of the router
  context in the bundle, in which case `useNavigate`/`useLocation` throw "may be used only in the context
  of a Router" depending on which specifier the calling module imported.
  *(Verified — read `apps/web/src/main.tsx:5` and `apps/web/src/App.tsx:1,14`. Note `App.test.tsx` renders
  `<App/>` inside a `MemoryRouter`, giving a third nesting level in tests — which is why the suite passes
  despite the defect.)*
- **Action** — Keep exactly one router, imported from one package.
- **Location** — `apps/web/src/main.tsx:5`; `apps/web/src/App.tsx:1,14`; `apps/web/src/App.test.tsx:3`
- **Solution Hint** — Remove the `<BrowserRouter>` from `App.tsx` and keep the one in `main.tsx` — that
  leaves `App` router-agnostic, which is what `App.test.tsx` already assumes when it supplies its own
  `MemoryRouter`. Standardise every import on `react-router-dom` (or on `react-router` v7's unified export,
  but not both) and add an ESLint `no-restricted-imports` rule for the loser so it cannot come back.

---

## 11. 🔵 P3 — Documentation

### DOC-01 — RESOLVED 2026-08-06: the two mirrored doc trees were removed

- **Problem** — `docs/` held 241 markdown files across two mirrored trees, `existing_codebase/` (117 files,
  descriptive) and `actual_improvements/` (116 files, prescriptive). Three independent measurements
  condemned them:
  1. **49% of anchored citations were stale** — 1,384 of 2,821 `file.gd:NN` citations no longer had the
     identifier the surrounding sentence named within +/-6 lines. "Moved" outnumbered "gone", i.e. the trees
     described an older revision.
  2. **Documents certified absent code as `IMPLEMENTED`.** `existing_codebase/audio-director.md` marked
     `_ensure_layer_streams()`, `_bake_fallback_tones()`, `_apply_profile_freqs()`, `_report_audio_content()`
     and a `LayerId` enum as IMPLEMENTED; **none of them exist** in `audio_director.gd`. It cited
     `audio_director.gd:789-798` in a 746-line file.
  3. **17 of 314 cited script paths pointed at files that never existed**, and 91 of 116 improvement plans
     were marked `Status: FINISHED` — completed work competing for attention with live work.
  *(Verified — automated citation audit plus manual verification of `combat-core.md`, `audio-director.md`,
  `enemies.md`, `ARCHITECTURE.md` and `SAVE_MIGRATIONS.md` against source.)*
- **Action** — **Done.** Both trees, `docs/MCP_AGENT_GUIDE.md`, the two `.batch*-prep.md` scratch files and
  the two twin-sync PowerShell scripts were deleted (233 files). The five surviving documents were rewritten
  against verified source. `docs_suite.gd` was repointed at `docs/`, and the four "doc exists" assertions in
  `m5_suite`, `m6_suite`, `m7_suite` and `progression_suite` were removed with the files they asserted on.
- **Location** — surviving set: `docs/ARCHITECTURE.md`, `docs/SAVE_MIGRATIONS.md`,
  `docs/ADR/0001-client-server-authority.md`, `docs/DOC-CONVENTIONS.md`,
  `docs/validation/manual-checklist.md`
- **Solution Hint** — *Remaining work:* add the CI guard that would have prevented this — extract every
  `apps/game/client/scripts/**.gd` path cited in `docs/**/*.md` and fail when one does not exist. The
  `docs-link-check` job is the natural home, but it currently references `lychee-action@v2`, which is not a
  valid action (see DEP-04). `DOC-CONVENTIONS.md` now mandates citing identifiers rather than line numbers,
  which removes the largest single source of the rot measured above.

### DOC-02 — Docstrings assert behaviour the code does not implement

- **Problem** — At least two load-bearing docstrings are false:
  `voxel_mesh_builder.gd:4` claims "greedy-merged voxel ArrayMeshes" (no greedy meshing exists — PERF-14), and
  `ContentLoader`'s header says the content root can be overridden "for exports" via `aumbrye/content_root`
  when that setting is empty and no export sets it (BUG-01). Docstrings that describe intent rather than
  implementation are worse than none.
  *(Verified — read both.)*
- **Action** — Correct them as part of the corresponding fixes; adopt a convention that docstrings describe
  behaviour, and intent goes in an ADR.
- **Location** — `apps/game/client/scripts/art/characters/voxel_mesh_builder.gd:4`;
  `apps/game/client/scripts/app/content_loader.gd:3-5`
- **Solution Hint** — `docs/DOC-CONVENTIONS.md` already exists — add the rule there and enforce it in review.

### DOC-03 — `SaveMigrator.STEPS_DOC` is an unread documentation table that is already out of sync

- **Problem** — `save_migrator.gd` declares `STEPS_DOC`, a parallel array intended to document each
  migration step's added/removed keys and recovery behaviour. It holds **8** entries against `STEPS`' **9**,
  stopping at the 8→9 step and omitting 9→10 entirely. It has **no reader anywhere in the project** —
  nothing validates it, nothing renders it. It is a documentation artefact with the same failure mode as the
  deleted doc trees, living inside the source file.
  *(Verified — counted entries in both arrays; grepped for `STEPS_DOC` across `apps/`: one hit, the
  declaration itself.)*
- **Action** — Either add a validation assertion that fails when `STEPS_DOC` and `STEPS` disagree, or delete
  `STEPS_DOC`.
- **Location** — `apps/game/client/scripts/save/save_migrator.gd` (`STEPS` and `STEPS_DOC` declarations)
- **Solution Hint** — The assertion is three lines in `save_suite.gd`: compare the `from`/`to` pairs of both
  arrays and fail on mismatch. That converts a silently-rotting table into a self-maintaining one, and gives
  `docs/SAVE_MIGRATIONS.md` a machine-checked source. If nobody wants that, delete `STEPS_DOC` — the markdown
  file is the only consumer that ever existed and it was maintained by hand.

---

## 12. 🔵 Future feature enhancements

These are opportunities, not defects. Each is sized against the architecture as it exists today, and several
become substantially cheaper once the P0/P1 items above land.

### FEAT-01 — Real adaptive music replacing procedural sine layers

- **Problem/Opportunity** — `AudioDirector` already models a four-layer system (ambience / explore / combat /
  boss) with crossfades, per-biome reverb presets, engagement counting, and stingers — genuinely good bones.
  All ten biome profiles do resolve real `.ogg` stems, so the synthesised fallback does not run in normal play
  (see the correction in PERF-06). What is missing is the layer *above* playback: the four stems crossfade on
  a discrete state, with no intensity blend, no vertical re-orchestration and no musical response to how a
  fight is actually going.
- **Action** — Commission or produce four stems per biome, wire them as the default, and add vertical
  re-orchestration on combat intensity.
- **Location** — `apps/game/client/scripts/audio/audio_director.gd`; `content/audio_profiles/*.json`;
  `apps/game/client/assets/audio/**`
- **Solution Hint** — The profile schema already has `layers.{ambience,explore,combat,boss}` with `path`,
  `volume_db` and `fallback_freq`. Add an `intensity` float driven by `_combat_engagements` + player health,
  and crossfade layer *gains* rather than swapping streams — the crossfade machinery is already there. Add a
  validation assertion that every declared path resolves (see PERF-06).

### FEAT-02 — Enemy AI: perception, group tactics and telegraph variety

- **Problem/Opportunity** — `CastleEnemyBase` implements PATROL/CHASE/INVESTIGATE/RETREAT/WINDUP/ATTACK/
  RECOVERY/STAGGER/DEAD with an attack-token system (`AttackTokenService`) that already limits simultaneous
  attackers — a strong foundation. What is missing: enemies do not communicate (no shared alert propagation),
  do not flank (chase is a straight line via `_apply_chase_velocity`), never use cover despite
  `DungeonBuilder._place_cover()` placing it, and `get_lock_priority()` returns a constant (DEAD-05).
- **Action** — Add a lightweight per-room blackboard for alert propagation and role assignment.
- **Location** — `apps/game/client/scripts/enemies/castle_enemy_base.gd`;
  `scripts/combat/attack_token_service.gd`; `scripts/dungeon/dungeon_builder.gd:416-442`
- **Solution Hint** — Extend `AttackTokenService` from "who may attack" to "who plays which role": token holders
  attack, non-holders are assigned `flank_left` / `flank_right` / `hold_cover` and get a positional goal instead
  of orbiting. Propagate aggro: when `_register_combat_engagement()` fires, notify the room's other enemies with
  a short delay so groups wake up organically. Do this **after** PERF-02 — the LOD system it needs is the same
  system that makes the extra logic affordable.

### FEAT-03 — Async floor streaming with a real loading experience

- **Problem/Opportunity** — Once PERF-03 makes floor construction chunked and threaded, the loading screen can
  become a feature rather than a stall: floor name, biome art, a tip, run stats, and a progress bar driven by
  the builder's `build_progress` signal.
- **Action** — Build a `SceneTransition` service that owns loading UI, threaded resource loading and progress.
- **Location** — new `apps/game/client/scripts/app/scene_transition.gd` (note: `docs/` already cites this file
  as though it exists — DOC-01); `scripts/ui/loading_screen.gd`; `scripts/app/run_scene_router.gd`
- **Solution Hint** — One API: `await SceneTransition.go_to(packed_or_path, {show_tips = true, biome = id})`.
  Every current `change_scene_to_file` call site routes through it.

### FEAT-04 — Lock-on target priority and soft-target assist

- **Problem/Opportunity** — `LockOn._find_best_target` scores by distance and cone angle only.
  `get_lock_threat()` exists and returns meaningful values (0.6 while winding up/attacking, 0.3 when aggroed),
  and `get_lock_priority()` exists but is a stub returning `0.0`. The scoring hook is already wired — it is just
  not fed.
- **Action** — Implement `get_lock_priority()` per archetype and fold threat + priority into the scoring
  function.
- **Location** — `apps/game/client/scripts/camera/lock_on.gd:361-400`;
  `scripts/enemies/castle_enemy_base.gd:74-75`; per-enemy overrides in `scripts/enemies/*.gd`
- **Solution Hint** — Return a value from content data (`_data.get("lockPriority", 0.0)`) so it is tunable
  without code changes — bosses 1.0, minibosses 0.7, ranged 0.5, trash 0.0. Score as
  `distance_score * angle_score - (threat + priority) * weight`. Add soft aim assist: when locked, bias the
  attack facing toward the target by up to a few degrees (`weapon_controller.gd:645` already computes the facing).

### FEAT-05 — Accessibility beyond the existing settings

- **Problem/Opportunity** — There is real accessibility work already: `AccessibilitySettings` with camera FOV,
  stick deadzone/curve, invert-Y and sensitivity; a colourblind status-icon atlas
  (`status_icon_atlas.gd:60` handles protanopia/deuteranopia/tritanopia); `ui_text_scale.gd`; input rebinding
  with a capture modal. Gaps: no subtitle/caption system for the dialogue runner, no screen-shake or
  hitstop intensity slider (both are hardcoded in `VfxService`), no high-contrast HUD mode, no
  reduced-motion toggle for the pixel screen-finish shader pulses.
- **Action** — Add intensity sliders for shake/hitstop/screen-pulse, a reduced-motion master toggle, and
  dialogue captions.
- **Location** — `apps/game/client/scripts/accessibility/accessibility_settings.gd`;
  `scripts/art/vfx/vfx_service.gd` (`_shake_amount`, `_update_hitstop`);
  `scripts/art/pipeline/pixel_diorama_viewport.gd:312-333` (`pulse_screen`);
  `scripts/dialogue/dialogue_runner.gd`; `scripts/ui/settings_schema.gd`
- **Solution Hint** — `settings_schema.gd` is data-driven, so new sliders are mostly a schema entry plus a
  multiplier read at the point of use. Route all three effect intensities through
  `AccessibilitySettings.effect_intensity` so one "reduced motion" toggle can zero them together. Note that
  `a11y_suite.gd` currently asserts accessibility by checking a file *exists* — convert those to behavioural
  assertions as part of QA-01.

### FEAT-06 — Deterministic replay and seed sharing

- **Problem/Opportunity** — The infrastructure is unusually close: `DungeonSeedDeriver` (C#) and
  `floor_seed_mix.gd` (GDScript) derive per-floor seeds from a run seed; `castle_entry_menu.gd` already accepts
  a typed seed; `start_run_with_seed()` exists on `RunFlow`; `procgen_seed_health.gd` sweeps 500 seeds in CI.
  What is missing is input recording.
- **Action** — Record the input stream + run seed to enable replay, seeded daily challenges and shareable runs.
- **Location** — `apps/game/client/scripts/app/run_flow.gd:124-130`;
  `scripts/dungeon/floor_seed_mix.gd`; `scripts/app/player_input.gd`; `packages/procedural/Generation/DungeonSeedDeriver.cs`
- **Solution Hint** — This is only feasible if REF-02 is resolved (one authoritative generator) **and**
  PERF-12's fixed physics tick is in place — replay determinism requires a fixed timestep and a single
  generator. Sequence it after both. A "daily seed" leaderboard is the natural first product on top, and the
  leaderboard backend already exists (`LeaderboardsEndpoints.cs`, `RedisLeaderboardService.cs`).

### FEAT-07 — Data-driven enemy authoring without per-enemy scripts

- **Problem/Opportunity** — There are 35 files under `scripts/enemies/`, most of which are thin subclasses of
  `CastleEnemyBase` overriding `_resolve_enemy_id()` and occasionally `_process_chase()`. Meanwhile the real
  behaviour is already almost entirely in `content/enemies/*.json` (health, poise, ranges, attacks, combos,
  telegraphs, status effects, weapon kits). The per-enemy scripts are mostly ceremony.
- **Action** — Collapse the archetype subclasses into a small set of behaviour strategies selected by content
  data.
- **Location** — `apps/game/client/scripts/enemies/**` (35 files);
  `content/enemies/*.json`; `content/bosses/*.json`; `scenes/enemies/*.tscn`
- **Solution Hint** — Identify the genuine behavioural variants (melee, ranged, shield, brute, caster, hound,
  swarm, boss-phase) and implement each as a `RefCounted` strategy the base class instantiates from
  `_data.get("behavior", "melee")`. Scenes then all reference `castle_enemy_base.gd` with a `catalog_id` export.
  This removes ~30 files, makes new enemies a JSON change, and pairs naturally with REF-04 (typed tuning) and
  PERF-02 (AI LOD).

### FEAT-08 — Room content variety and run modifiers

- **Problem/Opportunity** — `scripts/dungeon/room_content/` already defines 12 content types (hazard, locked
  door, locked vault, lore, merchant, NPC quest, puzzle, puzzle gate, rest, reward, trap). `run_modifier_service.gd`
  exists. `content/affixes/` exists. This is the scaffolding for a Hades/Dead-Cells-style run-variance system
  that is currently underused.
- **Action** — Add run modifiers (curses/blessings) selected at floor transitions, and weight room content by
  the active modifier set.
- **Location** — `apps/game/client/scripts/dungeon/run_modifier_service.gd`;
  `scripts/dungeon/procgen/room_content_assigner.gd`; `content/affixes/**`; `scripts/combat/run_buffs.gd`
- **Solution Hint** — `RunBuffs` is already an autoload and `room_content_assigner.gd` already weights content
  by room kind — extend the weight table with modifier multipliers rather than adding a parallel system. Surface
  the choice at the existing stair menu (`scripts/ui/stair_menu.gd`), which is already the floor-transition
  decision point.

---

## 13. 🎮 Improvement — closing the gap to the intended game

Sections 3–12 answer *what is broken*. This section answers *what already works but is not yet the game it
is meant to be*. Every item is measured against the stated design target and follows the same
Problem / Action / Location / Solution Hint shape.

The single most important measurement behind this section:

| Design pillar | What the code supports | What the content uses | Gap |
|---|---|---|---|
| Enemy movesets | `attacks[]` with per-attack damage, damage type, status, telegraph shape/radius, wind-up variance and `combo_followups` | **Zero** of 29 enemies and 11 bosses define `attacks` at all | Every enemy in the game has exactly one attack |
| Boss design | `_is_boss_enemy()` = "id contains 'boss'"; no phase system | 11 boss files, all with the same 10 flat keys as a grunt | No boss has phases, adds or a second move set |
| Biome roster | 10 biomes, 10 dungeons | 5 distinct enemy families, 5 distinct bosses | Dungeons 6–10 are verbatim palette swaps of 1–5 |
| Dungeon tiers | `DungeonTierService.MAX_TIER = 10` (unlock **count**) | `difficultyTiers` = 3 per dungeon | "10 tiers" exists as a dungeon ladder, not a difficulty ladder |
| Endless biomes | — | `start_endless_run()` hardcodes `BIOME_UMBRAL` | One biome, forever (`BUG-33`) |
| Floor skips | 4 rungs | 10 / 50 / 100 / 500 | 250 missing (`BUG-34`) |
| Rooms per floor | `roomCount` per biome | 9 of 10 biomes are `{min: 6, max: 10}` | Six-room dungeon floors |
| Floor verticality | `max_height_level` honoured by the generator | No biome declares `maxHeightLevel` | Every floor is flat; the height code is dead |
| Affix pool | Weighted prefixes + suffixes with per-rarity tiers | 7 prefixes + 7 suffixes = **14 affixes** | Six rarity tiers drawing from 14 affixes |
| Items | 90 item files | 21 weapons, 36 armour, 7 accessories, 9 consumables, 17 materials | 8 weapon archetypes, 1 shield |
| Inventory | Rect-packed grid, `gridWidth`/`gridHeight` per item | Grid is 6×4 = 24 cells; **64 of 90 items are 2×2** | Six equipment pieces fill the entire bag |
| Narrative | Branching dialogue with conditions and actions | 3 NPCs, 5 dialogue trees of 1–3 nodes, 4 quests | No story, no quest chains, no lore system |
| Statuses | Stacking status controller | 5 statuses (bleed, burn, freeze, poison, stun) | No buffs-as-statuses, no debuff variety |
| Traps | Trap pool per biome | 5 traps, 2 per biome | Traps are decoration, not a mechanic |

### A — Combat feel: Soulslike weight with snappy response

### IMP-A01 — The dodge costs 700 ms of agency for 250 ms of invulnerability

- **Problem** — `DODGE_DURATION = 0.45` and `DODGE_RECOVERY = 0.25` mean a roll takes 0.70 s during which the
  player has no control at all: `Dodge._process_dash()` overwrites `velocity.x/z` outright for the whole
  0.45 s, and `locks_movement()` then holds movement for another 0.25 s. Inside that, i-frames run from
  `IFRAME_START = 0.05` to `IFRAME_END = 0.30` — 0.25 s, or 36 % of the commitment. Dark Souls' medium roll is
  ~0.55 s total with ~0.43 s of i-frames (78 %), and has no post-roll movement lock at all. The current ratio
  reads as sluggish rather than deliberate: the player is punished for the roll's *tail*, which they cannot
  see, rather than for its *timing*, which they can.
- **Action** — Re-proportion the roll so most of its duration is invulnerable, and replace the hard recovery
  lock with a soft speed ramp.
- **Location** — `apps/game/client/scripts/player/dodge.gd` (`DODGE_DURATION`, `DODGE_RECOVERY`,
  `IFRAME_START`, `IFRAME_END`, `_process_dash`, `locks_movement`)
- **Solution Hint** — Target 0.10–0.45 i-frames inside a 0.55 s roll, and make `DODGE_RECOVERY` a period
  during which movement input is *accepted at reduced speed* (blend from `DODGE_END_SPEED` back to walk speed)
  instead of `locks_movement() == true`. Weight class should drive these numbers — `configure()` already
  accepts `weight_class` but currently uses it only for a stamina multiplier; make light rolls faster with
  proportionally more i-frames and heavy rolls slower with fewer, so armour weight becomes a real build
  decision. Expose all six numbers in `content/` per `REF-10`'s tuning-data principle.

### IMP-A02 — There is no attack cancel window, so the combat reads as committed rather than snappy

- **Problem** — `WeaponController._can_dodge_cancel()` allows a roll only in the last 45 % of `RECOVERY`, and
  nothing at all can cancel `STARTUP` or `ACTIVE`. There is no block-cancel, no sprint-cancel, no
  hit-confirm-dependent cancel and no combo-into-heavy branch — `_try_attack("heavy")` while a light is
  running only sets `_buffered_attack`, which replays the same linear `light_attacks` chain. Modern Soulslikes
  earn "snappy" from three things this build has none of: an early cancel into guard, a light→heavy branch,
  and directional attack variants. What exists is a single fixed combo string per weapon.
- **Action** — Add a cancel table to the attack definition and branch the combo on input.
- **Location** — `apps/game/client/scripts/combat/weapon_controller.gd` (`_can_dodge_cancel`, `_try_attack`,
  `_process_attack_phase`, `_end_attack`, `locks_movement`); `content/weapons/*.json`
- **Solution Hint** — Give each attack entry `cancel_into: ["dodge", "guard"]` and `cancel_after: 0.55`
  (fraction of recovery), and read them in `locks_movement()` / `_is_action_blocked()` rather than hardcoding
  the 0.55. For branching, let `light_attacks[i]` declare `heavy_branch: <index into heavy chain>` so a
  light-light-heavy finisher is authorable. Keep the existing `buffer_window` semantics — they are correct —
  but fix `BUG-06` first, because the duplicated buffer block currently fires buffered attacks outside their
  window and masks how the timing actually feels.

### IMP-A03 — Backstabs and ripostes exist as damage multipliers, not as actions

- **Problem** — A backstab is `BACKSTAB_DAMAGE_MULT = 1.6` applied inside `Hurtbox._apply_arc_multipliers()`;
  a riposte is `RIPOSTE_DAMAGE_MULT = 2.0` applied inside `_enable_hitbox_for_attack()` when
  `Guard.riposte_active` is set. Neither has an animation, a camera move, a positional snap, a distinct sound,
  a hit-stop, or an unblockable guarantee. The player cannot tell a backstab happened except by watching a
  damage number. In the genre these are the reward beats — the moments a run is remembered for — and here they
  are invisible arithmetic. `RIPOSTE_WINDOW = 1.4` s is also generous enough that the riposte often lands on a
  different enemy than the one parried, because nothing binds the window to the parried target.
- **Action** — Promote both to first-class actions with committed animations and a bound target.
- **Location** — `apps/game/client/scripts/combat/guard.gd` (`try_parry_attack`, `riposte_active`,
  `RIPOSTE_WINDOW`, `get_riposte_damage_multiplier`, `consume_riposte`);
  `apps/game/client/scripts/combat/hurtbox.gd` (`_apply_arc_multipliers`);
  `apps/game/client/scripts/combat/weapon_controller.gd` (`_enable_hitbox_for_attack`);
  `apps/game/client/scripts/player/player_anim_director.gd`
- **Solution Hint** — Store the parried node on `Guard` and require the riposte's hitbox to hit *that* node.
  Add `riposte` and `backstab` clips to the anim director's priority stack (it already owns one-shot
  attack/stagger/death clips), snap the player to a position offset from the victim's transform on
  execution, grant i-frames for the animation's duration, and route the hit through
  `info.ignore_guard = true`. `HitFeedback` already exists for hit-stop and camera shake — this is the single
  highest-leverage use of it. Depends on `BUG-20` (facing convention) being fixed first.

### IMP-A04 — Blocking is a flat 55 % reduction with no stability, no chip identity and no shield variety

- **Problem** — `Guard.BLOCK_DAMAGE_REDUCTION = 0.55` and `BLOCK_POISE_TRANSFER = 0.35` are constants; the
  per-shield `stability` and `reduction` that `set_combat_stat_modifiers()` was written to consume are never
  passed (`BUG-19`), and exactly one item in the entire catalogue uses the `secondary` equipment slot. So
  every block in the game is identical, and there is no reason to ever change shield. There is also no
  distinction between physical and elemental block (`modify_incoming_hit` ignores `info.damage_type`), no
  guard-counter, and no two-handed "no shield" trade-off beyond the flat `TWO_HAND_DAMAGE_MULT = 1.25`.
- **Action** — Make the shield the variable, and make blocking type-aware.
- **Location** — `apps/game/client/scripts/combat/guard.gd` (`modify_incoming_hit`,
  `set_combat_stat_modifiers`, `BLOCK_DAMAGE_REDUCTION`, `BLOCK_POISE_TRANSFER`);
  `content/items/equipment/`; `apps/game/client/scripts/items/equipment.gd` (`SLOT_ORDER`)
- **Solution Hint** — Fix `BUG-19` first so `block_data` arrives, then author a `block` object per shield:
  `{ "stability": 1.4, "reduction": { "physical": 0.85, "fire": 0.45, … }, "guardBreakPoise": 60 }`. Read the
  per-type reduction in `modify_incoming_hit` using `info.damage_type`. Author six to eight shields spanning
  light-parry-focused to greatshield, which gives the `secondary` slot a reason to exist and gives
  `IMP-F02`'s build variety an anchor.

### IMP-A05 — Hit feedback is well built and mistuned; fix the timing before adding anything to it

> **Corrected 2026-08-06.** An earlier draft of this item claimed there was no hit-stop, no camera kick and
> no rumble. That was wrong: `HitFeedback` implements hit-stop, a weighted camera punch, screen shake,
> controller vibration, damage numbers, a damage vignette, per-material hit SFX and a diorama flash, and
> `AccessibilitySettings` gates all of it. The gap is not that the layer is missing — it is that its timing
> is broken and its vocabulary is flat.

- **Problem** — Three things, in descending order of impact. (1) **The timing is wrong**: hit-stop measures
  its own duration on the scaled clock it just slowed, so an authored 0.09 s freeze lasts ~1.13 s of real time
  (`BUG-40`), and a second hit inside the window locks the game at 8 % speed forever (`BUG-39`). Whatever the
  intended feel was, nobody has experienced it. (2) **The vocabulary is flat**: `_apply_hitstop(weight)` takes
  one scalar derived from `clampf(damage / 20.0, 0.85, 1.35)` — a range of 1.6× — so a chip hit on a shield,
  a clean heavy and a riposte all freeze for approximately the same time. There is no distinct impact class
  for critical, backstab or riposte. (3) **The attacker gets no camera response**: `_apply_camera_punch` is
  called from `on_hit` with the *victim's* `HitFeedback` on `on_hit_received`, but `OrbitCamera.apply_punch`
  only ever moves the camera of whoever owns that `HitFeedback` — so landing a blow on an enemy punches the
  *enemy's* (nonexistent) camera, not the player's.
- **Action** — Fix the timing, then widen the impact vocabulary from one scalar to three named classes.
- **Location** — `apps/game/client/scripts/combat/hit_feedback.gd` (`_apply_hitstop`, `_process`,
  `_apply_camera_punch`, `on_hit`, `on_hit_received`, `on_hit_blocked`, `_on_parry_success`);
  `apps/game/client/scripts/combat/hurtbox.gd` (`_emit_victim_feedback`);
  `apps/game/client/scripts/camera/orbit_camera.gd` (`apply_punch`, `apply_shake`, `apply_camera_dip`)
- **Solution Hint** — `BUG-39` and `BUG-40` first; they are two-line fixes and they change the game more than
  anything else in this section. Then replace the scalar weight with an impact class — `GLANCING`, `SOLID`,
  `CRITICAL` — resolved from the `DamageResolution` that `Hurtbox` already builds (it carries `crit`,
  `backstab`, `blocked` and `absorbed_by_poise`), each mapping to its own freeze length, shake amplitude,
  vibration curve and audio layer. Route the attacker-side punch explicitly: `Hurtbox` knows `info.source`, so
  it can call the *attacker's* `HitFeedback` for the outgoing feel and the victim's for the incoming one.
  Prefer freezing the animators over `Engine.time_scale` where possible (`BUG-41` explains why the global is
  dangerous), keeping the global freeze for the rare `CRITICAL` class only.

### IMP-A06 — Weapon archetypes differ only in hitbox size and numbers

- **Problem** — `WeaponController._apply_hitbox_profile()` switches on archetype to pick a box size and offset;
  `content/weapons/` holds 8 files. Beyond the box dimensions, a spear, an axe and a greatsword differ only in
  their damage/stamina/timing numbers. There are no thrust-vs-sweep hit shapes (every hitbox is a
  `BoxShape3D`), no per-archetype combo lengths in practice, no running or rolling attacks, no jump attacks,
  and `art` (weapon art) is optional data that most weapons do not define. In a Soulslike the weapon *is* the
  build; here it is a stat block with a differently sized box.
- **Action** — Give each archetype a distinct move set and hit shape, not just distinct numbers.
- **Location** — `apps/game/client/scripts/combat/weapon_controller.gd` (`_apply_hitbox_profile`,
  `FALLBACK_WEAPON_DATA`, `_try_weapon_art`); `content/weapons/*.json`;
  `apps/game/client/scripts/combat/hitbox.gd`
- **Solution Hint** — Move the hitbox profile out of the `match` and into the weapon JSON as a shape
  descriptor (`{"shape": "capsule", "radius": 0.35, "height": 2.2}` for thrusts, a swept arc for sweeps), which
  removes a hardcoded archetype list *and* enables shapes the box cannot express. Then author per-archetype
  `light_attacks` chains of different lengths, a `running_attack` and a `rolling_attack` keyed off
  `Dodge.is_dodging` / `_sprint_blend`, and a weapon art for every weapon. Eight archetypes × a real move set
  is the cheapest path from "8 weapons" to "8 playstyles".

### B — Enemies and bosses

### IMP-B01 — Every enemy in the game has exactly one attack

- **Problem** — `CastleEnemyBase._select_attack_data()` reads `_data.get("attacks", [])`, and the state machine
  supports per-attack `windup_duration`, `windup_variance`, `active_duration`, `recovery_duration`,
  `attack_damage`, `attack_poise_damage`, `damage_type`, `status_on_hit`, `telegraph_radius`,
  `telegraph_shape` and `combo_followups`. **Not one of the 29 enemy JSON files or 11 boss JSON files defines
  `attacks`.** Every enemy therefore falls back to the single top-level `attack_damage` / `windup_duration`
  triple. The engine's entire combat-variety capability is built, tested and unused. This is the largest
  single gap between what the game can do and what the game does.
- **Action** — Author move sets. This is a content task, not an engineering task, and it is the highest-value
  work available.
- **Location** — `content/enemies/*.json` (29 files); `content/bosses/*.json` (11 files);
  `apps/game/client/scripts/enemies/castle_enemy_base.gd` (`_select_attack_data`, `_start_windup`,
  `_end_attack`)
- **Solution Hint** — Two or three attacks per basic enemy and four to six per boss, differentiated by range,
  wind-up length and punish window: a fast poke the player must roll, a slow overhead they can circle behind,
  and a delayed swing that punishes panic rolls. Use `windup_variance` so the same attack is not memorised as
  a metronome, and `combo_followups` for the two-hit strings that make crowd fights readable. Fix `BUG-25`
  (combo follow-ups have no telegraph) before authoring combos, and `BUG-35` (global RNG in wind-up variance)
  before relying on variance for balance. Add a content-schema rule requiring `attacks` to be non-empty so new
  enemies cannot regress to the fallback.

### IMP-B02 — No boss has phases; bosses are grunts with more HP

- **Problem** — Every file in `content/bosses/` carries the identical flat key set as a regular enemy. There is
  no phase threshold, no phase-transition beat, no arena mechanic, no add spawn, no enrage, no second move
  set. `boss_castle_knight` and `castle_grunt` are the same behaviour with `health` 900-ish versus 90.
  `scripts/bosses/` contains six scripts, but they cover arena setup and presentation, not fight logic. The
  boss fight is the payoff of a Soulslike run, and right now it is a longer version of a corridor fight.
- **Action** — Build a phase system and author real fights.
- **Location** — `content/bosses/*.json`; `apps/game/client/scripts/bosses/`;
  `apps/game/client/scripts/enemies/castle_enemy_base.gd` (`_is_boss_enemy`);
  `apps/game/client/scripts/dungeon/boss_room_door.gd`
- **Solution Hint** — See `REF-13` for the structural change. On top of it, each boss gets at least two phases
  with a threshold (`"phases": [{"hpBelow": 1.0, "attacks": [...]}, {"hpBelow": 0.5, "attacks": [...],
  "onEnter": {"vfx": …, "invulnerableFor": 1.2, "spawnAdds": [...]}}]`), a distinct opening tell so the player
  learns the phase change, and one arena interaction (`final_boss_cannon.gd` already demonstrates the pattern
  for the castle finale). Five bosses with two phases each beats eleven bosses with none.

### IMP-B03 — Enemies walk in a straight line and then stand still

- **Problem** — `_apply_chase_velocity()` sets `velocity = to_player.normalized() * move_speed` with no
  pathfinding, no obstacle avoidance and no navigation mesh anywhere in the project — an enemy separated from
  the player by a pillar walks into the pillar. When `dist <= attack_range * 0.85` it sets
  `velocity = Vector3.ZERO`: an enemy on cooldown, or one refused an attack token (`BUG-26`), stands
  motionless at melee range facing the player. There is no strafing, no circling, no backing off, no flanking
  and no spacing. `AttackTokenService` limits how many enemies attack at once, which is the right idea, but
  the enemies it holds back do nothing instead of repositioning — so a group fight is one enemy attacking and
  three statues.
- **Action** — Add navigation and a reposition behaviour for non-attacking enemies.
- **Location** — `apps/game/client/scripts/enemies/castle_enemy_base.gd` (`_apply_chase_velocity`,
  `_process_chase`, `_process_patrol`, `State`);
  `apps/game/client/scripts/combat/attack_token_service.gd`;
  `apps/game/client/scripts/dungeon/dungeon_builder.gd`
- **Solution Hint** — Bake a `NavigationRegion3D` per room in `DungeonBuilder` (rooms are already assembled
  from a known set of template scenes, so the bake is cheap and cacheable per template) and drive movement
  through `NavigationAgent3D`. Add `CIRCLE` and `REPOSITION` states entered when an attack token is refused or
  a cooldown is running: orbit the player at `attack_range * 1.4` with a per-enemy seeded direction, so a group
  visually surrounds rather than queues. This is the change that makes crowd fights read as Soulslike rather
  than as a conga line.

### IMP-B04 — Dungeons 6–10 are palette swaps with no new enemies or bosses

- **Problem** — `glacial_hollow`'s `enemyPool` is `frost_raider`/`frost_archer`/`frost_knight`/`frost_hound` —
  identical to `frozen_fortress` — with the same `boss_frost_warlord`. `iron_vault`'s pool is identical to
  `forgotten_castle`'s, with `boss_castle_knight`. `prism_depths` reuses crystal enemies, `venom_mire` reuses
  swamp enemies, `umbral_chapel` reuses cathedral enemies. So the second half of the ten-dungeon ladder — the
  part a player reaches after hours of investment — introduces no new opponent. `frozen_fortress` even lists
  `miniboss_castle_captain` in its boss pool, putting a castle miniboss inside an ice fortress.
- **Action** — Author a distinct enemy family and boss for each of the five reused biomes.
- **Location** — `content/biomes/{iron_vault,prism_depths,venom_mire,glacial_hollow,umbral_chapel}.json`
  (`enemyPool`, `bossPool`); `content/enemies/`; `content/bosses/`
- **Solution Hint** — Four enemies plus one miniboss plus one boss per biome is 25 enemy files and 5 boss
  files. Reuse the existing rigs and animation profiles where the silhouette allows, but give each family one
  mechanical identity the player must learn — a shield-wall unit that must be flanked, a caster that must be
  closed down, a swarm that punishes wide swings. Pair this with `IMP-B01`: a new enemy with one attack is
  still not a new enemy. Fix the misplaced `miniboss_castle_captain` entry in `frozen_fortress` while there.

### IMP-B05 — Enemy perception is a distance check plus one raycast; there is no awareness state

- **Problem** — `_has_aggro()` tests `distance_to(player) <= aggro_range` and one line-of-sight ray, then
  latches `_aggro_locked = true`. There is no sound propagation (sprinting past an enemy is as quiet as
  sneaking), no vision cone (an enemy facing away sees the player perfectly), no gradual awareness ramp, no
  alert-the-neighbours behaviour, and no unaware state to reward approach. `DEAGGRO_LOS_TIMEOUT = 3.0` is the
  only nuance. Backstabs (`IMP-A03`) have no setup because nothing is ever unaware.
- **Action** — Introduce a perception model with a vision cone, a hearing radius and an awareness meter.
- **Location** — `apps/game/client/scripts/enemies/castle_enemy_base.gd` (`_has_aggro`,
  `_has_line_of_sight_to_player`, `_drop_aggro`, `State.INVESTIGATE`);
  `apps/game/client/scripts/player/locomotion.gd` (`_sprint_blend`, `play_footstep_effects`)
- **Solution Hint** — Awareness as a 0→1 float that fills faster inside a forward cone and at close range, and
  is fed by a noise value the player emits (sprinting loud, walking quiet, rolling loud) — `play_footstep_effects`
  is already the single place footsteps are emitted, so it is the natural hook. `State.INVESTIGATE` already
  exists and already walks to `_last_known_player_pos`; wire partial awareness into it. On full alert, notify
  enemies within a radius so groups activate together, which makes room layout (`IMP-E02`) mean something.

### C — Dungeon mode: ten tiers, replayable

### IMP-C01 — "Ten tiers" is a ten-dungeon unlock ladder; each dungeon has only three difficulty tiers

- **Problem** — Two different things are both called "tier". `DungeonTierService.MAX_TIER = 10` counts how many
  **dungeons** are unlocked and labels the hub portal `"Aumbrye Dungeons — Tier N"`; `DungeonCatalog.order`
  runs 1–10 across the ten dungeon files. Separately, each dungeon JSON has a `difficultyTiers` array with
  exactly **three** entries, capped by `DungeonTierService.get_unlocked_difficulty_cap()`. The intended design
  — ten tiers of rising difficulty, each unlocked by clearing the previous, all replayable — maps onto the
  *difficulty* axis, not the dungeon axis, and that axis stops at three.
- **Action** — Extend `difficultyTiers` to ten per dungeon and separate the vocabulary.
- **Location** — `content/dungeons/*.json` (`difficultyTiers`);
  `apps/game/client/scripts/dungeon/dungeon_tier_service.gd` (`MAX_TIER`, `HUB_LABEL_PREFIX`,
  `get_unlocked_difficulty_cap`, `on_dungeon_cleared`);
  `apps/game/client/scripts/dungeon/dungeon_catalog.gd` (`max_difficulty_tier`,
  `get_difficulty_tier_data`); `apps/game/client/scripts/dungeon/castle_tier_difficulty.gd`
- **Solution Hint** — Author ten `difficultyTiers` entries per dungeon with `hpMult`, `damageMult`,
  `lootBonus`, a `label` and a `modifiers` array — the plumbing already reads all five. Rename the dungeon axis
  to "depth" or "dungeon" in `HUB_LABEL_PREFIX` and the menu title so "tier" means exactly one thing.
  `on_dungeon_cleared(dungeon_id, difficulty_tier)` already unlocks `difficulty_tier + 1` capped at
  `max_difficulty_tier`, so the unlock ladder works unchanged once the data has ten rungs. Generating the ten
  entries from a curve in `content/` (per `REF-10`) is better than hand-authoring 100 objects.

### IMP-C02 — Difficulty tiers change only two multipliers, so higher tiers are the same fight with bigger numbers

- **Problem** — `CastleTierDifficulty` exposes `hp_multiplier`, `damage_multiplier` and `loot_bonus`, all read
  straight from the tier JSON. `RunModifierService` defines exactly three named modifiers — `elite_packs`,
  `no_rest`, `sealed_doors` — and `DungeonCatalog.get_modifiers_for_difficulty()` reads a per-tier `modifiers`
  array that the shipped dungeon files leave unused. So tier 3 is tier 1 with more HP. A player who has beaten
  tier 1 has no new decision to make at tier 3, which is exactly the point at which a roguelite loses people.
- **Action** — Make each tier introduce a rule, not a multiplier.
- **Location** — `content/dungeons/*.json` (`difficultyTiers[].modifiers`);
  `apps/game/client/scripts/dungeon/run_modifier_service.gd` (`MODIFIER_*`, `ENDLESS_MODIFIER_ORDER`);
  `apps/game/client/scripts/dungeon/castle_tier_difficulty.gd`
- **Solution Hint** — Grow the modifier vocabulary to fifteen or twenty and attach two or three to each tier:
  enemy affixes (armoured, frenzied, volatile, spectral), rule changes (no healing items, one estus charge,
  fog of war, doors lock behind you until the room is cleared, elite guaranteed per floor), and reward changes
  (double affix rolls, guaranteed rare from the boss). `run_modifier_service.gd` is 48 lines and already has
  `has_modifier()` for consumers to query, so most of the cost is in the consumers — enemy spawning
  (`room_content_assigner.gd`), rest rooms (`room_rest_content.gd`), doors (`room_locked_door_content.gd`) —
  each of which needs one `if RunModifierService.has_modifier(...)`.

### IMP-C03 — Tier selection is a dropdown, not a progression screen

- **Problem** — `CastleEntryMenu` presents two `OptionButton`s (dungeon, difficulty) and three buttons. There
  is no indication of which tiers have been cleared, what a tier's modifiers are, what the reward difference
  is, what the player's best time or best depth was, or what is unlocked next. The selection is also discarded
  every time the menu opens (`BUG-38`). A ten-tier replayable ladder is a progression fantasy, and the UI
  presents it as a form.
- **Action** — Replace the dropdowns with a tier ladder that shows state, stakes and rewards.
- **Location** — `apps/game/client/scripts/ui/castle_entry_menu.gd` (`_build_dungeon_dropdown`,
  `_build_difficulty_dropdown`); `apps/game/client/scripts/dungeon/dungeon_tier_service.gd`;
  `apps/game/client/scripts/ui/game_ui_skin.gd`
- **Solution Hint** — A grid of ten tier cards per dungeon: cleared / available / locked, with the tier's
  modifier icons, its loot bonus, and the player's best result. `CharacterService` flags already persist the
  difficulty cap per dungeon (`dungeon_tier_<id>`), so recording a per-tier best result is the same mechanism.
  `game_ui_skin.gd` already owns the pixel UI vocabulary this should be built from (`IMP-J03`).

### IMP-C04 — Ten dungeon floors, six rooms each, with no run-shaping decisions

- **Problem** — `RunFloorConfig.MAX_FLOORS = 10` and nine of ten biomes generate 6–10 rooms per floor, so a
  full dungeon clear is roughly 60–100 rooms of which the critical path is about 40. Between floors the only
  decision point is `stair_menu.gd`. There is no branching path choice, no risk/reward fork, no optional
  challenge room with a stake, and no reason to explore off the critical path beyond a chest — `min_dead_ends`
  is 2 or 3. A roguelite is a sequence of interesting decisions; this is a sequence of rooms.
- **Action** — Add a between-floor choice and make off-path exploration a real trade.
- **Location** — `apps/game/client/scripts/dungeon/run_floor_config.gd` (`MAX_FLOORS`);
  `apps/game/client/scripts/ui/stair_menu.gd`;
  `apps/game/client/scripts/dungeon/procgen/room_content_assigner.gd`;
  `apps/game/client/scripts/dungeon/run_modifier_service.gd`
- **Solution Hint** — At each stairwell, offer two or three seeded descent options with visible trade-offs
  ("Cursed Depths: +40 % elite density, +1 relic"; "Quiet Halls: fewer enemies, no boss chest"). This reuses
  `RunModifierService` for the effect and `stair_menu.gd` for the presentation, and it makes the *same*
  procedural floor feel authored. For off-path rooms, put the reward behind a cost: a vault that consumes a
  key (`room_locked_vault_content.gd` exists), a challenge arena that seals until cleared, a shrine that
  offers a buff for a permanent run debuff.

### D — Endless mode

### IMP-D01 — Endless mode is one biome forever

- **Problem** — This is `BUG-33` stated as a design gap rather than a defect: `start_endless_run()` hardcodes
  `BiomeRegistry.BIOME_UMBRAL` and every floor after it inherits `current_biome_id`. Nine biomes, five enemy
  families, five bosses, ten audio profiles and ten material sets exist and none of them are reachable in the
  mode designed to be played the longest. The intended shape is 10–20 floors per biome, rotating indefinitely.
- **Action** — Build a seeded, resumable biome schedule and give the biome change a moment.
- **Location** — `apps/game/client/scripts/app/run_flow.gd` (`start_endless_run`,
  `_resolve_floor_definition`, `_transition_floor`);
  `apps/game/client/scripts/dungeon/biome_registry.gd`;
  `apps/game/client/scripts/audio/audio_director.gd`
- **Solution Hint** — A pure function `biome_for_floor(run_seed, floor_index) -> String` that walks seeded
  segments of `randi_range(10, 20)` floors from floor 1, drawing from `BiomeRegistry.ALL_BIOMES` without
  immediate repeats. Purity matters: a 500-floor skip must land on the same biome the schedule would have
  produced by walking there, and a reloaded save must agree. Cache the segment boundaries per run rather than
  re-walking from floor 1 on every query. Then make the transition an event — a distinct stairwell, a title
  card naming the region, a music change (`AudioDirector` already crossfades per biome profile) — because a
  visible milestone every 10–20 floors is most of what makes an endless mode feel like progress.

### IMP-D02 — Endless difficulty rises in 14 % steps every ten floors instead of slowly per floor

- **Problem** — `EndlessDifficulty.floor_tier(floor_index)` is `int(floor_index / 10.0)`, and
  `hp_multiplier()` is `1.0 + tier * HP_GROWTH` with `HP_GROWTH = 0.14`. Difficulty is therefore a **step
  function**: floors 10–19 are identical to each other, and floor 20 is 14 % harder than floor 19 in one jump
  (damage jumps 11 % at the same boundary). The intended behaviour is a slow, continuous per-floor rise on a
  different scale from dungeon mode. The step also interacts badly with floor skips: `skip_100_floors` lands
  the player on floor 101, one floor past a difficulty cliff.
- **Action** — Convert to a continuous per-floor curve, and keep the soft cap.
- **Location** — `apps/game/client/scripts/dungeon/endless_difficulty.gd` (`floor_tier`, `hp_multiplier`,
  `damage_multiplier`, `rare_drop_bonus`, `HP_GROWTH`, `HP_KNEE_TIER`, `HP_SOFT_CAP`)
- **Solution Hint** — Replace `floor_tier` with the floor index itself and divide the growth rates by ten
  (`HP_GROWTH_PER_FLOOR = 0.014`), keeping the knee and the soft cap but expressing their thresholds in floors
  (`HP_KNEE_FLOOR = 120`). The endpoints stay where they are today, so existing balance is preserved while the
  cliffs disappear. Then verify the curve is genuinely gentler than `CastleTierDifficulty`'s per-floor growth
  (`floorHpGrowth` defaults to 0.06 per floor — four times steeper), which is the stated intent. Also revisit
  `RunModifierService.endless_modifiers_for_floor()`: it adds one modifier per 50 floors from a list of
  exactly three, so from floor 150 onward every endless floor forever has the identical three modifiers.

### IMP-D03 — Floor skips have no ceremony, no economy and one missing rung

- **Problem** — Skips are consumables rolled by `GlobalDropService` on enemy death, spent in
  `UmbralEndlessMenu`, which lists them as raw ids (`"Use skip_10_floors → floor 11"`). There is no indication
  of what floor 501 will be like, no warning, no confirmation, no record of the player's best depth to compare
  against, and no way to combine or convert skips. The 250 rung does not exist (`BUG-34`). Drop chances come
  from `content/loot/global_drops.json` evaluated in file order, so the earliest entry is the most likely to
  drop regardless of its authored chance (`PERF-20`).
- **Action** — Turn skips into a legible economy with a real decision at the portal.
- **Location** — `apps/game/client/scripts/dungeon/skip_floor_service.gd`;
  `apps/game/client/scripts/ui/umbral_endless_menu.gd` (`_build_skip_buttons`, `_on_skip_start_pressed`);
  `content/loot/global_drops.json`; `apps/game/client/scripts/loot/global_drop_service.gd`
- **Solution Hint** — Show each skip with its item name, icon, quantity, target floor, the biome that floor
  falls in (once `IMP-D01` lands) and the difficulty multiplier it implies, then confirm. Let lower skips
  combine into higher ones at the blacksmith or merchant so a stack of ten `skip_10` has a use. Make the skip
  a *stake*: starting at floor 501 with no accumulated relics is the trade the player is choosing, and the UI
  should say so.

### IMP-D04 — Endless mode has no meta-progression, so there is nothing to come back for

- **Problem** — The endless loop is: start, descend until death, lose run loot, repeat. `RunFlow` strips
  `runLoot`-tagged items at run end. `AchievementService` notifies on milestones, `LeaderboardSettings` exists,
  and `CharacterService` persists gold and talents — but there is no depth-based unlock, no per-biome mastery,
  no endless-specific currency, no run history and no reason to push past a personal best other than the
  number itself. Endless modes retain players through ratchets; there is no ratchet here.
- **Action** — Add a depth ratchet that persists across runs.
- **Location** — `apps/game/client/scripts/app/run_flow.gd` (run-end path);
  `apps/game/client/scripts/progression/progression_service.gd`;
  `apps/game/client/scripts/meta/achievement_service.gd`;
  `apps/game/client/scripts/ui/results_screen.gd`
- **Solution Hint** — Persist `endless_best_floor` and award a permanent currency scaled by depth reached,
  spendable on talents or on starting bonuses. Unlock cosmetic and mechanical rewards at depth milestones
  (25 / 50 / 100 / 250 / 500) — this is also the natural source for the skip items themselves, which currently
  only drop from enemies. Show the previous best as a marker on the results screen so every run has a target.



### E — Room generation, per floor, per mode

### IMP-E01 — Six-to-ten room floors, with the generator's own capabilities switched off

- **Problem** — `RoomGraphConfig.from_biome()` reads `roomCount` from the biome. Nine of ten biomes declare
  `{"min": 6, "max": 10}`; only `forgotten_castle` declares `{"min": 18, "max": 22}`. Because the config's
  richer settings are gated on `min_rooms >= 16` and `min_rooms >= 12`, every biome except the castle silently
  gets the *reduced* generator: `branch_max_depth = 4`, `max_neighbor_count = 3`, `loop_budget = 2`,
  `allow_2x2_blocks = false`, `min_dead_ends = 2`, `max_generation_attempts = 100`. Meanwhile **no biome
  declares `maxHeightLevel`**, so `config.max_height_level` is always 0 and the entire height-variation branch
  in `_grow_critical_path` (the `HEIGHT_RUN_LENGTH` / `rng.randf() < 0.35` block) is dead code. Nine of ten
  dungeons are small, flat, nearly linear floors generated by a deliberately hobbled generator.
- **Action** — Raise room counts to the tier the generator was tuned for, and turn on verticality.
- **Location** — `content/biomes/*.json` (`roomCount`, `maxSecrets`, `maxHeightLevel`);
  `apps/game/client/scripts/dungeon/procgen/room_graph_config.gd` (`from_biome`, `max_height_level`);
  `apps/game/client/scripts/dungeon/procgen/room_graph_generator.gd` (`_grow_critical_path`,
  `HEIGHT_RUN_LENGTH`)
- **Solution Hint** — Set `roomCount` to 16–24 for the mid dungeons and 20–28 for the late ones so the
  `min_rooms >= 16` branch engages, and declare `maxHeightLevel: 1` or `2` plus `maxSecrets: 2–3` per biome.
  Then delete the magic-number gating from `from_biome()` and make every field explicit in the biome JSON —
  a generator whose behaviour changes silently at a room-count threshold is a generator nobody can tune.
  Verify against `room_content_validator.gd`, which already checks the result.

### IMP-E02 — Every room of a given kind has enemies in the same six places

- **Problem** — `RoomTemplateCatalog.KIND_SPECS` is a hardcoded GDScript dictionary of eleven room kinds, each
  with a fixed anchor list: `"courtyard"` always offers exactly the same six enemy anchors, four cover anchors,
  two chest anchors and one trap anchor at identical local coordinates. Every courtyard in every biome, on
  every floor, in every run, places its contents at those coordinates. Combined with `IMP-E01`'s six-room
  floors and eleven kinds, the player sees the same handful of room layouts within the first hour and never
  sees a new one. Procedural generation is varying the *graph*, not the *rooms*.
- **Action** — Move room layouts into data and author multiple variants per kind per biome.
- **Location** — `apps/game/client/scripts/dungeon/procgen/room_template_catalog.gd` (`KIND_SPECS`);
  `apps/game/client/scripts/dungeon/procgen/procgen_placements.gd`;
  `apps/game/client/scripts/dungeon/biome_registry.gd` (`ROOM_KINDS`, `get_room_scenes`)
- **Solution Hint** — Convert `KIND_SPECS` to `content/rooms/<biome>/<kind>_<variant>.json` with anchor sets,
  door masks and dimensions, and have `BiomeRegistry` index the variants; the loader already resolves scenes
  by `templatePrefix` + kind, so variant suffixes fit the existing naming. Three to five variants per kind per
  biome is 300–500 small JSON files — author two or three by hand and generate the rest by mirroring and
  rotating the anchor sets, which is a tools job (`tools/` already exists for exactly this kind of generation).
  Then randomise *within* a variant: jitter anchors by ±0.5 m using the floor's seeded RNG so no two instances
  are pixel-identical.

### IMP-E03 — Room content is one weighted roll with no pacing, no set-pieces and no guarantees

- **Problem** — `RoomContentConfig` is a flat weight table (`combat` 0.45, `empty` 0.14, `trap` 0.09,
  `hazard` 0.07, `reward` 0.06, `lore` 0.06, `rest` 0.05, `puzzle` 0.05, `npc_quest` 0.02, `merchant` 0.01)
  normalised across all off-path rooms. Nothing varies the table by floor depth, difficulty tier, run mode or
  position along the critical path. There is no guarantee of a rest room before a boss, no ramp from quiet to
  loud, no "this floor is a gauntlet" set-piece, and no anti-clumping rule — a seeded run can produce four
  consecutive combat rooms or a floor with no reward at all. Soulslike level design is fundamentally about
  pacing: pressure, relief, pressure, payoff.
- **Action** — Replace the flat table with a depth-aware pacing model and hard guarantees.
- **Location** — `apps/game/client/scripts/dungeon/procgen/room_content_config.gd`;
  `apps/game/client/scripts/dungeon/procgen/room_content_assigner.gd`;
  `apps/game/client/scripts/dungeon/procgen/room_content_validator.gd`
- **Solution Hint** — Three additions, in order of value. (1) **Guarantees**: at least one rest room within
  two rooms of the boss door, at least one reward room per floor, at most two consecutive combat rooms —
  `room_content_validator.gd` is already the right place to enforce them and already rejects invalid layouts.
  (2) **Depth curves**: make each weight a function of `floor_index / max_floors` so early floors lean on
  `empty` and `lore` and late floors lean on `combat` and `hazard`. (3) **Set-pieces**: a `floorTheme` rolled
  once per floor (ambush floor, treasure floor, silent floor) that swaps the whole table — the cheapest way to
  make a generated floor feel authored.

### IMP-E04 — Secret rooms, illusory walls and hidden levers exist but are barely reachable

- **Problem** — `illusory_wall.gd`, `hidden_lever.gd`, `room_locked_vault_content.gd`,
  `room_puzzle_gate_content.gd` and the `SECRET` slot type are all implemented, and `_place_secret_attachments`
  wires them into the graph. But `max_secrets` defaults to 2 and **no biome declares `maxSecrets`**, and with
  `min_rooms = 6` the placement rules leave little room to attach them. The discovery layer that gives a
  Soulslike its texture — the wall you hit on a hunch, the lever behind the banner — is built and effectively
  switched off.
- **Action** — Turn secrets on, and give them escalating rewards.
- **Location** — `content/biomes/*.json` (`maxSecrets`, `requiresSecret`);
  `apps/game/client/scripts/dungeon/procgen/room_graph_generator.gd` (`_place_secret_attachments`,
  `_apply_secret_door_masks`); `apps/game/client/scripts/dungeon/illusory_wall.gd`;
  `apps/game/client/scripts/dungeon/hidden_lever.gd`
- **Solution Hint** — Declare `maxSecrets: 2–3` and `requiresSecret: true` per biome once `IMP-E01` has raised
  room counts enough to place them. Then tier the payoff: a common secret holds materials, a rare one holds a
  unique weapon, and a chained secret (lever → wall → vault) holds a relic. Add a subtle, learnable tell —
  a wall texture variant, a distinct ambient sound cue, a draught VFX — so discovery is a skill rather than a
  matter of hitting every wall.

### IMP-E05 — The minimap does not teach the floor

- **Problem** — `minimap.gd` renders the room graph, but the generator produces information the player never
  sees: `on_critical_path`, `slot_type` (`START`, `SECRET`, `BOSS`), door masks including secret doors, dead
  ends, and `height_level`. Without a legend for cleared/uncleared, locked, boss, rest and unexplored, an
  eight-room floor is navigable by memory but a twenty-four-room floor (`IMP-E01`) will not be.
- **Action** — Surface room state and type on the minimap as the floors grow.
- **Location** — `apps/game/client/scripts/ui/minimap.gd`;
  `apps/game/client/scripts/dungeon/procgen/room_graph_slot.gd`;
  `apps/game/client/scripts/ui/hud_icon_atlas.gd`
- **Solution Hint** — Room state (unvisited / visited / cleared), an icon per content type, a locked-door
  indicator and a boss marker, drawn from the existing `hud_icon_atlas.gd` and `minimap_icons.png`. Keep
  secrets hidden until discovered — the map should reward exploration, not replace it.

### F — Items and inventory: Dark Souls × Diablo, in pixels

### IMP-F01 — The inventory holds six pieces of equipment

- **Problem** — `GridInventory.DEFAULT_WIDTH = 6`, `DEFAULT_HEIGHT = 4` — 24 cells. Of the 90 authored items,
  **64 are 2×2**, 15 are 1×1, 5 are 1×2, 4 are 2×3, one is 2×4 and one is 1×4. A 6×4 grid fits exactly six
  2×2 items (3 across × 2 down). The bag is full after six drops. For a game whose stated inventory model is
  Diablo-style spatial management crossed with Souls-style equipment depth, six slots is not a constraint to
  play around, it is a wall the player hits in the first room. `has_space_for` / `inventory_rejected("full")`
  will be the most-seen message in the game.
- **Action** — Size the grid for the drop rate, and make capacity a progression axis.
- **Location** — `apps/game/client/scripts/inventory/grid_inventory.gd` (`DEFAULT_WIDTH`, `DEFAULT_HEIGHT`);
  `apps/game/client/scripts/ui/inventory_ui.gd` (`_bound_grid_w`, `_bound_grid_h`);
  `apps/game/client/scripts/ui/storage_ui.gd`; `content/items/**` (`gridWidth`, `gridHeight`)
- **Solution Hint** — 10×6 (60 cells, ~15 equipment pieces) as the base, expandable to 10×10 through
  hub upgrades — `from_save_dict` already persists `gridWidth`/`gridHeight`, so growth is a save-data change
  rather than a code change, and `inventory_ui` already rebinds when the dimensions differ. Simultaneously
  vary item footprints: a dagger should be 1×2, a greatsword 2×4, a ring 1×1. Right now 71 % of items are the
  same size, which erases the spatial puzzle that justifies a grid at all. Fix `PERF-19` (O(cells × slots)
  placement) before enlarging the grid, and `BUG-16` / `BUG-17` before players start hitting a full bag.

### IMP-F02 — Fourteen affixes across six rarity tiers, and one shield

- **Problem** — `content/affixes/` holds 7 prefixes and 7 suffixes. `RarityRegistry.TIER_ORDER` defines six
  tiers (common → magic → rare → epic → legendary → aumbral), and `_roll_affix_count` draws up to the
  per-rarity maximum from a pool of at most 14 — filtered further by `itemTypes`. A legendary and an epic
  therefore roll from the same tiny pool and read as the same item with different numbers. There are no
  unique/named items with bespoke effects, no set bonuses, no implicit stats by item base, no corrupted or
  cursed modifiers, and no crafting beyond five recipes. On the equipment side, exactly **one** item occupies
  the `secondary` slot, so the off-hand is effectively unused.
- **Action** — Grow the affix pool and add a tier of hand-authored uniques.
- **Location** — `content/affixes/prefixes.json`, `content/affixes/suffixes.json`,
  `content/affixes/rarity_rules.json`; `content/items/equipment/`;
  `apps/game/client/scripts/loot/affix_roller.gd` (`_build_affix_pool`, `_roll_tier_value`);
  `apps/game/client/scripts/items/equipment.gd` (`STAT_KEYS`, `SLOT_ORDER`)
- **Solution Hint** — Target 40–60 affixes with `itemTypes` filters so weapon and armour pools genuinely
  diverge, and tier the values so a legendary roll is visibly out of reach of a rare. `Equipment.STAT_KEYS`
  already defines 28 stats including `lootQuality`, `goldFind`, `xpGain` and six resistances — most have no
  affix backing them. Then add 15–25 **uniques**: fixed-name items with one bespoke rule (`"heavy attacks
  apply bleed"`, `"parry restores 20 stamina"`) driven by an `onEvent` hook rather than a stat. Those are what
  players build around and what makes a drop memorable. Author six to eight shields at the same time
  (`IMP-A04`).

### IMP-F03 — Item tooltips render raw affix ids and mislabel most stats

- **Problem** — `InventoryService.format_slot_tooltip()` emits affix lines as
  `"  %s +%s" % [affix.get("affixId"), affix.get("value")]` — the player sees `"  prefix_sharp +4"`. Stat
  lines come from `Equipment.format_stat_line()`, whose `match` special-cases nine stats and sends the other
  nineteen to `"+%.0f %s" % [value, stat]`, so the player reads `"+5 resistFire"` and `"+3 poise"`. The
  `physicalDamage` branch in that `match` is unreachable: it is in `FLAT_DAMAGE_STAT_KEYS`, not `STAT_KEYS`,
  and the tooltip loop iterates `STAT_KEYS` only. Item comparison exists (`compare_slot_to_equipped`) but is
  appended as a parenthetical rather than shown as a side-by-side.
- **Action** — Give every stat and every affix a localised display name and a proper comparison panel.
- **Location** — `apps/game/client/scripts/inventory/inventory_service.gd` (`format_slot_tooltip`);
  `apps/game/client/scripts/items/equipment.gd` (`format_stat_line`, `format_delta_line`, `STAT_KEYS`,
  `FLAT_DAMAGE_STAT_KEYS`); `content/affixes/*.json`; `content/text/`
- **Solution Hint** — Add `displayName` and `template` to each affix definition (`"Sharp"` /
  `"+{value} Physical Damage"`) and a `STAT_DISPLAY` table keyed by stat id, both routed through
  `TranslationServer` so `content/text/` covers them. Replace the `match` ladders — two nearly identical
  20-line `match` blocks that must be kept in sync — with one table driving both `format_stat_line` and
  `format_delta_line`. Then render comparison as Diablo does: the hovered item beside the equipped one, green
  and red deltas per line.

### IMP-F04 — Rarity is a colour and a multiplier, never a feeling

- **Problem** — `RarityRegistry` defines six tiers with display colours and `sell_multiplier`. In play, a
  legendary drop produces the same pickup VFX, the same sound, the same world model and the same
  `"[Legendary] Iron Sword"` label as a common. `_notify_item_obtained` fires an achievement notification and
  nothing else. `world_item_pickup.gd` builds the same visual for every item via
  `DioramaSkin.build_loot_pickup`. The moment a rare item drops is the core reward loop of an ARPG, and here
  it is indistinguishable from picking up scrap.
- **Action** — Escalate drop presentation by rarity across visuals, audio and world beam.
- **Location** — `apps/game/client/scripts/inventory/world_item_pickup.gd` (`_ready`, `configure`);
  `apps/game/client/scripts/loot/rarity_registry.gd` (`DISPLAY_COLORS`);
  `apps/game/client/scripts/art/vfx/vfx_service.gd`; `apps/game/client/scripts/audio/audio_director.gd`
- **Solution Hint** — A vertical light beam tinted by `RarityRegistry.display_color()`, scaled by
  `tier_index()`; a distinct drop sting per tier; a screen-edge toast for epic and above; and a brief camera
  nudge for aumbral. The colours are already centralised in one dictionary, so the whole escalation is driven
  by one existing lookup. `IMP-J02`'s pixel-consistency rules apply to the beam and the toast.

### IMP-F05 — Upgrading is a flat 6 % per level with no branching and no risk

- **Problem** — `Equipment.upgrade_multiplier()` is `1.0 + 0.06 * level`, capped by
  `RarityRegistry.max_upgrade_level()` at 5 (10 for aumbral). `content/recipes/` holds five recipes.
  `BlacksmithService` tracks durability, and `InventoryService.apply_death_durability_loss()` reduces it on
  death — with `Equipment.slot_stats()` zeroing an item's stats entirely at zero durability. So the
  progression is: pay gold, multiply everything by 1.06, repeat five times. There is no infusion or elemental
  path, no risk of failure, no reforging of affixes, no transmutation of rarity, and no reason to keep a
  second copy of an item.
- **Action** — Add branching upgrade paths and affix manipulation at the forge.
- **Location** — `apps/game/client/scripts/items/equipment.gd` (`upgrade_multiplier`, `UPGRADE_STEP`,
  `slot_stats`); `apps/game/client/scripts/hub/blacksmith_service.gd`; `content/recipes/`;
  `apps/game/client/scripts/ui/blacksmith_ui.gd`
- **Solution Hint** — Souls-style **infusions** (fire / frost / poison / arcane) that convert part of the
  weapon's physical damage and change its scaling, plus Diablo-style **reroll one affix** and **upgrade
  rarity** operations consuming materials the run drops. `RecipeCatalog.upgrade_stat_bonus()` already supports
  per-level explicit stat bonuses (rather than the flat multiplier), which is the hook for non-linear paths.
  Durability is already implemented and is a good Soulslike pressure — surface it in the UI, because right now
  an item silently contributing zero stats is a bug from the player's point of view.

### G — NPCs, story and quests

### IMP-G01 — There are three NPCs and no story

- **Problem** — `content/npcs/` holds `blacksmith_aldric`, `merchant_elara` and `warden_mira`; all three are
  hub vendors or a greeter. `content/dialogue/` holds five trees of one to three nodes each. There is no
  narrative frame, no lore, no antagonist, no reason the player is descending, and no world state that
  changes. `room_npc_quest_content.gd` and `room_lore_content.gd` exist as room content types and pull from a
  single generic `dungeon_lore_default` / `dungeon_npc_stranded` tree apiece. `DialogueConditions` supports
  flags, level, quest state, gold, run count and death count — a real gating vocabulary with nothing to gate.
- **Action** — Write a story spine and give the hub a cast that reacts to it.
- **Location** — `content/npcs/`; `content/dialogue/`;
  `apps/game/client/scripts/dungeon/room_content/room_npc_quest_content.gd`;
  `apps/game/client/scripts/dungeon/room_content/room_lore_content.gd`;
  `apps/game/client/scripts/dialogue/dialogue_conditions.gd`
- **Solution Hint** — Souls-style delivery: no cutscenes, meaning carried by item descriptions, NPC lines that
  change with progress, and environmental storytelling. Six to eight hub NPCs, each with a personal arc gated
  on the `dungeon_tier_<id>` flags that already exist, plus rescuable dungeon NPCs who relocate to the hub and
  unlock a service — that single mechanic converts exploration into hub growth and is the strongest retention
  hook available. Thirty to fifty lore items placed in `room_lore_content` rooms, biome-specific, is the
  cheapest way to make ten dungeons feel like one world.

### IMP-G02 — The dialogue system cannot express most of what quests need

- **Problem** — `DialogueRunner._execute_action()` handles exactly four actions (`set_flag`, `add_gold`,
  `start_quest`, `complete_quest`) and re-emits everything else for the caller to interpret. There is no
  give-item, no take-item, no teleport, no unlock-recipe, no start-combat, no play-sound and no
  set-relationship. `DialogueConditions` has no item-possession, no biome, no dungeon-cleared and no
  difficulty-tier predicate. `NpcBase` routes by a four-value `interactType`. Any quest more complex than
  "kill three grunts" cannot currently be authored.
- **Action** — Expand the action and condition vocabularies, and validate them at build time.
- **Location** — `apps/game/client/scripts/dialogue/dialogue_runner.gd` (`_execute_action`);
  `apps/game/client/scripts/dialogue/dialogue_conditions.gd` (`evaluate`);
  `apps/game/client/scripts/npc/npc_base.gd` (`_on_interacted`); `content/schemas/`
- **Solution Hint** — Add `give_item`, `take_item`, `unlock_recipe`, `set_relationship`, `play_sfx` and
  `advance_story_beat` as actions; add `hasItem`, `dungeonCleared`, `biome`, `minTier` and `relationship` as
  conditions. Extend the JSON schema in `content/schemas/` in the same commit so `npm run validate` rejects
  unknown verbs — that is what turns `BUG-29` (unknown keys silently hide content) from a runtime mystery
  into a build error. Fix `BUG-28` (unbounded recursion) before the trees get deep.

### IMP-G03 — Four quests, none repeatable, none chained

- **Problem** — `content/quests/` holds `escape_castle`, `fetch_scrap`, `kill_grunts` and a one-entry
  `dungeon_quests.json`. `QuestService` supports three types (`kill`, `fetch`, `escape`); `register_fetch()`
  completes on the first matching pickup with no count, and there is no prerequisite, no chain, no repeatable
  or daily quest, no time limit, no bonus objective and no failure state. Quest state is a flat
  `inactive`/`active`/`completed` per id, so the same quest can never be offered twice.
- **Action** — Add quest types, chains and repeatables, and index the triggers.
- **Location** — `apps/game/client/scripts/quests/quest_service.gd` (`register_kill`, `register_fetch`,
  `accept_quest`, `complete_quest`, `_grant_rewards`); `content/quests/`;
  `apps/game/client/scripts/quests/dungeon_quest_catalog.gd`;
  `apps/game/client/scripts/ui/quest_board_ui.gd`
- **Solution Hint** — Add `requiredCount` to fetch quests (the field already exists for kill quests), a
  `prerequisites` array for chains, a `repeatable` flag with a completion counter instead of a boolean state,
  and `escort` / `survive` / `clear_without` types that reuse existing run signals. Twenty to thirty quests
  spanning one-off story beats and repeatable bounties gives `quest_board_ui.gd` something to be. Do `PERF-23`
  (index active quests by trigger) at the same time, since the per-kill linear scan is only acceptable at the
  current count of four.

### H — Buffs, traps, hazards and the reasons to keep playing

### IMP-H01 — Five statuses, all debuffs, none with a build-up meter

- **Problem** — `content/statuses/` holds `bleed`, `burn`, `freeze`, `poison`, `stun`. All five are things
  that happen *to* the player or enemy; none is a buff, none has a build-up meter (they apply on hit rather
  than accumulating toward a threshold, which is the mechanic that makes Souls status effects tense), and the
  only counterplay is a `cure` consumable that calls `StatusController.clear_all()`. `ConsumableService`
  routes `elixir_*` effects through `player.set_meta("consumable_buff_…")` rather than the status system, so
  buffs and debuffs live in two different places with two different lifetimes.
- **Action** — Add build-up meters, unify buffs into the status system, and give each status a real identity.
- **Location** — `content/statuses/`; `apps/game/client/scripts/combat/statuses/status_controller.gd`;
  `apps/game/client/scripts/combat/statuses/status_catalog.gd`;
  `apps/game/client/scripts/inventory/consumable_service.gd` (`_apply_consumable_status`)
- **Solution Hint** — Give each status a `buildUp` threshold and a decay rate; hits add build-up, the effect
  triggers at 100 and the meter resets with a rising resistance. Surface the meter in the HUD
  (`status_pip.gd` and `status_icon_atlas.gd` already exist). Then move `elixir_*` buffs out of node metadata
  and into `StatusController` as positive statuses, so buffs, debuffs, relic effects and consumables share one
  timing, stacking and display path — that unification is what makes `IMP-H03`'s variety affordable.

### IMP-H02 — Traps are scenery: five traps, two per biome, no interaction with combat

- **Problem** — `content/traps/` holds five definitions (`spike_trap`, `falling_trap`, `frost_trap`,
  `poison_pool`, `shadow_trap`), and each biome's `trapPool` lists two of them — usually `spike_trap` or the
  biome-flavoured one plus `falling_trap`. `RoomContentConfig.weight_trap` is 0.09 and `weight_hazard` 0.07.
  Traps deal damage to the player on contact and do nothing else: enemies are unaffected, traps cannot be
  triggered deliberately, disarmed, or used tactically, and they do not change how a room is fought. In a
  Soulslike, an environmental hazard is a tool as much as a threat.
- **Action** — Make traps damage enemies too, and make them part of room tactics.
- **Location** — `content/traps/`; `apps/game/client/scripts/dungeon/traps/spike_trap.gd`;
  `apps/game/client/scripts/dungeon/traps/falling_trap.gd`;
  `apps/game/client/scripts/combat/trap_damage_area.gd`;
  `apps/game/client/scripts/dungeon/procgen/room_content_assigner.gd`
- **Solution Hint** — `trap_damage_area.gd` already resolves a `Hurtbox`; widen the team filter so enemies
  take trap damage, and give enemy AI an "avoid trap volume" steering term once navigation exists (`IMP-B03`) —
  the interesting behaviour is enemies pathing *around* a trap the player can bait them across. Add ten to
  twelve traps with distinct verbs: swinging blades on a timer, collapsing floors, pressure plates that summon,
  arrow lines, gas that ignites. Author a per-biome pool of four to five so the two-trap monotony ends.

### IMP-H03 — Relics and run buffs exist but do not shape a run

- **Problem** — `content/relics/` holds eleven files, `RunBuffs` is an autoload with `add_relic()` and
  `get_stat_totals()`, and `InventoryService._on_item_added_success()` grants a relic when an item carries
  `runRelicId`. But relics only contribute flat stats to the same aggregation as equipment — there is no
  relic that changes a rule, no choice between relics, no synergy, and no escalating build within a run. A
  roguelite run is defined by the choices that make *this* run different from the last, and there are none.
- **Action** — Turn relics into rule-changing choices offered at decision points.
- **Location** — `content/relics/`; `apps/game/client/scripts/combat/run_buffs.gd`;
  `apps/game/client/scripts/dungeon/room_content/room_reward_content.gd`;
  `apps/game/client/scripts/ui/stair_menu.gd`
- **Solution Hint** — Offer a choice of three relics at each rest room and after each boss, drawn from a pool
  weighted by what the player is already carrying so synergies compound. Express relics as event hooks
  (`onKill`, `onParry`, `onRoomClear`, `onLowHealth`) rather than as stat bags — `RunBuffs` is 76 lines and is
  the right place for the dispatcher. Thirty to forty relics with real rules, some with drawbacks, gives the
  run-to-run variance that ten tiers and endless floors are asking for.

### IMP-H04 — Nothing in a run is worth telling someone about

- **Problem** — Pulling `IMP-B01` through `IMP-H03` together: every enemy has one attack, no boss has phases,
  every room of a kind is identical, relics are stat bags, rarity is a colour, and endless is one biome. The
  systems are individually competent and collectively produce a run with no peaks. `AchievementService`,
  `LeaderboardSettings` and `results_screen.gd` all exist to celebrate outcomes that are not yet distinct from
  one another.
- **Action** — Prioritise the changes that create peaks, and measure retention against them.
- **Location** — cross-cutting: `IMP-B01` (enemy movesets), `IMP-B02` (boss phases), `IMP-H03` (relic
  choices), `IMP-F04` (drop presentation), `IMP-D01` (endless biome rotation)
- **Solution Hint** — In order: enemy movesets, because everything else in combat is downstream of having
  more than one attack to react to; relic choices, because they are what make two runs differ; boss phases,
  because they are what a run is *for*. Drop presentation and biome rotation are cheap and high-visibility.
  Instrument the results screen with a per-run summary the player would screenshot — deepest floor, best relic
  combination, boss kill time — because the thing worth telling someone about must first be legible.

### I — Difficulty: Soulslike, not punishing

### IMP-I01 — Difficulty is expressed only as HP and damage multipliers

- **Problem** — Every difficulty lever in the game is a scalar: `CastleTierDifficulty.hp_multiplier` /
  `damage_multiplier`, `EndlessDifficulty` equivalents, `WavesDifficulty` equivalents, and per-floor growth
  factors. Nothing scales enemy *behaviour* — reaction speed, aggression, attack selection, group
  coordination, tell length. A tier-3 enemy telegraphs for exactly as long as a tier-1 enemy. Scaling numbers
  alone produces the failure mode the design explicitly rules out: not harder, just spongier and more punishing.
- **Action** — Scale behaviour alongside numbers, and cap the numeric scaling much earlier.
- **Location** — `apps/game/client/scripts/dungeon/castle_tier_difficulty.gd`;
  `apps/game/client/scripts/dungeon/endless_difficulty.gd`;
  `apps/game/client/scripts/enemies/castle_enemy_base.gd` (`_start_windup`, `_can_attack`, `_cooldown`);
  `apps/game/client/scripts/combat/attack_token_service.gd`
- **Solution Hint** — Per tier, shorten `windup_duration` by a bounded percentage (never below the player's
  reaction floor — roughly 0.35 s), shorten `attack_cooldown`, raise the `AttackTokenService` budget from 2 to
  3, and unlock later entries in each enemy's `attacks` array (`IMP-B01`) so higher tiers literally have more
  moves. Cap `hpMult` around 3–4× rather than letting it run: a Soulslike enemy should kill the player in two
  or three hits at every tier and die in a comparable number, because the difficulty lives in the exchange,
  not in the health bar. `EndlessDifficulty.HP_SOFT_CAP = 25.0` is far past the point where fights stop being
  readable.

### IMP-I02 — Death costs almost nothing, so the difficulty has no stakes

- **Problem** — On death, run-tagged loot is stripped and `apply_death_durability_loss()` reduces equipment
  durability. There is no currency loss, no bloodstain to recover, no lost progress within the dungeon beyond
  the current floor, and no escalating penalty. Meanwhile `BUG-13` means the player can restore full health at
  any time by touching the inventory. A Soulslike derives its tension from a meaningful, recoverable loss —
  the run currently has neither the loss nor the recovery.
- **Action** — Introduce a recoverable death stake, and fix the free heal that undermines it.
- **Location** — `apps/game/client/scripts/app/run_flow.gd` (run-end / death path);
  `apps/game/client/scripts/inventory/inventory_service.gd` (`apply_death_durability_loss`);
  `apps/game/client/scripts/player/player_combat_reactions.gd` (`_on_died`);
  `apps/game/client/scripts/progression/progression_service.gd`
- **Solution Hint** — Drop the run's accumulated currency at the death location as a recoverable marker, lost
  permanently on a second death — the canonical mechanic, and it makes the next run's route a decision. Pair
  it with a limited healing resource (a charged flask restored at rest rooms) rather than unlimited
  consumables, which is the other half of what makes Souls pacing work. `BUG-13` must be fixed first or the
  flask is decorative.

### IMP-I03 — There is no difficulty feedback loop and no accessibility ramp

- **Problem** — Difficulty is fixed per tier with no adaptation, no assist options and no telemetry.
  `settings_schema.gd` and `scripts/accessibility/` exist, but nothing exposes combat-affecting assists
  (lock-on strength, telegraph emphasis, i-frame generosity, damage taken). A player who bounces off tier 4
  has one option: stop. "Difficult but not very difficult" is a tuning claim that cannot be validated without
  data on where players actually fail.
- **Action** — Add opt-in assists and instrument failure points.
- **Location** — `apps/game/client/scripts/ui/settings_schema.gd`; `apps/game/client/scripts/accessibility/`;
  `apps/game/client/scripts/meta/achievement_service.gd`;
  `apps/game/client/scripts/ui/results_screen.gd`
- **Solution Hint** — Assists that do not change the fight's shape: stronger telegraph outlines, extended
  lock-on range, a more generous input window, and a damage-taken slider — visible in the results screen so
  the player owns the choice. For telemetry, record which enemy, which floor and which attack killed the
  player, aggregated locally and surfaced in the results screen; that is enough to tune tiers without a
  backend.

### J — Pixel-diorama presentation

### IMP-J01 — Characters are dozens of separate mesh instances, which is both the perf cost and the art ceiling

- **Problem** — `PERF-04` records the runtime cost of building characters from many `MeshInstance3D`s with
  per-instance materials. The art consequence is the more important one: because every part is a separate node
  with its own material, the pixel grid is not enforced across parts, silhouettes read inconsistently at
  distance, and the palette can drift per-part. `PixelDioramaStyle` at 1,471 lines mixes palette, geometry and
  material concerns (`REF-07`), which means there is no single place that guarantees "this is what an Aumbrye
  character looks like".
- **Action** — Collapse each character to one mesh with one palette-indexed material, enforced by the pipeline.
- **Location** — `apps/game/client/scripts/art/characters/diorama_character_skin.gd`;
  `apps/game/client/scripts/art/style/pixel_diorama_style.gd`;
  `apps/game/client/scripts/art/characters/voxel_mesh_builder.gd`;
  `apps/game/client/scripts/art/pipeline/`
- **Solution Hint** — This is the same change as `PERF-04` and `REF-05` viewed from the art side: merge parts
  at build time into one `ArrayMesh` with a palette texture, so colour is data and the material is shared.
  `PERF-14` (the mesher is advertised as greedy but emits two triangles per exposed face) is on the same path.
  Fix `BUG-02` first, because none of this is verifiable until meshes load in an exported build.

### IMP-J02 — Nothing enforces the pixel grid, so the "pixel look" is a per-scene accident

- **Problem** — The low-res `SubViewport` mirror and camera snap establish a target resolution, but there is
  no project-wide rule that UI, VFX, decals, damage numbers, telegraph rings and world sprites all quantise to
  the same pixel size. `VfxService`, `MaterialFlash`, `damage_number.gd` and `enemy_health_bar.gd` each draw in
  their own space. `enemy_health_bar.gd` builds a fresh `Image` and `ImageTexture` per health change
  (`PERF-05`), which is both slow and a place where the pixel grid is defined a second time. Sub-pixel drift
  and mixed pixel densities are what make a pixel game look cheap, and there is no guard against either.
- **Action** — Define one pixel-unit constant and route every drawing surface through it.
- **Location** — `apps/game/client/scripts/art/style/pixel_diorama_style.gd`;
  `apps/game/client/scripts/art/vfx/vfx_service.gd`;
  `apps/game/client/scripts/ui/enemy_health_bar.gd`; `apps/game/client/scripts/combat/damage_number.gd`;
  `apps/game/client/project.godot` (viewport / stretch settings)
- **Solution Hint** — One `PIXELS_PER_UNIT` constant and a `snap_to_pixel_grid()` helper used by every
  billboard, decal and world-space label; nearest-neighbour filtering everywhere; and a validation-suite check
  that fails if a new `Sprite3D`/`Label3D` is added without going through the helper. Replace
  `enemy_health_bar`'s per-hit `ImageTexture` with a shader reading a fill uniform, which fixes `PERF-05` and
  removes the second pixel-grid definition at once.

### IMP-J03 — The UI is functional but does not read as a Soulslike or as pixel art

- **Problem** — `game_ui_skin.gd` (661 lines) centralises the UI vocabulary, and the atlases
  (`item_icon_atlas`, `status_icon_atlas`, `hud_icon_atlas`, `input_glyph_atlas`, `ui_symbol_atlas`) are a
  genuinely good foundation — item icons are 16×16 cells with 109 entries covering all but two items
  (`boss_sigil` and the test fixture from `BUG-37`). But the screens themselves are stock control layouts: the
  castle entry menu is two `OptionButton`s (`IMP-C03`), the endless menu lists raw item ids (`BUG-34`), the
  inventory renders a plain `GridContainer` with a paper-doll built from a 3-column spacer layout, and tooltips
  are newline-joined strings (`IMP-F03`). The atlas work is ahead of the layout work.
- **Action** — Design the inventory, tier ladder and results screens as authored pixel layouts rather than as
  control containers.
- **Location** — `apps/game/client/scripts/ui/game_ui_skin.gd`;
  `apps/game/client/scripts/ui/inventory_ui.gd`; `apps/game/client/scripts/ui/inventory_ui_layout.gd`;
  `apps/game/client/scripts/ui/castle_entry_menu.gd`; `apps/game/client/scripts/ui/results_screen.gd`
- **Solution Hint** — Nine-slice pixel frames at a fixed scale factor, a paper-doll drawn over
  `paperdoll_silhouette.png` (already in `assets/ui/`) rather than assembled from spacer cells, rarity-tinted
  slot borders using `RarityRegistry.slot_background_color()` (already implemented and unused in the grid),
  and item comparison as a side-by-side panel. Keep everything in `game_ui_skin.gd` so there is one place the
  look is defined — that discipline already exists and is worth protecting.

### IMP-J04 — Two of ten biomes carry a colour-grade profile; the rest look the same lit differently

- **Problem** — `BiomeRegistry.get_grade_profile()` reads an optional `grade` object from the biome JSON. Only
  `frozen_fortress` and `umbral_chapel` declare one. The other eight rely on `lighting` and `materials` alone,
  so a crystal cavern and an iron vault differ in wall texture but share a colour identity. For a game whose
  ten dungeons and endlessly rotating biomes are the main source of visual variety, eight of ten biomes being
  ungraded is the largest single presentation gap.
- **Action** — Author a grade profile per biome and make the biome change visible at a glance.
- **Location** — `content/biomes/*.json` (`grade`, `lighting`, `materials`);
  `apps/game/client/scripts/dungeon/biome_registry.gd` (`get_grade_profile`);
  `apps/game/client/scripts/art/lighting/visual_lighting.gd`
- **Solution Hint** — A shadow tint, a highlight tint, a saturation target and a fog colour per biome, plus a
  restricted palette per biome enforced by the palette-indexed material from `IMP-J01`. The payoff compounds
  with `IMP-D01`: if endless mode rotates biomes every 10–20 floors, the biome change is the mode's core beat,
  and it should be unmistakable within one frame of walking through the door.

---

## 14. 🧩 Extension — growing the content bases toward high replayability

Section 13 says what is *wrong* relative to the design target. This section says what to *build*: concrete
extension plans for the item base, NPC base, quest base, story base, class and character customization, and
the systems that turn all of it into a loop players come back to.

The distinction matters for planning. Section 13 items are mostly engineering with a content tail; section 14
items are mostly **content and design with an engineering tail**, and several can be worked in parallel by
different people once the enabling code lands. Each item names its blocking prerequisite explicitly.

Scale targets used throughout this section, for a game meant to sustain 10 dungeon tiers plus an endless mode:

| Content base | Today | Early Access target | Why that number |
|---|---|---|---|
| Items | 90 | 350–450 | ~35 per biome × 10, plus shared bases and consumables |
| — of which uniques | 0 | 40–60 | 4–6 per biome; the items players build around |
| Affixes | 14 | 60–80 | enough that two rares of the same base read differently |
| Weapons (archetypes × bases) | 8 | 60–80 across 10–12 archetypes | archetype is the playstyle, base is the stat spread |
| Shields | 1 | 10–14 | the `secondary` slot currently has no reason to exist |
| Enemies | 29 | 70–90 | 7–9 per biome, each with 2–4 attacks |
| Bosses | 5 distinct | 20–24 | 1 boss + 1 miniboss per biome, all with phases |
| Relics / run modifiers | 11 / 3 | 60–80 / 25–30 | the roguelite variance layer |
| Statuses | 5 | 14–18 | including buffs, which currently live outside the system |
| Traps and hazards | 5 | 20–25 | 4–5 per biome with distinct verbs |
| NPCs | 3 | 18–25 | 8 hub + 10–15 rescuable/wandering |
| Dialogue nodes | ~10 | 800–1,200 | reactive lines across progression states |
| Quests | 4 | 60–80 | 25 story, 20 side chains, 15+ repeatable bounties |
| Lore entries | 0 | 150–200 | item descriptions plus placed readables |
| Classes | 5 | 7–8, each with a real identity | see `EXT-E01` |

These are sizing targets for scoping and hiring, not a commitment to author them by hand — `EXT-F05`
covers the tooling that makes numbers at this scale reachable.

### A — Item base

### EXT-A01 — Build the item base as bases × archetypes × affixes rather than as 350 hand-authored files

- **Problem/Opportunity** — All 90 items today are standalone JSON files with hardcoded stats, and 64 of them
  share the same 2×2 footprint. Authoring 350 more the same way is 350 more files to balance individually,
  and the affix roller can only make them differ by 14 modifiers (`IMP-F02`). Meanwhile the systems that would
  make a small authored set feel large — item bases with implicit stats, per-archetype scaling, tiered affix
  pools, uniques with rules — are absent, and `Equipment.STAT_KEYS` already defines 28 stats of which most
  have no affix backing them.
- **Action** — Introduce an item *base* layer beneath the item definition, and generate the common tier of
  items from bases × biome × rarity.
- **Location** — `content/items/**`; `content/items/catalog.json`;
  `apps/game/client/scripts/content/item_catalog.gd`;
  `apps/game/client/scripts/items/equipment.gd` (`STAT_KEYS`, `slot_stats`);
  `apps/game/client/scripts/loot/affix_roller.gd`; `content/schemas/`
- **Solution Hint** — A base declares archetype, slot, footprint, implicit stat, scaling letters and the
  material tier it belongs to (`iron_greatsword_base`); an item instance is base + biome skin + rarity. This
  collapses ~250 of the target 350 into roughly 40 bases × biome variants, generated by a tool in `tools/`
  and validated by the existing content schema. Reserve hand-authoring for the 40–60 uniques of `EXT-A02`,
  which is where the effort actually shows. Vary footprints while you are there — daggers 1×2, greatswords
  2×4, rings 1×1 — since `IMP-F01`'s grid only becomes an interesting decision when items differ in shape.

### EXT-A02 — 40–60 uniques, each with one rule the player can build around

- **Problem/Opportunity** — There is no unique item tier. `RarityRegistry` has six rarities, but a legendary
  differs from a rare only by affix count and value band, so no drop is ever *interesting* — only *bigger*.
  Uniques are the single cheapest way to create build identity, run-defining moments and the "I need to find
  one more" hook, and the engine is nearly ready for them: affixes already resolve to stats through a
  `Callable`, so a rule-based effect just needs an event dispatcher.
- **Action** — Author a unique tier keyed to biome and boss, with fixed names, bespoke art and one rule each.
- **Location** — `content/items/equipment/`; `content/affixes/`;
  `apps/game/client/scripts/loot/affix_roller.gd` (`roll_instance`);
  `apps/game/client/scripts/combat/run_buffs.gd` (event dispatcher);
  `apps/game/client/scripts/ui/item_icon_atlas.gd`
- **Solution Hint** — Build the event dispatcher once (`onHit`, `onKill`, `onParry`, `onBlock`, `onDodge`,
  `onLowHealth`, `onRoomClear`, `onFloorEnter`) and let uniques, relics (`IMP-H03`) and class perks
  (`BUG-52`) all register against it — three systems, one mechanism. Rules should be legible in one sentence:
  *"Riposte restores 30 stamina"*, *"Killing a bleeding enemy spreads bleed to nearby enemies"*,
  *"Each consecutive parry raises damage 8 %, resets on hit"*. Four to six per biome, one guaranteed from each
  boss's first kill, the rest in the general pool — that gives every dungeon a reason to be re-run.

### EXT-A03 — Give consumables a real role: flasks, throwables, buffs and utility

- **Problem/Opportunity** — Nine consumables exist, and `ConsumableService.apply()` supports five effect
  kinds (`heal`, `restoreMana`, `restoreStamina`, `applyStatus`, `cure`) plus the portal-only `skipFloors`.
  Healing is unlimited as long as the player carries potions, which is the other half of why difficulty has no
  stakes (`IMP-I02`). There are no throwables, no traps the player can place, no temporary weapon buffs, no
  utility items (light sources, key items, escape stones) and no crafting sinks.
- **Action** — Replace unlimited potions with a charged flask, and expand consumables into four distinct roles.
- **Location** — `content/items/consumables/`;
  `apps/game/client/scripts/inventory/consumable_service.gd` (`can_use`, `apply`);
  `apps/game/client/scripts/player/player_heal.gd`;
  `apps/game/client/scripts/dungeon/room_content/room_rest_content.gd`
- **Solution Hint** — Four roles: **flask** (charged, refilled at rest rooms, upgradable — the Souls
  pressure valve); **throwable** (firebomb, caltrops, lure — needs the projectile from `REF-14`);
  **buff** (temporary weapon enchant, resistance, movement — routed through `StatusController` per
  `IMP-H01`); **utility** (torch that reveals secrets, escape stone that ends a run keeping loot, homeward
  bone). The escape stone in particular converts a lost run into a decision, which is the single strongest
  retention mechanic in the genre. `ConsumableService.can_use()` already gates by run/hub context, so the
  routing exists.

### EXT-A04 — Materials, crafting and the reason to keep a second copy of a drop

- **Problem/Opportunity** — 17 materials exist and 5 recipes consume them. `BlacksmithService` supports
  upgrade, repair and unlock; `RecipeCatalog` supports per-level stat bonuses. But there is no salvage, no
  transmutation, no affix reroll, no infusion and no set crafting, so a duplicate drop is worth exactly its
  sell price and every material beyond the five recipes is inert. Diablo-style loops run on *converting*
  loot, not just replacing it.
- **Action** — Add salvage and four conversion recipes that consume materials in bulk.
- **Location** — `content/recipes/`; `content/items/materials/`;
  `apps/game/client/scripts/hub/blacksmith_service.gd`;
  `apps/game/client/scripts/hub/recipe_catalog.gd`; `apps/game/client/scripts/ui/blacksmith_ui.gd`
- **Solution Hint** — **Salvage** (item → materials scaled by rarity and upgrade level) gives every duplicate
  a use and every full inventory an alternative to dropping. Then **reroll one affix**, **upgrade rarity one
  tier**, **infuse** (elemental conversion, per `IMP-F05`) and **transfer a unique's rule onto another base**
  as a late sink. Tie material tiers to biomes so specific dungeons become farming targets — which is what
  makes a 10-tier ladder replayable rather than merely repeatable.

### B — NPC base

### EXT-B01 — Grow the hub cast from three vendors to eight characters with arcs

- **Problem/Opportunity** — `blacksmith_aldric`, `merchant_elara` and `warden_mira` are the entire cast, and
  two of them are shops. `NpcBase` routes by a four-value `interactType` (`dialogue`, `blacksmith`,
  `merchant`, `quest_board`), and `DialogueConditions` can already gate on flags, level, quest state, gold,
  run count and death count — a real reactivity vocabulary with almost nothing bound to it. The hub is where
  a roguelite player spends the time between runs, and right now there is nothing there to come back to.
- **Action** — Author eight hub NPCs, each with a service, an arc, and lines that change with progress.
- **Location** — `content/npcs/`; `content/dialogue/`;
  `apps/game/client/scripts/npc/npc_base.gd` (`interactType`, `_on_interacted`);
  `apps/game/client/scripts/npc/npc_catalog.gd`; `apps/game/client/scripts/hub/hub.gd`
- **Solution Hint** — Blacksmith (upgrade/infuse), merchant (rotating stock), quartermaster (flask and
  capacity upgrades), archivist (lore and bestiary), trainer (talents and respec), oracle (run modifiers and
  seed reading), a rival who runs the dungeon alongside the player and can be found dead or ahead of them,
  and one whose service unlocks only after a specific dungeon is cleared. Each needs three to five dialogue
  states keyed to the `dungeon_tier_<id>` flags that already persist. Extend `interactType` to a registry
  rather than a `match` so adding the ninth NPC is data, not code.

### EXT-B02 — Rescuable dungeon NPCs: the mechanic that makes exploration feed the hub

- **Problem/Opportunity** — `room_npc_quest_content.gd` exists as a room content type with weight 0.02, and
  it pulls a single generic tree (`dungeon_npc_stranded`). There is no consequence to finding one, and the
  hub does not change. The Souls convention — find a character in the world, they relocate to your hub and
  unlock something — converts optional exploration into permanent progression, and is the strongest single
  retention hook available to this design.
- **Action** — Make dungeon NPCs rescuable, persistent and hub-relocating.
- **Location** — `apps/game/client/scripts/dungeon/room_content/room_npc_quest_content.gd`;
  `content/npcs/`; `apps/game/client/scripts/hub/hub.gd`;
  `apps/game/client/scripts/save/character_flags.gd`;
  `apps/game/client/scripts/dungeon/procgen/room_content_config.gd` (`weight_npc_quest`)
- **Solution Hint** — 10–15 rescuable NPCs, each keyed to a biome and gated behind an optional route (a
  locked vault, a secret room per `IMP-E04`, an escort back to the stairs). Rescue sets a flag; the hub spawns
  them on next entry and their service becomes available. Some should be able to *die* — a rescuable NPC who
  is lost if the player descends without finding them creates the kind of stakes players talk about. Raise
  `weight_npc_quest` above 0.02 once there is more than one tree to show.

### EXT-B03 — Make NPCs react to what the player actually did

- **Problem/Opportunity** — Dialogue is currently static per NPC. `DialogueConditions` supports `minRuns`,
  `minDeaths`, `quest`, `flag`, `minLevel` and `gold`, so the reactivity machinery exists and is unused
  beyond a greeting gate. An NPC who comments on the player's third death in the Frozen Fortress, or on the
  legendary they just pulled, costs one condition and one line, and is disproportionately memorable.
- **Action** — Add a reactive-line layer keyed to recent run outcomes.
- **Location** — `apps/game/client/scripts/dialogue/dialogue_conditions.gd` (`evaluate`);
  `apps/game/client/scripts/dialogue/dialogue_runner.gd`; `content/dialogue/`;
  `apps/game/client/scripts/app/run_flow.gd` (run-end results)
- **Solution Hint** — Record a small `last_run` summary (outcome, biome, floor reached, killer, best drop)
  in `CharacterService` at run end, and add conditions for each field (this is part of the vocabulary
  expansion in `IMP-G02`). Then give each NPC a priority-ordered list of reactive lines checked before their
  default greeting. Fifty reactive lines across eight NPCs is a day of writing and changes how alive the hub
  feels. Requires `BUG-28` (dialogue recursion) and `BUG-29` (silent condition failure) fixed first, because
  both bugs bite hardest exactly when trees get conditional.

### C — Quest base

### EXT-C01 — Expand from three quest types to eight, and index them properly

- **Problem/Opportunity** — `QuestService` supports `kill`, `fetch` and `escape`. Quest state is a flat
  `inactive` / `active` / `completed` per id, so a quest can never be offered twice, and `register_fetch()`
  completes on the first matching pickup with no count. Four quests exist. `quest_board_ui.gd` is a screen
  with almost nothing to show, and `dungeon_quest_catalog.gd` holds a single entry.
- **Action** — Add quest types, completion counters, prerequisites and repeatability.
- **Location** — `apps/game/client/scripts/quests/quest_service.gd` (`register_kill`, `register_fetch`,
  `accept_quest`, `complete_quest`, `_grant_rewards`); `content/quests/`;
  `apps/game/client/scripts/quests/quest_catalog.gd`;
  `apps/game/client/scripts/quests/dungeon_quest_catalog.gd`;
  `apps/game/client/scripts/ui/quest_board_ui.gd`
- **Solution Hint** — Eight types: `kill` (with `requiredCount`, already supported), `fetch` (add the count),
  `escape`, `clear_without` (no healing / no deaths / under a time), `reach_depth`, `escort`, `discover`
  (find N secrets or lore entries) and `defeat_with` (kill a boss using a given weapon archetype or status).
  Replace the boolean state with `{state, completions, lastCompletedRun}` so repeatables work. Add
  `prerequisites: [questId]` for chains. Do `PERF-23` (index active quests by trigger type) in the same
  change — the current per-kill linear scan is only acceptable at four quests.

### EXT-C02 — Daily and weekly bounties as the between-run ratchet

- **Problem/Opportunity** — There is no reason to log in tomorrow. Progression is gold, talents and unlocked
  tiers, all of which advance only by playing longer. `AchievementService` and `LeaderboardSettings` exist,
  and `DungeonSeedService` already derives per-tier seeds — the ingredients for rotating, seeded challenges
  are present and unused.
- **Action** — Add rotating bounties with a seeded roll and their own reward currency.
- **Location** — `apps/game/client/scripts/quests/quest_service.gd`;
  `apps/game/client/scripts/dungeon/dungeon_seed_service.gd`;
  `apps/game/client/scripts/meta/achievement_service.gd`;
  `apps/game/client/scripts/ui/quest_board_ui.gd`; `content/quests/`
- **Solution Hint** — Three daily bounties and one weekly, rolled from a date-derived seed so they are the
  same for every player without a backend, drawn from the repeatable pool with a biome and modifier attached
  ("clear Venom Mire tier 4 without using a flask"). Reward the meta-currency from `IMP-D04`. Because the
  seed is derived, not served, this works fully offline and needs no API change — which matters given
  `BUG-51`'s state of the backend contract.

### EXT-C03 — Quest chains that change the hub and the dungeon

- **Problem/Opportunity** — No quest currently alters the world. `DialogueRunner._execute_action()` can set
  flags, grant gold and start/complete quests; it cannot give items, unlock recipes, spawn NPCs or open
  routes. So even with 60 quests authored, none of them could change anything the player sees.
- **Action** — Give quests world-changing outcomes, gated behind the expanded action vocabulary.
- **Location** — `apps/game/client/scripts/dialogue/dialogue_runner.gd` (`_execute_action`);
  `apps/game/client/scripts/quests/quest_service.gd` (`_grant_rewards`);
  `apps/game/client/scripts/app/world_flags.gd`; `apps/game/client/scripts/app/world_state.gd`;
  `apps/game/client/scripts/hub/hub.gd`
- **Solution Hint** — `world_flags.gd` and `world_state.gd` already exist as the persistence layer for
  exactly this. Five to seven chains of three to five steps each, whose completion adds a hub service, opens a
  permanent shortcut in a dungeon, changes a boss encounter, or unlocks an alternate ending. Chains are what
  make a story out of a quest list, and they are the reason to keep the `prerequisites` field from `EXT-C01`.
  Blocked on `IMP-G02` (action vocabulary) — do that first.

### D — Story base

### EXT-D01 — Establish a premise, an antagonist and a reason to descend

- **Problem/Opportunity** — There is no narrative frame at all: no premise, no antagonist, no stated goal
  beyond "the dungeon exists". The ten dungeons are unconnected biomes with an `order` field. `epilogue_card.gd`
  and `boss_intro_ui.gd` exist as presentation hooks with nothing to present. A roguelite does not need a
  heavy story, but it needs a **reason**, because the reason is what makes the tenth run feel different from
  the first.
- **Action** — Write a one-page premise and bind the ten dungeons into one place with one history.
- **Location** — `content/dialogue/`; `content/items/**` (`description` fields);
  `apps/game/client/scripts/ui/epilogue_card.gd`; `apps/game/client/scripts/ui/boss_intro_ui.gd`;
  `apps/game/client/scripts/dungeon/room_content/room_lore_content.gd`
- **Solution Hint** — Souls-style: the premise is stated once at the title, and everything after it is
  implication. Bind the ten dungeons with a single event in the past that each biome shows a different
  consequence of — that alone converts `IMP-B04`'s palette-swapped back half into "the same catastrophe,
  further along". Give each boss a two-line intro card (`boss_intro_ui.gd` is already there) and each dungeon
  clear an epilogue beat (`epilogue_card.gd` likewise). One writer, one week, and the game acquires a spine.

### EXT-D02 — 150–200 lore entries carried by item descriptions and placed readables

- **Problem/Opportunity** — `room_lore_content.gd` is a working room content type with weight 0.06 that
  serves a single generic tree (`dungeon_lore_default`). Item `description` fields exist in the schema and
  are surfaced in tooltips (`format_slot_tooltip`), and are currently one flavourless line each. These are
  the two cheapest narrative delivery channels in existence and both are empty.
- **Action** — Write lore into the item base and into placed readables, biome by biome.
- **Location** — `content/items/**` (`description`);
  `apps/game/client/scripts/dungeon/room_content/room_lore_content.gd`; `content/dialogue/`;
  `apps/game/client/scripts/inventory/inventory_service.gd` (`format_slot_tooltip`)
- **Solution Hint** — Every unique from `EXT-A02` carries a description that says something about who made it
  and why — 40–60 entries for free alongside content already being authored. Then 100–150 placed readables,
  10–15 per biome, gated so that a player who explores off the critical path assembles the history and one
  who does not still finishes the game. Add a codex screen that collects found entries: collection is a
  retention mechanic on its own, and `achievements_ui.gd` is the pattern to copy.

### EXT-D03 — A bestiary that rewards learning enemies

- **Problem/Opportunity** — `EnemyCatalog` holds full definitions including resistances, and `AchievementService`
  already receives per-kill notifications, but the player has no way to see any of it. In a Soulslike the
  player's real progression is knowledge — this enemy's third swing is delayed, that one resists fire — and
  nothing in the game acknowledges or accelerates it.
- **Action** — Add a bestiary that fills in as enemies are killed and rewards completion.
- **Location** — `apps/game/client/scripts/content/enemy_catalog.gd`;
  `apps/game/client/scripts/meta/achievement_service.gd`;
  `apps/game/client/scripts/save/character_flags.gd`; `apps/game/client/scripts/ui/achievements_ui.gd`
- **Solution Hint** — Track kills per enemy id (a flag dictionary, which `character_flags.gd` already
  persists) and reveal information in tiers: name and art at 1 kill, resistances at 10, full move set and
  a lore entry at 25. Grant a small permanent bonus against fully-studied enemies to make it mechanical rather
  than decorative. This becomes far more valuable once `IMP-B01` gives enemies move sets worth learning —
  sequence it after.

### E — Class and character customization

### EXT-E01 — Make the five classes mechanically distinct, then add two more

- **Problem/Opportunity** — Classes declare `perk`, `perkName` and `perkDescription`, all localised, and
  **no code reads any of them** (`BUG-52`). `allowedWeapons` is checked in one UI screen and bypassed by every
  real equip path (`BUG-53`). What remains is `statBonuses` — two stats each — and a starting weapon. Five
  classes that differ by two stats is one class with five names, and class choice is the first decision the
  player makes.
- **Action** — Implement the perks, enforce the restrictions, and give each class a unique mechanic.
- **Location** — `content/classes/*.json`; `apps/game/client/scripts/content/class_catalog.gd`;
  `apps/game/client/scripts/combat/run_buffs.gd`;
  `apps/game/client/scripts/inventory/grid_inventory.gd` (`equip_from_index`);
  `apps/game/client/scripts/ui/class_card.gd`
- **Solution Hint** — Fix `BUG-52` and `BUG-53` first — they are the difference between "classes are
  unfinished" and "classes are fake". Then give each class one *mechanic*, not one stat: Berserker builds a
  rage meter on damage taken; Sentinel converts blocked damage into a shield; Rogue's backstabs refund
  stamina; Scholar channels mana into weapon enchants; Knight's poise regenerates faster while guarding.
  Add a Hunter (ranged, needs the projectile from `REF-14`) and a Herald (summons/status specialist) once the
  event dispatcher from `EXT-A02` exists. Each class should also carry a starting relic and a class-only
  talent branch (`EXT-E03`).

### EXT-E02 — Deepen appearance customization and make it persist into the diorama

- **Problem/Opportunity** — `CharacterAppearance` offers height (3), bulk (3), skin tone (3), hair (3), face
  (3), head covering (3) and trim (3), plus 5 aspects — a reasonable skeleton, but every axis has exactly
  three options, and the aspect list is five biome palettes. For a pixel-diorama game where the character is
  on screen constantly, that is a thin identity layer, and there is no transmog, dye or cosmetic progression
  to extend it over time.
- **Action** — Widen each axis and add earned cosmetics.
- **Location** — `apps/game/client/scripts/save/character_appearance.gd` (`HEIGHT_VARIANTS`,
  `BULK_VARIANTS`, `SKIN_TONES`, `HAIR_STYLES`, `FACE_STYLES`, `HEAD_*`);
  `content/appearance/aspects.json`; `apps/game/client/scripts/ui/character_create_ui.gd`;
  `apps/game/client/scripts/art/characters/diorama_character_skin.gd`
- **Solution Hint** — Six to eight options per axis, plus a dye system that recolours equipment within the
  biome palette (which the palette-indexed material from `IMP-J01` makes almost free) and transmog that
  separates appearance from stats. Then make cosmetics *earned*: an aspect per dungeon cleared at tier 10, a
  dye per boss first-kill, a title per achievement. Cosmetic progression is the cheapest possible content per
  hour of retention, and this game's art pipeline is unusually well suited to it.

### EXT-E03 — Grow the talent tree from 18 nodes to a real build space, with class branches

- **Problem/Opportunity** — `content/talents/tree.json` has three branches (`arms`, `guard`, `aptitude`) of
  six nodes each — 18 nodes total, shared by all five classes. `ProgressionService` supports spending and
  respec (`BlacksmithService.RESPEC_COST = 250`), and `Equipment.STAT_KEYS` has 28 stats to draw on. Eighteen
  shared nodes cannot express five distinct classes, let alone the build variety a 10-tier ladder needs.
- **Action** — Expand to shared plus per-class branches, with keystones that change rules.
- **Location** — `content/talents/tree.json`;
  `apps/game/client/scripts/progression/progression_service.gd` (`get_talent_stat_totals`,
  `respec_talents`); `apps/game/client/scripts/ui/talents_ui.gd`;
  `apps/game/client/scripts/combat/combat_stat_modifiers.gd`
- **Solution Hint** — Keep the three shared branches but grow each to 10–12 nodes, and add a 10-node
  class-exclusive branch per class — roughly 90 nodes total. Most nodes stay stat-shaped (they flow through
  `get_talent_stat_totals()` unchanged), but each branch should end in a **keystone** that changes a rule
  rather than a number, routed through the same event dispatcher as uniques, relics and perks. That single
  dispatcher (`EXT-A02`) now serves four systems, which is what makes 90 nodes affordable.

### EXT-E04 — Multiple characters, and a reason to make a second one

- **Problem/Opportunity** — `CharacterService` holds one character; `character_create_ui.gd` creates it once.
  A player who wants to try Scholar after 20 hours as a Knight must abandon their progress or not try. Every
  successful game in this genre supports multiple characters, because a second character is the cheapest
  possible "new content".
- **Action** — Add character slots with a shared account-level meta layer.
- **Location** — `apps/game/client/scripts/save/character_service.gd`;
  `apps/game/client/scripts/save/local_save.gd`; `apps/game/client/scripts/ui/character_create_ui.gd`;
  `apps/game/client/scripts/ui/continue_menu.gd`; `apps/game/client/scripts/save/save_migrator.gd`
- **Solution Hint** — Split the save into account scope (unlocked dungeons, bestiary, lore codex, cosmetics,
  the endless depth record from `IMP-D04`) and character scope (level, talents, inventory, quests). Three to
  five slots. The stash (`StorageService`, already a separate 8×6 grid) becomes account-shared, which gives
  a second character an immediate reason to exist. This needs a save-schema migration — sequence it with
  `BUG-48`'s currency collapse so there is one migration rather than two.

### F — Systems that turn content into retention

### EXT-F01 — A run-summary and progression screen worth looking at

- **Problem/Opportunity** — `results_screen.gd` exists and reports an outcome. There is no run history, no
  personal best, no comparison to previous attempts, no build summary and no share affordance. Players return
  to games that show them getting better; nothing here does.
- **Action** — Turn the results screen into the progression feedback loop.
- **Location** — `apps/game/client/scripts/ui/results_screen.gd`;
  `apps/game/client/scripts/app/run_flow.gd` (run-end results);
  `apps/game/client/scripts/meta/achievement_service.gd`;
  `apps/game/client/scripts/save/character_flags.gd`
- **Solution Hint** — Depth or tier reached against personal best, damage dealt and taken, best drop, relic
  loadout, boss kill times, deaths by cause, and a seed the player can copy and share. Persist the last 20
  runs and show a trend. Pair with `IMP-I03`'s telemetry — the same data that tells the player they are
  improving tells you where the difficulty curve is wrong.

### EXT-F02 — Weekly seeded challenge runs

- **Problem/Opportunity** — `DungeonSeedService` derives per-tier seeds, `RunModifierService` applies named
  modifiers, and `LeaderboardSettings` exists. Everything needed for a shared weekly challenge is present and
  none of it is combined. A fixed seed plus fixed modifiers plus a shared scoreboard is the highest
  engagement-per-line-of-code feature available to this project.
- **Action** — Add a weekly challenge mode built from the existing seed and modifier services.
- **Location** — `apps/game/client/scripts/dungeon/dungeon_seed_service.gd`;
  `apps/game/client/scripts/dungeon/run_modifier_service.gd`;
  `apps/game/client/scripts/meta/leaderboard_settings.gd`;
  `apps/game/client/scripts/app/run_flow.gd`; `services/backend/src/Aumbrye.Application/Services/LeaderboardService.cs`
- **Solution Hint** — Derive the week's seed and modifier set from the ISO week number so every client agrees
  offline; score by depth, time or kills. The backend already has a `LeaderboardService`, so an online board
  is optional rather than required — ship it offline-first with a local best, and light up the board when the
  API is available. Requires `BUG-45` (unseeded crit and AI rolls) fixed, or two players on the same seed will
  not have the same run.

### EXT-F03 — Boss rush, gauntlets and alternate rule sets

- **Problem/Opportunity** — Three modes exist (castle, waves, endless) and share one dungeon builder. Once
  bosses have phases (`IMP-B02`) and modifiers have a real vocabulary (`IMP-C02`), new modes are recombinations
  rather than new systems — and each one multiplies the value of content already authored.
- **Action** — Add two or three recombination modes once their prerequisites land.
- **Location** — `apps/game/client/scripts/app/run_mode_config.gd`;
  `apps/game/client/scripts/app/run_flow.gd`; `apps/game/client/scripts/dungeon/dungeon_builder.gd`;
  `apps/game/client/scripts/dungeon/run_modifier_service.gd`
- **Solution Hint** — Boss rush (every boss in sequence, one flask, scored by time); gauntlet (a fixed
  10-floor route with escalating modifiers and no rest); ironman (one life, permanent loss). `run_mode_config.gd`
  is 22 lines and is already the branch point — the cost is in the mode's rules, not its plumbing. Deliberately
  schedule these *after* section 13, because a new mode built on one-attack enemies is a new way to do the
  same thing.

### EXT-F04 — Make the hub a place that visibly grows

- **Problem/Opportunity** — `hub.gd` and `hub_diorama.gd` build a static hub. Nothing about it changes as the
  player progresses: no new buildings, no rescued NPCs appearing (`EXT-B02`), no trophies, no visual record
  of the ten dungeons. The hub is the between-run beat, and it currently communicates nothing.
- **Action** — Bind hub state to progression so returning to it is a reward.
- **Location** — `apps/game/client/scripts/hub/hub.gd`; `apps/game/client/scripts/hub/hub_diorama.gd`;
  `apps/game/client/scripts/app/world_flags.gd`; `apps/game/client/scripts/save/character_flags.gd`
- **Solution Hint** — Drive hub dressing from flags that already persist: a banner per dungeon cleared, a
  trophy per boss, a workshop that upgrades visibly as the blacksmith levels, NPC arrival for each rescue.
  `hub_diorama.gd` is already data-driven dressing; this is mostly a matter of gating existing prop spawns on
  flags. Low engineering cost, disproportionate effect on the sense of progress.

### EXT-F05 — Build the authoring tools before authoring the content

- **Problem/Opportunity** — The scale targets at the top of this section — 350+ items, 60+ affixes, 80
  enemies, 60+ quests, 1,000+ dialogue nodes, 300–500 room-layout variants (`IMP-E02`) — are not reachable by
  hand-editing JSON. `tools/` exists (Python, linted by Ruff in CI), `scripts/validate-content` validates
  against `content/schemas/`, and `packages/` holds C# helpers. The infrastructure for generation and
  validation is present; the generators are not.
- **Action** — Write the generators and validators first, then author against them.
- **Location** — `tools/`; `scripts/validate-content/`; `content/schemas/`;
  `apps/game/client/scripts/validation/suites/`
- **Solution Hint** — In priority order: (1) an **item generator** from bases × biomes × rarity (`EXT-A01`);
  (2) a **room-variant generator** that mirrors and rotates authored anchor sets (`IMP-E02`); (3) a
  **balance exporter** that dumps every enemy, weapon and tier multiplier to a spreadsheet so the curve can be
  seen — `scripts/balance/balance-cli.mjs` already exists as the seed of this; (4) **reachability validation**
  (every enemy in a pool, every item in the catalog, every dialogue node reachable, every quest completable)
  which would have caught `BUG-37`, `BUG-47` and the orphan-item class of bug outright; (5) a **dialogue
  graph linter** for the cycles in `BUG-28` and the unknown keys in `BUG-29`. Note that this is also the
  answer to `QA-01`: content validation that checks *meaning* is worth far more than 145 assertions that check
  source text.

---

## 15. Suggested execution order

The dependencies between items matter more than their individual severity.

**Phase 0 — Make it shippable (days)**
`BUG-01` → `BUG-02` → `QA-05` (export smoke test, which proves the first two) → `BUG-03` → `BUG-10` / `DEP-04`
(Godot 4.7.1 pin) → `DEAD-03` (exclude the MCP addon from exports) → `BUG-37` (move the test fixture out of
shipping content).

**Phase 0.5 — Stop the run economy leaking, and fix the two-line bugs that break the feel (days)**
`BUG-13` (inventory changes full-heal the player) is the single highest-value fix in this document: until it
lands, no combat, difficulty or economy tuning means anything. Then `BUG-39` (`>=` should be `>`) and
`BUG-40` (hit-stop on unscaled time) — two of the smallest diffs here and the largest change to how the game
feels. Then `BUG-42` / `BUG-43` (the refund exploit and the non-transactional purchase), `BUG-14` / `BUG-15` /
`BUG-18` (loot rolls and instance identity), `BUG-16` / `BUG-17` (inventory transactions), `BUG-27` + `BUG-41`
(`Engine.time_scale` ownership) and `BUG-30` (endless-mode memory and save growth).

**Phase 1 — Make it fast (weeks)**
Profile first and commit a baseline (`QA-02`). Then `PERF-01` + `PERF-02` + `REF-04` + `PERF-16` / `PERF-17` /
`PERF-18` / `PERF-22` as one combat-performance change (they are all the same fix — cache the node, drop the
dynamic dispatch); `PERF-05`; `PERF-06`; `PERF-07` + `BUG-36`; `PERF-09` / `PERF-11` / `PERF-20` / `PERF-21`;
then `PERF-03` + `PERF-24` + `FEAT-03` together (async loading is both the fix and the feature). `PERF-12`
(physics interpolation) should land early in this phase because it changes how everything else feels.
`PERF-19` and `PERF-23` are prerequisites for `IMP-F01` and `IMP-G03` respectively, not for shipping.

**Phase 2 — Make it correct (weeks)**
`BUG-05` → `BUG-06` → `BUG-07` → `BUG-08` → `BUG-09` / `BUG-11` / `BUG-12` → `REF-08` (pause ownership).
Then the combat-correctness cluster, in this order because each depends on the last:
`BUG-20` (one facing convention) → `BUG-21` (one hit-arc classification) → `BUG-23` (hyperarmor covers startup)
→ `BUG-22` (parry has a cost) → `BUG-31` (resources simulate on the physics tick) / `BUG-32`.
`BUG-24` / `BUG-25` / `BUG-26` / `BUG-35` / `BUG-45` are the enemy-side equivalents and gate all of
section 13-B; `BUG-45` additionally gates `EXT-F02` (weekly seeded challenges), because two players on one
seed must get one run. `BUG-28` / `BUG-29` gate all of section 13-G and 14-B/C/D.
`BUG-52` / `BUG-53` gate `EXT-E01`, and `BUG-44` / `BUG-50` finish `REF-08`.
Content hygiene that unblocks validation: `BUG-47` (orphan boss) and `BUG-48` (the `gold`/`coins` collapse,
which should share a save migration with `EXT-E04`).

**Phase 3 — Make it maintainable (months)**
`DEP-01` / `DEP-02` (backend to .NET 10) → `DEP-03` (web) → `BE-01` / `BE-02` / `BE-03` → `QA-01` (the big
validation conversion) → `REF-01` (autoload consolidation) → `REF-05` / `DEAD-01` / `DEAD-02` (art pipeline
collapse) → `REF-07` → `REF-09` … `REF-14` → `DOC-01`. `REF-10` (one difficulty profile, tuned from
`content/`) is a hard prerequisite for section 13-I, and `REF-13` for `IMP-B02`.

**Phase 4 — Make it the game it is meant to be (ongoing)**

This is section 13, ordered by leverage rather than by category. Content work dominates; most of it is
unblocked by small engineering changes already listed above.

1. **`IMP-B01` — author enemy move sets.** The engine already supports everything; zero content uses it.
   Nothing else in combat matters until enemies have more than one attack. Gated on `BUG-25` / `BUG-35`.
2. **`IMP-D01` / `BUG-33` — rotate biomes in endless mode.** Nine biomes exist and are unreachable. Small
   change, largest visible payoff. Take `IMP-D02` (continuous difficulty) and `BUG-34` (the 250 rung) with it.
3. **`IMP-F01` — resize the inventory.** Six equipment slots is a wall players hit in the first room.
   Gated on `PERF-19`, `BUG-16`, `BUG-17`.
4. **`IMP-A01` / `IMP-A02` / `IMP-A05` — dodge proportions, cancel windows, hit-stop.** This is "snappy".
5. **`IMP-C01` — ten real difficulty tiers**, then `IMP-C02` (tiers change rules, not multipliers) and
   `IMP-C03` (a tier ladder rather than a dropdown, with `BUG-38`).
6. **`IMP-H03` — relics as choices**, then `IMP-F02` (affix pool and uniques) and `IMP-F04` (drop
   presentation). This is the roguelite variance layer.
7. **`IMP-B02` — boss phases** (gated on `REF-13`), then `IMP-B04` (distinct enemies for dungeons 6–10) and
   `IMP-B03` (navigation and repositioning).
8. **`IMP-E01` / `IMP-E02` / `IMP-E03` — bigger floors, room-layout variants, pacing rules.**
   Then `IMP-E04` (secrets) and `IMP-E05` (minimap).
9. **`IMP-G01` / `IMP-G02` / `IMP-G03` — story, dialogue vocabulary, quests.** Gated on `BUG-28` / `BUG-29`.
10. **`IMP-I01` / `IMP-I02` / `IMP-I03` — behavioural difficulty, death stakes, assists.** Do this last of the
    design work: it can only be tuned once the systems above exist.
11. **Presentation throughout:** `IMP-J02` (pixel grid) is cheap and everywhere; `IMP-J04` (biome grading)
    compounds with `IMP-D01`; `IMP-J01` shares its implementation with `PERF-04` / `REF-05`; `IMP-J03` follows
    `IMP-C03` and `IMP-F03`.

The remaining engineering features — `REF-02` (one generator, and `BUG-51` if it stays), `FEAT-01`,
`FEAT-02`, `FEAT-04`…`FEAT-08` — slot in alongside. Note that `FEAT-02`, `FEAT-04` and `FEAT-08` are now
largely superseded by `IMP-B03`, `IMP-A03` and `IMP-E03` / `IMP-H03`, which state the same gaps against the
design target.

**Phase 5 — Build the content bases (months, parallelisable)**

This is section 14. Unlike phase 4 it is mostly writing and authoring, so it parallelises across people once
the enabling code exists. Two things must come first, in this order:

- **`EXT-F05` — build the tooling before the content.** The generators, the balance exporter and especially
  the reachability validators. Authoring 350 items and 1,000 dialogue nodes by hand-editing JSON without them
  is how a content push stalls. This also subsumes most of `QA-01`'s value.
- **The shared event dispatcher** (`onHit`, `onKill`, `onParry`, `onLowHealth`, `onRoomClear`, …), specified
  in `EXT-A02`. Four separate systems need it — uniques, relics (`IMP-H03`), class perks (`BUG-52`) and
  talent keystones (`EXT-E03`) — so building it once converts four large content efforts from "engineering
  per entry" into "data per entry". It is the highest-leverage single object in this document.

Then, in rough dependency order:

1. `EXT-A01` (item bases) → `EXT-A02` (uniques) → `EXT-A03` (flask and consumable roles) → `EXT-A04`
   (salvage and conversion). `EXT-A03`'s flask is also the other half of `IMP-I02`'s death stakes.
2. `EXT-E01` (real classes) → `EXT-E03` (talent branches) → `EXT-E02` (customization and cosmetics) →
   `EXT-E04` (character slots, sharing a save migration with `BUG-48`).
3. `EXT-D01` (premise) → `EXT-B01` (hub cast) → `EXT-B02` (rescuable NPCs) → `EXT-C01` (quest types) →
   `EXT-C03` (chains) → `EXT-D02` (lore) → `EXT-B03` (reactive lines).
4. `EXT-F01` (results screen) and `EXT-F04` (a hub that grows) are cheap and should land early for the
   feedback they give; `EXT-C02` (bounties) and `EXT-F02` (weekly challenges) are the retention ratchets;
   `EXT-D03` (bestiary) and `EXT-F03` (alternate modes) come last because both only pay off once enemies and
   bosses are worth re-fighting.

---

## 16. Verification notes and caveats

- **Nothing here was profiled.** Performance items describe structural costs read from source; they are ranked
  by expected impact, not by measurement. Capture a baseline before acting on Phase 1.
- **Nothing here was executed.** The Godot project was not run, the .NET solution was not built, and the web app
  was not started during this analysis. Items marked *Verified* are verified **against the source**, not against
  runtime behaviour.
- **BUG-01 and BUG-02 are inferences from engine semantics** applied to verified code. Both are high-confidence
  (`globalize_path` + `FileAccess` on `res://` paths cannot read from a `.pck`), but the fastest way to confirm
  is to export a build and run it — which is exactly what QA-05 proposes and why it is in Phase 0.
- **Dependency versions were resolved live** from npmjs.com and api.nuget.org on 2026-08-06 and will drift.
  Re-check with `npm outdated` and `dotnet list package --outdated` before executing DEP-02 / DEP-03.
- **The unreferenced-scene scan produced 167 candidates that are almost entirely false positives** — room,
  prop and enemy scenes are referenced through string interpolation (`"res://scenes/rooms/%s/%s_%s.tscn"` in
  `biome_registry.gd:183`) and through `content/**/*.json` `scene` fields. They are **not** listed as dead code
  above for that reason. That fragility is itself worth noting: there is no compile-time link between content
  ids and scene files, so a typo in a JSON `scene` field fails only at spawn time.
- **`docs/` was deliberately not consulted** as a source of truth, per the brief. It appears only in DOC-01 and
  DOC-02 as a remediation target.
- **This document does not claim to contain every bug in the project, and no static reading could.**
  What it contains is every defect found by reading the source; the honest boundary is worth stating
  precisely, because the difference matters for planning.

  **What the sweep covers:** all of `apps/game/client/scripts/` was walked. The systems most likely to hold
  gameplay-affecting defects — combat, player, camera, inventory, items, loot, dungeon and `procgen/`,
  enemies, hub services, quests, dialogue, npc, save, app, content, and the design-critical UI screens —
  were read function by function, and every item in section 5A names the function it was found in.
  `content/**` was parsed programmatically (every JSON in every subtree), which is how `BUG-37`, `BUG-47`
  and the `IMP-B01` / `IMP-B04` findings surfaced. The backend and web sources were read at a lower
  resolution, targeting contract and lifecycle issues rather than logic.

  **What it cannot cover.** Four classes of bug are structurally invisible to this method:
  (1) **runtime-only failures** — nothing was executed, so null dereferences on paths not taken, ordering
  bugs between autoloads, and anything depending on real frame timing will not appear;
  (2) **scene-graph bugs** — 227 `.tscn` files were not audited node by node, and much of this project's
  behaviour lives in exported `NodePath`s, collision layers and signal wiring done in the editor;
  (3) **the `.cs` and `apps/web` trees**, read for contracts rather than logic, so `BUG-49` and `BUG-51` are
  representative rather than exhaustive;
  (4) **shader and material bugs**, not examined at all.
  `QA-05` (an export smoke test) and `QA-02` (an enforced frame-budget gate) would catch more real defects
  in a week of CI than another pass of static reading would. That is the recommendation: the highest-value
  next step for bug discovery is not more analysis, it is instrumentation.

- **Two claims in this document were wrong in earlier revisions and are corrected inline:** `PERF-06`
  (the audio director does *not* synthesise sine tones in normal play — all ten biomes resolve real stems)
  and `IMP-A05` (hit-stop, camera punch, shake, vibration and damage numbers *do* exist and are well built —
  the defects are `BUG-39` and `BUG-40`, which break their timing). Both carry a dated correction note at the
  item. If a third turns up, the same treatment applies: correct in place, say so, do not quietly edit.

- **Section 14's scale targets are sizing estimates, not measurements.** The "today" column is counted from
  `content/`; the "target" column is a judgement about what a 10-tier ladder plus an endless mode needs to
  sustain, calibrated against comparable games rather than against playtest data from this one. Treat them as
  input to scoping and hiring, and revise once `EXT-F01` / `IMP-I03` are producing real retention numbers.
- **Section 13 is a design gap analysis, not a design document.** It states what the code does today against
  the stated target and proposes a direction. Numbers in the Solution Hints (grid sizes, affix counts, i-frame
  windows, room counts) are starting points chosen to be defensible, not tuned values — they need playtesting,
  and `IMP-I03` exists because there is currently no instrumentation to tune them against.
- **The content census in section 1 was produced by parsing `content/` directly** (every `*.json` under each
  subtree) on 2026-08-06. The two counts most likely to surprise — *zero* enemies with an `attacks` array and
  *zero* bosses with phases — were verified by loading all 40 files and checking for the key, not by grep.
- **`IMP-B04`'s "palette swap" claim is a literal comparison of `enemyPool` and `bossPool` arrays.**
  `glacial_hollow` and `frozen_fortress` list the same four enemies and the same boss; `iron_vault` and
  `forgotten_castle` likewise. It is possible this is intentional staging for content that is planned but
  not authored; either way the player-facing result today is that dungeons 6–10 introduce no new opponent.
