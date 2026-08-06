# Quality bar — replacing placeholders

## Status: FINISHED

Acceptance checks when replacing PLACEHOLDER / STUB / FAKE / BROKEN / ABSENT surfaces listed in [`../existing_codebase/00-PLACEHOLDER-INVENTORY.md`](../existing_codebase/00-PLACEHOLDER-INVENTORY.md). Grounded in systems that already exist under `apps/game/client/`, `content/`, `services/backend/`, and `apps/web/`. Doc conventions: [`../DOC-CONVENTIONS.md`](../DOC-CONVENTIONS.md).

## Done criteria (per surface)

A replacement is done only if all apply:

1. **Player-facing** — no generator/sine/ColorRect/emoji/Unicode stand-in remains for that surface.
2. **Wired** — loaded through the real catalog/scene/profile path; fallbacks are error-only.
3. **Honest** — rewards, quests, and results match the event that occurred.
4. **Readable at play speed** — telegraphs, recovery, and hit confirmation are clear.
5. **Tested** — suite under `scripts/validation/suites/` updated when automatable; otherwise a short manual checklist.
6. **Authored when the surface is art** — characters, weapons, and props that claim to be pixel/voxel are authored from discrete cells, not procedural boxes with a pixel filter. See [`character-authoring.md`](character-authoring.md).

## Domain checks

### Character authoring (P0 art direction)

| Criterion | Status | Done | Fail |
|-----------|--------|------|------|
| Source of geometry | **FINISHED** — `build_from_manifest()` loads `content/characters/*.json` + committed `.mesh` from `tools/voxel-import/`; box fallback logs `push_error` only | Committed voxel-authored `ArrayMesh` parts from `tools/voxel-import/` | Runtime `BoxMesh` from `DioramaCharacterSkin._build_humanoid` |
| Grid | **FINISHED** — `VoxelGrid.EDGE := 0.04`; manifests use integer voxel joints | Every vertex on a `VoxelGrid.EDGE` (0.04 m) boundary | Arbitrary float sizes in `PROFILES` |
| Palette | **FINISHED** — `VoxelMeshBuilder._snap_to_palette()` + `use_vertex_color` on character materials | Vertex colours snap to `PixelDioramaStyle.PALETTES` | Free RGB / procedural `cell_hash` tint as the silhouette |
| Rig contract | **FINISHED** — pivot names (`Root`, `LegL`, `Torso`, `ArmR`, etc.) match `DioramaAnimLibrary` track paths | Manifest pivots match existing animation track names | Renamed pivots that break clips |
| Equipment visuals | **FINISHED** — `apply_equipment()` + `visual` blocks on helm items; wired from `InventoryService` | Items with `"visual"` change the body in one frame | Stats change, silhouette does not |
| Scale | **FINISHED** — discrete height/bulk archetype manifests; uniform scale only; no `Root.scale` for proportions | No non-uniform `Root.scale` on any character | `height`/`bulk` via `root.scale` |

### Combat

| Criterion | Status | Done | Fail |
|-----------|--------|------|------|
| Hit confirmation | **FINISHED** — authored SFX in `assets/audio/sfx/` + diorama body flash via `HitFeedback` | Authored SFX + feedback on diorama body | Generator beep; pulse on unused mesh |
| Swing phases | **FINISHED** — `build_attack()` injects `anim_hitbox_on/off` method tracks; `WeaponController` syncs from anim when bound | Windup/active/recovery match hitbox | Timer/anim disagree |
| Guard | **FINISHED** — distinct `block.wav` / `parry.wav` + VFX/anim; stamina scales with poise damage | Distinct block/parry feedback + stamina cost | Same cue for all |
| Heal | **FINISHED** — dedicated `heal` clip in `DioramaAnimLibrary`; SFX `heal_raise` / `heal_gulp` / `heal_commit` | Dedicated heal anim/SFX | Heal reuses stagger |
| Lunge | **FINISHED** — `get_attack_lunge_velocity()` uses weapon `lunge_distance` + phase timing | Non-zero, collision-safe motion from `get_attack_lunge_velocity()` | Still `Vector3.ZERO` |

### Audio

| Criterion | Status | Done | Fail |
|-----------|--------|------|------|
| Combat SFX | **FINISHED** — `content/audio/sfx.json` + `.ogg` under `assets/audio/sfx/`; `AudioDirector` streams file-backed combat cues; `_prime_tone_burst` is error-only fallback | Streams from `assets/audio/` via `AudioDirector` | Sine/`AudioStreamGenerator` only |
| Biome ambience | **FINISHED** — `_restore_generator_streams()` preserves file-backed streams on `_ambience`/`_music` | Profile OGG plays and stays | `_restore_generator_streams()` clobbers load |

### Loot / UI / meta honesty

| Criterion | Status | Done | Fail |
|-----------|--------|------|------|
| Icons | **FINISHED** — `ItemIconAtlas` + `item_icons.png` atlas cells | Item `iconPath` / atlas cells | Unicode-only cells |
| Affix tiers | **FINISHED** — `affix_roller.gd` filters by `itemTypes` and rolls `tiers[rarity]` | `affix_roller.gd` respects rarity tables | Flat 1–3 rolls |
| Results | **FINISHED** — `results_screen.gd` handles `waves_failed` / `waves_complete` | Outcome keys match run mode (castle/waves) | Waves win/fail ignored |
| Escape quests | **FINISHED** — `quest_service.gd` completes escape only on `escaped` / `waves_complete` outcomes | Complete only on real escape | Complete on any `run_ended` / death |
| Fetch quests | **FINISHED** — `inventory_service.add_item` calls `QuestService.register_fetch` | `register_fetch` wired from inventory pickup | Quest impossible to progress |

### Dungeon builder

| Criterion | Status | Done | Fail |
|-----------|--------|------|------|
| Height transitions | **FINISHED** — `_build_height_transitions()` builds stairs per edge delta or asserts flat when `maxHeightLevel=0` | Real implementation replacing `pass` | Still no-op |
| Shortcuts | **FINISHED** — loop edges emit `kind: "shortcut"`; builder opens doors and nav-links them; `dungeon_suite.gd` tests | Called from build path with tests | Function exists uncalled |
| Floor 10 | **FINISHED** — `_generate_final_floor()` reads biome `finalFloor` (entrance→arena→boss, themed boss id) | Uses selected biome fantasy | Always Forgotten Sovereign layout |

### Platform

| Criterion | Status | Done | Fail |
|-----------|--------|------|------|
| Online runs | **FINISHED** — `USE_ONLINE_PROCgen := false` with API guard; not enabled without parity | `USE_ONLINE_PROCgen` enabled only with API + parity suites green | Flag flipped without parity |
| CI Godot | **FINISHED** — `ci.yml` and `release.yml` read `apps/game/client/.godot-version` (4.7.0); `project.godot` features `4.7` | Workflow version matches `project.godot` features | 4.4 CI vs 4.7 project |

## Related

- Placeholder inventory: [`../existing_codebase/00-PLACEHOLDER-INVENTORY.md`](../existing_codebase/00-PLACEHOLDER-INVENTORY.md)
- Character authoring plan: [`character-authoring.md`](character-authoring.md)
- Loop integrity: [`00-ADDICTION-AND-FUN.md`](00-ADDICTION-AND-FUN.md)
- Architecture: [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
