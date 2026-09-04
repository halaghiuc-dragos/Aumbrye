# Aumbrye — MVP depth plan

**Status:** authoring plan. Nothing here is implemented yet.
**Written against:** the working tree as read on 2026-09-02 (all 406 GDScript files under
`apps/game/client/scripts/`, the procgen and dungeon stacks, the UI stack, and `content/`).

---

## 0. How to use this document (read this first)

This plan is written to be executed by an AI model working one item at a time. Follow these rules
literally.

1. **One item per change.** Each item has an ID (`EN-04`, `RM-01`, …). Do exactly one, verify it,
   then move on. Do not batch items from different workstreams.
2. **§7 is a separate, per-file audit** of bugs, optimisations and enhancements found by reading the
   tree. Its rows are not items — fix them inside whichever phase touches the same file.
3. **Every item has the same five fields.** `Files` (the only files you should need to touch),
   `Problem` (the defect, with the evidence that proves it), `Action` (numbered, mechanical),
   `Solution` (the strong hint: shapes, constants, invariants, and the trap that will bite you),
   `Done when` (the check that proves it worked).
4. **`Files` is a starting set, not a cage.** If a change needs a file not listed, that is allowed —
   but if it needs more than ~3 extra files, stop and re-read the item; you have probably
   misunderstood the scope.
5. **Never invent a system that already exists.** §1 is the inventory of what is already built and
   good. Re-read it before every item. The single most expensive mistake available in this codebase
   is rewriting something that works.
6. **Tunables go in `content/`, not in `const`.** If a designer would ever want a different number
   per biome, per enemy, per weapon or per floor, it belongs in a JSON file under `content/` and is
   read through `ContentLoader.load_json`. `const` is only for engine-level facts (layer bits,
   physics epsilons, buffer sizes).
7. **Repository rules (from `CLAUDE.md`, non-negotiable):** no CI, no GitHub Actions, no Dependabot,
   and **no test files of any kind, in any language** — nothing named `test_*`, `*_test.*`,
   `*.test.*`, `*.spec.*`, and no `tests/` or `__tests__/` directories. Verification is the debug
   scenes under `apps/game/client/scenes/debug/` and `node scripts/validate.mjs`, run by hand. If an
   item seems to want a test, add a check to an existing debug scene instead and say so.
8. **Zero warnings.** `project.godot` promotes ~40 GDScript warnings to errors. Every script you
   touch must still pass `res://scenes/debug/lint_scripts.tscn`. Common traps: unused parameters
   (prefix with `_`), shadowed variables, integer division, unsafe void return, untyped enum casts.
9. **Determinism is a hard invariant.** Anything that runs inside floor generation must draw from a
   seeded `RandomNumberGenerator` obtained via `ProcgenRng.stream(run_seed, "<name>")` or
   `FloorSeedMix.mix(...)`. Never call the global `randf()`/`randi()` inside procgen. A floor must
   build identically from the same seed forever.
10. **Save compatibility is a hard invariant.** Any new persisted field must be added through
   `scripts/save/save_migrator.gd` (`CURRENT_VERSION` is 12; add a step, bump the version) and
   accepted by `scripts/save/save_validator.gd`. Never widen a save shape without a migration.
11. **Facing convention.** Rig forward is **`+basis.z`**, resolved through
    `CombatFacing.forward_of()` / `aim_forward_of()`. Do not write `-transform.basis.z` anywhere in
    gameplay code.

### Conventions used below

- `→ ID` means "that item must land first".
- `<file>.json:key` means a key in that file.
- A path marked ***(new)*** does not exist yet — this plan is asking you to create it.
  `scripts/check-doc-paths.mjs` honours that marker, so do not "fix" those citations.
- `file.gd:symbol()` means that function in that file.
- **Sizes** are rough: `S` ≈ under an hour of focused edits, `M` ≈ a session, `L` ≈ multiple
  sessions, `XL` ≈ a whole workstream on its own.


### Item index

138 items across 17 workstreams, plus a 67-row per-file audit in §7. Pick one, do it, verify it, stop. **`BG-01` first — the game currently drops the
player out of the world.**

| § | Items |
|---|---|
| **BG** Blocking defects (§BG) | `BG-01` bedrock floor · `BG-02` height transitions at the door · `BG-03` out-of-world recovery · `BG-04` geometry-hole audit · `BG-05` room tracking cost · `BG-06` mana regen · `BG-07` shield damage types · `BG-08` frontal-arc dead code |
| **EN** Enemy intent (§EN) | `EN-01` author attack classes · `EN-02` make the class mechanically real · `EN-03` telegraph = real reach · `EN-04` intent glyph · `EN-05` feints/holds · `EN-06` directional hit reactions · `EN-07` enemy defensive verbs · `EN-08` real flanking · `EN-09` off-screen danger · `EN-10` **enemy diversity** · `EN-11` biome roster shape · `EN-12` real elites |
| **PH** Physics (§PH) | `PH-01` knockback · `PH-02` stagger displacement + hit-stop split · `PH-03` swept hitbox · `PH-04` projectile ballistics · `PH-05` crowd separation |
| **AN** Animation (§AN) | `AN-01` stepped animation · `AN-02` anticipation/follow-through · `AN-03` attacker recoil · `AN-04` held charge pose |
| **RM** Rooms (§RM) | `RM-01` circular rooms · `RM-02` multi-door arenas · `RM-03` variant shape+props · `RM-04` one-way doors · `RM-05` legible key ring · `RM-06` no-soft-lock proof · `RM-07` fog gates + lock-in · `RM-08` ambushes · `RM-09` findable secrets · `RM-10` landmark art · `RM-11` dressing density · `RM-12` generation success rate · `RM-13` **per-biome topology** · `RM-14` corridors · `RM-15` kill the blob · `RM-16` real doors · `RM-17` size pacing · `RM-18` floor scoring · `RM-19` verticality · `RM-20` dead shop kind · `RM-21` empty prop scenes · `RM-22` two room-scene generations |
| **HD** HUD (§HD) | `HD-01` one HUD contract · `HD-02` banner queue · `HD-03` turn the pixel UI on · `HD-04` per-mode matrix · `HD-05` waves radar · `HD-06` combat readouts · `HD-07` damage direction · `HD-08` unified prompts · `HD-09` objective line · `HD-10` minimap info |
| **CB** Combat (§CB) | `CB-01` charged heavy · `CB-02` plunge attack · `CB-03` just-guard · `CB-04` stagger execution · `CB-05` archetype identity · `CB-06` widen the rules bus · `CB-07` mana tension · `CB-08` status identity and answers |
| **BS** Bosses (§BS) | `BS-01` **six empty boss scripts** · `BS-02` boss entrance · `BS-03` phase appearance · `BS-04` hazard telegraph language · `BS-05` boss door ritual · `BS-06` minibosses · `BS-07` epilogue · `BS-08` final floors |
| **RG** Ranged (§RG) | `RG-01` aim mode · `RG-02` recovering quiver · `RG-03` block/parry projectiles · `RG-04` throwables |
| **IV** Loot (§IV) | `IV-01` behavioural gear · `IV-02` set bonuses · `IV-03` talent keystones · `IV-04` wire the loot juice · `IV-05` field salvage |
| **UX** Screens (§UX) | `UX-01` **four list-box screens** · `UX-02` plannable talents · `UX-03` one item cell everywhere · `UX-04` dialogue presentation · `UX-05` stair-menu cards · `UX-06` loading screens · `UX-07` settings tabs · `UX-08` creation previews the fight · `UX-09` menu consistency · `UX-10` notification lanes |
| **AD** Retention (§AD) | `AD-01` run contract · `AD-02` reward cadence · `AD-03` visible floor themes · `AD-04` surface the session layer · `AD-05` results points forward · `AD-06` death recap · `AD-07` the first hour · `AD-08` endless as the long game |
| **MD** Mode depth (§MD) | `MD-01` **the Vigil mutates** · `MD-02` extraction stakes · `MD-03` the Waning made visible · `MD-04` tier ladder in-run · `MD-05` alternate rule sets · `MD-06` weekly presence · `MD-07` mode unlocks as events |
| **AU** Audio (§AU) | `AU-01` placeholder SFX · `AU-02` impact material · `AU-03` stingers · `AU-04` enemy voice |
| **VS** Visual style (§VS) | `VS-01` **value range** · `VS-02` crispness · `VS-03` biome palettes · `VS-04` no unskinned meshes · `VS-05` player silhouette · `VS-06` enemy silhouettes · `VS-07` VFX budget · `VS-08` **performance baseline** · `VS-09` camera set-pieces |
| **AX** Access (§AX) | `AX-01` telegraph shape · `AX-02` pad parity · `AX-03` glyph coverage · `AX-04` text scale |
| **SY** Everything else (§SY) | `SY-01` traps as a mechanic · `SY-02` quests/NPC/dialogue wiring · `SY-03` a hub that grows · `SY-04` class weapon identity · `SY-05` quality presets · `SY-06` save migrations · `SY-07` localisation sweep · `SY-08` world simulation indoors · `SY-09` extend the audits · `SY-10` backend scope statement · `SY-11` release readiness · `SY-12` keep the audit alive |

---

## 1. Ground truth — what already exists

Read this before writing any code. Everything in this table was verified by reading the file.

### 1.1 Built, working, and good — **do not rewrite**

| System | Where | What it already does |
|---|---|---|
| Attack phase machine | `scripts/combat/weapon_controller.gd` | STARTUP/ACTIVE/RECOVERY/DRAWING, input buffering (`buffer_window`), cancel windows (`cancel_into`/`cancel_after`), lunge, two-hand (×1.25 dmg / ×1.35 poise), weapon arts with cooldown, situational rolling/running attacks, riposte + backstab executions with i-frames, soft-lock facing snap (100° cone / 14 m), attack-speed scaling applied once into a copy of the attack dict |
| Stamina / poise / guard | `scripts/combat/{stamina,poise,guard}.gd` | Regen states (normal/blocking/suppressed), exhaustion, poise break + stagger duration, parry window 0.18 s with 0.4 s cooldown and 10 stamina cost, riposte window 1.4 s at ×2.0, 120° block arc, block cost `poise_damage × 0.55 / stability`, guard break on poise or stamina failure |
| Damage resolution | `scripts/combat/hurtbox.gd` | i-frames → evasion → immunity → arc (back ×1.6 dmg / ×2.0 poise) → parry → block → region mult → armour (soft curve, `points/(points+340)`, cap 0.75) → resistances → status damage-taken → poise-broken ×1.35 → accessibility scale. Emits `hurt_received`, dispatches `CombatEvents` |
| Enemy AI | `scripts/enemies/castle_enemy_base.gd` | 10-state machine, vision cone + hearing + awareness ramp + ally alerts, attack tokens (2 concurrent per group), roles from `EnemyBlackboard`, circling, committed wind-ups (`tracking_fraction` 0.55 then facing locks), combo follow-ups, `NavigationAgent3D` with avoidance, AI LOD (stride 1/4/16 by distance) |
| Boss phases | `scripts/bosses/boss_phase_controller.gd` | Fully data-driven from `content/bosses/*.json`: `hpBelow` thresholds, per-phase attack sets and modifiers, `onEnter` with tell duration, invulnerability, telegraph, VFX, SFX, music, shake, add spawns, hazard rings |
| Telegraphs | `scripts/art/vfx/vfx_service.gd:play_telegraph()` | Circle / ring / line / cone ground glyphs with a sweeping fill, class-tinted, plus a head-mounted wind-up meter (`ui/enemy_health_bar.gd`) |
| Colourblind system | `scripts/accessibility/accessibility_settings.gd` | Telegraph classes, damage numbers and status icons all remapped for protanopia / deuteranopia / tritanopia; plus assists (damage taken, i-frame generosity, lock-on range, telegraph emphasis) reported on the results screen |
| Floor graph generation | `scripts/dungeon/procgen/room_graph_generator.gd` | Critical path walk → branches → bounding-box fill → door assignment → **shortcut loops chosen by largest detour** → special room assignment → secrets → validation (connectivity, dead-end count, boss distance, min loops, no sealed rooms) |
| Lattice layout | `scripts/dungeon/procgen/room_graph_layout.gd` | Cell occupancy grid (CELL = 4.0), doors slide along shared walls, loop-aware placement scoring, 4 attempts + a straight-line fallback that cannot fail |
| Locks and keys | `room_lock_placer.gd`, `room_content_validator.gd`, `floor_keyring.gd` | 1–3 locks per floor, key rooms chosen from `reachable_without_edge` (a key can **never** sit behind its own lock), boss-reachability key-BFS validation, Doom-style red/blue/yellow keyring held as `WorldState` flags, never consumed, cleared on floor change |
| One-way shortcuts | `room_content_assigner.gd:_add_shortcut_gates()`, `room_shortcut_gate_content.gd` | Realised loop edges become barred gates that only open from the far (harder) side, and the far side always gets a guaranteed armoury chest |
| Room pacing | `content/progression/room_pacing.json` + `room_content_config.gd` | Shallow→deep weight interpolation, per-floor theme roll with multipliers, guarantees (≥1 reward room, ≥1 rest, a rest within 3 of the boss, max 2 consecutive combat rooms on the critical path) |
| Behavioural rules bus | `scripts/combat/combat_events.gd` | 14 events, 10 effects, per-rule cooldown / chance / conditions / stacking, wired to relics (per stack), unique items, affixes, class perks and talent keystones |
| Loot depth | `scripts/loot/`, `scripts/items/` | Affix prefixes/suffixes with group limits, quality/condition tiers, upgrade levels and paths, infusions, durability, and a forge that salvages, rerolls, transmutes, infuses and **transfers a rule between items** |
| Inventory | `scripts/inventory/`, `scripts/ui/inventory_ui.gd` | 10×6 Tetris grid, rarity frames, durability bars, `+N` upgrade badges, pointer **and** cursor input models, drag ghost, comparison tooltips vs equipped, stat panel, filters, search, quick-slot binds |
| HUD | `scripts/ui/combat_hud.gd` | HP (with a draining ghost trail) / SP / MP / PO / XP, status pips with timers, status build-up meters, keycard row, heal charges, quick slots, lock reticle (screen-clamped, tinted when occluded), parry/block bars, boss bar with phase pips, branch banner, objective marker, minimap + full-map overlay, region title, safe area, auto-hiding control hints |
| Meta layer | `scripts/meta/`, `scripts/quests/`, `scripts/progression/` | Vault content unlocks, achievements + toasts, mode unlocks, weekly challenge with local bests, run history (20 runs, bests, success rate), bestiary tiers at 1/10/25 kills, hub growth standing, 3 daily + 1 weekly bounties, 8 quest types, descent tokens, failure hotspots |
| Adaptive audio | `scripts/audio/audio_director.gd` | Four music layers (ambience/explore/combat/boss) mixed from a live intensity value (0.26 per engaged enemy, capped 0.72, +0.18 at low vitality), biome reverb presets, boss phase music, pooled 3D SFX |
| Art pipeline | `scripts/art/` | Voxel greedy meshing with per-theme palette snapping, procedural equipment models, first-person viewmodel with its own render pass, low-res pixel post stack, camera pixel snap, day/night with real sun/moon phases, weather, wind |
| Save | `scripts/save/` | 12 migration steps, validator, 5 backups, per-character files, quarantine-on-corrupt with a recovery prompt, cloud outbox |

### 1.2 The gaps this plan exists to close

Each is a verified fact traced through the code, not an impression.

0. **The player falls out of the world.** Four independent causes compound: the floor shell builds
   perimeter walls and **no ground plane**; height-transition stairs are placed on a wall chosen by
   the centre-delta guess the codebase already retired, at the wall's centre rather than under the
   door, and with the rise **inverted**; and `RoomTemplate.contains_world_point()` ignores Y, so the
   existing safe-spawn recovery can never fire. Every biome sets `maxHeightLevel` to 1 or 2, so this
   is reachable everywhere. Full trace and fixes: **§BG**.
1. **No enemy attack in the entire game declares its class.** `grep '"attackClass"' content/` returns
   nothing. `CastleEnemyBase._current_attack_class()` therefore guesses from poise damage against
   `Guard.DEFAULT_GUARD_BREAK_POISE` (26), and only ever returns `blockable` or `unblockable`. The
   `parryable` colour defined in `accessibility_settings.gd` is emitted by **no code path in the
   game**. → §EN
2. **"Unblockable" is a lie.** Nothing in `guard.gd` reads the attack class. An attack the game paints
   red can be blocked and parried exactly like any other. → `EN-02`
3. **Nothing in the game applies knockback.** `grep -rn "knockback\|impulse" --include=*.gd` returns
   zero hits. Hits deal damage, poise and a material flash; bodies never move. → §PH
4. **Animation is continuously interpolated.** `diorama_anim_library.gd:2132` sets
   `INTERPOLATION_LINEAR` + `UPDATE_CONTINUOUS` on every track, so voxel characters move like smooth
   3D rather than pixel animation. → `AN-01`
5. **The pixel UI is switched off for every player.** `pixel_diorama_settings.gd:RESOLUTION_PRESETS`
   holds exactly one entry, flagged `"native": true`, so `GameUISkin.is_native_hd_preset()` is always
   true and `is_pixel_ui()` is always false. `apply_pixel_theme()` therefore takes the HD branch and
   sets **linear** filtering on the whole UI, with rounded corners and drop shadows. Only the resource
   bars escape, because `style_progress_bar()` hardcodes nearest filtering. → `HD-03`
6. **Every room is an axis-aligned rectangle on a grid.** `RoomTemplateCatalog.KIND_SPECS` is 11
   width/depth pairs; `CastleBlockout` builds four straight walls with up to four cardinal doors. The
   floor definition record has no shape field at all. There is no circular room in the game. → §RM
7. **Waves mode gets a HUD but not *the* HUD.** `waves_run.gd:_build_combat_hud()` instantiates
   `combat_hud.tscn` and then never calls `configure_minimap`, `set_objective_world_position`,
   `bind_boss`, `show_region_title` or `set_branch_previews` — all of which `castle_run.gd` calls.
   `WavesRunService.is_boss_wave()` does spawn a boss every 10th wave, and that boss has no boss bar.
   Meanwhile `waves_run_ui.gd` anchors its own panel centre-top, where `BranchBanner`,
   `WarningBanner` and `RegionBanner` already live. → §HD
8. **Fifty-two of fifty-four enemies are a tint and a scale.** Only `castle_archer.gd` adds behaviour
   (kiting + a locked shot trajectory). `crystal_bat`, `crystal_shade` and `swamp_witch` are
   `extends castle_archer` plus a colour. Everything else is `_apply_mesh_tint()` and `scale`. → §EN
9. **Ranged combat is a straight line with gravity.** `Projectile` uses a fixed `ARC_LIFT_RATIO` of
   0.12 regardless of distance, so long shots undershoot; player arrows are parented to
   `tree.current_scene`; `CombatLayers.PROJECTILE` is defined and never used, so arrows cannot be
   blocked, shot down, or interact with anything but the world mask. There is no reticle, no aim
   mode, and no ammo decision. → §RG
10. **The talent tree is a stat list.** `content/talents/tree.json` is 10 branches × 5 nodes, and every
    node is a flat scalar (`physicalDamage +0.03`). No node changes a verb. → `IV-04`
11. **Floor generation succeeds 26.6 % of the time on the first attempt.** `local_procgen.gd` carries
    18 seed salts and its own comment records the measurement: a typical floor load spends ~0.2 s
    re-rolling and the worst case runs over a second. → `RM-12`
12. **The meta layer is complete and invisible.** Vault, bounties, weekly challenge, bestiary tiers,
    hub growth, descent tokens and run history all exist and all work; almost none of them are
    surfaced where the player makes a decision. → §AD
13. **The ten biomes generate the identical floor.** Every `content/biomes/*.json` carries the same
    `roomCount` (22–28), `loopBudget` (4), `fillBoundingBox`, `allow2x2Blocks`, `branchMaxDepth` (8)
    and the same ten room templates. The only generator value that differs between the Forgotten
    Castle and the Poison Swamp is `maxHeightLevel`. → `RM-13`
14. **The bestiary is eight fights in fifty-four costumes.** `enemy_type` takes five values across
    all 54 enemies; every enemy has 3 or 4 attacks; and the five late-biome "big melee" enemies are
    byte-for-byte the same profile (`melee`, `greatsword`, `move_speed 2.8`, four attacks) with
    different threat costs. → `EN-10`, `EN-11`

### 1.3 Claims in older documents that are now stale — do not act on them

- `docs/GAME_FEEL_REVIEW.md` §3.3 says the results screen is "four dashes in a box". It is not:
  `ui/results_screen.gd` now renders a rarity-framed loot row (best find last and larger), a run
  report with personal bests, relic procs, best hit, failure hotspots and vault unlocks, plus a
  focused "Descend again" button.
- The same document says gear has "zero behavioural effects". 54 content files now carry `rules`,
  and `AffixRoller.is_behavioural()` plus `InventoryService._sync_unique_rules()` wire them in.
- `docs/remaining_points.md` M-04 (secret edges pointing at rooms that do not exist) is fixed:
  `RoomGraphGeometry._placed_secret_ids()` only emits an edge for a secret the solver actually seated.
- `docs/CORE_GAMEPLAY_REVIEW.md` carries 244 `✅ FIXED` markers. Treat any unmarked item there as
  *possibly* still open and verify against the tree before acting.

---

## 2. Sequencing

Do the phases in order. Within a phase, items may be done in any order unless one carries a `→`.

| Phase | Items | Why here | Size |
|---|---|---|---|
| **P0 — Stop the bleeding** | `BG-01`…`BG-08` | The game drops the player out of the world on any floor with a height change, and every biome has them. Nothing else matters until this is closed. | M |
| **P1 — Make the fight readable** | `EN-01`…`EN-09`, `PH-01`…`PH-05`, `AN-01`…`AN-04`, `VS-08` | The combat *rules* are already right; the player cannot currently see them. Every later tuning question is answered through this. | XL |
| **P2 — Make the floor a place** | `RM-01`…`RM-22`, `VS-04` | Room shape and gating are what make exploring feel authored. Doing this after P1 means new rooms are judged with working feedback. | XL |
| **P3 — Make the three modes one game** | `HD-01`…`HD-10`, `MD-01`…`MD-07` | Consistency is cheap once the HUD has its final elements from P1. Doing it earlier means doing it twice. | L |
| **P4 — Make the build matter** | `EN-10`…`EN-12`, `CB-01`…`CB-08`, `RG-01`…`RG-04`, `IV-01`…`IV-05`, `BS-01`…`BS-08` | Build-crafting and ranged both need combat feedback to be legible before they can be judged. | L |
| **P5 — Make them come back** | `AD-01`…`AD-08`, `UX-01`…`UX-10` | The meta loop must be tuned against a game that is already fun for ten minutes. | M |
| **P6 — Polish and the long tail** | `AU-01`…`AU-04`, `AX-01`…`AX-04`, `VS-01`…`VS-09`, `SY-01`…`SY-12` | Additive; blocks nothing. §SY is the sweep that makes sure no system was left unexamined. | L |

**Minimum shippable MVP** if scope must be cut: **all of P0** (non-negotiable), all of P1,
`RM-01`, `RM-04`, `RM-05`, `RM-06`, `RM-07`, `RM-08`, `RM-13`, `RM-14`, `RM-16`, all of P3,
`EN-10`, `EN-12`, `CB-01`, `CB-03`, `CB-05`, `RG-01`, `RG-02`, `IV-01`, `AD-01`, `AD-05`, `AD-06`,
`AD-07`, `AU-01`, `SY-05`, `SY-07`, `SY-09`.

**If you can only do five things:** `BG-01`, `BG-02`, `EN-01`+`EN-02`, `PH-01`, `HD-03`. That is
"the player stays in the world, the telegraph tells the truth, hits move bodies, and the game looks
like pixel art" — the four sentences a player would use to describe what is wrong today.

---

## §BG — Blocking defects (Phase P0)

**Do these before anything else in this plan.** Each one is a shipped defect with a traced cause, not
a design improvement. `BG-01`…`BG-04` are four halves of the same bug: *the player falls through the
map*. `BG-05`…`BG-08` are correctness defects found while tracing it.

---

### The fall-through, diagnosed

The bug the owner reports is real and reproducible on any castle floor that rolls a height change.
Here is the full chain, traced through the code.

**Setup.** `content/biomes/forgotten_castle.json` sets `maxHeightLevel: 1`.
`RoomGraphGenerator._grow_critical_path()` promotes a room's `height_level` on every fourth path
room with a 35 % chance, and `_smooth_height_levels()` spreads it. `RoomGraphGeometry.HEIGHT_STEP` is
`3.0`, so an elevated room is built with its floor at **y = 3.0** while its neighbour sits at
**y = 0.0**.

**Fact 1 — the floor is per-room and nothing fills the space between levels.**
`CastleBlockout._build_floor()` builds one box of `room_width × 0.5 × room_depth` centred at
`y = -0.25`, so a room's walkable surface is exactly its own footprint at its own height. Under an
elevated room, from `y = 0` to `y = 3`, there is **nothing**.

**Fact 2 — there is no ground plane under the level.**
`FloorShellBuilder.build()` builds *four perimeter walls* and calls the ceiling-lighting pass. It
builds **no floor**. Read it: `_build_perimeter_walls()` is the only geometry it emits. So any hole
in the room tiling is a hole into the void, not a visible seam.

**Fact 3 — the connecting stairs are built on a wall chosen by the guess the codebase already
retired.** `DungeonBuilder._build_height_transitions()` calls
`lower_room.door_mask_toward(higher_room)`, which derives the wall from the **line between the two
room centres**. `DungeonBuilder.door_socket_between()` exists specifically because that guess is
wrong once doors slide along their wall — its own comment says so: *"two neighbours routinely sit
diagonally offset and the centre line points at a corner: the guess picks whichever of the two walls
is nearer, and half the time that is the wall the rooms do not share at all."* The height-transition
path never got the fix. On an offset pair, the stairs are built against a wall with no doorway in it.

**Fact 4 — even on the right wall, the flight is centred and inverted.**
`CastleBlockout._build_height_stairs()` places every step at the wall's **centre**
(`x = 0.0` for north/south, `z = 0.0` for east/west) and ignores `door_north_offset` and its
siblings entirely — so a door that slid 6 m along the wall has its stairs 6 m away. Worse, the rise
runs the wrong way: step `i` is at `-room_depth * 0.5 + i * 0.8` with height `step_height * (i + 0.5)`,
so the **lowest** step is at the wall and the **highest** is 4 m inside the room. To reach the
elevated doorway you must be at `y ≈ 3` *at the wall*, and the staircase puts you at `y = 0.25` there.

**Fact 5 — nothing detects or recovers a player who has left the world.**
`RoomTemplate.contains_world_point()` tests `absf(local.x) <= half_w and absf(local.z) <= half_d` and
**never looks at Y**. `castle_run.gd:_find_room_id_at()` therefore still reports a room for a player
falling at `y = -400`, so the existing safety net (`_teleport_to_safe_spawn`, which fires when
`_find_room_id_at()` returns `""`) can never trigger — and it only runs at spawn and restore anyway,
never during play.

**Result.** The player walks through a doorway at a height change, steps into the empty space beneath
the elevated room, finds no floor there and none under the level, falls forever, and no system
notices.

`BG-01` makes the fall impossible. `BG-02` makes the geometry correct. `BG-03` makes it recoverable
anyway. `BG-04` makes it detectable before it ships.

---

### BG-01 — Give the floor a floor — **S** — *do this first; it turns a fatal bug into a cosmetic one*

**Files:** `apps/game/client/scripts/dungeon/floor_shell_builder.gd`

**Problem.** `FloorShellBuilder` builds perimeter walls and no ground plane, so every gap in the room
tiling — from a height change, a pruned room, a mis-seated secret, or any future defect — drops the
player out of the world instead of onto something.

**Action.**
1. In `build()`, before the perimeter walls, add a **bedrock plane**: one `StaticBody3D` with a
   `BoxShape3D` spanning the full padded bounds, thickness 1.0, top surface at
   `min_room_y - BEDROCK_DROP` where `BEDROCK_DROP = 2.0` and `min_room_y` is the lowest room
   `transform.y` on the floor.
2. Skin it with the biome floor material darkened by 0.4 so a player who lands on it can see it is
   not a room.
3. Set `set_meta("surface", "stone")` and add it to a new group `"floor_bedrock"`.
4. Also build **skirt walls** under any room whose `heightLevel > 0`: a box around that room's
   footprint from the bedrock top to the room's floor, so the space beneath an elevated room is
   solid rather than a pit you can walk into sideways.

**Solution.** The bedrock must be **below** the lowest room, not level with it — level with it and it
becomes a walkable surface that competes with real floors and breaks `snap_to_floor_below`. Two
metres down is enough that a player who reaches it knows something went wrong, and close enough that
`PROBE_MAX_DROP` (6.0) in `CharacterFloorSnap` can still find it.

**Trap.** Do not give the bedrock a navigation mesh contribution. It is a safety net, not a floor:
`_setup_floor_nav_map()` bakes from the room blockouts, and adding bedrock to the nav map would let
enemies path across the void.

**Done when.** Deleting a room's floor by hand in the debugger leaves the player standing on dark
stone instead of falling.

---

### BG-02 — Build height transitions from the edge, at the door — **M**

**Files:** `apps/game/client/scripts/dungeon/dungeon_builder.gd`,
`apps/game/client/scripts/dungeon/castle/castle_blockout.gd`

**Problem.** Facts 3 and 4 above: `_build_height_transitions()` picks the wall with the retired
centre-delta guess, and `_build_height_stairs()` centres the flight on the wall and runs it the wrong
way.

**Action.**
1. In `_build_height_transitions()`, replace `lower_room.door_mask_toward(higher_room)` with
   `_socket_for_edge(lower_room, higher_room, edge)` — the edge is already in scope in that loop —
   and derive the direction from `socket.direction`. Pass the socket's **lateral offset** through as
   well (`_door_lateral(lower_room, socket, edge)`).
2. Change `add_height_stairs(step_count, direction, step_height)` to
   `add_height_stairs(step_count, direction, step_height, lateral)` (default 0.0 so nothing else
   breaks) and store `lateral` in the pending record.
3. In `_build_height_stairs()`, offset the flight along the wall by `lateral`, and **invert the
   run**: the top step must be flush against the wall. For a north wall:
   `z = -room_depth * 0.5 + (step_count - 1 - i) * step_depth`, height `step_height * (i + 0.5)`.
4. Widen each step to `CastleRoomConstants.DOOR_WIDTH + 1.0` rather than `room_width * 0.4`, so the
   flight is the width of the doorway it serves rather than a fraction of an unrelated dimension.
5. Add a landing: one extra step-depth of flat floor at full height, flush with the wall, so the
   player arrives level rather than mid-step.

**Solution.** The invariant to write in a comment: **the top of the flight is level with the
neighbouring room's floor and sits directly under its doorway.** Both halves matter — the height and
the lateral position — and the second one is what the current code has no concept of at all.

**Trap.** `_build_height_stairs()` calls `_add_wall_segment()`, which parents into the walls body.
That is fine for collision but means the steps inherit `wall_material`. Give them `floor_material`
instead, or the stairs read as a wall lying on the ground.

**Done when.** On a floor with a height change, walking through the doorway from either side is a
smooth climb, and `res://scenes/debug/floor_connectivity_audit.tscn -- --seeds=32` reports every room
reachable.

---

### BG-03 — Detect and recover an out-of-world player — **S**

**Files:** `apps/game/client/scripts/dungeon/room_template.gd`,
`apps/game/client/scripts/dungeon/castle_run.gd`,
`apps/game/client/scripts/dungeon/waves_run.gd`

**Problem.** Fact 5: `contains_world_point()` ignores Y, so nothing can tell that the player has left
the level, and the recovery that exists only runs at spawn and restore.

**Action.**
1. Add a Y band to `contains_world_point()`: the point must also be within
   `[room.position.y - 4.0, room.position.y + WALL_HEIGHT + 4.0]`. Keep the X/Z test a rectangle even
   for round rooms (see `RM-01`).
2. In `castle_run.gd:_physics_process()`, where `_find_room_id_at()` is already called every frame,
   add: if the result is `""` **and** the player is below `lowest_room_y - 8.0`, call
   `_teleport_to_safe_spawn({"playerRoomId": player_room_id})`, deal `PIT_DAMAGE` (10 % of max
   health), and `RunFlow.emit_run_warning(tr("WARN_FELL"))`.
3. Do the same in `waves_run.gd` against the arena floor plane.
4. Never kill the player for it. A fall out of the world is the game's fault.

**Solution.** Reuse `_teleport_to_safe_spawn()` exactly as it is — it already prefers the last known
room and falls back to the entrance, and it already calls `snap_to_floor_below`. The only new thing
is the trigger.

**Trap.** Do not gate this on a timer or a velocity check. The condition is positional and must hold
even if the player is somehow stationary in the void.

**Done when.** Teleporting the player to `y = -500` in the debug console returns them to the last room
with a scratch of damage and a warning, within one physics frame.

---

### BG-04 — Make the audits catch geometry holes — **M** — `→ BG-01`, `BG-02`

**Files:** `apps/game/client/scripts/tools/floor_connectivity_audit.gd`,
`apps/game/client/scripts/dungeon/dungeon_builder.gd`

**Problem.** `floor_connectivity_audit.gd` reasons about the **definition** — rooms, edges, distances.
It never builds the floor, so it cannot see a hole in the geometry. And
`DungeonBuilder._verify_doorway_alignment()` is explicitly "purely a tripwire — it builds nothing":
it `push_error`s a footprint mismatch and lets the floor ship anyway.

**Action.**
1. Add a **walkability sweep** to the audit: build the floor for real (the audit can instantiate
   `DungeonBuilder` headlessly), then for each room cast a downward ray from
   `room_centre + Vector3(0, 2, 0)` and from the four points 1 m inside each doorway. Any ray that
   finds no collider within 6 m is a hole — report the room, the doorway and the seed.
2. Add a **doorway continuity check**: for every non-secret edge, sample five points across the
   threshold at 0.5 m intervals and confirm each has floor within 0.5 m of the expected height. A
   height change must show a monotonic staircase, not a cliff.
3. Escalate `_verify_doorway_alignment()` from `push_error` to a build abort in debug builds
   (`OS.is_debug_build()`), so a footprint mismatch is impossible to miss during development, while
   release builds still limp rather than crash.

**Solution.** This is the check that would have caught the reported bug before it was reported. Put
the ray sweep behind the same `--seeds=N` argument the audit already parses, and print a per-biome
hole count so a regression is one line of output.

**Done when.** `res://scenes/debug/floor_connectivity_audit.tscn -- --seeds=32` reports `0 holes` and
`0 cliffs` across all ten biomes, and deliberately breaking `_build_height_stairs` makes it fail.

---

### BG-05 — Room tracking is O(rooms) every physics frame — **S**

**Files:** `apps/game/client/scripts/dungeon/castle_run.gd`

**Problem.** `_find_room_id_at()` loops every room on the floor calling `contains_world_point()` —
which does a `to_local()` transform each time — and `_physics_process()` calls it **every frame**. On
a 28-room floor that is 28 transforms and 28 rectangle tests per tick, forever, to answer a question
whose answer changes a few times a minute.

**Action.** Check the current room first (the player is almost always still in it), then its graph
neighbours from the definition's edges, and only then fall back to the full scan. Cache the neighbour
list per room id at floor load.

**Solution.** This becomes load-bearing after `BG-03` adds a Y test to the same call. Do it in the
same pass.

**Done when.** `res://scenes/debug/perf_audit.tscn` shows the castle run scene's per-frame script
cost measurably lower, and room transitions still fire correctly.

---

### BG-06 — Mana regenerates through combat — **S**

**Files:** `apps/game/client/scripts/combat/mana.gd`

**Problem.** `Stamina` has a `RegenState` (normal / blocking / suppressed) and a `REGEN_DELAY` that
`WeaponController` drives on every attack. `Mana` has neither: `_physics_process()` regenerates
unconditionally after a flat 0.7 s delay, with no suppression while attacking. A caster therefore has
no resource tension, which makes `CB-07` and the `staff` archetype unbalanceable.

**Action.** Mirror `Stamina`'s API exactly: add `RegenState`, `set_regen_state()`, and have
`WeaponController` suppress mana regen for the duration of an attack the same way it already
suppresses stamina in `_start_attack()` / `_end_attack()`.

**Done when.** Mana behaves like stamina under sustained attacking.

---

### BG-07 — `ShieldHurtbox` ignores damage type — **S**

**Files:** `apps/game/client/scripts/combat/shield_hurtbox.gd`

**Problem.** `ShieldHurtbox.receive_hit()` applies a flat `block_mitigation` (0.75 by default) to
**every** damage type, while the player's own `Guard._reduction_for()` distinguishes physical (0.55)
from elemental (0.35). A fire build is therefore no better than a physical build against a shield
enemy, which removes the entire reason to carry an infusion.

**Action.** Give `ShieldHurtbox` the same per-type table `Guard` uses, read from the enemy definition
(`"block_reduction"` as a dictionary or a flat number, exactly the shape `Guard._parse_block_reduction`
already accepts).

**Done when.** Infusing a weapon with fire measurably improves damage against `castle_shield`.

---

### BG-08 — Dead code that will mislead the next reader — **S**

**Files:** `apps/game/client/scripts/combat/guard.gd`,
`apps/game/client/scripts/player/player_anim_director.gd`

**Problem.** `Guard._is_frontal_hit()` is never called by `Guard` — `modify_incoming_hit()` and
`try_parry_attack()` both use `arc` from `DamageInfo.classify_arc()`. It survives only because
`PlayerAnimDirector._is_frontal_hit()` reaches across and calls it by name through
`_guard.call("_is_frontal_hit", direction)`, which is a private call across a module boundary and
uses a 55° half-angle where `Guard`'s own `BLOCK_ARC_DEGREES` is 120° (60° half-angle). So the
animation and the mechanics disagree about what "frontal" means.

**Action.** Make it public as `Guard.is_frontal_hit(direction)`, implement it once against
`BLOCK_ARC_DEGREES`, and have the anim director call the public method. Delete the director's own
copy.

**Done when.** Blocking and the block-impact animation agree on the same arc.

---

## §EN — Enemy intent and readability

The soulslike contract is *the enemy tells you what it is about to do, and you answer*. Every piece
of that machinery exists here except the part that says **which** answer is correct.

---

### EN-01 — Author an attack class on every enemy attack — **S** — *do this first, everything in §EN depends on it*

**Files:** `content/enemies/*.json` (54), `content/bosses/*.json` (16),
`content/schemas/enemy.*.json`, `apps/game/client/scripts/enemies/castle_enemy_base.gd`,
`apps/game/client/scripts/tools/definition_health.gd`

**Problem.** No attack anywhere declares `attackClass`. `CastleEnemyBase._current_attack_class()`
falls back to `poise >= Guard.DEFAULT_GUARD_BREAK_POISE (26.0) ? "unblockable" : "blockable"`. Every
enemy in the bestiary therefore telegraphs in one of two colours, chosen by a number the designer set
for a different reason, and the third colour the accessibility system defines (`parryable`, blue)
never appears in the game.

**Action.**
1. Define exactly four classes and write them into the enemy schema as an enum on each attack entry:
   `blockable`, `parryable`, `unblockable`, `grab`.
2. Add `"attackClass"` to every attack entry in all 54 `content/enemies/*.json` and all 16
   `content/bosses/*.json`. Use the assignment rule below — do not guess per file.
3. Delete the poise-derived fallback in `_current_attack_class()` and replace it with: read
   `attackClass` from the attack entry, then from the enemy root, then default `"blockable"` **and
   `push_warning` once per enemy id** so a missing one is loud rather than silent.
4. Add a check to `scripts/tools/definition_health.gd` that walks every enemy and boss definition and
   fails if any attack entry lacks `attackClass`.

**Solution.** The assignment rule, applied mechanically so the bestiary reads consistently:

- `parryable` — a single committed melee swing with `windup_duration >= 0.45` and
  `attack_poise_damage < 26`. This is the enemy's "answer me" attack. Roughly the most common class;
  aim for ~45 % of all melee entries.
- `blockable` — fast pokes (`windup_duration < 0.45`), and every ranged/projectile attack.
- `unblockable` — anything with `attack_poise_damage >= 26`, plus any attack whose `telegraph_shape`
  is `cone` or `ring` (area attacks read as "get out", not "hold shield"). ~20 %.
- `grab` — new class. Reserve for boss attacks you also give `"grabbing": true` (see `EN-05`). Zero
  today; add one to each of the ten floor bosses in a later pass, not now.

Keep the ratio deliberate: if everything is `unblockable` the shield is dead, and if everything is
`parryable` the parry stops being a read. The wind-up threshold of 0.45 s is chosen because
`Guard.PARRY_WINDOW` is 0.18 s and `PARRY_COOLDOWN` is 0.4 s — an attack faster than that cannot be
answered by a player reacting to the tell.

**Trap.** `combo_followups` entries are nested attack dictionaries and are read through the same
`_current_attack_data`. They need `attackClass` too. A grep for `"windup_duration"` finds 379
entries across the content tree; that is the number of classes you must author, not 70.

**Done when.** `grep -L '"attackClass"' content/enemies/*.json content/bosses/*.json` prints nothing,
`res://scenes/debug/definition_health.tscn` reports 0 failures, and walking into a fight shows amber,
blue and red telegraph rings in the same room.

---

### EN-02 — Make the attack class mechanically real — **M** — `→ EN-01`

**Files:** `apps/game/client/scripts/combat/damage_info.gd`,
`apps/game/client/scripts/combat/hitbox.gd`, `apps/game/client/scripts/combat/guard.gd`,
`apps/game/client/scripts/combat/hurtbox.gd`, `apps/game/client/scripts/enemies/castle_enemy_base.gd`

**Problem.** The class is presentation only. `guard.gd:modify_incoming_hit()` and
`try_parry_attack()` never see it, so a red "unblockable" telegraph is blocked and parried exactly
like an amber one. The telegraph is a lie, which is worse than having no telegraph: it teaches the
player that colour does not matter.

**Action.**
1. Add `var attack_class: String = "blockable"` to `DamageInfo` and set it in `DamageInfo.create()`
   from a new parameter (default `"blockable"` so existing call sites keep compiling).
2. Add `_attack_class` to `Hitbox`, set through `set_attack_values()` (append the parameter; do not
   reorder the existing ones), and pass it into `DamageInfo.create()` in `_try_hit()`.
3. In `CastleEnemyBase._start_attack()` pass `_current_attack_class()` into `set_attack_values`.
4. In `Guard.modify_incoming_hit()`: if `info.attack_class == "unblockable"`, skip the block path
   entirely and return `{"amount": info.amount, "poise": info.poise_damage, "blocked": false}` — but
   **first** call a new `_trigger_guard_break()` only when the guard was actually raised, so the
   player is punished for holding shield into a red attack rather than merely ignored.
5. In `Guard.try_parry_attack()`: reject `unblockable` and `grab` outright. For `parryable`, widen the
   window by a per-class multiplier (see below).
6. In `Hurtbox.receive_hit()`, when `info.attack_class == "grab"`, bypass poise entirely and call a
   new `apply_grab()` on the victim's `PlayerCombatReactions` (a fixed-duration lock, no i-frames,
   damage applied at the end).

**Solution.** Put the windows in `content/combat/dodge.json`'s sibling — create
`content/combat/guard.json` *(new)* with:

```
{ "parry_window": 0.18,
  "parry_window_by_class": { "parryable": 1.35, "blockable": 1.0 },
  "block_reduction": { "physical": 0.55, "default": 0.35 },
  "guard_break_on_unblockable": true,
  "grab_duration": 1.6 }
```

`Guard` reads it in `_ready()` with the current constants as the fallback dictionary, exactly the way
`Dodge._load_tuning()` already does. The 1.35× multiplier on `parryable` (0.18 → 0.243 s) is the
whole design: the blue attack is the one the game *wants* you to parry, and it is generous enough
that a player who reads the colour succeeds.

**Trap.** `ShieldHurtbox.receive_hit()` applies a flat `block_mitigation` before calling `super`. It
must also honour the class or shield enemies will absorb unblockables. Add the same early-out there.

**Done when.** Holding block into a red telegraph breaks your guard and staggers you; parrying a blue
telegraph is noticeably easier than parrying an amber one; parrying a red one does nothing.

---

### EN-03 — Derive the telegraph from the attack's real reach — **M** — `→ EN-01`

**Files:** `apps/game/client/scripts/enemies/castle_enemy_base.gd`,
`apps/game/client/scripts/art/vfx/vfx_service.gd`, `content/enemies/*.json`

**Problem.** `_show_attack_telegraph()` reads `telegraph_radius` straight from content, which is
authored independently of `max_range` and of the hitbox that will actually open. The ring on the
ground can be smaller or larger than the attack, so a player who learns to trust the ring is
punished for it. Content shows this directly: `glacial_warden`'s `cleave` has `max_range: 3.3` and
`telegraph_radius: 3.0`.

**Action.**
1. Make `telegraph_radius` **optional**. When absent, derive it: `max_range` for `circle`/`ring`, and
   `max_range * 1.05` for `cone`/`line` (a cone's tip should slightly overshoot so the player can see
   the edge before they are in it).
2. Add `telegraph_arc_deg` (default 90 for `cone`) and honour it in
   `VfxService._telegraph_cone()`.
3. Strip `telegraph_radius` from any content entry where it differs from the derived value by less
   than 15 %; keep it only where a designer deliberately wants the tell bigger than the hit.
4. Add a check to `scripts/tools/definition_health.gd`: warn when `telegraph_radius` is more than
   25 % smaller than `max_range` (a tell that under-promises is a trap, not a tell).

**Solution.** The invariant to hold, and to write in a comment above the derivation: **the telegraph
must never be smaller than the attack.** A larger tell is a design choice; a smaller one is a bug the
player experiences as unfairness. Do not clamp the derived radius — a boss with a 12 m sweep should
draw a 12 m ring.

**Done when.** Standing just outside a drawn ring never takes the hit, on every attack of every
enemy, for ten minutes of play.

---

### EN-04 — A pixel intent glyph above the enemy's head — **L** — `→ EN-01`

**Files:** `apps/game/client/scripts/ui/enemy_intent_glyph.gd` *(new)*,
`content/ui/intent_atlas.json` *(new)*, `apps/game/client/assets/ui/intent_icons.png` *(new)*,
`apps/game/client/scripts/ui/enemy_health_bar.gd`,
`apps/game/client/scripts/enemies/castle_enemy_base.gd`

**Problem.** The only in-world statement of intent is a coloured bar and a coloured ring. Colour alone
is a weak channel (and the reason `accessibility_settings.gd` has to remap it three ways). The player
learns "red is bad" but never "this is the sweep, roll left".

**Action.**
1. Author a 4-cell 16×16 pixel icon sheet: `sword` (blockable), `shield_break` (unblockable),
   `parry_star` (parryable), `hand` (grab). Same visual grammar as
   `assets/ui/minimap_icons.png` (8 px cells) — hard edges, two-value shading, one accent colour.
2. Write `content/ui/intent_atlas.json` *(new)* in the exact shape of `content/ui/hud_atlas.json`
   (`{"texture": "...", "<cell>": {"x":..,"y":..,"w":..,"h":..}}`) and a loader modelled on
   `scripts/ui/hud_icon_atlas.gd`.
3. In `EnemyHealthBar`, add a fourth `Sprite3D` above the attack bar (`ATTACK_BAR_OFFSET_PIXELS` is
   -4; put the glyph at -12) using the same `_make_bar_sprite()` helper so it inherits
   `BILLBOARD_FIXED_Y`, nearest filtering and render priority.
4. Show it in `begin_attack_telegraph()`, hide it in `hide_attack_telegraph()`. Pop it in with a
   1-frame scale overshoot (0.6 → 1.15 → 1.0 over 0.09 s) so it *arrives* rather than appears.

**Solution.** Use `PixelStyle.configure_pixel_sprite()` and `PixelStyle.WORLD_PIXEL` for sizing — the
health bar already does, and matching it is what keeps the glyph on the same pixel grid as everything
else. Tint the glyph with `AccessibilitySettings.get_telegraph_class_color(attack_class)` so shape
**and** colour carry the message; that is the whole point of adding shape.

**Trap.** `Sprite3D` quads write no depth. `EnemyHealthBar` handles this with explicit
`render_priority` (`BAR_PRIORITY_BG` 0, `BAR_PRIORITY_FILL` 1). Give the glyph priority 2 or it will
composite under the bar it sits above.

**Done when.** Every wind-up in the game shows a shape as well as a colour, the shape is legible at
15 m, and turning on `colorblind_mode` changes the colour but not the shape.

---

### EN-05 — Feints and delayed attacks — **M** — `→ EN-01`

**Files:** `apps/game/client/scripts/enemies/castle_enemy_base.gd`, `content/bosses/*.json`,
`content/schemas/enemy.*.json`

**Problem.** Every wind-up in the game is honest and constant-rate. `windup_variance` jitters the
duration but the telegraph fills linearly to match, so a player can dodge on the ring rather than on
the enemy. There is no attack that punishes a panic roll, which means there is no reason ever to
wait.

**Action.**
1. Add two optional attack fields: `"hold_fraction"` (0.0–0.6, default 0) and `"feint_chance"`
   (0.0–0.4, default 0).
2. In `_enter_windup()`, if `hold_fraction > 0`, split the wind-up: run to
   `(1 - hold_fraction) * duration`, then **freeze** the telegraph fill and the animation
   (`_animator.set_speed_scale(0.0)`) for `hold_fraction * duration`, then release.
3. If `feint_chance` rolls true on `_enemy_rng`, cancel at the hold point: hide the telegraph, play a
   short recovery, and set `_cooldown` to a *shorter* value than normal so the real attack follows
   quickly.
4. Author `hold_fraction` on exactly one attack per floor boss and on no basic enemy.

**Solution.** The telegraph must visibly *stop*, not slow down —
`EnemyHealthBar.set_attack_telegraph_progress()` is already driven from `castle_enemy_base` each tick,
so simply stop advancing `elapsed` during the hold. A held tell that keeps creeping reads as lag; a
tell that stops dead reads as a decision the enemy made.

**Trap.** `_windup_commit_ratio()` drives facing lock via `tracking_fraction`. Commit **before** the
hold begins, not after, or a held attack tracks the player through the entire hold and the feint
becomes unavoidable.

**Done when.** One boss attack makes an experienced player roll early and get hit, and rolling late
works.

---

### EN-06 — Directional hit reactions — **S**

**Files:** `apps/game/client/scripts/enemies/castle_enemy_base.gd`,
`apps/game/client/scripts/art/characters/diorama_anim_controller.gd`

**Problem.** `CastleEnemyBase._on_hurt()` calls `_animator.play_flinch()` with **no arguments**, so
every enemy in the game flinches the same way regardless of where it was hit — despite
`DioramaAnimController.play_flinch(direction)` already selecting from four directional clips via
`_flinch_clip_for()`, and despite `info.direction` being right there in the same function.

**Action.** Pass `info.direction` into `play_flinch()`. Then do the same audit on
`apply_stagger()`, which calls `_animator.play_stagger(duration)` without the direction argument the
controller accepts.

**Solution.** One-line changes. `_last_hit_direction` is already assigned at the top of `_on_hurt()`;
use that so a stagger triggered later by poise break still knows which way the last hit came from,
exactly as `PlayerCombatReactions._on_poise_broken()` already does for the player.

**Done when.** Backstabbing an enemy makes it lurch forward; hitting it from the left makes it lurch
right.

---

### EN-07 — Give enemies defensive verbs — **L** — `→ EN-01`

**Files:** `apps/game/client/scripts/enemies/castle_enemy_base.gd`,
`apps/game/client/scripts/enemies/enemy_blackboard.gd`, `content/enemies/*.json`

**Problem.** The enemy state machine has ten states and not one of them is defensive: `PATROL`,
`CHASE`, `INVESTIGATE`, `RETREAT`, `CIRCLE`, `WINDUP`, `ATTACK`, `RECOVERY`, `STAGGER`, `DEAD`. An
enemy cannot block, cannot step back, cannot punish a whiff. Combat is therefore one-directional: the
player reads the enemy and the enemy never reads the player. `castle_shield` carries
`block_mitigation` in its data and only ever uses it passively through `ShieldHurtbox`.

**Action.**
1. Add three states: `GUARD`, `SIDESTEP`, `PUNISH`.
2. Add per-enemy data: `"guard_chance"`, `"sidestep_chance"`, `"punish_window"` (default all 0, so
   every existing enemy is unchanged until authored).
3. In `_process_chase()` and `_process_circle()`, before `_can_attack()`, roll `guard_chance` when
   the player is inside `_engage_range` and the player's `WeaponController.is_attacking` is true and
   its `current_phase` is `STARTUP` — enter `GUARD` for the duration of the player's startup + active.
4. `GUARD`: zero velocity, `_animator.set_blocking(true)`, and route incoming damage through the
   existing `ShieldHurtbox` mitigation by setting a `_guarding` flag the hurtbox reads.
5. `SIDESTEP`: a 0.35 s lateral dash along `_circle_direction` with a short i-frame window, rolled
   when the player begins an attack at range.
6. `PUNISH`: when the player's attack ends in `RECOVERY` within `punish_window` seconds, skip the
   attack cooldown and go straight to `_start_windup()` with the fastest attack in `_attacks`.
7. Author values only on `castle_shield`, `frost_knight`, `iron_sentinel`, `cathedral_warden`,
   `crystal_guardian` and the ten floor bosses. Leave grunts and beasts at 0.

**Solution.** Gate all three behind the attack token (`AttackTokenService`) the same way attacks are,
or a room of six enemies will all sidestep at once and read as a dance troupe. The correct feel: the
*one* enemy currently holding a token is the one that reacts; the rest keep circling.

**Trap.** `_is_action_blocked()` on the player side does not know about enemy states, and it should
not. Do not add player-side coupling; the enemy reads the player's public `WeaponController` state,
never the other way round.

**Done when.** A shield enemy raises its shield when you swing at it from the front, and an
over-committed heavy swing gets punished by a knight.

---

### EN-08 — Real flanking from the blackboard — **M**

**Files:** `apps/game/client/scripts/enemies/enemy_blackboard.gd`,
`apps/game/client/scripts/enemies/castle_enemy_base.gd`

**Problem.** `EnemyBlackboard._assign_roles()` assigns `ENGAGER` / `FLANKER` / `WAITER` **by
insertion order into the `engaged` array**. A "flanker" therefore does not flank; it stands
`FLANKER_RADIUS_MULT` (1.15) further away in whatever direction it happened to arrive from. The
group AI reads as a queue rather than a pack.

**Action.**
1. In `_assign_roles()`, sort the engaged list by the angle between each member's position and the
   player's facing direction (obtain it from the player once per assignment, not per member).
2. Assign `ENGAGER` to the two members nearest the player's front arc, and `FLANKER` to the two
   nearest the ±90° arcs. Everything else is `WAITER`.
3. Give each flanker a target *angle* rather than a radius multiplier: store
   `desired_angle_deg` on the enemy (±100° from the player's facing) and have
   `_process_circle()` steer toward that bearing instead of just orbiting.
4. Re-run the assignment on a timer (every 1.5 s) rather than only on membership change, so roles
   follow the player as they turn.

**Solution.** Reuse the existing cached room bounds in `_room_bounds()` so this stays cheap. The
assignment already runs off a shared record; adding an angle sort is a handful of comparisons on a
list that is at most six long.

**Trap.** Do **not** make waiters walk toward the player. The waiter's job is to be visible and
threatening at a distance; a pack that all closes at once removes the space the combat model needs.

**Done when.** Fighting three grunts, one is in front of you and one is always trying to get behind
you, and turning to face the flanker makes the roles swap within two seconds.

---

### EN-09 — Off-screen danger indicator — **S** — `→ EN-01`

**Files:** `apps/game/client/scripts/ui/combat_hud.gd`,
`apps/game/client/scripts/enemies/castle_enemy_base.gd`

**Problem.** An archer behind the player winds up, fires and hits, with no on-screen information at
any point. The HUD already solves this exact problem for the objective marker
(`_update_objective_marker()` clamps an off-screen world point to a screen-edge arrow) and for the
lock reticle — the pattern exists and is not used for threats.

**Action.**
1. Have `CastleEnemyBase` emit its existing `attack_telegraph_started(attack_class)` signal onto a
   HUD-visible path: register the enemy in a `"telegraphing"` group on wind-up and remove it on
   attack/cancel.
2. In `combat_hud.gd`, in the existing `SLOW_UPDATE_INTERVAL` (0.1 s) tick, walk that group, project
   each to screen space, and for any that is behind the camera or outside the viewport, draw a small
   class-tinted chevron clamped to the screen edge — reuse `_update_objective_marker()`'s clamping
   maths verbatim.
3. Cap it at three chevrons; sort by distance ascending.

**Solution.** Do not add a new per-frame process. The HUD already has a slow tick precisely for this
class of work, and a 0.1 s update is imperceptible for a wind-up that lasts 0.4–1.5 s.

**Done when.** Turning your back on an archer shows a chevron on the edge of the screen a beat before
the arrow arrives.

---

### EN-10 — Enemy diversity: the roster is eight fights wearing fifty-four costumes — **XL**

**Files:** `content/enemies/*.json` (54), `apps/game/client/scripts/enemies/*.gd`,
`apps/game/client/scripts/enemies/castle_enemy_base.gd`, `content/biomes/*.json`

**Problem — three layers, all verified.**

*Layer 1, the scripts.* Of 54 catalogued enemies, exactly **one** has behaviour of its own:
`castle_archer.gd` (kites, and locks its shot trajectory until the wind-up commits).
`crystal_bat.gd`, `crystal_shade.gd` and `swamp_witch.gd` are `extends castle_archer` plus a colour.
Every remaining shell is `_apply_mesh_tint()` and a `scale` line. `boss_cathedral_hollow.gd`,
`boss_frost_warlord.gd` and `miniboss_cathedral_bell.gd` are empty classes that exist only to carry
an id and a signal.

*Layer 2, the data.* `enemy_type` takes exactly five values across the whole bestiary: `melee` (27),
`ranged` (15), `shield` (3), `boss` (6), and one untyped training dummy. Every enemy has three or
four attacks. There is no `enemy_type` for a flyer, a swarm, a summoner, a burrower or a caster.

*Layer 3, the rosters.* The biomes are structural clones of each other. Line up the "big melee" of
each late biome — `glacial_cairn_golem`, `iron_bellows_golem`, `prism_facet_golem`,
`umbral_reliquary_golem`, `venom_bloat_brute` — and every one is `melee`, `greatsword`,
`move_speed 2.8`, four attacks. The staff casters are all `move_speed 3.1`. The spear mids are all
`3.5`. The five late biomes are the five early enemies with the numbers multiplied.

The consequence: a player who has cleared the Forgotten Castle has seen every fight the game has.
Ten biomes of content, one bestiary.

**Action — three passes, in this order.**

**Pass 1 — five behaviour mixins in the base class (code, ~1 session).**
Do **not** write 50 AI scripts. Add five optional data-driven behaviours to `CastleEnemyBase`, each
guarded by `if _data.has(...)` so an enemy without the key pays nothing:

| Key | Shape | Reuses |
|---|---|---|
| `"leaps"` | `{range, windup, distance, cooldown}` — a committed gap-closer with its own telegraph | `_enter_windup` + `_apply_attack_lunge` |
| `"burrows"` | `{cooldown, reappear_behind}` — vanish, reposition, re-emerge with a telegraph | `_finalize_death`'s dissolve, in reverse |
| `"splits"` | `{enemyId, count, health_fraction}` — on death, spawn smaller copies | `spawn_adds()` (already used by boss phases) |
| `"summons"` | `{enemyId, count, cooldown, max_alive}` | `spawn_adds()` |
| `"aura"` | `{statusId, radius, interval, build_up}` — pressures the player just by being near | `StatusController.add_build_up()` |

**Pass 2 — three new `enemy_type` values (code + data).**
`enemy_type` drives `CharacterSkin.profile_for_enemy_data()` and the animation profile, so adding a
type adds a silhouette as well as a behaviour. Add:
- `flyer` — ignores ground nav, hovers at `hover_height`, strafes, dives to attack. Give it a simple
  height-holding steering term instead of a `NavigationAgent3D`.
- `swarm` — low health, high count, no attack token requirement (they are *meant* to all come at
  once), dies in one hit from most weapons.
- `caster` — never closes; channels a telegraphed area attack from range and must be interrupted or
  walked out of.

**Pass 3 — assign one identity per enemy (content, the bulk of the work).**
Every enemy gets **exactly one** mixin or new type, chosen so that each biome's roster contains five
*different* answers rather than five stat blocks. Use this assignment:

| Role in a roster | Identity | Examples |
|---|---|---|
| The fast one | `leaps` | `castle_hound`, `frost_hound`, `cathedral_shade`, `umbral_cowl`, `prism_shardling` |
| The many | `swarm` type + `splits` | `swamp_swarm`, `crystal_slime`, `venom_drifter`, `swamp_leech` |
| The big one | `aura` (a slow/pressure field) | the five golems, `swamp_toad`, `venom_bloat_brute` |
| The support | `summons` | `swamp_hag`, `umbral_censer`, `venom_censer`, `cathedral_acolyte` |
| The ambusher | `burrows` | `crystal_crawler`, `iron_needle`, `swamp_bogling` |
| The zoner | `caster` type | `crystal_wisp`, `prism_lantern`, `prism_refractor`, `glacial_keener` |
| The wall | `shield` + `EN-07` guard verbs | `castle_shield`, `iron_sentinel`, `glacial_hollowed` |
| The flyer | `flyer` type | `crystal_bat`, and one new flyer per late biome |

Then **break the numeric cloning**: the five golems must not all be `move_speed 2.8` with four
attacks. Give each a different profile — one slow and unblockable, one that charges, one that
summons, one with an aura, one that splits.

**Solution.** The measure of success is not variety for its own sake: it is that a player can look at
a silhouette and know what it will do. One verb per enemy, consistently applied, beats five verbs
applied randomly. Keep the mixin count at five and the new type count at three for the MVP; a sixth
of either is a post-launch decision.

**Trap 1.** `spawn_adds()` parents new enemies to `get_parent()` — the room. That is correct and
load-bearing: room culling, `EnemyBlackboard.room_key()` and the builder's enemy tracking all depend
on it. Never parent a spawned enemy to its spawner.

**Trap 2.** `swarm` enemies must be exempted from `AttackTokenService`, and `splits` must cap total
population — set `max_alive` and check it in `spawn_adds`, or a room of splitting slimes becomes a
frame-rate bug.

**Trap 3.** `ProcgenPlacements._enemy_threat_cost()` reads `threat_cost` to spend the room budget.
A summoner or a splitter is worth far more than its stat block; raise those `threat_cost` values or
a single room will field six of them.

**Done when.** Loading `res://scenes/combat/combat_arena.tscn` with each biome's pool in turn shows
five visibly different fight patterns per biome, and the five late-biome golems play differently from
each other.

---

### EN-11 — Give each biome a roster shape, not a stat rescale — **M** — `→ EN-10`

**Files:** `content/biomes/*.json`, `content/enemies/*.json`

**Problem.** Every biome's `enemyPool` is the same five roles with different weights. Combined with
`EN-10`'s layer 3, the late game is the early game with bigger numbers — which is also why
`docs/remaining_points.md` records the balance tool flagging `endgame_soft_for_maxed_build`.

**Action.** Give each biome a **composition rule** rather than a flat weighted list:
`{"melee": 0.5, "ranged": 0.3, "support": 0.2}` per biome, and have
`ProcgenPlacements._attempt_place_enemy()` respect the target mix per room rather than rolling each
slot independently. Then differentiate:

- forgotten_castle — melee-heavy, one archer; teaches the basics
- frozen_fortress — shields and spears; teaches poise and spacing
- poison_swamp — swarms and status; teaches build-up meters
- crystal_caverns — flyers and casters; teaches verticality and interrupts
- dark_cathedral — summoners; teaches target priority
- iron_vault — armoured and slow; teaches unblockables
- prism_depths — zoners; teaches movement under fire
- venom_mire — splitters; teaches area damage
- glacial_hollow — mixed elites; the exam
- umbral_chapel — everything, faster

**Solution.** The composition rule turns "which enemies" into "what does this room ask of me". That is
the same job `content/progression/room_pacing.json` already does for room content, so mirror its
shape — a weights dictionary with guarantees.

**Done when.** Each biome asks the player to do something the previous one did not.

---

### EN-12 — Elites that exist outside a modifier — **S** — `→ EN-10`

**Files:** `apps/game/client/scripts/dungeon/procgen/procgen_placements.gd`,
`apps/game/client/scripts/dungeon/dungeon_builder.gd`,
`apps/game/client/scripts/enemies/castle_enemy_base.gd`

**Problem.** `_attempt_place_enemy()` only marks an enemy elite when `elite_packs` or `elite_vigil` is
an active run modifier. `DungeonBuilder._spawn_enemy()` then sets `is_elite` as **metadata and
nothing else** — nothing reads it. So elites do not exist in a normal run, and even under the
modifier they are ordinary enemies with a flag.

**Action.**
1. Place one elite per floor by default, from floor 3 onward, in an off-path combat room — the
   reward for exploring should be a harder fight, not only a chest.
2. Make `is_elite` real in `CastleEnemyBase._ready()`: ×1.6 health, ×1.25 damage, ×1.4 poise, +15 %
   scale, a distinct emissive rim (reuse `LightEmbersScript.attach`), and a name plate on the health
   bar.
3. Guarantee an elite kill drops one piece of equipment (route through
   `GlobalDropService.roll_enemy_drop` with a forced-equipment flag).

**Done when.** Every floor has one fight that is visibly harder than the others, and it pays.

---

## §PH — Physics and impact

Hits currently change numbers. They must change *positions*. This is the single highest-value block
in the plan for how the game feels in the hand.

---

### PH-01 — Knockback — **L** — *nothing in the game does this today*

**Files:** `apps/game/client/scripts/combat/damage_info.gd`,
`apps/game/client/scripts/combat/hitbox.gd`, `apps/game/client/scripts/combat/hurtbox.gd`,
`apps/game/client/scripts/combat/knockback.gd` *(new)*,
`apps/game/client/scripts/player/locomotion.gd`,
`apps/game/client/scripts/enemies/castle_enemy_base.gd`, `content/weapons/*.json`,
`content/enemies/*.json`

**Problem.** `grep -rn "knockback\|impulse\|push_back\|apply_force" --include=*.gd` returns **zero
hits** across 406 scripts. A greatsword and a dagger move a body by exactly the same amount: none. A
hit is a flash and a number, which is why the combat "looks like almost nothing happened" even though
the timing model underneath is correct.

**Action.**
1. Add `var knockback: float = 0.0` to `DamageInfo`; carry it from `Hitbox.set_attack_values()`
   (append the parameter) and from `Projectile.launch()`.
2. Create `scripts/combat/knockback.gd` *(new)* as a small `Node` that attaches to any `CharacterBody3D`:
   it owns `var _impulse: Vector3` and exposes `apply(direction, strength)` and
   `consume(delta) -> Vector3`, decaying the impulse toward zero at a fixed rate.
3. In `Hurtbox.receive_hit()`, after poise is applied and **only when `res.outgoing > 0.0` and the
   hit was not blocked**, resolve the victim's `Knockback` node and call `apply(info.direction,
   scaled_strength)`.
4. In `Locomotion._physics_process()`, add the consumed impulse into `velocity` before
   `move_and_slide()` — in **every** branch, including the movement-locked and landing-locked ones,
   or a staggered player will absorb knockback and not move.
5. Same in `CastleEnemyBase._physics_process()`, before its `move_and_slide()`.
6. Author `"knockback"` per attack in `content/weapons/*.json` and `content/enemies/*.json`.

**Solution.** Numbers that work with this codebase's scale (player walk speed 4.5, dodge peak 11–12.5):

```
decay rate            18.0 m/s²   (impulse is gone in ~0.15 s at typical strengths)
light attack           1.2 – 1.8
heavy attack           3.0 – 4.5
greatsword heavy       5.5
poise-break bonus     ×2.0        (only when the hit broke poise this frame)
enemy attack           2.0 – 3.5 on the player
mass scaling          strength × (1.0 / clampf(mass, 0.5, 3.0))
```

Read `mass` from the enemy definition, defaulting to 1.0; give `crystal_golem` and every boss 2.5–3.0
so a greatsword moves a grunt across a room and barely rocks a golem. That contrast **is** the
feature — knockback that applies equally to everything reads as a bug.

**Trap 1.** Knockback must be horizontal only for grounded targets. Zero the Y component in
`apply()`, or every hit launches enemies into the ceiling.

**Trap 2.** Do not knock back a target that is mid-`ATTACK` with hyperarmor. `Hurtbox` already
computes `_is_hyperarmor_active()`; multiply the strength by `HYPERARMOR_POISE_MULT` (0.25) in that
case so a hyperarmored boss visibly *shrugs*.

**Trap 3.** `CharacterBody3D.move_and_slide()` is the only mover in this codebase. Do not add a
`RigidBody3D`. Do not write `global_position +=`.

**Done when.** A greatsword heavy visibly shoves a grunt back a metre; the same swing barely moves a
golem; a boss mid-swing does not move at all.

---

### PH-02 — Stagger displacement and hit-stop separation — **M** — `→ PH-01`, `EN-06`

**Files:** `apps/game/client/scripts/player/player_combat_reactions.gd`,
`apps/game/client/scripts/combat/hit_feedback.gd`,
`apps/game/client/scripts/enemies/castle_enemy_base.gd`

**Problem.** `_apply_stagger()` sets a timer and plays a clip; the body does not move. And
`HitFeedback._apply_hitstop()` freezes the **attacker's** animation (`director.set_speed_scale(0.05)`)
while `VfxService.push_time_scale()` only fires on `CRITICAL` — so a solid hit freezes the swinger
and not the swung-at, which is backwards from how impact reads.

**Action.**
1. In `_apply_stagger()`, apply a knockback impulse of `0.8 × poise_damage / STAGGER_POISE_HIGH`
   along `stagger_direction`.
2. In `HitFeedback`, split hit-stop into two calls: `_freeze_attacker(ms)` (the existing anim speed
   scale) and `_freeze_victim(ms)`, and make the victim's freeze **longer** than the attacker's
   (`victim = freeze × 1.4`).
3. Move `IMPACT_PROFILES` out of the `const` block and into `content/combat/impact.json` *(new)*, read once
   with the current dictionary as the fallback.
4. Add a fourth profile, `PARRY`, with a longer freeze (0.22) than `CRITICAL`.

**Solution.** The rule from every game that feels good: **the attacker recovers first.** That
asymmetry is what makes the hit feel like *you* did something rather than like the game paused.
Keep the current durations as the starting point (glancing 0.04 / solid 0.085 / critical 0.17) and
tune from there — they are already close.

**Done when.** Landing a heavy makes the enemy hitch visibly longer than you do, and the difference
is felt rather than measured.

---

### PH-03 — Swept hitbox test — **M**

**Files:** `apps/game/client/scripts/combat/hitbox.gd`

**Problem.** `Hitbox._scan_overlaps()` does a stationary `intersect_shape` once per physics frame.
A dagger's active window is 0.12 s ≈ 7 frames at 60 Hz, which is fine — but the same hitbox on a
lunging attack (`lunge_distance` up to 0.35, plus the enemy's own `_apply_attack_lunge()` which can
move a body at `distance/active_duration` ≈ 10 m/s) can travel further than the shape's own thickness
between frames and pass through a thin target.

**Action.**
1. Cache `_last_shape_transform` on `Hitbox`.
2. In `_scan_overlaps()`, when the distance from `_last_shape_transform.origin` to the current origin
   exceeds half the shape's smallest extent, use `PhysicsShapeQueryParameters3D.motion` to sweep from
   the previous transform to the current one instead of testing statically.
3. Reset `_last_shape_transform` in `enable()` so the first frame of a swing does not sweep from
   wherever the hitbox was last swing.

**Solution.** Godot's `intersect_shape` honours `motion` on the query parameters; you do not need to
step the transform manually. Keep `MAX_OVERLAP_RESULTS` at 32 — sweeping does not change the result
cap.

**Trap.** The per-swing line-of-sight cache (`_los_clear_this_swing`) and the re-hit table
(`_hit_times`) already prevent double hits. Do not add a second guard; sweeping only widens the
volume tested, it does not change hit bookkeeping.

**Done when.** `res://scenes/combat/combat_arena.tscn` with `debug_hitboxes` on shows no swing passing
through a dummy without registering.

---

### PH-04 — Projectile physics that reads — **M**

**Files:** `apps/game/client/scripts/combat/enemy_projectile.gd`,
`apps/game/client/scripts/combat/combat_layers.gd`,
`apps/game/client/scripts/combat/weapon_controller.gd`

**Problem.** Three concrete defects. (a) `ARC_LIFT_RATIO` is a fixed 0.12 of launch speed regardless
of range, so an arrow aimed at a target 20 m away lands short while one at 5 m lands high. (b)
`CombatLayers.PROJECTILE` is defined and used by nothing: the projectile masks only
`WORLD_OCCLUDERS`, so an arrow cannot be blocked by a shield, shot out of the air, or stopped by a
gate. (c) Player arrows are added to `tree.current_scene`, which survives room teardown by ordering
luck rather than by design.

**Action.**
1. Replace the fixed lift with a solved ballistic angle: given launch origin, target point (from
   lock-on, or a ray from the aim direction to the first world hit) and `speed`, solve the low-arc
   launch elevation and use it. Fall back to the current flat-plus-lift behaviour when there is no
   target point.
2. Put projectiles on `collision_layer = CombatLayers.PROJECTILE` and give shields and gates a mask
   that includes it, so `ShieldHurtbox` can eat an arrow.
3. Add `"drag"` (per-second speed multiplier, default 1.0) and a maximum range beyond which the
   arrow fades rather than vanishing at a hard `_lifetime` boundary.
4. Parent spawned arrows to a `Node3D` named `Projectiles` under the run root (created on demand by
   `castle_run.gd` / `waves_run.gd`), not to `tree.current_scene`.

**Solution.** The low-arc solution for a target at horizontal distance `d` and height difference `h`
with speed `v` and gravity `g`:
`angle = atan((v² − sqrt(v⁴ − g·(g·d² + 2·h·v²))) / (g·d))`. When the discriminant is negative the
target is out of range — clamp to 45° and let the shot fall short honestly.

**Trap.** `Projectile._face_velocity()` already pitches the model down its own path. Keep it; it is
the thing that makes the arc readable. Do not orient the arrow to the aim direction.

**Done when.** A locked-on bow shot at 20 m hits centre mass, an arrow fired into a raised shield is
stopped, and leaving a room does not leave arrows in the tree.

---

### PH-05 — Crowd separation — **S**

**Files:** `apps/game/client/scripts/enemies/castle_enemy_base.gd`

**Problem.** `NavigationAgent3D` avoidance is enabled (`_ensure_nav_agent()` sets `radius 0.55`,
`neighbor_distance 4.0`, `max_neighbors 6`) but the agent's avoidance velocity is never read — the
enemy computes its own direction from `get_next_path_position()` and ignores the avoidance result
entirely. Five enemies converging on the player therefore stack into one silhouette.

**Action.** Either (a) connect `_nav_agent.velocity_computed` and drive velocity from the callback,
which is the engine-supported path; or (b) if that fights the existing state machine, add a cheap
separation force: sum `(self.pos − other.pos).normalized() / distance` over `EnemyBlackboard.nearby()`
within 1.2 m, clamp it, and add it to `velocity` in `_apply_chase_velocity()`.

**Solution.** Prefer (b) for this codebase. The state machine already writes `velocity` directly in
seven places and the avoidance callback would fight all of them. A separation term added at the one
choke point (`_apply_chase_velocity`) is smaller, deterministic and easier to reason about. Cap the
separation contribution at 30 % of `_move_speed` so it nudges rather than steers.

**Done when.** Six grunts chasing you form an arc, not a column.

---

## §AN — Animation

The animation system is a code-authored library of ~30 clips per rig with method tracks for VFX,
footsteps and hitbox timing. It is good machinery producing non-pixel motion.

---

### AN-01 — Stepped animation — **M** — *the single change that makes the game read as pixel art in motion*

**Files:** `apps/game/client/scripts/art/characters/diorama_anim_library.gd`,
`apps/game/client/scripts/art/pipeline/pixel_diorama_settings.gd`

**Problem.** `diorama_anim_library.gd:2132` sets `INTERPOLATION_LINEAR` and `UPDATE_CONTINUOUS` on
every track it compiles. The world is rendered through a pixel post-process and the characters are
voxel meshes, but they *move* on a continuous curve — the same reason 3D-rendered "pixel art" usually
reads as 3D. The player looks at their own character 100 % of the time.

**Action.**
1. Add `static var animation_steps_per_second: float = 12.0` to `PixelDioramaSettings` (persisted
   through its existing `load_from_save`/`save` pair; 0 means "off / continuous").
2. In `_compile()`, when the setting is > 0, quantise: keep `INTERPOLATION_LINEAR` **off** by using
   `Animation.INTERPOLATION_NEAREST` for rotation and position tracks.
3. Because nearest-interpolation on sparse keys will pop badly, first **resample** each authored
   track onto a fixed grid of `1.0 / steps_per_second` before inserting keys — i.e. evaluate the
   authored linear curve at each step and insert that value.
4. Leave the additive `head_look` library continuous. A stepped head-track reads as a glitch.

**Solution.** 12 steps/second is the right default: it is the classic hand-animated cadence, it
divides evenly into 60 Hz (5 physics frames per animation frame), and at typical clip lengths
(0.28–1.35 s) it yields 4–16 poses per clip, which is what a pixel animator would actually draw.
Expose it in settings so it can be compared side by side, but ship at 12.

**Trap 1.** Method tracks (`SWING_VFX`, `FOOTSTEP`, `HITBOX_ON`, `HITBOX_OFF`) must **not** be
resampled. They fire on exact times and `WeaponController` promotes phases from them
(`enable_hitbox_from_anim`). Quantising them would shift the active window.

**Trap 2.** `AnimLibrary.library_digest()` and `expected_exported_clip_count()` are used by the export
tool and by `can_use_authored_library()`. If you change compilation, the digest changes and authored
`.res` libraries will be considered stale — which is correct, but re-export them
(`scripts/tools/export_diorama_anim_libraries.gd`) rather than working around it.

**Done when.** The warden's run cycle visibly steps, hitboxes still open on the same frames, and
`res://scenes/debug/lint_scripts.tscn` is clean.

---

### AN-02 — Anticipation and follow-through on attack clips — **M** — `→ AN-01`

**Files:** `apps/game/client/scripts/art/characters/diorama_anim_library.gd`

**Problem.** Read `attack_light_1` (line 1091): `startup_end` 0.34, `active_end` 0.58, and the ArmR
rotation track goes `0.0 → 0.34 (wind back) → 0.5 (swing through) → 0.7 → 1.0`. The wind-back is a
single key at the end of startup, so the arm travels there linearly across the whole startup: there
is no *snap*. The swing reads as a smooth sweep rather than a strike.

**Action.** For each of the ten attack clips, restructure the key layout to:
`0.0` rest → `0.12` a small **counter-move** (arm dips forward slightly before winding back) →
`startup_end × 0.85` the wound pose → `startup_end` hold → `active_end` the follow-through
**overshoot** (past the resting pose) → `1.0` settle back.

**Solution.** The proportions that work: anticipation occupies the first 15 % of startup, the wound
pose holds for the last 15 % of startup (this is the readable frame — the one a player recognises),
the active window is 2–3 stepped frames, and the follow-through overshoots the rest pose by ~20 % of
the swing arc before settling.

**Trap.** `startup_end` and `active_end` in the clip dictionary must keep matching the timings in
`content/weapons/*.json`, because `DioramaAnimController.play_attack()` scales the clip to the
attack's real phase durations. Change the *shape* of the curve, not the phase boundaries.

**Done when.** A paused frame at 85 % of startup is instantly recognisable as "this is the heavy".

---

### AN-03 — Attacker impact recoil — **S** — `→ PH-02`

**Files:** `apps/game/client/scripts/art/characters/diorama_anim_controller.gd`,
`apps/game/client/scripts/combat/hit_feedback.gd`

**Problem.** When your swing connects, the only thing that happens to *your* character is that its
animation slows to 0.05 speed for 85 ms. The weapon does not stop against the target; it passes
through and the animation resumes.

**Action.** Add `play_impact_recoil(strength: float)` to `DioramaAnimController`: a very short
additive pose (2 stepped frames) that pushes `ArmR` back along the swing axis and dips `Torso`
slightly. Call it from `HitFeedback.on_hit()`.

**Solution.** Use the existing additive `AnimationPlayer` (`_setup_additive_player`) rather than
interrupting the main clip — the main clip must keep running so the hitbox method tracks fire on
schedule. Scale the pose by `ImpactClass`: glancing 0.3, solid 0.7, critical 1.0.

**Done when.** Hitting a golem visibly stops your arm; hitting air does not.

---

### AN-04 — A held pose for charged attacks — **S** — `→ CB-01`

**Files:** `apps/game/client/scripts/art/characters/diorama_anim_controller.gd`,
`apps/game/client/scripts/art/characters/diorama_anim_library.gd`

**Problem.** The bow already has a draw state (`AttackPhase.DRAWING`) with no held pose — the
character stands in an idle while `_draw_charge` accumulates. Charged melee (`CB-01`) will need the
same thing.

**Action.** Add `hold_at(clip, normalized_time)` to the controller: play the clip, then set
`speed_scale = 0` at the requested time. Add a `charge_shake` additive that grows with charge (a
1-pixel tremor at full charge).

**Solution.** Freeze at the clip's `startup_end` — the wound pose from `AN-02` is exactly the frame a
charge should hold on, which is why `AN-02` comes first.

**Done when.** Holding heavy freezes the warden at the top of the swing, with a growing tremor.

---

## §RM — Room generation: making a floor feel authored

**This is the workstream the project owner flagged as most critical.** Read §1.1 first: the graph
generator, the lattice solver, the lock placer and the key-soundness validator are all built and all
correct. The gap is **shape**, **gating variety**, and **the moment of entering a room**.

The floor definition contract you are extending (produced by `dungeon_procgen.gd`, consumed by
`dungeon_builder.gd`, validated by `dungeon_definition_validator.gd`):

```
rooms[]          { id, templateId, type, transform{x,y,z,yaw}, tags[], heightLevel,
                   size{x,z}, doorOffsets{north|east|south|west: float}, kind, locked? }
edges[]          { from, to, kind: door|corridor|shortcut|secret, dir?, door{x,z}? }
placements       { enemies[], loot[], traps[], secrets[], cover[], boss, exit, entrance }
roomContent[]    { roomId, layoutId, contentType, templateId, items?, keyId?, lockId?, flagId? }
locks[]          { lockId, from, to, keyId, keyRoomIds[], keysRequired, keyLabel }
puzzles[]        { puzzleId, roomId, kind, flagId, gateRoomId, leverCount, solutionOrder[] }
shortcutGates[]  { gateId, roomA, roomB, openRoomId }
branchPreviews[] { fromRoomId, toRoomId, hint: reward|danger|neutral }
landmarks[]      { kind, position{x,y,z}, scale{x,y,z} }
```

**Golden rule for this whole section:** every new field must be *optional* with a defaulting read, so
a floor definition written before your change still builds. `DungeonDefinitionValidator` must accept
old and new shapes.

---

### RM-01 — Circular rooms — **L** — *the owner's first named requirement*

**Files:** `apps/game/client/scripts/dungeon/castle/castle_blockout.gd`,
`apps/game/client/scripts/dungeon/procgen/room_template_catalog.gd`,
`apps/game/client/scripts/dungeon/procgen/room_graph_geometry.gd`,
`apps/game/client/scenes/rooms/*/*_arena.tscn` (and the boss/courtyard scenes per biome)

**Problem.** Every room in the game is an axis-aligned box. `CastleBlockout` builds four straight
walls from `room_width` × `room_depth` and cuts up to four cardinal doorways.
`RoomTemplateCatalog.KIND_SPECS` is eleven width/depth pairs. There is no shape concept anywhere in
the definition or the builder. A soulslike arena is a rotunda — the shape is what tells the player
"this is the fight".

**Action.**
1. Add `@export var shape: StringName = &"rect"` to `CastleBlockout`, accepting `rect`, `round`,
   `octagon`.
2. In the wall-building pass, branch on shape:
   - `round` — build the perimeter from `N` box segments (`N = 24`) placed on a circle of radius
     `min(room_width, room_depth) * 0.5`, each rotated to the tangent, each
     `(2πr/N + overlap) × WALL_HEIGHT × WALL_THICKNESS`. Skip the segments that fall inside a
     doorway arc.
   - `octagon` — the same with `N = 8` and no per-segment rotation error to worry about.
3. Doorways on a round room: the door still belongs to a cardinal direction (the lattice requires
   that), but its **position** is on the circle at that bearing, and the doorway is a straight
   corridor stub of length `(half_extent − radius)` connecting the circle to the cell edge. Build the
   stub as two side walls plus floor.
4. Floor and ceiling: use a `CylinderMesh` for `round`, and a `PrismMesh`-style fan for `octagon`.
   Keep `NavigationRegion3D` baking exactly as it is — it bakes from geometry, so a round floor bakes
   round.
5. Add `"shape"` to `KIND_SPECS` per kind and carry it into the built room record in
   `RoomGraphGeometry.build_rooms()` as `rooms[].shape`.
6. Assign `round` to `arena` and `boss`, `octagon` to `courtyard`, `rect` to everything else.

**Solution — the part that keeps the solver untouched.** A circular room still **reserves a square
footprint** on the lattice. `RoomGraphLayout.footprint_cells()` reads `half_extent_x/z` from the spec
and must keep returning the bounding square. This is the entire trick: the lattice, the door
sliding, the loop scoring, the overlap validator and the minimap all keep working unchanged, because
from their point of view nothing changed. Only the *geometry built inside the reserved square*
changes.

**Trap 1.** `RoomTemplate.contains_world_point()` tests the blockout's rectangular half-extents, and
`castle_run.gd` calls it every physics frame to decide which room the player is in. For a round
room the square bound is still correct (the player cannot be outside the walls but inside the
square, except in the door stubs, which is where you want them counted anyway). **Leave it as a
rectangle test.** Do not add circle maths there.

**Trap 2.** Door lateral offsets. `dungeon_builder.gd:_door_lateral()` slides a door along a straight
wall. On a round room, a nonzero lateral offset must be converted into a **bearing offset** on the
circle — `angle = base_angle + lateral / radius`. Get this wrong and doors will be cut in the wrong
place, which is the one failure that produces doors opening onto rock.

**Trap 3.** `_clear_doorway_obstructions()` computes rectangular doorway zones from
`_doorway_zones(blockout)`. Extend it to return the stub's rectangle for round rooms rather than the
wall-centre rectangle.

**Done when.** `res://scenes/debug/floor_connectivity_audit.tscn -- --seeds=16` is green, and every
arena and boss room in every biome is a rotunda you can walk the full perimeter of.

---

### RM-02 — Multi-cell arena rooms — **M** — `→ RM-01`

**Files:** `apps/game/client/scripts/dungeon/procgen/room_template_catalog.gd`,
`apps/game/client/scripts/dungeon/procgen/room_graph_generator.gd`

**Problem.** `boss` is 28×28 and `arena` is 24×24, which on a 4-unit lattice are 7×7 and 6×6 cells —
so a big room already eats a big square, but the *graph* still treats it as one node with at most
four doors. A boss arena with a single approach reads correctly; a 24×24 arena reached through one
door in the middle of one wall reads like a cul-de-sac.

**Action.**
1. Allow `arena` and `courtyard` to declare `"maxDoors": 3` and let `_apply_door_connections` prefer
   giving them more edges (a small bias in `_open_shortcut_loops`'s candidate scoring when one end is
   an arena).
2. Guarantee the boss room keeps exactly one non-secret door (it already tends to, because
   `_pick_boss_id` prefers dead ends — make it a hard constraint in `_validate_graph`).

**Solution.** The design intent, stated so the implementer does not over-rotate: **arenas want
multiple entrances, boss rooms want exactly one.** Multiple entrances make an arena a place you pass
*through* and can be flanked in; a single entrance makes a boss room a place you commit to.

**Done when.** Arena rooms average >1.5 doors and boss rooms always have exactly 1 across 16 seeds in
the connectivity audit's printed shape report.

---

### RM-03 — Room shape and prop variety per biome — **M** — `→ RM-01`

**Files:** `content/rooms/*.json` (10 biomes), `apps/game/client/scripts/dungeon/procgen/room_layout_catalog.gd`,
`apps/game/client/scripts/dungeon/diorama_room_dressing.gd`

**Problem.** `content/rooms/<biome>.json` variants can only override **anchor positions**
(`RoomLayoutCatalog.anchors_for()` reads `variants[kind][n].anchors[role]` and nothing else). A
variant cannot change size, shape, doors, or props. So the tenth `castle_hall` you enter is the first
one with the chests moved.

**Action.** Extend the variant record (all keys optional):
```
{ "id": "...", "weight": 2,
  "shape": "round|octagon|rect",
  "anchors": { "enemy": [...], "cover": [...], "chest": [...], "trap": [...] },
  "props": [ { "kind": "pillar|brazier|rubble|statue|altar", "at": [x,y,z], "yaw": 0 } ],
  "coverPattern": "ring|corridor|scatter|none" }
```
Have `RoomLayoutCatalog` return the whole variant, not just anchors; have
`DioramaRoomDressing` place `props`; have `ProcgenPlacements._place_cover()` honour `coverPattern`.

**Solution.** Author **three variants per kind per biome** — that is 3 × 11 × 10 = 330 records, which
is a content job, not a code job. Do the code first, then author `forgotten_castle` fully as the
reference biome, then clone-and-edit.

**Trap.** `variant_for_room()` derives the variant index from `FloorSeedMix.mix(run_seed, room_id
hash)`. Adding variants changes which one a given seed picks. That is acceptable (floors are not
save-persisted geometry, only seeds are) but it means the connectivity audit's numbers move; re-run
it and record the new baseline.

**Done when.** Ten `hall` rooms in one run are visibly different rooms.

---

### RM-04 — One-way doors on the critical path — **M**

**Files:** `apps/game/client/scripts/dungeon/procgen/room_content_assigner.gd`,
`apps/game/client/scripts/dungeon/room_content/room_shortcut_gate_content.gd`,
`apps/game/client/scripts/dungeon/procgen/room_graph_generator.gd`

**Problem.** One-way doors exist (`_add_shortcut_gates`) but only on **realised loop edges**, and the
lattice only realises a loop when two rooms happen to end up sharing a wall. Floors where the solver
closed no loops get zero one-way doors. The soulslike shape — "you unlock the door back to the
bonfire from the far side" — therefore appears on some floors and not others.

**Action.**
1. Make one-way gates a **guarantee**, not an opportunity: after `_add_shortcut_gates()` runs, if
   `shortcutGates` is empty, promote a *dead-end branch* to a one-way: pick the deepest dead-end room
   whose parent is on the critical path, and add a gate on that edge that opens only from the dead
   end. The reward chest at the dead end becomes the reason to go in, and the gate becomes the exit.
2. Add a **drop-down** kind: on floors with `maxHeightLevel > 0`, an edge between two rooms at
   different `heightLevel` can be marked `"oneWay": "down"` — passable downward, walled upward. Build
   it in `dungeon_builder.gd:_build_height_transitions()` by omitting the ramp on that edge.
3. Show one-way edges on the minimap with a chevron rather than a plain line.

**Solution.** State the invariant in a comment where you add it: **a one-way door may never be the
only route to anything the floor requires.** Before accepting a promoted gate, run
`RoomGraphPaths.reachable_without_edge(graph, from, to)` and confirm the boss, the stairs and every
key room are still reachable from the entrance with that edge cut in the blocked direction. This is
the same primitive the lock placer already uses, so reuse it rather than writing a new walk.

**Done when.** Every floor across 16 audit seeds has at least one one-way gate, and the connectivity
audit still reports every room reachable.

---

### RM-05 — Make the key ring legible — **M**

**Files:** `apps/game/client/scripts/dungeon/room_content/room_locked_door_content.gd`,
`apps/game/client/scripts/dungeon/room_content/room_locked_vault_content.gd`,
`apps/game/client/scripts/ui/combat_hud.gd`, `apps/game/client/scripts/ui/minimap.gd`,
`apps/game/client/scripts/dungeon/procgen/room_lock_placer.gd`

**Problem.** The lock system is sound and invisible. A locked door is an untextured box with a
`telegraph_material` tint of `(0.55, 0.35, 0.12)` — the same slab shape as a puzzle gate
`(0.35, 0.55, 0.85)` and a shortcut gate `(0.3, 0.3, 0.34)`. `FloorKeyring` defines red/blue/yellow
tints and **the door never uses them**. The HUD key row is always three pips even on a floor with one
lock. The minimap draws a generic lock mark with no colour.

**Action.**
1. `RoomLockPlacer.place_locked_doors()` — assign a colour per lock index via
   `FloorKeyring.color_for_index(i)` and write `"keyColor"` into the lock record; make `keyId` end
   with `_<color>` so `FloorKeyring.color_of()` resolves.
2. `room_locked_door_content.gd` — tint the barrier with `FloorKeyring.tint_for(_key_id)`, and give
   it a **door shape** rather than a slab: two vertical jambs, a lintel, and a central panel with a
   keyhole-sized emissive inset in the key colour. Use `DioramaInteractableSkin` helpers for the
   frame so it matches the biome.
3. `room_locked_vault_content.gd` — tint the key chest the same colour.
4. HUD — show only as many key pips as the floor has locks (read from the definition, passed in
   through a new `configure_keys(lock_count)` called by `castle_run.gd` next to `configure_minimap`).
5. Minimap — draw the lock mark in the lock's colour, and mark the key room with the same colour once
   it has been *seen*.

**Solution.** The design rule, from Doom, already written in `floor_keyring.gd`'s own header comment:
a lit red card next to a red door explains itself. Everything here is making the game keep that
promise. Do not add a tutorial line; add colour.

**Done when.** On a three-lock floor the player can point at a door and say which key it wants,
without reading any text.

---

### RM-06 — Formalise the no-soft-lock guarantee — **M** — `→ RM-04`

**Files:** `apps/game/client/scripts/dungeon/procgen/room_content_validator.gd`,
`apps/game/client/scripts/tools/floor_connectivity_audit.gd`

**Problem.** `RoomContentValidator.validate_definition()` runs a key-BFS proving the boss is reachable
with earned keys — which is correct and is the reason the "key behind its own lock" class of bug is
closed. But it only considers `locks`. It does **not** consider one-way shortcut gates, puzzle gates,
or secret edges, and after `RM-04` there will be one-way doors on the critical path.

**Action.** Extend the BFS to a full traversability model:
1. Build the adjacency with an explicit direction per edge: `locks` block `from → to` until the key
   is held; `shortcutGates` block `openRoomId → roomA` permanently (they only open the other way);
   `puzzles[].gateRoomId` blocks until the lever flag is set, and the lever is in
   `puzzles[].roomId`; `secret` edges are traversable only after the secret is opened, and the
   mechanism is in the parent room.
2. Run the same fixpoint loop already there (walk, collect what you can reach, repeat while new
   capabilities were gained), where a "capability" is now {key held, lever pulled, secret opened}.
3. Fail the floor if **the boss, the stairs, or any key room** is unreachable.
4. Mirror the check in `floor_connectivity_audit.gd` so it reports soft-locks per seed rather than
   only reporting graph connectivity.

**Solution.** Write the invariant at the top of the function in one sentence, because it is the single
most important rule in the generator:

> *From the entrance, using only capabilities obtainable from rooms already reached, the player must
> be able to reach the stairs and the boss. A floor that cannot prove this does not ship.*

**Trap.** Do not let the fixpoint loop run unbounded. Cap it at `rooms.size()` iterations; a
capability set can only grow, so that bound is sound.

**Done when.** `res://scenes/debug/floor_connectivity_audit.tscn -- --seeds=32` reports zero
soft-locks across all ten biomes and all floors.

---

### RM-07 — Fog gates and arena lock-in — **M**

**Files:** `apps/game/client/scripts/dungeon/boss_room_door.gd`,
`apps/game/client/scripts/dungeon/room_content/room_arena_gate_content.gd` *(new)*,
`apps/game/client/scripts/dungeon/dungeon_builder.gd`,
`apps/game/client/scripts/dungeon/castle_run.gd`

**Problem.** The boss room already seals behind you (`castle_run.gd:_physics_process` calls
`seal_door()` once the player is `BOSS_GATE_DEPTH_THRESHOLD` (4.0) deep) — but the door is a barrier
box, there is no fog wall, and no *other* room ever locks. Every non-boss fight is optional: walk
back through the door and the enemies lose aggro (`DEAGGRO_LOS_TIMEOUT` 3.0 s).

**Action.**
1. Give `boss_room_door.gd` a fog-gate visual: a translucent plane with a scrolling noise shader in
   the biome accent colour, plus a `Label3D` prompt. Keep the collision barrier behind it.
2. Add an `arena` room-content type: when a combat room is marked `"lockIn": true`, spawn gates on
   **every** doorway that close when the player enters and open when
   `WorldFlags.room_cleared(room_id)` is set. `DungeonBuilder` already emits `room_cleared` and
   `_dispatch_room_clear()` already fires it.
3. In `room_content_assigner.gd`, mark exactly one combat room per floor as `lockIn` — the one
   immediately before the boss (`pre_boss_layout`, which the assigner already computes and forces to
   `COMBAT`).

**Solution.** One lock-in per floor. Two is oppressive and turns exploration into a series of
corridors between fight boxes. The pre-boss room is the right one because it is where the game wants
to test you before the real test.

**Trap.** The gates must open on `room_cleared` **and** on load: check the flag in `configure()` the
same way `room_shortcut_gate_content.gd` checks its door flag, or a saved run resumed inside a
cleared arena will be sealed in.

**Done when.** Entering the pre-boss room drops gates, killing everything raises them, and reloading
a save taken inside a cleared arena leaves the gates up.

---

### RM-08 — Encounter triggers and ambushes — **M**

**Files:** `apps/game/client/scripts/dungeon/dungeon_builder.gd`,
`apps/game/client/scripts/dungeon/procgen/procgen_placements.gd`,
`apps/game/client/scripts/enemies/castle_enemy_base.gd`

**Problem.** Every enemy on a floor exists from build time and wakes only through perception. Nothing
is ever *sprung*. Combined with fixed anchors (six per room kind, taken in order), a room's encounter
is fully visible from the doorway on every floor of every run.

**Action.**
1. Add `"trigger"` to an enemy placement: `"idle"` (default, current behaviour), `"ambush"`
   (inactive and hidden until the player crosses the room's centre), `"delayed"` (spawns `n` seconds
   after room entry, at the far anchor).
2. In `DungeonBuilder._spawn_enemy()`, honour it: an ambusher starts with its hurtbox and collision
   disabled, visual hidden; the room's existing entry detection (`castle_run.gd:_notify_room`) wakes
   it via a new `builder.wake_ambushers(room_id)`.
3. On wake, play a 0.35 s emerge: `VfxService.play_telegraph()` under the spawn point, then reveal
   and set `_latch_aggro()`.
4. In `ProcgenPlacements._attempt_place_enemy()`, mark at most **one** enemy per room as `ambush`, and
   only in rooms whose depth from the entrance is ≥3, and never in the entrance's neighbours
   (`_spawn_safe_room_ids` already computes that set).

**Solution.** An ambush that kills you is a bad ambush; an ambush that makes you turn around is a good
one. Place ambushers *behind the doorway the player came in through* (use the room's `doorOffsets`
to find it) so the surprise is directional, not damage.

**Done when.** Roughly one room per floor has something come out from behind you, and it never
happens in the first two rooms.

---

### RM-09 — Make secrets findable — **S**

**Files:** `apps/game/client/scripts/dungeon/illusory_wall.gd`,
`apps/game/client/scripts/dungeon/hidden_lever.gd`,
`apps/game/client/scripts/dungeon/dungeon_builder.gd`

**Problem.** `illusory_wall.gd` deliberately takes the biome's own wall material so it is
"indistinguishable from the wall it sits in" — correct for the fiction, but the only way to find one
is to walk the perimeter of every room pressing interact. There is no tell of any kind.

**Action.** Add exactly one **subtle, deniable** tell per mechanism:
1. Illusory wall — a very slow, very faint dust-mote emitter in front of the panel
   (`LightEmbersScript.attach` with tiny spread and low alpha), plus a distinct footstep sound when
   the player stands within 1.5 m (set a `surface` meta of `"hollow"` on the floor patch there; the
   surface probe in `locomotion.gd` already reads collider `surface` meta).
2. Hidden lever — put it in a place the room's lighting already draws the eye to: place it at the
   room's brightest fixture anchor rather than at a socket.
3. Add a run-level counter: `WorldState` flag `secrets_found_this_floor`, shown on the results screen.

**Solution.** The rule: **the tell must be ignorable.** A player who is not looking should walk past.
A player who is looking should feel clever. Anything louder than dust motes turns a secret into a
waypoint.

**Done when.** A player told "there is a secret on this floor" finds it in under two minutes without
mashing interact on walls.

---

### RM-10 — Landmarks that are art — **S**

**Files:** `apps/game/client/scripts/dungeon/dungeon_builder.gd:_build_landmarks()`,
`apps/game/client/scripts/art/props/diorama_prop_factory.gd`

**Problem.** `_build_landmarks()` builds a `BoxMesh` with the biome accent material for each of
`boss_spire`, `boss_silhouette` and `orientation_spire`. The wayfinding system — which is a genuinely
good idea, generated in `dungeon_procgen._build_landmark_hints()` — renders as untextured coloured
boxes floating over the level.

**Action.** Replace the box with a built prop per landmark kind: a tapered spire with a lit beacon at
the top for `boss_spire`, a banner-and-chain silhouette for `boss_silhouette`, a smaller pillar with
a hanging lantern for `orientation_spire`. Build them with `PixelBoxBatch` so they cost one draw call
each.

**Solution.** Keep the positions and scales the generator already computes; only change what is built
at them. Add an `OmniLight3D` at the boss spire's tip with the biome torch colour, so the objective is
visible as a light before it is visible as geometry.

**Done when.** Standing at the entrance, the boss's direction is readable from the skyline.

---

### RM-11 — Room dressing density — **M**

**Files:** `apps/game/client/scripts/dungeon/diorama_room_dressing.gd`, `content/biomes/*.json`

**Problem.** Rooms are furnished by anchors and a per-biome `propKit` of a pillar, a sconce and two
rubble variants. A 24×24 arena dressed from four prop types reads as a big empty box, which is what
`docs/GAME_FEEL_REVIEW.md` saw as "60 % of the frame is one flat tile pattern".

**Action.**
1. Extend each biome's `propKit` to eight kinds: `pillar`, `sconce`, `rubble_a`, `rubble_b`,
   `banner`, `statue`, `altar`, `debris_pile`.
2. Add a density rule to the dressing pass driven by room area: `props = clampi(area / 26, 3, 14)`.
3. Place props on a seeded Poisson-ish scatter that respects (a) the doorway zones
   `_doorway_zones()` already computes, (b) every anchor in the room's variant, and (c) a 1.5 m
   clearance from cover obstacles.

**Solution.** Draw calls matter: use `PixelBoxBatch` (MultiMesh) for repeated props. Check the result
with `res://scenes/debug/draw_call_probe.tscn` before and after — the budget is what it was, not
"whatever it becomes".

**Done when.** `res://scenes/debug/capture_world_screens.tscn` frames show no room where the floor
occupies more than half the frame unbroken, and `draw_call_probe` is within 15 % of the pre-change
number.

---

### RM-12 — Raise first-attempt generation success — **M**

**Files:** `apps/game/client/scripts/dungeon/procgen/room_graph_generator.gd`,
`apps/game/client/scripts/dungeon/procgen/room_graph_layout.gd`,
`apps/game/client/scripts/dungeon/local_procgen.gd`

**Problem.** `local_procgen.gd`'s own comment records the measurement: a single attempt validates
26.6 % of the time; 18 salts are needed to reach 98.2 %; a typical floor load spends ~0.2 s and the
worst case over a second re-rolling. The cause is that the **graph** is generated with no knowledge
of whether the **lattice** can seat it, so a graph that is topologically fine is discarded after a
full layout attempt.

**Action.**
1. Instrument first: add a counter per rejection reason (`RoomGraphGenerator._last_validate_reason`
   already exists; aggregate it) and print the histogram from
   `scripts/tools/procgen_seed_health.gd`. **Do not optimise before you know which reason dominates.**
2. Then fix the top reason. The two likely candidates, in order:
   - *Room count below minimum* — `_grow_branches` gives up after `stuck_turns > 12` in the critical
     path walk and after `max_walk_attempts` in branches. Make the branch frontier prefer cells with
     more free neighbours (a simple degree heuristic) so branches do not strangle themselves.
   - *Layout dropped a critical room* — feed the lattice's footprint sizes back into
     `_can_place_room`: a room whose template is 7×7 cells cannot sit adjacent to three others in a
     9-cell-wide grid. Add a coarse pre-check that the sum of footprints along any grid row fits.
3. Only after (2), reduce `SEED_SALTS` to the smallest count that still reaches ≥98 % over 400 seeds,
   and record the new measurement in the comment. **Keep the array append-only** — removing an early
   salt changes which floor an existing seed produces.

**Solution.** The target is ≥60 % first-attempt success, which brings the typical load under 100 ms.
Do not chase 100 %: the retry loop is correct and cheap insurance.

**Done when.** `scripts/tools/procgen_seed_health.gd` over 400 seeds reports ≥60 % first-attempt and
≥99 % overall, and the average attempt count is below 2.0.

---

### RM-13 — Ten biomes generate the identical floor — **L** — *the reason the generator feels weak*

**Files:** `content/biomes/*.json` (10), `apps/game/client/scripts/dungeon/procgen/room_graph_config.gd`

**Problem.** Compare the ten biome files. Every one of them has `roomCount` 22–28, `loopBudget` 4,
`fillBoundingBox` true, `allow2x2Blocks` true, `minDeadEnds` 4 or 5, `branchMaxDepth` 8,
`maxNeighborCount` 4, and the same ten room templates. The **only** generator value that differs is
`maxHeightLevel` (1 or 2). So the Forgotten Castle and the Poison Swamp produce structurally
identical floors, and the difference between two biomes is their materials, their enemy pool and
their palette. Ten biomes, one dungeon.

**Action.** Give each biome a distinct *topology* by tuning the knobs that already exist, and add
three that do not. Author these as a deliberate spread, not as noise:

| Biome | Shape it should have | `roomCount` | `loopBudget` | `branchMaxDepth` | `fillBoundingBox` | new `corridorRatio` | `maxHeightLevel` |
|---|---|---|---|---|---|---|---|
| forgotten_castle | the baseline: balanced, loopy | 22–28 | 4 | 8 | true | 0.15 | 1 |
| frozen_fortress | long halls, few branches | 20–24 | 2 | 4 | true | 0.30 | 1 |
| crystal_caverns | sprawling, many dead ends | 26–32 | 5 | 10 | false | 0.05 | 1 |
| poison_swamp | wide and shallow, few loops | 24–28 | 1 | 5 | false | 0.10 | 1 |
| dark_cathedral | one long spine, deep branches | 22–26 | 2 | 12 | true | 0.25 | 1 |
| iron_vault | tight grid, heavy gating | 20–24 | 3 | 6 | true | 0.20 | 2 |
| prism_depths | vertical, layered | 22–26 | 4 | 8 | false | 0.10 | 2 |
| venom_mire | mazy, low visibility | 26–32 | 5 | 10 | false | 0.05 | 2 |
| glacial_hollow | few big rooms | 18–22 | 3 | 6 | true | 0.15 | 2 |
| umbral_chapel | the finale: everything at once | 26–30 | 4 | 9 | true | 0.20 | 2 |

Add to `RoomGraphConfig.from_biome()`: `corridor_ratio` (what fraction of non-special rooms should be
corridors → `RM-14`), `size_bias` (a multiplier on how often the assigner picks the larger template
for a kind), and `dead_end_reward_ratio` (how often a dead end gets a reward rather than combat).

**Solution.** Do not add new generator *algorithms* per biome — the algorithm is fine. Change the
inputs. `loopBudget` 1 versus 5 is the difference between a swamp you get lost in and a fortress you
learn; `branchMaxDepth` 4 versus 12 is the difference between a hub-and-spoke and a spine.

**Trap.** `RoomGraphConfig.grid_width` is derived as `max(13, ceil(sqrt(max_rooms)) + 6)`. Raising
`roomCount.max` to 32 raises the grid to 13 — fine — but it also raises generation cost. Re-measure
with `procgen_seed_health.gd` after retuning (`→ RM-12`).

**Done when.** A player dropped into a floor with the materials swapped to grey can still tell which
biome it is from the map alone.

---

### RM-14 — Corridors: give the floor negative space — **M**

**Files:** `apps/game/client/scripts/dungeon/procgen/room_graph_assigner.gd`,
`apps/game/client/scripts/dungeon/procgen/room_template_catalog.gd`,
`apps/game/client/scripts/dungeon/procgen/room_graph_generator.gd`

**Problem.** The lattice seats every room flush against its neighbours, so a floor is a **solid block
of rooms sharing walls**. There is no corridor between two rooms, no threshold, no moment of "leaving"
one space before "entering" another. A `corridor` template exists (8×12, north/south doors only) and
the assigner has **no rule that ever selects it** — the only path to a corridor is
`pick_template_for_doors` falling back to it by door mask. Doors are holes in a shared wall, so
every transition in the game is instantaneous.

**Action.**
1. Add a corridor pass to `RoomGraphAssigner.assign()`: after the special rooms are resolved, convert
   `corridor_ratio` (from `RM-13`) of the remaining `NORMAL` slots that have **exactly two doors on
   opposite walls** into corridors.
2. Add two more corridor templates to `KIND_SPECS`: `corridor_long` (8×20, N/S) and `corridor_bend`
   (12×12, N/E) so corridors can turn.
3. Give corridors their own dressing profile in `DioramaRoomDressing`: lower ceiling
   (`wall_height` 4.5 instead of 6.0), sconces at 4 m intervals, no cover obstacles, no enemy anchors
   beyond two.
4. In `ProcgenPlacements._trap_room_pool()`, corridors already get `weight += 1.0`. Keep that: a
   corridor is where a trap belongs.

**Solution.** The purpose is rhythm, not connectivity. A corridor is a **compression** between two
open spaces: it is where the music drops, where the light narrows, where an arrow trap makes sense,
and where the player's stamina refills before the next room. Aim for one corridor between roughly
every three rooms — that is what `corridor_ratio` 0.15 buys on a 26-room floor.

**Trap.** A corridor's `doors` mask is `NORTH | SOUTH` only. `pick_template_for_doors` must not hand
a corridor to a slot needing three doors, and `supports_doors()`'s `primary_door_mask` fallback is
loose enough to let that happen. Add `corridor` to a new `KIND_STRICT_DOORS` list checked before the
fallback.

**Done when.** Walking a floor has a beat: room, corridor, room, big room, corridor, room.

---

### RM-15 — Kill the bounding-box blob — **M**

**Files:** `apps/game/client/scripts/dungeon/procgen/room_graph_generator.gd`

**Problem.** `_fill_bounding_box()` fills every empty cell inside the graph's bounding rectangle with
`is_filler` rooms until `min_rooms` is reached, and `_connect_fillers()` connects each to its
nearest-to-start neighbour. Nine of ten biomes have `fillBoundingBox: true`. The result is that a
floor's silhouette tends toward a filled rectangle, and roughly a fifth of its rooms are rooms with
no authored reason to exist — `RoomContentAssigner` marks every filler `EMPTY`, so they are literally
empty boxes the player walks through.

**Action.**
1. Change the fill from "fill the rectangle" to "fill toward a target **shape**". Add
   `floorSilhouette` to the biome: `blob`, `cross`, `ring`, `spine`, `scatter`. Fill only cells whose
   distance from the graph's medial axis matches the silhouette.
2. Cap fillers at 15 % of `min_rooms`; if the target cannot be reached, prefer **growing a branch**
   (call `_grow_branches` again with a larger `branch_max_depth`) over filling.
3. Never mark a filler `EMPTY` in `RoomContentAssigner`: give it the same content roll as any
   off-path room. A room the player walks through should always be *something*.
4. Set `fillBoundingBox: false` for the four biomes in `RM-13`'s table that want sprawl.

**Solution.** The rule: **a room exists because the graph wanted it, not because a rectangle had a
hole in it.** Fillers are a last resort to hit a minimum, and if they are a fifth of the floor the
minimum is wrong.

**Done when.** The connectivity audit's shape report shows filler rooms under 15 % on every biome, and
no floor's outline is a plain rectangle.

---

### RM-16 — Doors that are objects, not holes — **M**

**Files:** `apps/game/client/scripts/dungeon/castle/castle_blockout.gd`,
`apps/game/client/scripts/art/props/diorama_interactable_skin.gd`,
`apps/game/client/scripts/dungeon/dungeon_builder.gd`

**Problem.** `_build_wall()` cuts a `DOOR_WIDTH × DOOR_HEIGHT` rectangle out of the wall and adds a
lintel above it. That is the entire door. There is no frame, no threshold, no jamb, no actual door
leaf anywhere in the game except the boss door and the three gate types — and all four of those are
untextured boxes with a telegraph material.

**Action.**
1. Add `DioramaInteractableSkin.build_doorway_frame(parent, biome_id, width, height)`: two jambs, a
   lintel with a keystone, and a threshold strip in the floor material, built from `PixelBoxBatch`.
2. Call it from `DungeonBuilder._open_blockout_door_toward()` after the hole is cut, positioned from
   the socket.
3. Give every gate type (`room_locked_door_content`, `room_puzzle_gate_content`,
   `room_shortcut_gate_content`, `boss_room_door`) a real leaf: two panels, hinge-side inset, banded
   metal, tinted by purpose (key colour → `RM-05`, puzzle blue, shortcut iron, boss biome accent).
4. Animate opening: the leaf swings or sinks over 0.4 s rather than `visible = false`.

**Solution.** This is cheap and it is most of what makes a corridor read as architecture. Reuse the
biome's own wall and accent materials so a frame is never a colour the room does not already contain.

**Done when.** Every doorway in the game has a frame, and every gate visibly opens.

---

### RM-17 — Size pacing across a floor — **S**

**Files:** `apps/game/client/scripts/dungeon/procgen/room_graph_assigner.gd`

**Problem.** `_resolve_room()` picks the combat template by cycling
`COMBAT_SEMANTICS = ["courtyard", "hall", "arena"]` in **index order**: the first combat room is a
courtyard (20×20), the second a hall (16×16), the third an arena (24×24), and everything after that
is `combat_N` which resolves through `combat_preferred` keyed by that same rotation. Room size
therefore has no relationship to depth, role, or what happened in the previous room.

**Action.** Pick the size from the room's **graph distance and role**:
- distance 1–2 → small (`corridor`, `hall`)
- mid-path, on the critical path → medium (`courtyard`)
- a dead end → small, unless it is the treasure room
- the pre-boss room → large (`arena`)
- a room with 3+ doors → large (it is a junction; give it space to fight in)

**Solution.** The feel to aim for: the floor should **open up** as it goes. Starting in a big room and
ending in a small one reads backwards.

**Done when.** A floor's biggest room is always near its end, and the entrance neighbourhood is tight.

---

### RM-18 — Score a floor and reject a boring one — **M** — `→ RM-12`, `RM-15`

**Files:** `apps/game/client/scripts/dungeon/procgen/room_graph_generator.gd`,
`apps/game/client/scripts/tools/procgen_seed_health.gd`

**Problem.** `_validate_graph()` answers "is this floor legal" — connected, enough rooms, enough dead
ends, boss far enough. It never asks "is this floor **good**". A floor that is a straight line of 22
rooms with four stubs off it passes every check.

**Action.** Add `_score_graph(graph, config) -> float` combining, each normalised 0–1 and weighted:
- **branching** — fraction of rooms not on the critical path (target 0.35–0.55)
- **loopiness** — realised loops ÷ `loop_budget` (target ≥ 0.5)
- **path length** — critical path ÷ room count (target 0.30–0.45)
- **spread** — bounding-box aspect ratio (target 0.6–1.0, i.e. not a line)
- **dead-end depth** — mean branch depth of dead ends (target ≥ 2)

Reject any graph scoring below a threshold and re-roll. Because generation already re-rolls up to
256 times, this costs almost nothing — but keep the threshold **adaptive**: after 60 % of the attempt
budget, lower it linearly so a hostile seed still produces a floor.

**Solution.** Print the score distribution from `procgen_seed_health.gd` **before** picking the
threshold. Set it at roughly the 35th percentile of current output: high enough to cut the worst
third, low enough that generation cost does not move.

**Done when.** `procgen_seed_health.gd` reports a mean floor score above the old median with no
increase in mean attempts.

---

### RM-19 — Verticality that is used — **M** — `→ BG-02`

**Files:** `content/biomes/*.json`, `apps/game/client/scripts/dungeon/procgen/room_graph_generator.gd`,
`apps/game/client/scripts/dungeon/castle/castle_blockout.gd`

**Problem.** Five biomes set `maxHeightLevel: 2` and five set 1, but `_grow_critical_path()` only
promotes a level on every fourth path room with a 35 % chance and only along the critical path — so
height changes are rare, always on the main route, and (before `BG-02`) broken. Nothing else uses
height: no balconies, no rooms overlooking rooms, no drop-downs (`RM-04` adds those).

**Action.**
1. Promote height on **branches** too, not just the critical path — a side branch that climbs is a
   better use of the mechanic than a main route that does.
2. Add a `balcony` room kind: a room whose floor is at `heightLevel + 1` over only half its footprint,
   with a railing and a drop-down to the lower half. Build it as two floor boxes plus a railing in
   `CastleBlockout` under `shape: "split"`.
3. Make one room per floor with `maxHeightLevel >= 2` a balcony overlooking a combat room, with an
   archer on it. This is the single most soulslike thing verticality can do.

**Solution.** Depends on `BG-02` landing first — do not add more height changes to a system whose
height transitions are broken.

**Done when.** At least one floor in three has a room you can look down into before you fight in it.

---

### RM-20 — The shop room kind is dead content — **S**

**Files:** `content/biomes/*.json`, `apps/game/client/scripts/dungeon/procgen/room_graph_assigner.gd`

**Problem.** `RoomGraphSlot.SlotType.SHOP` exists, `_pick_shop_id()` runs with a 35 % chance and
picks a dead end between distance 2 and `boss_distance - 2`, and `KIND_SPECS` has a `shop` entry
(12×12). But **no biome lists `<prefix>_shop` in `roomTemplateIds`**, so
`RoomGraphAssigner._resolve_room()` clears `shop_preferred` and hands the slot whatever template fits
its door mask. The shop room is generated and then rendered as a random other room.

**Action.** Either author ten `<prefix>_shop.tscn` room scenes and add them to `roomTemplateIds`, or
delete the `SHOP` slot type and rely entirely on the `MERCHANT` room-content type (which works and is
placed by `RoomContentAssigner`). **Prefer the second** — one merchant mechanism is better than two,
and the content path already handles restocking and dungeon merchant stock.

**Solution.** If you delete it, remove `_pick_shop_id`, the `SHOP` enum member, the `shop` branch in
`_resolve_room`, and the `shop` entry in `KIND_SPECS` — and raise `weight_merchant` in
`content/progression/room_pacing.json` from 0.01 so merchants actually appear (`→ AD-02`).

**Done when.** `grep -rn "SlotType.SHOP"` returns nothing, or every biome has a shop scene.

---

### RM-21 — Every biome prop scene is an empty node — **M** — `→ RM-11` `→ RM-10`

**Files:** `apps/game/client/scenes/props/*/pillar.tscn`, `sconce.tscn`, `rubble_a.tscn`,
`rubble_b.tscn` (40 files), `content/biomes/*.json` (the `propKit` block),
`apps/game/client/scripts/dungeon/diorama_room_dressing.gd`

**Problem.** All ten biomes declare a `propKit` in their definition JSON:

```json
"propKit": {
  "pillar": "res://scenes/props/vault/pillar.tscn",
  "sconce": "res://scenes/props/vault/sconce.tscn",
  "rubble": ["res://scenes/props/vault/rubble_a.tscn", "res://scenes/props/vault/rubble_b.tscn"]
}
```

Every one of those 40 scenes is **three lines long and contains nothing**:

```
[gd_scene format=3]

[node name="Pillar" type="Node3D"]
```

No mesh, no collision, no material. And nothing reads `propKit` — `grep -rn "propKit\|prop_kit"`
over `apps/game/client/scripts` returns **zero hits**. The actual dressing comes from
`diorama_room_dressing.gd`, which builds pillars and sconces procedurally from `BoxMesh`/`CylinderMesh`
in code and never touches the scene files. So the repository carries a decorative content pipeline
that is declared in ten content files, wired to forty empty scenes, and read by nobody.

This matters twice. It is the reason a reader inspecting `content/biomes/*.json` believes rooms are
dressed with authored art when they are dressed with code-generated boxes, and it is 40 files of
false signal sitting exactly where the pixel/voxel art work in `RM-10` and `RM-11` has to land.

**Action.**

1. Decide the single source of truth. **Choose the scene files**, not the code path: the art targets
   in `RM-10` (landmarks) and `RM-11` (dressing density) need authored, per-biome silhouettes, and a
   `.tscn` is where a voxel model imported by `tools/voxel-import/` can live. The procedural path in
   `diorama_room_dressing.gd` stays as the fallback for a biome whose kit is incomplete.
2. Author the 40 scenes for real, or start with four and alias the rest. Each is a `Node3D` with a
   `MeshInstance3D` carrying a mesh from `tools/voxel_sculpt.py` and the biome's shared
   `pixel_diorama_surface` material, plus a `StaticBody3D` + `CollisionShape3D` for the pillar only
   (rubble and sconces must not block movement or the room's navmesh).
3. Make `diorama_room_dressing.gd` read `propKit` through `BiomeRegistry`, instance the scene when
   the path resolves to a scene with at least one child, and fall back to its current procedural
   builder when it does not. Do the "does this scene have content?" check **once per biome per run**
   and cache it — never per prop.
4. Add the check to `res://scenes/debug/scene_sweep.tscn`: a scene referenced by a `propKit` that has
   no `MeshInstance3D` descendant is a failure, not a silent pass. This is the same class of defect
   `check-doc-paths.mjs` was written for — the path existed, the content did not.

**Solution.** Constants that keep this cheap and consistent:

- Pillar footprint ≤ `1.2 m` radius so `RM-01`'s circular rooms can seat four of them without
  narrowing the fighting ring below the `RM-17` minimum.
- Sconce is emissive-only — use `pixel_diorama_emissive.gdshader`, no `OmniLight3D` per sconce. Ten
  sconces per room × 25 rooms is 250 real-time lights and will cost more than the whole floor.
  `MD-04`'s lighting budget assumes the emissive path.
- Rubble gets **no collision at all** and is spawned into the same `MultiMeshInstance3D` batch the
  draw-call work in `VS-05` sets up; two rubble variants at 20 instances is one draw call, not 20.
- Trap: `ResourceLoader.exists()` is true for all 40 of these files today. Existence is not content.
  Test for a `MeshInstance3D` child, not for the path.

**Done when.** `res://scenes/debug/scene_sweep.tscn` reports every `propKit` entry as carrying
geometry, a dungeon floor screenshot from `res://scenes/debug/capture_world_screens.tscn` shows
biome-distinct props, and `grep -rn "propKit" apps/game/client/scripts` returns at least one hit.

---

### RM-22 — Two generations of room scene disagree about doors — **S** — `→ RM-16` `→ RM-02`

**Files:** `apps/game/client/scenes/rooms/*/*.tscn` (100 files),
`apps/game/client/scripts/dungeon/castle/castle_room_scene.gd`,
`apps/game/client/scripts/dungeon/dungeon_builder.gd`

**Problem.** The 100 room scenes fall into two generations that were authored under different rules,
and nothing in the project states which one is current.

**Generation one — `castle`, `crystal`, `swamp` (30 scenes).** Door flags are authored per template
and the socket count matches them: `castle_entrance` has one socket and `door_south = true`;
`castle_hall` has three sockets and three flags; `castle_courtyard` has four.

**Generation two — `cathedral`, `frozen`, `hollow`, `mire`, `prism`, `umbral`, `vault` (70 scenes).**
Every non-corridor room has **exactly two sockets (N and S)** and `door_south = false,
door_north = false` — that is, the authored geometry has no openings at all, and two of the four
walls have no socket authored.

Neither generation is broken at run time, and that is worth stating plainly so nobody "fixes" it into
a real bug. `DungeonBuilder._close_all_blockout_doors()` clears all four flags on every room and
`_open_blockout_door_toward()` re-opens exactly the ones the graph edge names, and
`CastleRoomScene._ensure_socket_completeness()` synthesises any of the four sockets a scene did not
author. The authored values only decide how the scene looks when it is opened on its own in the
editor.

But the inconsistency has a real cost. A designer opening `vault_courtyard.tscn` sees a sealed box
and cannot tell whether that is intentional; a designer opening `castle_courtyard.tscn` sees four
doors. `RM-02` (multi-door arenas) and `RM-16` (real doors) both edit these files, and doing so
against two conflicting conventions is how a genuine mismatch gets introduced.

There is also measurable waste. Each of the eight door-related `@export`s on `CastleBlockout` calls
`_request_rebuild()` in its setter. Closing all four doors and re-opening one with an offset is six
rebuild requests per room; a 25-room floor issues roughly 150. Outside the editor `_request_rebuild`
only sets `_geometry_dirty`, so the cost today is small — but it is a trap waiting for anyone who
makes the runtime path rebuild eagerly.

**Action.**

1. Pick generation two's convention as canonical — the run-time path owns doors, so authored flags
   should be neutral — and normalise all 100 scenes to it: `door_* = false` on every blockout, all
   four sockets authored explicitly rather than synthesised.
2. Author the two missing sockets in the 70 generation-two scenes rather than leaving them to
   `_ensure_socket_completeness()`. A synthesised socket lands at the wall's centre; an authored one
   can be offset to suit the room's interior, which is what `RM-01`'s circular rooms need.
3. Add a one-line comment at the top of `castle_blockout.gd` stating that authored `door_*` values are
   editor preview only and the builder is authoritative. This is the fact that was not written down.
4. Coalesce the rebuild: make `_request_rebuild()` in the editor defer through
   `call_deferred("_rebuild")` guarded by `_geometry_dirty`, so setting eight exports in a row costs
   one rebuild instead of eight.

**Solution.**

- Do this with a script over the `.tscn` text, not by hand in the editor — 100 files, and the editor
  will reformat unrelated properties. The socket block is a fixed shape; the four transforms are
  `Transform3D(1,0,0,0,1,0,0,0,1, 0,0,-half_d)` for N, `(-1,0,0,0,1,0,0,0,-1, 0,0,half_d)` for S,
  and the corresponding ±X pair for E/W, with `direction` 0/2/1/3 as `CastleRoomConstants.Direction`
  orders them.
- After the rewrite, run `res://scenes/debug/floor_connectivity_audit.tscn -- --seeds=200`. The socket
  positions feed `_socket_for_edge()`, so a transform typo shows up there as an unreachable room, not
  as a visual glitch.
- Trap: `castle_corridor.tscn` and its nine siblings already author four sockets and **no** `door_*`
  flags. Leave them alone — they are already canonical.

**Done when.** All 100 room scenes author four sockets and no `true` door flag, the connectivity
audit passes 200 seeds, and `castle_blockout.gd` says who owns doors at run time.

---

## §HD — HUD and mode consistency

**This section answers the owner's "CRITICAL: ensure consistency of what is already there with hud,
dungeon, wave, endless mode."**

The three run modes are: **castle** (tiered dungeons, `castle_run.tscn`), **endless** (the same
scene, `run_mode == "endless"`, floors without a cap), and **waves** (`waves_run.tscn`, a single
arena with lobbies). Castle and endless share one scene and therefore share their HUD wiring by
construction. Waves does not, and that is where every inconsistency lives.

---

### HD-01 — One HUD contract, honoured by every mode — **M** — *do this first in §HD*

**Files:** `apps/game/client/scripts/ui/combat_hud.gd`,
`apps/game/client/scripts/dungeon/waves_run.gd`, `apps/game/client/scripts/dungeon/castle_run.gd`

**Problem.** `waves_run.gd:_build_combat_hud()` instantiates `combat_hud.tscn`, sets `player_path` and
`lock_on_path`, and stops. `castle_run.gd` additionally calls `configure_minimap`,
`set_objective_world_position`, `bind_boss`, `show_region_title`, `set_branch_previews`,
`mark_room_visited`, `set_current_room`, `mark_room_cleared`, `set_minimap_fog_of_war` and
`show_respawn_outcome`. So in the Vigil: no map, no objective marker, no boss bar (even though
`WavesRunService.is_boss_wave()` spawns a warden every tenth wave), no region title, no respawn
outcome.

**Action.**
1. Define the contract explicitly at the top of `combat_hud.gd` as a documented block of public
   methods, and add the missing mode-neutral ones:
   `configure_for_mode(run_mode: String)`, `set_objective_text(text: String)`,
   `configure_keys(lock_count: int)`.
2. `configure_for_mode` hides what a mode does not have rather than leaving it unconfigured: in
   `waves` hide the minimap anchor, the branch banner and the key row; in `endless` hide nothing but
   change the objective label.
3. Make `waves_run.gd` call: `configure_for_mode("waves")`, `bind_boss()` when a boss wave spawns a
   boss, `show_region_title("The Vigil", "Wave %d")` at each wave start, `show_run_warning` for
   errors instead of writing them into its own panel, and `show_respawn_outcome` on failure.
4. Add a one-line comment in both run scripts pointing at the contract block, so the next mode added
   knows what it owes.

**Solution.** The rule: **the HUD is owned by `combat_hud.gd`; a run scene may only call its public
methods.** Today `waves_run_ui.gd` draws its own panel, which is how the duplication happened. Do not
delete `waves_run_ui.gd` (it owns the lobby/reward/cash-out flows, which are genuinely
waves-specific) — strip it down to those, and move everything that is "status" onto the HUD.

**Done when.** Playing all three modes back to back, the same information appears in the same place,
and a Vigil boss has a boss bar.

---

### HD-02 — One owner for the centre-top banner — **S**

**Files:** `apps/game/client/scripts/ui/combat_hud.gd`,
`apps/game/client/scripts/ui/waves_run_ui.gd`, `apps/game/client/scenes/ui/combat_hud.tscn`

**Problem.** Four things claim the top-centre band: `BranchBanner` (`anchors_preset = 10`),
`WarningBanner` (`anchors_preset = 10`), the `RegionBanner` built at runtime
(`PRESET_CENTER_TOP`), and `waves_run_ui.gd`'s own panel (anchored centre-top with
`offset_top = 16`). They can and do overlap.

**Action.**
1. Build a small banner queue in `combat_hud.gd`: one container, one visible message at a time, with
   priorities `region (3) > warning (2) > branch (1)`, a minimum display time of 1.2 s, and a queue
   that drains rather than a stack that overlaps.
2. Route `show_region_title`, `show_run_warning` and `set_branch_previews` through it.
3. Move the waves panel to the **top-left under the resource bars** or make it use the queue.

**Solution.** Branch previews are ambient and should not interrupt: give them a persistent slot
*below* the queue rather than a turn in it. Warnings and region titles are events and belong in the
queue.

**Done when.** Entering a new floor while holding a full inventory shows both messages in sequence,
neither on top of the other.

---

### HD-03 — Turn the pixel UI on — **M** — *high impact, small change*

**Files:** `apps/game/client/scripts/art/pipeline/pixel_diorama_settings.gd`,
`apps/game/client/scripts/ui/game_ui_skin.gd`, `apps/game/client/scripts/ui/settings_schema.gd`

**Problem.** `RESOLUTION_PRESETS` holds exactly one entry, flagged `"native": true`. Therefore
`is_native_hd_preset()` is always true, `is_pixel_ui()` is always false, and
`GameUISkin.apply_pixel_theme()` takes the HD branch — setting `TEXTURE_FILTER_LINEAR` on the whole
UI, `PANEL_CORNER_RADIUS_HD` (8) on every panel and an 8 px drop shadow. The entire pixel treatment
is dead code for every player. `style_progress_bar()`'s own comment states this outright: *"a real
player has never seen the pixel bar style this function otherwise draws."*

**Action.**
1. Add real presets to `RESOLUTION_PRESETS`, each with `"native": false` and its own `tuning` block:
   `640×360` (pixel_scale 3.0), `854×480` (2.5), `960×540` (2.0), `1280×720` (1.5), plus the existing
   `1920×1080` native.
2. Make `960×540` the `"default": true` entry.
3. Verify `GameUISkin.is_pixel_ui()` now returns true, and walk every screen: `main_menu`,
   `character_create`, `inventory`, `settings`, `talents`, `blacksmith`, `merchant`, `results`,
   `pause`, `combat_hud`.
4. Fix whatever the pixel branch breaks — expect the font to need an integer scale
   (`build_scaled_theme`) and expect some fixed-size panels to need their half-extents re-checked
   against `clamped_panel_half_size()`.
5. Expose the preset in settings (`settings_schema.gd` already has the plumbing) so it is
   comparable side by side.

**Solution.** This is the change that makes the owner's "pixelled HUD" requirement true. The art is
already drawn for it: `make_pixel_frame`, `make_bar_fill_style` (an 8-px tile with a shaded seam),
`PIXEL_UNIT = 2`, the pixel font, the status/HUD/item/glyph atlases. All of it is waiting behind one
boolean.

**Trap.** `apply_pixel_theme()` walks the tree with `find_children("*", "Label")` etc. on every call.
With the pixel branch live that walk now actually does work. Call it once per screen in `_ready()`,
never per frame, and check `res://scenes/debug/perf_audit.tscn` afterwards.

**Done when.** Every UI screen renders with nearest filtering, square corners and no drop shadows,
and `capture_ui_screens.tscn` produces a contact sheet with no blurry text.

---

### HD-04 — The per-mode HUD matrix — **S** — `→ HD-01`

**Files:** `apps/game/client/scripts/ui/combat_hud.gd`, this document

**Problem.** There is no statement anywhere of which HUD elements each mode should have, so drift is
invisible until someone plays all three.

**Action.** Implement `configure_for_mode` against exactly this table, and paste the table into a
comment above it:

| Element | castle | endless | waves |
|---|---|---|---|
| HP / SP / MP / Poise / XP | ✅ | ✅ | ✅ |
| Status pips + build-up meters | ✅ | ✅ | ✅ |
| Heal charges | ✅ | ✅ | ✅ |
| Quick slots | ✅ | ✅ | ✅ |
| Lock reticle / guard bars | ✅ | ✅ | ✅ |
| Boss bar + phase pips | ✅ | ✅ | ✅ (boss waves) |
| Minimap + map overlay | ✅ | ✅ | ❌ (one arena) |
| Objective marker | ✅ stairs/boss | ✅ stairs | ✅ cresset / portal |
| Objective text | "Floor N — find the stairs" | "Depth N — The Waning" | "Wave N — M left" |
| Key row | ✅ (lock count) | ✅ | ❌ |
| Branch previews | ✅ | ✅ | ❌ |
| Region title | ✅ floor + theme | ✅ biome + depth | ✅ wave banner |
| Warning banner | ✅ | ✅ | ✅ |
| Respawn outcome | ✅ | ✅ | ✅ |

**Done when.** Every ❌ is hidden rather than empty, and every ✅ is populated.

---

### HD-05 — Arena radar for waves — **S** — `→ HD-01`

**Files:** `apps/game/client/scripts/ui/minimap.gd`, `apps/game/client/scripts/dungeon/waves_run.gd`

**Problem.** The Vigil arena is 210 units across with enemies spawning on a 24-unit ring; the minimap
is hidden because there is no room graph. But knowing where the pack is *is* the information the
mode needs.

**Action.** Add `enable_radar_mode(half_extent: float)` to `minimap.gd`: draw the arena bounds, the
player arrow, and a dot per live enemy (from the `"enemy"` group) plus a pulsing marker per pending
spawn (from `waves_run.gd`'s `_spawn_markers`). Reuse `_map_point()` with a fixed bounds rect instead
of the graph's.

**Solution.** Keep it to two colours: enemies in the health-bar red, pending spawns in the telegraph
amber. A radar with five colours is a second job for the player.

**Done when.** The waves HUD shows where the next wave is coming from during the 1.1 s spawn
telegraph.

---

### HD-06 — Combat readouts the model already earns — **M**

**Files:** `apps/game/client/scripts/ui/combat_hud.gd`,
`apps/game/client/scripts/combat/weapon_controller.gd`,
`apps/game/client/scripts/combat/stamina.gd`

**Problem.** Three things the combat model computes and the HUD never shows: the stamina an action
will cost, the two-hand/infusion stance, and where you are in a combo. All three are decisions the
player is asked to make blind.

**Action.**
1. **Stamina cost ghost.** `WeaponController` already knows `_scaled_stamina_cost()` for the next
   attack. Expose `get_next_attack_cost()` and draw a dimmed segment at the right end of the stamina
   bar showing what the next light attack would consume. Turn it red when it would exhaust.
2. **Stance readout.** A small pixel icon row beside the quick slots: two-hand on/off (from
   `WeaponController._two_hand`), infusion element (from `_infusion`), weapon-art cooldown as a
   radial or a shrinking bar (`get_weapon_art_cooldown_duration` and `_art_cooldown_timer`).
3. **Combo pips.** Three tiny pips lighting as `_combo_index` advances, dimming when
   `_combo_idle_timer` expires.

**Solution.** All three go in the existing `ResourcePanel/VBox`, below the bars, using
`GameUISkin.make_symbol_rect` and the 2 px `PIXEL_UNIT` spacing so they inherit the pixel grid. Add
getters to `WeaponController` rather than reaching into private fields from the HUD.

**Done when.** A player can see, without experimenting, that their next swing will exhaust them.

---

### HD-07 — Damage direction indicator — **S** — `→ PH-01`

**Files:** `apps/game/client/scripts/ui/combat_hud.gd`,
`apps/game/client/scripts/combat/hurtbox.gd`

**Problem.** `Hurtbox` emits `hurt_received(amount, poise_damage, direction)` for the player and the
HUD ignores the direction. Getting hit from off-screen gives a vignette pulse and no bearing.

**Action.** Draw a short arc at the screen edge, in the direction of the hit, fading over 0.6 s.
Compute the bearing from the hit direction against the camera's forward, not against the player's
facing.

**Solution.** Reuse the objective marker's clamping maths again — it is the third consumer of the same
"world direction → screen edge" transform, so lift it into a small static helper
(`ui/screen_edge.gd`) that all three use. *(new)*

**Done when.** Taking an arrow from behind shows which side it came from.

---

### HD-08 — Unify interaction prompts — **S**

**Files:** `apps/game/client/scripts/dungeon/room_content/*.gd`,
`apps/game/client/scripts/hub/hub_interactable.gd`, `apps/game/client/scripts/ui/interact_prompt.gd` *(new)*

**Problem.** Prompts are inconsistent per object. `room_locked_door_content.gd` and
`room_locked_vault_content.gd` build their own `Label3D`. `room_lore_content.gd`,
`room_merchant_content.gd` and `room_npc_quest_content.gd` have **no prompt at all** — you must guess
that interact does something. The hub has its own highlight-and-label system.

**Action.** Write one `InteractPrompt` helper that any node can attach: a billboarded `Label3D` with
the outline settings already used by the locked door (`font_size 24`, `outline_size 11`, black at
0.85), text built from `InputGlyphService.format_interact_name(name)`, shown on player proximity.
Replace all bespoke prompts with it.

**Solution.** Keep `HubInteractable`'s emissive highlight — it is better than a label — and add the
label to it rather than replacing it. In the dungeon, use the label alone (the props there are not
all shader-lit).

**Done when.** Every interactable object in the game announces itself the same way.

---

### HD-09 — Objective line per mode — **S** — `→ HD-01`

**Files:** `apps/game/client/scripts/ui/combat_hud.gd`, `castle_run.gd`, `waves_run.gd`

**Problem.** The objective marker points at a world position with no words. In endless the player
does not know the Waning is happening until they read the stair menu.

**Action.** Add a single-line objective label under the minimap, set from the mode:
castle `"Floor N — reach the stairs"` / `"Floor N — the boss bars the stair"`,
endless `"Depth N"` + `EndlessDifficulty.describe_pressure(floor)` when past `WANE_FLOOR` (150),
waves `"Wave N — M remaining"` or `"Light the cresset to call wave N"`.

**Done when.** At any moment in any mode, one line on screen says what to do next.

---

### HD-10 — Minimap information pass — **S** — `→ RM-05`

**Files:** `apps/game/client/scripts/ui/minimap.gd`

**Problem.** The minimap draws rooms, kinds, locks and cleared state, but not: which key a lock wants,
which direction a one-way gate opens, where the stairs are relative to you, or the floor number.

**Action.** Add (a) lock marks tinted by key colour, (b) a chevron on one-way edges pointing the
passable way, (c) a persistent gold outline on the stairs room once seen, (d) the floor number in the
minimap corner.

**Done when.** The map answers "where do I go and what do I still need" without opening the overlay.

---

## §CB — Combat depth

The combat *model* is complete. These items add verbs, not systems.

---

### CB-01 — Charged heavy attack — **M** — `→ AN-04`

**Files:** `apps/game/client/scripts/combat/weapon_controller.gd`, `content/weapons/*.json`

**Problem.** Heavy attack is a single fixed attack fired on press. The bow already has a charge model
(`AttackPhase.DRAWING`, `_draw_charge`, `draw_time`) and melee has none, so the heaviest weapons have
exactly the same input depth as the lightest.

**Action.**
1. Add `"charge"` to a weapon's `heavy_attack`: `{"max_time": 0.9, "damage_mult": 1.8,
   "poise_mult": 1.6, "stamina_mult": 1.5, "hyperarmor_at": 0.5}`.
2. On `heavy_attack` press, enter `DRAWING` for melee too, accumulate `_draw_charge`, and fire on
   release (or auto-fire at `max_time`).
3. Scale the released attack's `damage`, `poise_damage`, `stamina_cost` and `lunge_distance` by the
   charge, and grant hyperarmor once `charge >= hyperarmor_at`.
4. Movement during charge uses `COMMIT_SPEED_MULT` (0.2), same as startup.

**Solution.** Reuse `_scaled_attack()`: build the charged attack dictionary as a **duplicate** with
scaled values, exactly the way `_fire_bow_shot()` already does. Never mutate the weapon data
dictionary — it is shared and the multiplier would compound every swing.

**Done when.** Holding heavy on a greatsword produces a visibly bigger, slower, hyperarmored swing
that costs more stamina.

---

### CB-02 — Jump and plunge attack — **S**

**Files:** `apps/game/client/scripts/combat/weapon_controller.gd`,
`apps/game/client/scripts/player/locomotion.gd`, `content/weapons/*.json`

**Problem.** `_situational_attack()` handles `rolling_attack` and `running_attack` but not airborne.
Jumping is a movement verb with no combat consequence, and there is no reward for the height changes
`maxHeightLevel` creates.

**Action.** Add `"plunge_attack"` to weapon data; select it in `_situational_attack()` when the body
is not on the floor and has been falling for >0.2 s. On landing during the active window, deal the
attack's damage in a small radius and apply knockback.

**Solution.** Detect landing through `Locomotion._on_landed(fall_height)` — it already fires with the
height. Scale the plunge damage by `clampf(fall_height / 4.0, 1.0, 2.0)`.

**Done when.** Dropping onto an enemy from a ledge is worth doing.

---

### CB-03 — Just-guard (perfect block) — **S** — `→ EN-02`

**Files:** `apps/game/client/scripts/combat/guard.gd`, `content/combat/guard.json` *(new)*

**Problem.** Guard has exactly two outcomes: blocked (pay stamina) or guard-broken. There is no
skill expression between them, so blocking is a resource decision rather than a timing one, and
parry — with a 0.18 s window and a 10 stamina cost — is the only timed defensive verb.

**Action.** Add a third outcome: if the block is raised within `just_guard_window` (0.12 s) of the hit
landing, the stamina cost is zero, chip damage is zero, and the attacker takes a small poise hit
(but no stagger — that is the parry's job).

**Solution.** `Guard` already tracks `_parry_timer` from `_enter_guard()`. The just-guard window is
simply "the parry window's tail": if `parry_window_active` was false because the parry was on
cooldown or unaffordable, but the guard was raised within 0.12 s, apply the just-guard result. This
gives a player who cannot afford a parry something to aim for.

**Done when.** Blocking on reaction feels different from blocking early.

---

### CB-04 — Stagger execution window — **M** — `→ EN-06`, `PH-02`

**Files:** `apps/game/client/scripts/combat/weapon_controller.gd`,
`apps/game/client/scripts/enemies/castle_enemy_base.gd`

**Problem.** Breaking an enemy's poise costs the player real effort (`poise_damage` is a stat gear
rolls for) and pays out a stagger animation and nothing else. Meanwhile the execution system —
riposte and backstab, with i-frames and ×2.0 damage — only triggers off a parry or a back arc.

**Action.** Make a poise-broken enemy a valid execution target: in
`WeaponController._resolve_riposte_target()`, also accept an enemy whose `Poise.is_broken()` is true
and which is within `EXECUTION_RANGE` and in front. Play the riposte execution.

**Solution.** This closes the loop the poise stat already promises: build for poise damage → break
them → execute. Gate it so it can only fire once per break (set a flag on the enemy consumed by the
execution) or a fast weapon will execute repeatedly during one stagger.

**Done when.** Breaking a knight's poise and pressing attack performs a visceral execution.

---

### CB-05 — Weapon archetype identity — **L**

**Files:** `content/weapons/*.json` (8), `apps/game/client/scripts/combat/weapon_controller.gd`

**Problem.** Eight weapon files exist (`sword_basic`, `castle_sword`, `axe`, `dagger`, `greatsword`,
`spear`, `staff`, `bow`) and the differences between them are numbers in the same three-attack shape.
`CombatStatModifiers.FLAT_DAMAGE_CAP_RATIO`'s own comment explains why this matters: without
distinct movesets, "the player is not really swinging a dagger or a greatsword, they are swinging
their gear."

**Action.** Give each archetype one structural property, not just numbers:
- `dagger` — 4-hit light chain, `rolling_attack` with a big lunge, best backstab multiplier.
- `sword` — the baseline; 3-hit chain with a `heavy_branch` off the second light.
- `greatsword` — 2-hit chain, hyperarmor on every heavy, largest `knockback`.
- `axe` — heavies only in the chain; `poise_damage` per hit is the highest.
- `spear` — longest `hitbox.size.z`, thrust `running_attack`, can attack while guarding
  (a new `"attack_while_guarding": true` flag honoured in `_is_action_blocked`).
- `staff` — mana-costed attacks; the only archetype whose `light_attacks` spend `Mana` instead of
  `Stamina` (add an optional `"mana_cost"` handled beside `_scaled_stamina_cost`).
- `bow` — see §RG.

**Solution.** Author it in content wherever possible; add code only for the two genuinely new rules
(`attack_while_guarding`, `mana_cost`). Everything else is already expressible.

**Done when.** Swapping weapons changes how you fight, not just how hard you hit.

---

### CB-06 — Widen the rules bus — **M**

**Files:** `apps/game/client/scripts/combat/combat_events.gd`,
`apps/game/client/scripts/combat/hurtbox.gd`,
`apps/game/client/scripts/player/player_combat_reactions.gd`

**Problem.** `EFFECTS` holds ten effects, and all ten are resource restores or status applications.
There is no way for an item to say "deal damage", "grant a barrier", "make the next attack stronger",
or "reduce a cooldown" — which is most of what makes a build feel like a build. `ALL_EVENTS` is
missing `onDeath`, `onPerfectDodge` (a dodge that actually avoided a hit), `onGuardBreak`,
`onExecute`, `onFlask`.

**Action.**
1. Add effects: `deal_damage` (to `ctx.target`), `grant_barrier` (temporary absorb tracked on
   `Health`), `empower_next` (a one-shot damage multiplier consumed by `WeaponController`),
   `reduce_cooldown`, `knockback` (→ `PH-01`).
2. Add events: `ON_DEATH`, `ON_PERFECT_DODGE`, `ON_GUARD_BREAK`, `ON_EXECUTE`, `ON_FLASK`.
3. Dispatch the new events from where they already happen: `Hurtbox` (dodge with `res.dodged`),
   `Guard._trigger_guard_break()`, `WeaponController._try_start_execution()`,
   `PlayerHeal._on_heal_commit()`, `PlayerCombatReactions._on_died()`.
4. Add rule conditions: `ifWeaponArchetype`, `ifHealthBelow`, `ifEnemyType`.

**Solution.** Keep `register()`'s validation strict — it already drops unknown events and effects with
a `push_warning`, which is how a typo in content becomes visible. Extend the validation, do not relax
it.

**Done when.** A relic can say "on perfect dodge, your next attack deals +40 %".

---

### CB-07 — Mana as a real resource — **S** — `→ CB-05`

**Files:** `apps/game/client/scripts/combat/mana.gd`

**Problem.** `Mana` regenerates unconditionally — unlike `Stamina`, which has a `RegenState`
(normal/blocking/suppressed) and a `REGEN_DELAY`. A caster therefore has no resource tension at all.

**Action.** Give `Mana` the same `RegenState` model: suppressed while attacking, slowed while
blocking, with a `REGEN_DELAY` after a spend. Mirror `Stamina`'s API exactly so callers look the same.

**Done when.** A staff build has to manage mana the way a sword build manages stamina.

---

## §BS — Bosses and set-piece fights

Ten floor bosses, six catalogued boss enemies, a fully data-driven phase controller, arena hazards,
a boss door and an intro card. The machinery is good and the fights are thin.

---

### BS-01 — Six of the boss scripts are empty classes — **L** — `→ EN-01`, `EN-10`

**Files:** `apps/game/client/scripts/enemies/boss_cathedral_hollow.gd`,
`apps/game/client/scripts/enemies/boss_frost_warlord.gd`,
`apps/game/client/scripts/enemies/miniboss_cathedral_bell.gd`,
`apps/game/client/scripts/bosses/castle_knight.gd`,
`apps/game/client/scripts/bosses/crystal_sovereign.gd`, `content/bosses/*.json` (16)

**Problem.** Read them. `boss_cathedral_hollow.gd` is an id, a signal and a `_ready()` that calls
`super`. So is `boss_frost_warlord.gd`. `miniboss_cathedral_bell.gd` is an id and a `_ready()`.
`castle_knight.gd` and `crystal_sovereign.gd` are an id, a bar height and an aim point. Only
`swamp_hydra.gd` adds a verb (cleanse windows on a phase flag) and only
`final_boss_forgotten_castle.gd` is an authored fight (three phases: combat → spike bursts →
crystal-and-cannon puzzle). Nine of ten floor bosses are `CastleEnemyBase` with bigger numbers and a
phase list.

**Action.** Do not write ten bespoke boss scripts. Give `BossPhaseController` three new `onEnter`
capabilities and author the fights in `content/bosses/*.json`:
1. `"arenaChange"` — raise or lower a section of the arena floor, close a ring of gates, or flood a
   quadrant with a hazard. Build it from `ArenaHazard`, which already does telegraph → active → fade.
2. `"vulnerability"` — a phase where a named weak point (a `Hurtbox` with a `region` and a
   `region_damage_mult`) is the only thing that takes full damage. `Hurtbox` already supports
   regions; no boss uses them.
3. `"pattern"` — a fixed, ordered attack sequence for a phase instead of the weighted roll, so a
   phase can be *learned*. `set_active_attacks()` already exists; add an `"ordered": true` flag read
   by `_select_attack_data()`.

Then author each of the ten: one arena change, one vulnerability window, one ordered pattern.

**Solution.** The reason to do it in data rather than script: `boss_phase_controller.gd` is already
the best-factored system in the project (hpBelow thresholds, per-phase attacks and modifiers, tell
duration, invulnerability, telegraph, VFX, SFX, music, shake, adds, hazards). Adding three verbs
there gives all sixteen boss definitions access to them at once.

**Done when.** Each of the ten floor bosses has a phase the player must *do something different* in.

---

### BS-02 — The boss entrance is a fading label — **M**

**Files:** `apps/game/client/scripts/ui/boss_intro_ui.gd`,
`apps/game/client/scripts/camera/orbit_camera.gd`,
`apps/game/client/scripts/dungeon/castle_run.gd`

**Problem.** `boss_intro_ui.gd` is 51 lines: fade a title and a lore line in over 0.35 s, hold 2.2 s,
fade out. `castle_run.gd` plays an `AudioDirector.play_stinger("boss_reveal")` alongside it. That is
the entire set-piece. The camera does not move, the boss does not react, the door behind you is not
shown closing.

**Action.**
1. Add `OrbitCamera.play_intro_framing(target, duration)`: pull back and orbit slowly to frame the
   boss, then return control. Suppress player input for the duration via `PlayerInput.block_groups`.
2. Have the boss play an idle-to-ready animation (a new `boss_wake` clip) and its phase-1 `onEnter`
   telegraph while the camera holds.
3. Show the fog gate closing behind the player (`RM-07`).
4. Make the whole sequence skippable on any input after 0.6 s — always.

**Solution.** Keep it under three seconds. The intro exists to say "this is different"; past three
seconds it says "you are not playing".

**Done when.** Entering a boss room is a moment, and pressing a button skips it.

---

### BS-03 — Phases do not change the boss's appearance — **S**

**Files:** `apps/game/client/scripts/bosses/boss_phase_controller.gd`,
`apps/game/client/scripts/art/characters/material_flash.gd`,
`apps/game/client/scripts/enemies/castle_enemy_base.gd`

**Problem.** `_play_entry()` plays a telegraph, VFX, SFX, music and shake — all transient. The boss
body looks identical in phase 3 and phase 1, so the only lasting signal that the fight has escalated
is the health bar's pip row.

**Action.** Add `"bodyTint"`, `"emissive"` and `"scaleMult"` to a phase's `onEnter`, applied
permanently to the diorama visual through `CharacterSkin.apply_body_tint()` and a persistent emissive
override. Author a visible change for every phase 2 and 3 in the game.

**Done when.** A screenshot of the fight tells you which phase it is.

---

### BS-04 — Arena hazards do not speak the telegraph language — **S** — `→ EN-01`, `AX-01`

**Files:** `apps/game/client/scripts/bosses/arena_hazard.gd`,
`apps/game/client/scripts/bosses/crystal_pillar_hazard.gd`,
`apps/game/client/scripts/dungeon/traps/hazard_trap.gd`

**Problem.** `ArenaHazard._telegraph_tint()` returns a hardcoded `Color(1, 0.5, 0, 0.5)` and
`crystal_pillar_hazard.gd` overrides it with a hardcoded blue. Neither goes through
`AccessibilitySettings.get_telegraph_class_color()`, so a colourblind player gets the remapped colour
for an enemy attack and the raw colour for a hazard that will kill them just as dead.

**Action.** Route every hazard telegraph through the accessibility helper with an attack class
(hazards are `unblockable`), and honour `assist_telegraph_emphasis`.

**Done when.** Colourblind mode recolours hazards as well as attacks.

---

### BS-05 — The boss door has no ritual — **S** — `→ RM-07`, `RM-16`

**Files:** `apps/game/client/scripts/dungeon/boss_room_door.gd`

**Problem.** Five states (`LOCKED`, `CLOSED`, `OPEN`, `SEALED`, `RELEASED`) and a barrier box with a
`Label3D`. `configure()` reads a requirement (`none` / `sigil` / `all_keys`) from `DungeonCatalog`,
and `all_keys` is checked against the floor's locks. The one moment in the run where the player
commits is a box turning invisible.

**Action.** Give each state a distinct read: `LOCKED` shows the requirement as icons (key colours
from `RM-05`, or a sigil), `CLOSED` shows a push prompt, `OPEN` animates the leaves, `SEALED` slams
and dims the corridor light behind you, `RELEASED` stays open with its lights lit.

**Done when.** The door tells you what it wants and what just happened.

---

### BS-06 — Minibosses are not a category — **M** — `→ EN-12`

**Files:** `apps/game/client/scripts/dungeon/procgen/procgen_placements.gd`,
`content/enemies/*.json`, `content/biomes/*.json`

**Problem.** `miniboss_cathedral_bell` exists as one enemy and one empty script.
`_is_reserved_boss_enemy()` excludes anything starting with `miniboss_` from the normal pool, and
nothing ever places one. So the category is defined, excluded, and never used.

**Action.** Add a `minibossPool` to each biome and place one miniboss on every third floor, in a
dead-end room with a guaranteed equipment drop and its own health bar treatment (a smaller boss bar,
no phase pips). Reuse the boss bar binding path from `HD-01`.

**Done when.** Every third floor has a named fight that is not the floor boss.

---

### BS-07 — The epilogue is one card — **S**

**Files:** `apps/game/client/scripts/ui/epilogue_card.gd`,
`apps/game/client/scripts/dungeon/castle_run.gd`

**Problem.** `epilogue_card.gd` is 57 lines: show text, wait for input, emit. Finishing a tier —
ten floors and a final boss — resolves to one card and the results screen.

**Action.** Give the final boss of each dungeon an epilogue that names what changed: the vault entry
it unlocked, the tier it opened, the biome it revealed. Pull the text from
`content/dungeons/<id>.json` and the facts from `VaultService` and `DungeonTierService`.

**Done when.** Clearing a dungeon feels like it closed something.

---

### BS-08 — The final boss is one authored fight — **M**

**Files:** `apps/game/client/scripts/enemies/final_boss_forgotten_castle.gd`,
`apps/game/client/scripts/dungeon/final_boss_cannon.gd`, `content/biomes/*.json`

**Problem.** `final_boss_forgotten_castle.gd` is a real three-phase set piece with spikes, crystals
and a cannon. It is the only one. `_generate_final_floor()` builds the same entrance → arena → boss
line for every biome, and `_resolve_final_boss_id()` falls back to the biome's first boss.

**Action.** Either author a set piece per biome (expensive), or — preferred for the MVP — make the
final floor's *arena* the variable: each biome's `finalFloor` block declares its own arena hazard
set, add waves and a modifier. One authored fight plus nine distinct arenas is a better use of the
budget than ten half-authored fights.

**Done when.** Reaching the end of a tier is different per dungeon, even if the boss pattern is not.

---

### CB-08 — Statuses need identity and an answer — **M**

**Files:** `apps/game/client/scripts/combat/statuses/status_controller.gd`,
`apps/game/client/scripts/combat/statuses/status_catalog.gd`, `content/statuses/*.json` (10)

**Problem.** The status system is deep — build-up meters with grace and decay, escalating resistance
per application, stack decay, `expireStatusId` chains, stat tables, slow/haste, stun with a pulse
mode, damage-taken multipliers. Ten statuses are authored (bleed, burn, freeze, poison, stun, torpor,
plus the buffs focus, resolve, stoneskin, swiftness). What is missing is on the player's side: there
is **no way to cleanse a status** (`clear_status` exists as a rules effect and nothing in the content
uses it), no visible warning as a build-up meter approaches its threshold, and no self-applied buff
verb — the four buff statuses can only arrive from an item rule.

**Action.**
1. Add a cleanse: a consumable and a rest-room option that calls `StatusController.clear_all()`.
   `RunFlow.rest_at_bonfire()` is the natural home.
2. Flash the build-up meter and play a rising cue in the last 20 % before a threshold — the meter
   exists in the HUD (`_refresh_build_up_meters`) and gives no warning.
3. Give at least three items and three relics a `clear_status` or self-buff rule so the buff statuses
   are reachable in play.
4. Author a distinct **screen** treatment per debuff (`PixelDioramaViewport.pulse_screen` and the
   biome grade both exist): burn warms the grade, freeze desaturates, poison greens the vignette.

**Done when.** A player can see poison coming, and do something about it.

---

## §RG — Ranged

---

### RG-01 — Aim mode — **M**

**Files:** `apps/game/client/scripts/combat/weapon_controller.gd`,
`apps/game/client/scripts/camera/orbit_camera.gd`,
`apps/game/client/scripts/ui/combat_hud.gd`

**Problem.** `is_bow_aiming` is set (`PlayerInput.pressed(&"block")` or light attack) and read by
nothing. There is no reticle, no camera change and no visual difference between aiming and standing.

**Action.**
1. While `is_bow_aiming`: pull the camera in (`_lock_dolly`-style, ~0.8 m), narrow the FOV by 8°, and
   bias the shoulder offset so the aim line is clear.
2. Show a crosshair at the projected impact point (raycast along the aim direction, or the solved
   ballistic landing point from `PH-04`).
3. Draw a draw-strength arc around the crosshair that fills with `_draw_charge`.

**Solution.** Reuse `OrbitCamera`'s existing lock-on dolly and FOV machinery rather than adding a
second camera mode — add `set_aim_active(bool)` next to `set_lock_on_active(bool)` and let the two
compose.

**Done when.** Drawing a bow visibly changes the camera and shows where the arrow will land.

---

### RG-02 — Ammo without an ammo screen — **S**

**Files:** `apps/game/client/scripts/combat/weapon_controller.gd`,
`apps/game/client/scripts/ui/combat_hud.gd`

**Problem.** Bow shots cost only stamina, so a bow at range is strictly better than a melee weapon at
range with no trade-off. But a quiver with pickup management is a second inventory the game does not
want.

**Action.** Use a **recovering quiver**: `arrows_max` (12) that refills fully at a bonfire and by 1
every 6 s out of combat. Show it as a small pip row beside the heal charges. No pickups, no inventory
slot, no shop.

**Solution.** This is the smallest rule that makes the bow a *choice* rather than a default. Store it
on the player like heal charges (`PlayerHeal` is the template: charges, a signal, HUD pips, refill at
rest).

**Done when.** A bow build has to decide when to shoot.

---

### RG-03 — Enemy projectiles can be answered — **S** — `→ PH-04`, `EN-02`

**Files:** `apps/game/client/scripts/combat/enemy_projectile.gd`,
`apps/game/client/scripts/combat/shield_hurtbox.gd`, `apps/game/client/scripts/combat/guard.gd`

**Problem.** An arrow cannot be blocked by a raised shield in any meaningful way (it goes through the
normal hurtbox path and pays the standard block reduction, but the projectile is not stopped and does
not visibly interact with the shield), and it cannot be parried at all.

**Action.** On the `PROJECTILE` layer added in `PH-04`, give `Guard` an arc test against incoming
projectiles: a blocked projectile is destroyed with a spark; a **parried** one is destroyed with the
parry effect and refunds stamina.

**Done when.** Raising a shield against an archer works, and timing it perfectly feels great.

---

### RG-04 — Throwables in the quick slots — **S**

**Files:** `apps/game/client/scripts/inventory/consumable_service.gd`,
`apps/game/client/scripts/app/player_controls.gd`, `content/items/consumables/`

**Problem.** Quick slots hold consumables that heal or buff. There is no ranged option for a melee
build, so a melee player has no answer to an archer on a ledge.

**Action.** Add a `"throwable"` consumable kind: on use, spawn a `Projectile` with the item's damage,
status and radius, aimed via `_get_soft_lock_aim_direction()`. Author three: a firebomb, a poison
flask, a lure that draws aggro to a point.

**Done when.** A melee build can answer an archer without closing the distance.

---

## §IV — Loot and builds

---

### IV-01 — Behavioural coverage on gear — **M**

**Files:** `content/items/equipment/*.json`, `content/affixes/{prefixes,suffixes}.json`

**Problem.** 54 of 263 content files carry `rules`. The rest are pure stat lines, so most drops are a
number comparison rather than a decision.

**Action.** Bring behavioural coverage to **every legendary and aumbral item, and at least one
suffix per affix group**, using the effects added in `CB-06`. Target ~35 % of equipment carrying at
least one rule.

**Solution.** Write rules that change *what you do*, not *how much you do it*. Good: "on parry, your
next attack is unblockable". Bad: "on hit, +5 damage". The relic pool (`content/relics/`, 35 files,
e.g. `a_debt_of_breath`: −5 % damage, restore 26 stamina on kill) is the voice to copy — it is
already written by someone who understands this.

**Done when.** Picking up a legendary changes how the next room is played.

---

### IV-02 — Set bonuses — **M** — `→ CB-06`

**Files:** `apps/game/client/scripts/items/equipment.gd`,
`apps/game/client/scripts/inventory/inventory_service.gd`, `content/items/equipment/*.json`

**Problem.** Nine equipment slots, no reason to fill them from one family. Every slot is an
independent stat comparison.

**Action.** Add `"setId"` to equipment. In `InventoryService._sync_unique_rules()`, count equipped
pieces per `setId` and register a set's rules at 2/4/6 pieces from `content/items/sets.json` *(new)*.

**Solution.** Register set rules through the same `CombatEvents.register()` path with a source id of
`set/<id>/<tier>`, so unequipping unregisters cleanly — that mechanism already works for relics per
stack.

**Done when.** Wearing four castle pieces does something the four pieces alone do not.

---

### IV-03 — Talents that change verbs — **L**

**Files:** `content/talents/tree.json`, `apps/game/client/scripts/progression/progression_service.gd`

**Problem.** Ten branches × five nodes, every node a flat scalar (`physicalDamage +0.03`,
`maxHealth +15`). `ProgressionService._sync_keystone_rules()` exists and can register
`CombatEvents` rules from a talent — and **no node uses it**.

**Action.** Convert the fifth node of each branch into a keystone that carries `rules` rather than
`effects`. Ten keystones, one per branch, each changing a verb. Examples that fit the existing
systems: *Arms* — heavy attacks gain hyperarmor from 50 % charge; *Guard* — a just-guard refunds
stamina instead of costing it; *Aptitude* — the first chest on each floor rolls one rarity higher.

**Solution.** The rule shape is already validated by `CombatEvents.register()`, so a bad keystone
fails loudly at load. Keep every keystone to one rule.

**Done when.** Two level-40 characters with different keystones play differently.

---

### IV-04 — Wire the loot juice that already exists — **S**

**Files:** `apps/game/client/scripts/loot/loot_chest.gd`,
`apps/game/client/scripts/inventory/world_item_pickup.gd`,
`apps/game/client/scripts/loot/rarity_registry.gd`

**Problem.** `RarityRegistry` defines `drop_beam_height()`, `drop_beam_energy()`, `drop_sfx_id()`,
`wants_drop_toast()` and `wants_camera_nudge()` per rarity. Grep the call sites: most are unused. The
game has a designed loot-moment vocabulary and does not speak it.

**Action.** On every item that enters the world or the inventory, use them: a light beam at the drop
scaled by rarity, the rarity's SFX, a toast for rarities that want one, and a small camera nudge for
the top tiers.

**Done when.** A legendary drop is impossible to miss and a common one is silent.

---

### IV-05 — Salvage from the inventory, in the dungeon — **S**

**Files:** `apps/game/client/scripts/ui/inventory_ui.gd`,
`apps/game/client/scripts/items/forge_service.gd`

**Problem.** `ForgeService.salvage()` exists and is only reachable at the hub blacksmith. Mid-run, a
full 10×6 grid means `inventory_rejected("full")` and a warning banner, with no action available.

**Action.** Add a "Salvage" action button to the inventory's action row, available anywhere, yielding
materials at a reduced rate outside the hub (`SALVAGE_YIELD` × 0.6).

**Done when.** A full bag on floor 7 is a decision, not a dead end.

---

## §UX — Menus, screens and the things around the fight

Sixty-four UI scripts. `inventory_ui.gd` (1,659 lines) is the best of them and shows what the rest
should be: dual pointer/cursor input, drag ghost, comparison tooltips, rarity frames. Several other
screens are `ItemList`s.

---

### UX-01 — Four screens are flat list boxes — **L**

**Files:** `apps/game/client/scripts/ui/talents_ui.gd`,
`apps/game/client/scripts/ui/bestiary_ui.gd`,
`apps/game/client/scripts/ui/achievements_ui.gd`,
`apps/game/client/scripts/ui/loadout_ui.gd`

**Problem.** All four build a single `ItemList` and fill it with strings. The talent screen is the
worst case: `content/talents/tree.json` is a **tree** with ten branches and `requires` edges, and it
is rendered as a scrolling list of names. The player cannot see the shape of their build, cannot see
what a node leads to, and cannot compare branches.

**Action.**
1. **Talents** — draw the actual tree: ten branch columns, nodes as pixel-framed cells, `requires`
   edges as lines, rank pips, locked nodes dimmed with their blocker named (`ProgressionService.blocked_by()`
   already returns it). Keyboard/pad navigation along edges. This is the highest-value screen rewrite
   in the game and it becomes essential once `IV-03` adds keystones.
2. **Bestiary** — a grid of enemy portraits (reuse `CharacterSkin.build_enemy_body` into a
   `SubViewport`, as `warden_preview_rig.gd` already does for the player), tier progress rings, and
   the progressive reveal `BestiaryService.get_revealed()` already computes.
3. **Achievements** — a grid of icons with locked/unlocked states and progress bars, grouped by
   category.
4. **Loadout** — show the weapon models (`DioramaWeaponKit.build()` exists) and their archetype
   identity from `CB-05`, not a list of names.

**Solution.** All four already have the data; only the presentation is a list. Build them out of
`GameUISkin.make_pixel_frame` + a `GridContainer`, and reuse `inventory_ui.gd`'s
`InputMode.POINTER`/`CURSOR` model rather than inventing a third input pattern.

**Done when.** No screen in the game that represents a structure renders it as a flat list.

---

### UX-02 — The talent tree cannot express a build — **M** — `→ UX-01`, `IV-03`

**Files:** `apps/game/client/scripts/ui/talents_ui.gd`,
`apps/game/client/scripts/progression/progression_service.gd`

**Problem.** Beyond presentation: `unlock_talent()` is one-way except through a 250-gold blacksmith
respec, there is no preview of what a node does before you spend, and there is no way to plan.

**Action.** Add a **preview mode**: hovering a node shows the stat delta against the current build,
and a "planned" state lets the player queue several nodes before committing. Add a free respec on the
first three levels after a new node unlocks, so experimenting is not punished.

**Done when.** A player can plan two levels ahead without spending.

---

### UX-03 — Shops and services are lists of names — **M**

**Files:** `apps/game/client/scripts/ui/merchant_ui.gd`,
`apps/game/client/scripts/ui/blacksmith_ui.gd`, `apps/game/client/scripts/ui/storage_ui.gd`

**Problem.** `merchant_ui.gd` (205 lines) and `storage_ui.gd` (179) present items as text rows, while
the inventory next door presents them as rarity-framed icon cells with comparison tooltips. The same
item looks like two different things depending on which panel it is in. `blacksmith_ui.gd` (581) is
richer but still text-forward for upgrade previews.

**Action.** Extract the inventory's cell renderer into a shared `ui/item_cell.gd`
(icon + rarity frame + stack + upgrade badge + durability bar) and use it in all four panels. Show
the same comparison tooltip (`InventoryService.format_slot_tooltip_bbcode()` already produces it)
everywhere an item appears.

**Done when.** An item looks identical in the inventory, the shop, the stash and the forge.

---

### UX-04 — Dialogue is a text box — **S**

**Files:** `apps/game/client/scripts/ui/dialogue_ui.gd`,
`apps/game/client/scripts/dialogue/dialogue_runner.gd`

**Problem.** 176 lines: a speaker label, a text label, a choices box, a hint. 46 dialogue trees with
conditions and relationship tracking run through it, and the presentation gives the writing nothing —
no portrait, no name plate, no typewriter reveal, no indication that a choice is gated by a
relationship level.

**Action.** Add a portrait (the NPC's own rig into a `SubViewport`), a pixel name plate, a typewriter
reveal that a press completes, and a visible marker on choices gated by a flag or relationship —
`DialogueConditions.evaluate()` already knows.

**Done when.** Talking to an NPC looks like it was written on purpose.

---

### UX-05 — The stair menu is the most important decision in the run and it is a list — **S** — `→ AD-08`

**Files:** `apps/game/client/scripts/ui/stair_menu.gd`,
`apps/game/client/scripts/dungeon/stair_lever.gd`

**Problem.** `stair_lever.floor_options()` builds descent-pact offers, ascend, descend and retreat as
**label strings** — including the pact description, which is the run's biggest fork — and
`stair_menu.gd` (140 lines) renders them as buttons.

**Action.** Render pacts as **cards** with the same treatment `relic_offer_ui.gd` gives relics (which
is good: 320×360 cards, gives/takes colouring, event labels). Show the pressure bar from `AD-08`
alongside.

**Done when.** Choosing a pact looks as considered as choosing a relic.

---

### UX-06 — Loading and transitions — **S**

**Files:** `apps/game/client/scripts/ui/loading_screen.gd`,
`apps/game/client/scripts/app/scene_transition.gd`

**Problem.** `SceneTransition` is solid (threaded load, progress bar, watchdog, builders report
progress). `loading_screen.gd` is 63 lines and shows a label. Floor loads spend up to ~1 s in
`LocalProcgen`'s salt retries (`RM-12`) with nothing to look at.

**Action.** Show, on the floor-transition screen: the floor number, the biome name, its floor theme
label, a lore line from `content/dungeons/<id>.json`, and the run contract's top objective
(`AD-01`). A loading screen is free reading time.

**Done when.** A floor load teaches the player something.

---

### UX-07 — Settings needs a shape — **S** — `→ SY-05`, `HD-03`

**Files:** `apps/game/client/scripts/ui/settings_ui.gd`,
`apps/game/client/scripts/ui/settings_schema.gd`

**Problem.** The schema-driven settings screen is well built, but after `HD-03` and `SY-05` it will
carry five resolution presets, three quality presets and the full pixel tuning block. A flat list of
every option is already long.

**Action.** Group into five tabs — Display, Graphics, Audio, Controls, Accessibility — and put the
three quality presets at the top of Graphics with the tuning block collapsed behind "Advanced".

**Done when.** A new player can change what they need without scrolling past `shade_dither`.

---

### UX-08 — Character creation should preview the fight — **S** — `→ SY-04`, `CB-05`

**Files:** `apps/game/client/scripts/ui/character_create_ui.gd`,
`apps/game/client/scripts/ui/class_card.gd`,
`apps/game/client/scripts/ui/warden_preview_rig.gd`

**Problem.** The creation screen has a live preview rig, appearance options and stat ratings. What it
does not show is how the class *plays*: its starting weapon's archetype, its perk in action, its
talent branch.

**Action.** Add to the class card: the weapon archetype row (`SY-04`), the perk stated as a verb, and
a one-line "plays like" summary. Have the preview rig hold the class's starting weapon
(`DioramaWeaponKit.build()` with `startingWeaponItemId`).

**Done when.** The class you pick is the class you expected to be playing.

---

### UX-09 — Menu consistency audit — **S** — `→ AX-02`

**Files:** `apps/game/client/scripts/ui/menu_shell.gd`,
`apps/game/client/scripts/ui/menu_stack.gd`, all `ui/*_ui.gd`

**Problem.** `MenuShell.build_modal()` and `MenuStack` give every panel a consistent shell, and most
screens use them — but the ones that build their own (`quest_board_ui.gd`, `loadout_ui.gd`,
`umbral_*_menu.gd`) drift on escape handling, initial focus and backdrop.

**Action.** Walk every panel and assert five things: it pushes and pops `MenuStack`, `ui_cancel`
closes it, it grabs an initial focus, it has a backdrop, and closing it restores mouse capture via
`PlayerControls.capture_mouse_if_allowed()` (never a bare `Input.mouse_mode = CAPTURED`).

**Done when.** Every panel opens, closes and focuses the same way.

---

### UX-10 — The toast and notification layer — **S** — `→ HD-02`

**Files:** `apps/game/client/scripts/ui/achievement_toast.gd`,
`apps/game/client/scripts/ui/combat_hud.gd`

**Problem.** Achievements toast through their own scene; run warnings, XP grants, depth records,
milestones and vault unlocks all go through `show_run_warning()`; loot toasts are specified in
`RarityRegistry.wants_drop_toast()` and not implemented. Four notification paths, three of them
sharing one banner.

**Action.** One notification service with a queue and three lanes — **banner** (top centre, one at a
time, from `HD-02`), **toast** (top right, stacked, achievements and loot), **inline** (the HUD
warning slot for gameplay errors like "inventory full").

**Done when.** Three things happening at once produce three legible notifications, not one
overwritten banner.

---

## §AD — The addiction loop

**This section answers the owner's "CRITICAL: addictive gameplay is a must."**

The single most important finding for this section: **the systems are already built.** Vault unlocks,
bounties, weekly challenges, bestiary tiers, hub growth, descent tokens, run history, achievements,
mode unlocks, failure hotspots, repeat-run — all exist, all work, and almost none of them are visible
where the player makes a decision. The work here is *surfacing and pacing*, not building.

A roguelite is addictive when four loops all close, at four different timescales:

| Loop | Length | Question it answers | Where it lives now |
|---|---|---|---|
| **Encounter** | 5–40 s | "can I beat this room?" | §EN, §PH, §CB — P1 |
| **Run** | 15–40 min | "how far can I get *this time*?" | `AD-01`…`AD-03` |
| **Session** | 1–3 h | "what am I doing today?" | `AD-04`…`AD-06` |
| **Account** | weeks | "what am I still missing?" | `AD-07`…`AD-08` |

---

### AD-01 — The run contract: state the goal at the start — **M**

**Files:** `apps/game/client/scripts/ui/castle_entry_menu.gd`,
`apps/game/client/scripts/ui/umbral_endless_menu.gd`,
`apps/game/client/scripts/ui/umbral_waves_menu.gd`, `apps/game/client/scripts/app/run_flow.gd`

**Problem.** A run begins with no stated goal beyond "descend". Everything the game *could* promise
— an active bounty, the weekly challenge, the next vault unlock, a bestiary tier two kills away, the
depth record to beat — is computed and sits behind other menus. A player pressing "Descend" has no
answer to "why this run".

**Action.** Build a **run contract card** shown on the entry menu of every mode, listing 3–5 live
objectives drawn from the systems that already exist:
1. Any active bounty whose progress can advance in this mode (`BountyService.active_bounties()` +
   `QuestService`).
2. The weekly challenge if this run qualifies (`ChallengeService.get_active_challenge()`).
3. The record to beat (`RunHistoryService.best_depth/best_time` scoped to this mode+dungeon).
4. The nearest vault unlock and its shortfall (`VaultService` + `ProgressCounters.shortfall()`).
5. The nearest bestiary tier (`BestiaryService.kills_to_next_tier()` over the biome's `enemyPool`).

**Solution.** Compute all five in one place — add `run_flow.gd:build_run_contract(mode, dungeon_id,
tier) -> Array[Dictionary]` returning `{icon, text, progress, target}` — and have all three entry
menus render the same card. One source, three consumers.

**Trap.** Cap the card at five lines and sort by *closeness to completion*, not by category. A card
listing everything is a wall; a card listing the three things you are about to finish is a hook.

**Done when.** Every entry menu answers "what am I chasing" before the run starts.

---

### AD-02 — Reward cadence inside a run — **M**

**Files:** `apps/game/client/scripts/dungeon/castle_run.gd`,
`apps/game/client/scripts/dungeon/descent_pact_service.gd`,
`apps/game/client/scripts/combat/run_buffs.gd`, `content/progression/room_pacing.json`

**Problem.** The run's build-defining decisions arrive too rarely. A relic offer is **one per
ten-floor block** (`castle_run.gd`: offered only when `RunFloorConfig.floor_within_block() == 1`), and
descent pacts are offered only at the stair. A tier-1 run is ten floors with **one** relic choice, so
nine of ten floors change nothing about how you play.

**Action.** Retune to a rhythm the player can feel:
- **Every floor** offers something: a descent pact at the stair (already true) *or* a relic offer.
- **Every boss** offers a relic (three choices, tag-weighted — `RunBuffs.roll_offer()` already does
  the synergy weighting at `SYNERGY_MULTIPLIER` 1.75, cap 4.0).
- **Every rest room** offers a small choice: refill flask, or trade a flask charge for a temporary
  buff to the next floor. (`rest_at_bonfire` already refills; add the alternative.)
- **Every third floor** guarantees one `merchant` room (raise `weight_merchant` from 0.01 and add a
  guarantee alongside `min_reward_rooms` in `_enforce_pacing`).

**Solution.** The target rhythm: a meaningful choice roughly every 3–5 minutes. Measure it — play a
tier-1 run with a stopwatch and count the decisions. If the gap ever exceeds 6 minutes, the floor in
that gap is the one to change.

**Done when.** A ten-floor run contains 8–12 build decisions rather than 1.

---

### AD-03 — Make floor themes visible — **S**

**Files:** `apps/game/client/scripts/ui/combat_hud.gd`,
`apps/game/client/scripts/dungeon/run_modifier_service.gd`, `content/progression/room_pacing.json`

**Problem.** `room_pacing.json:floorThemes` rolls a theme per floor (`ambush` multiplies combat by
1.6, traps by 1.4, rest by 0.5, and carries the label "Something is waiting in these halls"). The
label is passed to `show_region_title` as a subtitle for 3.2 s and then gone. `RunModifierService`
modifiers (`hostile_halls`, `fog_of_war`, `sealed_doors`, `frenzied_foes`, …) are similarly invisible
once the banner fades.

**Action.** Add a persistent modifier strip: small pixel icons under the minimap, one per active
floor theme and run modifier, with a tooltip. Populate it from `RunModifierService.active()` and the
definition's `floorTheme` at floor entry.

**Solution.** This is the cheapest legibility win in the plan. The generator already varies floors
meaningfully; the player currently cannot tell that it does, which means the variety does not exist
for them.

**Done when.** A player can look at the HUD and say "this floor is the ambush one".

---

### AD-04 — Surface the session layer in the hub and main menu — **M**

**Files:** `apps/game/client/scripts/hub/hub.gd`, `apps/game/client/scripts/ui/tower_board_ui.gd`,
`apps/game/client/scripts/ui/main_menu.gd`

**Problem.** Bounties (3 daily + 1 weekly), the weekly challenge, hub growth standing and mode
unlocks are all behind the quest board or the tower board — two clicks and a walk from where the
player stands when they load the game.

**Action.**
1. Add a "today" line to the main menu under Continue: `"3 bounties · weekly challenge resets in
   2d 4h"`, computed from `BountyService` and `ChallengeService.format_remaining()`.
2. In the hub, put a physical board near the spawn point showing the same, using the existing
   `HubInteractable` highlight so it reads as a place, not a menu.
3. When a bounty completes mid-run, show it through the HUD warning banner immediately, not at the
   results screen.

**Done when.** Loading the game tells you what today's reasons to play are, before you press
anything.

---

### AD-05 — The results screen must point forward — **S**

**Files:** `apps/game/client/scripts/ui/results_screen.gd`

**Problem.** The results screen is strong (loot row, run report, personal bests, vault unlocks,
"Descend again" focused first) but it is entirely **retrospective**. The most valuable line on a
roguelite end screen — *what you are close to* — is missing.

**Action.** Add a "Next" block above the buttons with 1–3 lines, each a near-miss or a next step:
`"Two floors deeper unlocks the Long Dark."` / `"Six more castle grunts masters their bestiary
entry."` / `"180 gold from the next blacksmith unlock."` Reuse `ProgressCounters.shortfall()` and
`VaultService.describe_progress()`.

**Solution.** Rank by smallest shortfall and show at most three. A near-miss the player can act on in
the next fifteen minutes is the hook; a distant goal is noise.

**Done when.** The results screen makes the case for the next run before the player decides.

---

### AD-06 — Death recap — **S** — `→ EN-01`

**Files:** `apps/game/client/scripts/app/run_flow.gd`, `apps/game/client/scripts/ui/results_screen.gd`

**Problem.** `_record_failure_point()` stores a label and `get_failure_hotspots()` surfaces recurring
causes across runs, which is genuinely good. But the *individual* death is summarised as "You fell at
X" with no account of what happened.

**Action.** Capture, at death: the killing enemy id, its attack id and `attackClass`, whether the
player was blocking/dodging/attacking at the time, and their health before the killing blow. Render
one sentence: `"A Castle Knight's High Cleave (unblockable) killed you while you were blocking."`

**Solution.** Everything needed is already flowing through `Hurtbox.receive_hit()`. Store the last
inbound `DamageInfo` on `PlayerCombatReactions` and read it in `on_player_died()`.

**Trap.** A death sentence that reads as blame is bad; one that reads as information is good. Name
what happened; never say "you should have".

**Done when.** Every death tells you what killed you and what you were doing.

---

### AD-07 — The first hour — **M**

**Files:** `apps/game/client/scripts/hub/hub_tutorial_service.gd`, `content/hub/tips.json`,
`apps/game/client/scripts/ui/combat_hud.gd`

**Problem.** Onboarding is a tip queue in the hub plus a control-hint row that auto-hides after 60 s
once the player has used dodge, jump, lock-on and inventory. Nothing teaches the *combat model* —
telegraph classes, parry, poise, backstab, stamina — which is the thing that makes the game
comprehensible.

**Action.** Add a contextual teaching pass that fires **once per account**, triggered by the event
rather than by a menu:
- First telegraph seen → freeze-frame hint naming the colour ("Amber: this can be blocked").
- First blue telegraph → "Blue: this can be parried. Raise your guard as it lands."
- First red telegraph → "Red: this cannot be blocked. Move."
- First poise break dealt → "Broken. Attack now for an execution."
- First stamina exhaustion → "Out of stamina. You cannot dodge."
Each shows once, in the HUD warning slot, and is recorded as a `CharacterService` flag.

**Solution.** Use the training arena (`scenes/combat/combat_arena.tscn` has the machinery; the hub has
a training dummy) as the safe place to trigger the first three deliberately.

**Done when.** A new player who has never played a soulslike can explain what the three colours mean
after ten minutes.

---

### AD-08 — Endless as the long game — **S**

**Files:** `apps/game/client/scripts/ui/umbral_endless_menu.gd`,
`apps/game/client/scripts/dungeon/stair_lever.gd`,
`apps/game/client/scripts/progression/progression_service.gd`

**Problem.** Endless already has the best-designed decision in the game: `EndlessDifficulty`'s Waning
(past floor 150 an unbounded difficulty term is added, so every run must end) combined with the
stair menu's bank-or-descend choice and `describe_pressure()`. It is shown as a line of text in a
menu.

**Action.**
1. Show the pressure curve graphically on the stair menu: a small bar of "what the next floor costs"
   versus "what you have banked".
2. Show the personal-best depth as a marker on that bar.
3. Show descent tokens earned this run and the next milestone
   (`ProgressionService.get_endless_depth_data()`).

**Done when.** The decision to take one more floor feels like a bet with visible odds.

---

## §VS — Visual style, lighting and performance

The owner asked for **pixel/voxel graphics**. The pipeline for it is complete and largely switched
off or under-used. `docs/GAME_FEEL_REVIEW.md`'s screenshot critique — "everything is midtone", "no
true blacks, no bright highlights", "nothing is crisp" — maps entirely onto this section.

---

### VS-01 — The value range is compressed — **M** — `→ HD-03`

**Files:** `content/art/lighting.json`, `apps/game/client/scripts/art/lighting/visual_lighting.gd`,
`apps/game/client/scripts/art/pipeline/pixel_diorama_settings.gd`

**Problem.** Twelve lighting profiles are authored (`hub`, `arena`, `waves_outdoors`, `waves_arena`,
`castle_interior` and one per biome) each with `ambient`, `atmosphere`, `fill`, `fog`, `key_light`,
`sky`, `sun`, `torch` — so the system is real. What the captures show is that the *result* sits in a
narrow value band: no true black, no bright highlight except a gold path, and the player, the enemies
and the floor all read at the same value.

**Action.**
1. Set a **value target per profile** and check it: the darkest 10 % of pixels below 0.08 luminance,
   the brightest 5 % above 0.85. Add the measurement to
   `res://scenes/debug/capture_world_screens.tscn` so it prints a histogram per capture.
2. Push ambient down and key/torch up per profile until the target is met. `PixelDioramaSettings`
   already has `shade_bands` (8) and `color_levels` (16) — a compressed range wastes most of those
   bands on midtones.
3. Give the player character a **rim light** that keys off the camera, so the thing the player looks
   at 100 % of the time separates from the floor at every value.

**Solution.** The single most effective change is contrast, not colour. Pixel art reads because its
palette is small **and its value steps are wide**; 16 colour levels across a narrow range is a muddy
gradient with extra steps.

**Done when.** Every capture's histogram meets the target and the warden is legible against every
floor.

---

### VS-02 — Nothing is crisp — **M** — `→ HD-03`, `AN-01`

**Files:** `apps/game/client/scripts/art/pipeline/pixel_diorama_viewport.gd`,
`apps/game/client/scripts/art/pipeline/pixel_camera_snap.gd`,
`apps/game/client/scripts/art/pipeline/pixel_diorama_settings.gd`

**Problem.** The pipeline is configured correctly — integer stretch, nearest filtering,
`snap_2d_transforms_to_pixel`, camera origin and basis snapping — and the result still reads as a
soft upscale. With `HD-03` adding real low-res presets, the internal resolution will finally be below
native and the remaining softness sources become visible: anti-aliasing inside the SubViewport
(`anti_aliasing_off` is a *setting*, so it is not always off), mipmaps on world textures, and
sub-pixel camera drift between the snap and the render.

**Action.**
1. Force `anti_aliasing_off` on whenever `low_res_viewport_enabled` is true, and remove the option
   from the UI in that mode — they are mutually exclusive by definition.
2. Audit every texture import for nearest filtering and mipmaps off.
3. Verify `PixelCameraSnap.snap_origin_to_view()` runs **after** all camera effects
   (`_apply_camera_effects_transform` writes `h_offset`/`v_offset` in `_process`) — a shake applied
   after the snap re-introduces sub-pixel motion, and shake is exactly when crispness matters most.

**Done when.** A 4× zoom of a still frame shows hard pixel edges.

---

### VS-03 — Give each biome a palette identity — **M**

**Files:** `content/art/palettes.json`,
`apps/game/client/scripts/art/style/pixel_diorama_style.gd`

**Problem.** `PixelDioramaStyle` has palette themes per biome and tile atlases, so the machinery is
there. The captures show the same problem as the generator (`RM-13`): the biomes differ in hue and
not in *structure* — same value distribution, same accent placement, same number of colours.

**Action.** Give each biome palette a deliberate identity: a dominant hue, one accent that appears
nowhere else, a value range (the swamp is low-contrast and murky; the vault is high-contrast and
metallic; the prism is saturated), and a distinct light temperature. Author it as a table so the
biomes can be compared side by side.

**Done when.** A one-colour swatch strip per biome is recognisably ten different places.

---

### VS-04 — The dungeon looks unfinished in the one place it matters — **M** — `→ RM-11`, `RM-16`

**Files:** `apps/game/client/scripts/dungeon/diorama_room_dressing.gd`,
`apps/game/client/scripts/art/props/diorama_prop_factory.gd`

**Problem.** `docs/GAME_FEEL_REVIEW.md` calls the dungeon slice "the weakest image, and honestly the
one that would stop me buying": a flat untextured grey rectangle where a doorway should be, a brown
noise panel that reads as a missing material. `RM-16` gives doorways frames and `RM-11` raises prop
density; this item is the material pass that goes with them.

**Action.** Audit every material a dungeon room can show: floor, wall, ceiling, accent, door frame,
gate, chest, lever, bonfire, lectern, banner, pillar, sconce, rubble. Each must (a) come from
`BiomeRegistry`, (b) carry the biome palette, and (c) never render as Godot's default grey. Add an
assertion to `res://scenes/debug/scene_sweep.tscn`: fail if any `MeshInstance3D` in a built floor has
a null `material_override` **and** a null surface material.

**Done when.** `scene_sweep` reports zero unskinned meshes on a built floor in every biome.

---

### VS-05 — Character silhouettes do not read — **M**

**Files:** `apps/game/client/scripts/art/characters/diorama_character_skin.gd`,
`apps/game/client/scripts/art/characters/equipment_model_kit.gd`,
`art-source/characters/`

**Problem.** The review's sharpest line is about the player: "a grey blob with a brown skirt and a
strange blue disc through the shoulders. I cannot tell what class they are, what they are holding, or
which way they are facing." The rig system supports far more than that — nine equipment slots with
procedural voxel models, per-class garments, five frames, hair and face options.

**Action.**
1. **Facing** — give every character a front/back asymmetry that reads at gameplay distance: a
   different chest value, a cloak or a belt at the back, a face plate at the front.
2. **Class** — make the class garment silhouette-distinct, not just recoloured: the berserker is
   broad-shouldered, the rogue is narrow and hooded, the scholar has long robes.
3. **Weapon** — the held weapon must be visible in silhouette from behind the camera. `DioramaWeaponKit`
   builds real models; check their scale against the rig at the default camera distance.
4. Verify with `res://scenes/debug/capture_warden_variants.tscn` and
   `equipment_visual_audit.gd`, both of which exist for this.

**Done when.** A black-silhouette screenshot of five classes is five recognisable shapes.

---

### VS-06 — Enemy silhouettes must match their behaviour — **M** — `→ EN-10`

**Files:** `apps/game/client/scripts/art/characters/diorama_character_skin.gd`,
`apps/game/client/scripts/art/characters/character_rig_catalog.gd`, `content/characters/` (21)

**Problem.** `CharacterSkin.profile_for_enemy_data()` picks the rig from `enemy_type`, and
`enemy_type` has five values (`EN-10`). So 54 enemies share five silhouettes, and after `EN-10` adds
three new types they will share eight. The behaviour and the shape must agree or the whole read-the-
enemy loop fails before it starts.

**Action.** Give each of the eight types a distinct silhouette rule (the swarm is small and low, the
flyer has no legs and a wide profile, the caster is tall and thin with a raised implement, the shield
is wide and flat-fronted), and give each biome a shape motif on top — crystal growths, iron plating,
fungal blooms — applied by `build_enemy_body` from the biome theme.

**Done when.** A player can name what an enemy does from its outline at 20 m.

---

### VS-07 — VFX budget and readability — **S**

**Files:** `apps/game/client/scripts/art/vfx/vfx_service.gd`, `content/vfx/effects.json`

**Problem.** `VfxService` is well built — pooled CPU and GPU bursts, decals, ribbons, trails,
telegraph glyphs, a time-scale stack. The risk this plan creates is volume: `PH-01` adds impact
effects, `EN-04` adds glyphs, `RM-07` adds fog gates, `IV-04` adds drop beams. A fight with six
enemies must stay readable.

**Action.**
1. Give the pools a hard priority: telegraphs and intent glyphs are **never** culled; hit sparks,
   decals and embers are culled first under load.
2. Honour `PixelDioramaSettings.particle_amount_scale()` everywhere (it exists; check every
   `_play_burst_layer` path uses it).
3. Measure with `res://scenes/debug/perf_audit.tscn` in a six-enemy fight before and after each §PH
   and §EN item.

**Done when.** A six-enemy fight at the Performance preset holds frame rate and every telegraph is
still visible.

---

### VS-08 — A performance budget, written down — **M** — `→ SY-05`

**Files:** `apps/game/client/scripts/tools/perf_audit.gd`,
`apps/game/client/scripts/tools/draw_call_probe.gd`, `docs/validation/manual-checklist.md`

**Problem.** Two performance tools exist and there is no stated budget, so "is this slower" has no
answer. This plan adds knockback, sweeps, stepped animation, more props, more VFX, more UI and round
rooms — all of which cost something.

**Action.** Set and record a budget: frame time at the Balanced preset on a 28-room floor with six
active enemies; draw calls per floor; script time per frame; particle count. Measure **now**, before
P1, and record the baseline in `docs/validation/manual-checklist.md`. Re-measure at the end of each
phase.

**Solution.** Without a baseline taken before the work, every later regression is unattributable.
This item is cheap and it must be done **first** — do it alongside P0.

**Done when.** `manual-checklist.md` carries a before/after table per phase.

---

### VS-09 — The camera needs a set-piece vocabulary — **S** — `→ BS-02`, `CB-04`

**Files:** `apps/game/client/scripts/camera/orbit_camera.gd`,
`apps/game/client/scripts/combat/weapon_controller.gd`

**Problem.** `OrbitCamera` has punch, shake, landing dip, FOV kick, sprint FOV, lock-on framing and a
death framing — a good vocabulary for *reactions*, and nothing for *moments*. An execution
(`CB-04`), a riposte, a boss entrance (`BS-02`) and a secret reveal all pass with the camera exactly
where it was.

**Action.** Add three composable framings, each short and each skippable:
`play_execution_framing(target)` (0.6 s, pull in and slightly orbit), `play_reveal_framing(point)`
(0.8 s, look at a secret or an opened gate), and `play_intro_framing(target, duration)` (`BS-02`).
Route all three through the existing `_lock_dolly` and pitch-bias machinery rather than taking over
the transform.

**Trap.** Never move the camera during player-controlled combat except for the execution framing,
which happens during i-frames. A camera that moves while the player is fighting is a bug, not a
flourish.

**Done when.** An execution is filmed, and it never costs the player control.

---

## §AU — Audio

---

### AU-01 — Replace the eleven placeholder SFX — **M**

**Files:** `content/audio/sfx.json`, `apps/game/client/assets/audio/`

**Problem.** `door_open`, `door_release`, `door_seal`, `footstep_snow`, `footstep_stone`,
`footstep_water`, `footstep_wood`, `lever_pull`, `lever_unlock`, `portal_enter`, `portal_open` are
synthesised tones flagged `"placeholder": true`, and `AudioDirector._report_placeholder_sfx()` warns
about them on every boot. Four of the eleven are footsteps — the sound the player hears most.

**Action.** Author or source eleven cues, prioritising the four footsteps. Remove the `placeholder`
flag as each lands; the warning list is the checklist.

**Done when.** `AudioDirector` boots with no placeholder warning.

---

### AU-02 — Impact audio that carries information — **M** — `→ EN-01`, `PH-01`

**Files:** `apps/game/client/scripts/combat/hit_feedback.gd`, `content/audio/sfx.json`

**Problem.** `HitFeedback._play_hit_sfx()` picks between `"hit"` and `"hit_armor"` by checking whether
the enemy id **contains the substring** `"shield"` or `"knight"`. That is the entire material model.

**Action.** Add `"hit_material"` to enemy definitions (`flesh`, `armour`, `stone`, `crystal`, `bone`,
`ooze`) and cue from it. Add a distinct cue per `ImpactClass`, and a distinct cue for a hit that
breaks poise.

**Done when.** You can tell what you hit and how hard, with the screen off.

---

### AU-03 — Stingers on the beats that matter — **S**

**Files:** `apps/game/client/scripts/audio/audio_director.gd` and the callers of the events below

**Problem.** `play_stinger()` exists and is used for `boss_reveal` only. The moments a roguelite
needs to punctuate — secret found, key taken, lock opened, shortcut opened, floor cleared, rare drop,
personal best — pass in silence.

**Action.** Add one stinger per beat and fire it where the flag is already set
(`WorldFlags.secret_opened`, `key_held`, `lock_opened`, `door_opened`, `room_cleared`).

**Done when.** Finding a secret sounds like finding a secret.

---

### AU-04 — Enemy voice tied to attack class — **S** — `→ EN-01`

**Files:** `apps/game/client/scripts/enemies/castle_enemy_base.gd`, `content/enemies/*.json`

**Problem.** `_enter_windup()` plays a single global `"windup"` cue for every attack of every enemy.
Audio carries none of the read that the colour and the shape carry.

**Action.** Cue from `attackClass`: a rising tone for `parryable`, a low growl for `unblockable`, a
short grunt for `blockable`, a shout for `grab`. Add an optional per-enemy `"voice"` prefix so a
biome can sound distinct.

**Done when.** A player facing away can tell an unblockable is coming.

---

## §AX — Accessibility and input

---

### AX-01 — Telegraph shape, not just colour — **S** — `→ EN-04`

**Files:** `apps/game/client/scripts/accessibility/accessibility_settings.gd`,
`apps/game/client/scripts/art/vfx/vfx_service.gd`

**Problem.** `get_telegraph_class_color()`'s own comment states the problem: the three classes "are
told apart by tint alone, since the shape of a telegraph says where the attack lands rather than what
kind it is." `EN-04` fixes this with a head glyph; the ground ring is still colour-only.

**Action.** Add a per-class ring **pattern**: solid for blockable, dashed for parryable, and a
double ring for unblockable. Honour `assist_telegraph_emphasis` by thickening the rim.

**Done when.** A greyscale screenshot of a fight still reads correctly.

---

### AX-02 — Controller parity audit — **S**

**Files:** `apps/game/client/scripts/ui/*.gd`, `apps/game/client/scripts/app/input_bindings.gd`

**Problem.** The inventory has an explicit dual input model (`InputMode.POINTER` / `CURSOR`) which is
excellent; other screens vary. `InputBindings.KEYBOARD_ONLY` exists, implying some actions have no
pad binding.

**Action.** Walk every screen on a pad only: main menu, character create, continue, castle entry,
endless, waves, tower board, quest board, inventory, talents, blacksmith, merchant, storage,
settings, results, pause, stair menu, relic offer, map overlay. Fix focus order and initial focus.

**Done when.** The whole game is playable from a pad with the mouse unplugged.

---

### AX-03 — Input glyph coverage — **S**

**Files:** `apps/game/client/scripts/ui/input_glyph_service.gd`, `content/ui/input_glyph_atlas.json`

**Problem.** Prompts built in `RM`/`HD` items will ask for glyphs for actions that may not be in the
atlas (`two_hand`, `weapon_art`, `map`, `quick_slot_cycle`).

**Action.** Audit `project.godot`'s 44 actions against the atlas; add any missing cell.

**Done when.** No prompt anywhere renders a fallback box.

---

### AX-04 — Text scale and subtitle pass — **S** — `→ HD-03`

**Files:** `apps/game/client/scripts/ui/ui_text_scale.gd`,
`apps/game/client/scripts/ui/game_ui_skin.gd`

**Problem.** `build_scaled_theme()` scales font sizes but panels are sized from constants
(`PANEL_HALF_W` 690, `MENU_HALF_W` 345). At a large text scale with the pixel theme on, text will
overflow fixed panels.

**Action.** After `HD-03`, re-walk every screen at text scale 1.0, 1.25 and 1.5 and make the panels
that clip use `clamped_panel_half_size()`.

**Done when.** Nothing clips at 1.5× text scale.

---

## §MD — Mode depth: the Vigil, the Long Dark, and the tier ladder

§HD makes the three modes *consistent*. This section makes them *different from each other* — which
is the only reason to ship three.

---

### MD-01 — The Vigil is one arena for fifty waves — **L**

**Files:** `apps/game/client/scripts/dungeon/waves_run.gd`,
`apps/game/client/scripts/dungeon/waves_run_service.gd`, `content/waves/umbral_waves.json`

**Problem.** `content/waves/umbral_waves.json` sets `finalWave` 50, `intermissionEvery` 5,
`bossEvery` 10, `cashOutFromWave` 20 — a good shape. What runs inside it never changes: the same
210-unit walled arena, the same eight chests in a ring of radius 7.5, the same spawn ring of radius
24. Wave 3 and wave 47 are the same space with more enemies.

**Action.**
1. **Arena mutation per intermission block.** Every fifth wave, change the arena: raise a central
   platform, drop pillars, flood a quadrant with a hazard, kill half the torchlight. Build each from
   `WavesOutdoorsDiorama` + `ArenaHazard`; author five in
   `content/waves/umbral_waves.json:arenaStates`.
2. **Wave modifiers.** Reuse `RunModifierService`: from wave 10, each wave rolls one modifier from a
   small pool (`frenzied_foes`, `armoured_foes`, `fog_of_war`, `relentless_foes`) and the HUD shows it
   (`AD-03`).
3. **Spawn variety.** `_spawn_point_for()` always uses the edge ring. Add two more patterns:
   converge (all from one side, so the player must reposition) and scatter (spread but simultaneous).
4. **A reason to move.** Put the cresset's light on a timer so standing in one corner goes dark.

**Solution.** The Vigil's fantasy is a siege you are losing slowly. Every fifth wave should take
something away — light, space, ground — not just add enemies.

**Done when.** Wave 45 is a different fight from wave 5, not a longer one.

---

### MD-02 — The Vigil's extraction decision needs teeth — **M**

**Files:** `apps/game/client/scripts/dungeon/waves_run_service.gd`,
`apps/game/client/scripts/dungeon/waves_cash_out_portal.gd`,
`apps/game/client/scripts/ui/waves_run_ui.gd`

**Problem.** The mode is an extraction roguelite: you start with nothing, loot chests into a
run-local 8×5 grid, and from wave 20 an intermission portal lets you bank **exactly one** item. That
is a genuinely good hook and the presentation gives it nothing — the choice is a list of item names
in a panel.

**Action.**
1. Show the cash-out choice as item **cards** with the full tooltip and rarity frame (`UX-03`).
2. Show what you are risking: "bank 1 of 7 — the other 6 are lost if you fall".
3. Scale the offer with depth: from wave 30 bank two, from wave 40 bank three. The escalating offer is
   what makes staying tempting rather than merely greedy.
4. Show a running "best Vigil" marker (`RunHistoryService`) so the decision has a benchmark.

**Done when.** Walking to the portal at wave 25 feels like a decision with a number attached.

---

### MD-03 — The Long Dark's tension is a line of text — **S** — `→ AD-08`

**Files:** `apps/game/client/scripts/dungeon/endless_difficulty.gd`,
`apps/game/client/scripts/dungeon/skip_floor_service.gd`,
`apps/game/client/scripts/ui/umbral_endless_menu.gd`

**Problem.** `EndlessDifficulty` is the best-designed piece of maths in the project: soft caps at
4.5× health and 3.0× damage with a knee at floor 120, then **the Waning** — an unbounded linear term
past floor 150 that guarantees every run ends, with a comment explaining exactly why the mode had no
arc without it. The player experiences this as `describe_pressure()` printed in a menu.

**Action.**
1. Make the Waning *visible in the world*: past floor 150, desaturate the biome grade progressively
   (`PixelDioramaSettings.set_biome_screen_grade` already exists), dim torches, and raise the ambient
   fog. The floor should look like it is getting harder.
2. Add a depth milestone banner every 25 floors with the current multipliers.
3. Surface `SkipFloorService`'s stake items on the entry menu as a real risk/reward card, not a
   button list — starting deeper for a consumed item is a good decision presented as a form.

**Done when.** A player at floor 180 can feel the Waning without opening a menu.

---

### MD-04 — The tier ladder is invisible mid-run — **M**

**Files:** `apps/game/client/scripts/dungeon/dungeon_tier_service.gd`,
`apps/game/client/scripts/dungeon/castle_tier_difficulty.gd`,
`apps/game/client/scripts/ui/castle_entry_menu.gd`

**Problem.** `RunFloorConfig` defines a tier as N blocks of ten floors with a boss on each tenth, so
tier 10 is a hundred floors and ten bosses. `DungeonTierService` records clears and unlocks tiers,
and `castle_entry_menu.gd` renders a tier ladder of cards. Once the run starts, the ladder is gone:
nothing on the HUD says which tier you are on, how many blocks remain, or what the next block's boss
is.

**Action.**
1. Put block progress on the HUD objective line (`HD-09`): "Depth 2 · floor 4 of 10 · warden ahead".
2. At each block boundary, show a region banner naming the block and its boss.
3. On the results screen, show the ladder with the reached rung marked (`AD-05`).

**Done when.** A player mid-tier knows how far through it they are.

---

### MD-05 — Alternate rule sets are three JSON entries — **M**

**Files:** `content/modes/catalog.json`, `apps/game/client/scripts/meta/run_mode_catalog.gd`,
`apps/game/client/scripts/ui/tower_board_ui.gd`

**Problem.** `content/modes/catalog.json` defines three alternate rule sets — `boss_rush` (five
floors, a warden on each), `gauntlet` (ten floors, no hearths, escalating modifiers at floors 3, 5,
7, 9) and `ironman` (endless, permadeath). They are well written, they are gated behind
`dungeonsCleared` and `endlessBestFloor`, and they are reachable only through the tower board — a
menu inside a menu inside the hub.

**Action.**
1. Surface them on the main entry menu as a mode row once unlocked, with their flavour line and their
   modifier icons.
2. Give each its own results-screen treatment and its own `RunHistoryService` scope so bests are
   tracked per rule set.
3. Add two more once the framework proves itself: a "no relics" purist run and a "one weapon" run —
   both expressible entirely in `modifiers` with no new code.

**Done when.** A returning player sees three named ways to play tonight, not one.

---

### MD-06 — Weekly challenge has no presence — **S** — `→ AD-04`

**Files:** `apps/game/client/scripts/meta/challenge_service.gd`,
`apps/game/client/scripts/ui/tower_board_ui.gd`

**Problem.** `ChallengeService` rotates weekly with a seeded challenge, scoring, a local best and a
countdown (`format_remaining()`). It lives on the tower board and is announced nowhere.

**Action.** Put it on the main menu "today" line (`AD-04`), on the hub board (`SY-03`), and on the
results screen when a run qualifies (`AD-05` already reads `results.challenge`). Show the countdown
everywhere it appears — a deadline is the entire mechanism.

**Done when.** A player knows there is a weekly challenge without going looking for one.

---

### MD-07 — Mode unlocks should be an event — **S**

**Files:** `apps/game/client/scripts/meta/mode_unlock_service.gd`, `content/modes/unlocks.json`,
`apps/game/client/scripts/hub/hub.gd`

**Problem.** `ModeUnlockService` already carries an `announce` string per mode ("The Vigil answers.
Something in the tower has started counting.") and a `consume_announcements()` drain. The writing is
good. The delivery is a hub message line.

**Action.** On return to the hub with a pending announcement: light the portal, play a stinger
(`AU-03`), show the announce line as a region-banner-sized card, and pan the hub camera to the portal
once. Unlocking a mode is one of maybe five genuinely new things that will ever happen to this
player.

**Done when.** Unlocking the Vigil is a moment you would tell someone about.

---

## §SY — Every remaining system

The workstreams above cover combat, enemies, rooms, HUD, loot and retention. This section covers the
rest of the game so that nothing is left unexamined. Each item states the current state honestly —
several of these systems are in good shape and need only a small pass.

---

### SY-01 — Traps: make them a mechanic, not a tax — **M**

**Files:** `apps/game/client/scripts/dungeon/traps/*.gd`, `content/traps/*.json` (12),
`apps/game/client/scripts/dungeon/procgen/procgen_placements.gd`

**Current state — good foundations.** Twelve authored traps with telegraph → active → cooldown
timing, a shared `TrapTactics` module with hazard registration, status build-up feeding, and an
`enemyDamageMultiplier` (0.7 on `arrow_line`) that already means **traps can hurt enemies**.
`_trap_room_pool()` weights the run-up to the stairs and treasure rooms and excludes the entrance and
the boss room, with a comment explaining exactly why.

**Problem.** The one thing missing is the player's side of the interaction: nothing in the game
encourages luring an enemy into a trap, traps are never re-armable by the player, and a trap the
player has already triggered stays triggered with no visual difference from one that has not.

**Action.**
1. Give a sprung trap a distinct spent look (retracted spikes, a snapped chain) so a room can be read
   after the fact.
2. Add `"resets_after"` to trap data (default 0 = never) so some traps re-arm and become terrain
   rather than a one-off tax.
3. Give `TrapTactics.strike()` a kill credit path: an enemy killed by a trap should count for
   `RunFlow.register_kill()` and award an achievement (`"trap_kill"`), which `RunBuffs.note_trap_catch`
   is already counting for the results screen.
4. Add a `lure` throwable (`RG-04`) so luring is a verb, not an accident.

**Done when.** Killing an enemy with a trap is something a player does on purpose.

---

### SY-02 — Quests, NPCs and dialogue: connect the content that exists — **M**

**Files:** `apps/game/client/scripts/quests/quest_service.gd`,
`apps/game/client/scripts/ui/quest_board_ui.gd`,
`apps/game/client/scripts/ui/quest_tracker_ui.gd`, `apps/game/client/scripts/npc/npc_base.gd`,
`apps/game/client/scripts/npc/npc_catalog.gd`, `content/quests/` (50), `content/dialogue/` (46),
`content/npcs/` (16)

**Current state.** 50 quests across all eight quest types (14 kill, 8 fetch, 7 discover, 6 escort,
5 reach_depth, 5 clear_without, 3 defeat_with, 1 escape), 46 dialogue trees with conditions and
relationship tracking, 16 NPCs. `QuestService` tracks progress and completions correctly.

**Problem.** The quest tracker (`quest_tracker_ui.gd`, 63 lines) is a text list refreshed on
`quest_updated`, and it is not part of the combat HUD — so during a run, an active kill quest is
invisible. Escort quests (6 of them) have no escort mechanic in the dungeon at all: `register_rescue`
exists and nothing calls it from a run.

**Action.**
1. Fold the quest tracker into `combat_hud.gd` as a compact two-line panel under the minimap, showing
   at most two active quests with progress counts.
2. Fire `quest_updated` progress toasts through the HUD banner queue (`HD-02`) when a counter moves.
3. Implement escort: reuse `room_npc_quest_content.gd` and give `npc_base.gd` a follow mode — an NPC
   that trails the player through a floor using the same `NavigationAgent3D` pattern
   `castle_enemy_base.gd` uses, and calls `QuestService.register_rescue()` at the stairs. One escort
   per floor at most, and the NPC must be invulnerable: an escort that can die is a run you cannot
   finish.
4. Wire `discover` quests to `WorldFlags.secret_opened` and `room_cleared` so they progress in play.

**Done when.** A quest accepted at the board visibly progresses during a run.

---

### SY-03 — The hub: make it the place between runs — **M**

**Files:** `apps/game/client/scripts/hub/hub.gd`, `apps/game/client/scripts/hub/hub_diorama.gd`,
`apps/game/client/scripts/meta/hub_growth_service.gd`, `content/ui/hub_growth.json`

**Current state.** A full village diorama (tents, fountain, banners, lanterns, crowd, birds, weather,
day/night), six services (loadout, blacksmith, merchant, storage, quest board, appearance mirror),
catalogue NPCs, and a `HubGrowthService` that unlocks hub content from progress counters.

**Problem.** `HubGrowthService` computes a standing and unlocks entries, and the hub **does not
visibly change** when they unlock — the growth is a list in a menu. A hub that never changes is a
loading screen with a fountain.

**Action.**
1. Bind each `hub_growth.json` entry to a physical change: a new tent, a lit brazier, a repaired
   wall, an NPC that appears, the fountain running. `hub_diorama.gd` already builds all of these
   procedurally, so gate the build on `HubGrowthService.is_unlocked(id)`.
2. Announce an unlock on return from a run through the existing hub message system.
3. Add the "today" board from `AD-04` as a physical object near spawn.

**Done when.** Coming back after ten runs, the hub is visibly a different place.

---

### SY-04 — Classes and character creation — **S**

**Files:** `content/classes/*.json` (7), `apps/game/client/scripts/ui/character_create_ui.gd`,
`apps/game/client/scripts/content/class_catalog.gd`

**Current state — genuinely strong.** Seven classes, each with stat bonuses across twelve stats,
an allowed weapon list and family list, a perk implemented in `ClassPerks`, a talent branch, three
`CombatEvents` rules, `statRatings` for the UI, and localised role/perk text. Character creation has
appearance (frame, skin tone, hair style and colour, face, head covering) with a live preview rig.

**Problem.** Only one thing is missing, and it is the thing that makes a class choice feel like a
build: `allowedWeapons` and `allowedWeaponFamilies` are authored and **the restriction is invisible
at the point of choice**. The creation screen shows stat ratings but not "this class fights with
greatswords and axes".

**Action.** Add a weapon-family row to the class card showing the archetypes the class can use, using
the same pixel icons as the inventory. After `CB-05` gives archetypes real identities, this line
becomes the most informative thing on the screen.

**Done when.** Picking a class tells you how you will fight, not just what your numbers will be.

---

### SY-05 — Settings, display and performance — **M**

**Files:** `apps/game/client/scripts/ui/settings_schema.gd`,
`apps/game/client/scripts/app/display_service.gd`,
`apps/game/client/scripts/art/pipeline/pixel_diorama_settings.gd`

**Current state.** A schema-driven settings screen, display service with a HUD safe area, rebindable
input with conflict detection, accessibility assists, and a deep pixel-render tuning block.

**Problem.** Three gaps. (a) After `HD-03` there will be five resolution presets and no guidance on
which to pick. (b) There is no performance preset — a player on weak hardware has to understand
`shade_bands` and `edge_strength` to get a frame rate. (c) `PixelDioramaSettings.apply_beauty_defaults()`
exists and nothing in the UI offers it.

**Action.**
1. Add three one-click quality presets — **Performance**, **Balanced**, **Beauty** — each setting the
   resolution preset, particle scale, shadow softness, glow, AO, reflections and outline in one go.
2. Add an FPS/frame-time readout toggle, driven by the existing debug overlay machinery but shipped
   as a normal setting.
3. Run `res://scenes/debug/perf_audit.tscn` at each preset on a floor with 28 rooms and record the
   numbers in `docs/validation/manual-checklist.md`.

**Done when.** A player can pick one of three words and get a frame rate.

---

### SY-06 — Save, cloud and platform — **S**

**Files:** `apps/game/client/scripts/save/*.gd`, `apps/game/client/scripts/net/cloud_outbox.gd`,
`apps/game/client/scripts/platform/steam_service.gd`

**Current state — the strongest system in the project.** Twelve migration steps, a validator, five
rotating backups, per-character files, quarantine-on-corrupt with a recovery prompt on the main menu,
a debounced autosave, playtime tracking, and a cloud outbox.

**Problem.** Nothing structural. Two operational gaps: (a) `SteamService.is_stub_mode` is `true`
because the GodotSteam binaries are absent, so achievements and Cloud are local-only — this is
tracked and accepted (`docs/remaining_points.md` R-10); (b) every item in this plan that persists a
new field needs a migration step, and there is no single place recording which.

**Action.**
1. Add a short "pending migrations" list to `docs/SAVE_MIGRATIONS.md` naming the fields this plan
   introduces: quiver charges (`RG-02`), keystone talent ids (`IV-03`), set bonuses (`IV-02`),
   secrets-found counter (`RM-09`), tutorial-seen flags (`AD-07`).
2. Bundle them into **one** migration step (v12 → v13) at the end of the phase that introduces them,
   rather than a step per item.

**Done when.** `SaveMigrator.CURRENT_VERSION` moves once per phase, not once per feature.

---

### SY-07 — Localisation — **S**

**Files:** `apps/game/client/translations/strings.csv`, `apps/game/client/scripts/ui/*.gd`

**Current state — better than expected.** 740 keys in English and Romanian; 338 `tr()` keys are used
in code and **all 338 are defined** — there are no missing translations today.

**Problem.** Not every user-facing string goes through `tr()`. `room_locked_door_content.gd` builds
`"E — Unlock (%s)"` and `"Locked — needs the %s"` as literals; `stair_lever.gd` builds
`"Sealed — defeat the floor boss"`, `"Ascend to floor %d"` and every option label as literals;
`FloorKeyring.COLORS` carries English labels. Everything this plan adds risks widening that gap.

**Action.**
1. Sweep the dungeon interaction scripts and the stair menu for literal user-facing strings and route
   them through `tr()` with new keys.
2. Add a check to `node scripts/validate.mjs`: flag any string literal passed to `Label3D.text`,
   `Label.text` or `Button.text` in `scripts/` that is not a `tr()` call and is longer than two
   characters. Warn, do not fail — some are debug.
3. Every new string this plan introduces gets a key in both languages.

**Done when.** Switching to Romanian leaves no English text in a dungeon.

---

### SY-08 — World simulation: use what is already running — **S**

**Files:** `apps/game/client/scripts/art/world/day_night_service.gd`,
`apps/game/client/scripts/art/world/weather_service.gd`,
`apps/game/client/scripts/dungeon/castle_run.gd`

**Current state.** A real day/night cycle with sun and moon directions from
`Celestial.sun_direction()` / `moon_direction()` and moon phase illumination, a weather service with
rain phases (dry 240–600 s, rain 200–420 s) and wind-scaled ambience, and a wind service driving
banners and embers.

**Problem.** All of it runs **outdoors only** — the hub and the waves arena. A dungeon floor never
sees weather or time of day, so the systems pay their cost in the two places the player spends the
least time.

**Action.**
1. Let a biome declare `"outdoorRooms": true` (courtyards) and apply the sky, weather and time of day
   in those rooms only, with the interior lighting elsewhere.
2. Show time of day on the hub board (`AD-04`) — it is a free reason for a session to feel different.
3. Tie one thing to it mechanically: night floors roll one extra enemy per combat room, day floors
   roll one extra loot item. Small, visible, and it makes the cycle matter.

**Done when.** Walking into a castle courtyard at night looks different from noon.

---

### SY-09 — Debug tooling and content validation — **S**

**Files:** `apps/game/client/scripts/tools/*.gd`, `scripts/validate.mjs`,
`apps/game/client/scripts/app/content_schema_validator.gd`

**Current state.** 40 diagnostic scripts and debug scenes covering procgen health, connectivity,
combat stats, item quality, inventory UX, icon atlases, scene sweeps, perf, draw calls, camera, and
contact-sheet captures. `content/schemas/` holds 63 schema files.

**Problem.** The audits are only as good as their coverage, and this plan adds systems none of them
know about: attack classes, knockback, room shapes, one-way gates, HUD parity across modes.

**Action.** Extend, do not add. Specifically:
- `definition_health.gd` — assert every attack has an `attackClass` (`EN-01`) and every enemy has an
  identity (`EN-10`).
- `floor_connectivity_audit.gd` — the walkability sweep and cliff check (`BG-04`), the soft-lock proof
  (`RM-06`), and the floor score histogram (`RM-18`).
- `combat_stats_audit.gd` — assert knockback values are within band per archetype (`PH-01`).
- `scene_sweep.gd` — assert every mode's HUD populates the elements its row of the `HD-04` matrix
  requires.
- `procgen_seed_health.gd` — the rejection-reason histogram (`RM-12`).

**Done when.** Each of the four `CRITICAL` requirements in this plan has an audit that would catch a
regression.

---

### SY-12 — Keep the per-file audit alive — **S**

**Files:** `scripts/audit-sweep.mjs`, `docs/MVP_DEPTH_PLAN.md` §7

**Problem.** §7 is a per-file audit taken at a point in time. Audits rot: the one in
`docs/CORE_GAMEPLAY_REVIEW.md` needed 244 `✅ FIXED` markers to stay honest, and three of its claims
are stale enough that §1.3 has to warn about them.

**Action.**
1. Run `node scripts/audit-sweep.mjs` at the end of every phase.
2. Fold new hits into §7.3, and move anything you verified-and-dismissed into §7.5 with the reason —
   that list is what stops the next reader re-deriving a false positive.
3. When a §7 finding is fixed, delete the row. Do not add a `FIXED` marker; the row's absence and
   the sweep's silence are the record.
4. Add a check to the sweep whenever this plan introduces a new invariant worth policing — the
   `res://`-to-`ContentLoader` check exists because that bug was found by hand first.
5. **Delete the six references to a test suite that no longer exists, and replace the one guarantee
   they made.** `services/backend/tests/` is gone — `CLAUDE.md` forbids test files anywhere — but
   `content/fixtures/schema_versions.json` and `content/schemas/MANIFEST.json` still tell a reader
   that `ClientVersionParityTests` asserts the backend and client schema versions "cannot drift
   silently", and `docs/ADR/0002-procgen-authority-split.md` and `docs/CORE_GAMEPLAY_REVIEW.md` still
   name the suite four more times. A comment that promises a guard nobody can run is worse than no
   comment. Rewrite the two content files to describe the manual check, and add the drift comparison
   to `scripts/validate-content/validate.mjs` — a tenth cross-reference pass alongside the nine it
   already runs, which is the only form of automated guard this repository's rules permit.

6. **Close the 133.** §7.1 records that 133 of the 372 scripts are named nowhere in this plan, and
   that a twenty-five-file sample of them produced six findings — including the external-i-frame bug
   in `dodge.gd` and the raw-id status tooltip. Work the remaining ~108 down over the phases, adding
   a row per file: a finding when there is one, `CLEAN` when there is not. A `CLEAN` row is worth
   writing; silence is not, because silence is what let those six sit unnoticed.

**Done when.** The sweep is part of the end-of-phase routine, §7 has no stale rows,
`grep -rn "ParityTests" .` returns nothing outside a changelog, and every script has either a
finding or a `CLEAN` row.

---

### SY-11 — Release readiness — **M**

**Files:** `apps/game/client/scripts/platform/crash_logger.gd`,
`apps/game/client/scripts/platform/privacy_settings.gd`,
`apps/game/client/scripts/debug/debug_overlay.gd`,
`apps/game/client/scripts/debug/debug_console.gd`, `apps/game/client/export_presets.cfg`

**Current state — better than the older docs suggest.** `CrashLogger` writes scrubbed reports to
`user://crash_reports/` with rotation (20 files, 5 MB) and an opt-in telemetry upload gated by
`PrivacySettings`. `DebugOverlay.show_debug` defaults to `OS.is_debug_build()`, so the overlay that
`docs/GAME_FEEL_REVIEW.md` saw in a hub capture **is** off in an exported build — treat that review
line as stale. Export presets exist for Windows, Linux and macOS with `export_filter="all_resources"`.

**Problem.** Three real gaps for shipping. (a) `DebugConsole` is an autoload in every build; confirm
it cannot be opened in release. (b) `content/` lives **outside** `res://`, so an export must copy it
next to the binary — `ContentLoader` resolves it at runtime and there is no CI to do the copy
(`CLAUDE.md` forbids adding one), so this must be a documented manual step or an export script.
(c) There is no crash-free smoke pass over an actual exported build.

**Action.**
1. Gate `DebugConsole` behind `OS.is_debug_build()` the same way the overlay is, and verify with an
   export.
2. Write `docs/validation/release-checklist.md` *(new)*: export each platform, copy `content/`, launch, run
   the manual checklist, confirm no placeholder-SFX warnings (`AU-01`), no `push_error` on boot, and
   the save round-trips.
3. Add a `--smoke-test` pass over the **exported** binary, not only over the editor project.
4. **Reconcile the release version, which exists in five places and already disagrees in one.**
   `apps/game/client/project.godot` (`config/version`), `apps/game/client/scripts/net/api_config.gd:10`
   (`CLIENT_VERSION`), `apps/web/package.json` (compiled into `__APP_VERSION__`) and
   `packages/shared/Contracts/ApiVersions.cs` (`ExpectedClientVersion`) all say `0.4.0`; the newest
   patch note in `apps/web/content/patch-notes/` says `0.6.0`. When any of the first four moves alone,
   the version gate 426s every client of the others. List all five in the checklist as a single step.
5. **Fix what the public site says about the game.** `apps/web/src/content/biomes.json`,
   `apps/web/content/wiki/biomes.md` and `apps/web/index.html`'s meta description all describe **five**
   biomes; ten ship. `apps/web/content/wiki/controls.md` advertises a "Q parry" that has no input
   action and omits heavy attack, weapon arts, two-handing, healing and the quick slots. This is the
   first thing a prospective player reads, and every line of it is checkable against the repo.
6. **Make the Steam app id readable.** `SteamService._resolve_app_id()` cannot parse
   `config/platform.json` — Godot returns the JSON number as a float, so `str(...)` gives `"480.0"`
   and `is_valid_int()` rejects it (verified on 4.7.2). The app id therefore always falls back to the
   dev id and `_initialize()` drops into stub mode, so **a shipped Steam build is a stub build**
   unless `AUMBRYE_STEAM_APP_ID` is set in the environment. Parse the number as a number, and make
   the release check assert `SteamService.is_stub_mode == false` in an exported build.
7. **Serve the site correctly.** `apps/web/nginx.conf` sets no `Cache-Control`, so a stale
   `index.html` is exactly the failure `VersionGate`'s cache-busting reload was written to defeat.
   Add `no-cache` for `index.html`, `immutable` for the hashed bundle, and the four standard security
   headers.

**Done when.** An exported build boots, plays a floor and quits with a clean log; the five version
strings are changed by one documented step; and the wiki, the sitemap and the meta description
describe the game that actually ships.

---

### SY-10 — Backend, web and online — **S** — *scope statement, not work*

**Files:** `services/backend/`, `apps/web/`, `packages/procedural/`

**Current state.** A C# backend with run recording and leaderboards, a React web app with an account
page, and a second full dungeon generator in C# under `packages/procedural/`.

**Decision for the MVP.** None of these are on the critical path and none should be touched:
- `USE_ONLINE_PROCgen` is hardcoded `false`; local generation is the only generator
  (`docs/remaining_points.md` R-07).
- OAuth is deferred post-EA (R-08); Steam runs in stub mode (R-10).
- The C#/GDScript generator duality is accepted debt with a written contract
  (`docs/ADR/0002-procgen-authority-split.md`, R-02).

**Action.** Three things, and nothing else.

1. When `RM-01`…`RM-22` change the floor definition shape, update
   `docs/ADR/0002-procgen-authority-split.md` to record that the GDScript generator has diverged, so
   the C# side is not later assumed to be in parity when it is not.
2. **Fix the CORS ordering in `services/backend/src/Aumbrye.Api/Program.cs`.** This is a two-line
   move — `app.UseCors("web")` above `app.UseMiddleware<VersionHeaderMiddleware>()` — and without it
   the web app's entire version-mismatch path is dead from a browser: the 426 carries no
   `Access-Control-Allow-Origin`, the browser drops the response, and the user sees a generic network
   error instead of "this page is out of date, please reload". It is in scope because it is a
   user-facing break in something that already ships, not new online work.
3. **Fix the two non-reproducible asset generators**, `tools/generate_weather_audio.py:127` and
   `tools/generate_music.py:311`. Both seed NumPy from `abs(hash(name))`, and Python randomises string
   hashing per process, so regenerating one sound rewrites every sound with different noise. Swap in a
   SHA-256-derived seed. In scope because it silently corrupts shipped assets the moment anyone reruns
   a generator.

Everything else §7.3 records about the backend, the web app and `packages/procedural` — the missing
concurrency tokens, the tree-only C# layout, the `HashSet` iteration order feeding a checksum, the
48-attempt catch-all — is **written down and deliberately not scheduled**. Read §7.3 before touching
any of it; do not schedule it for the MVP.

**Done when.** The ADR states the current truth, `UseCors` precedes the version middleware, and both
generators seed from a stable digest.

---

## 3. Verification

There is no test suite and none is to be added. Verify by hand, with these:

| What you changed | Run this |
|---|---|
| anything | `node scripts/validate.mjs` |
| any script | `res://scenes/debug/lint_scripts.tscn` (warnings are errors) |
| the game still boots | `godot --path apps/game/client --headless -- --smoke-test` |
| floor generation | `res://scenes/debug/definition_health.tscn` |
| **rooms, doors, locks, one-ways** | `res://scenes/debug/floor_connectivity_audit.tscn -- --seeds=32` |
| generation success rate | `apps/game/client/scripts/tools/procgen_seed_health.gd` |
| combat numbers reach the fight | `res://scenes/debug/combat_stats_audit.tscn` |
| the player↔enemy exchange is in band | `node scripts/balance/balance-cli.mjs` |
| item rolls and condition | `res://scenes/debug/item_quality_audit.tscn` |
| inventory icons and condition reads | `res://scenes/debug/inventory_ux_audit.tscn` |
| every icon resolves | `res://scenes/debug/icon_atlas_audit.tscn` + `python tools/icon-gen/atlas_build.py --check` |
| every scene loads and is skinned | `res://scenes/debug/scene_sweep.tscn -- --verbose` |
| per-frame cost | `res://scenes/debug/perf_audit.tscn` (needs a display) |
| draw calls on a floor | `res://scenes/debug/draw_call_probe.tscn` |
| camera | `res://scenes/debug/camera_zoom_audit.tscn`, `camera_follow_audit.tscn` |
| how it looks | the `res://scenes/debug/capture_*.tscn` contact sheets |
| cited paths in docs | `node scripts/check-doc-paths.mjs` |
| the whole-tree static audit (§7) | `node scripts/audit-sweep.mjs` |

After the items that add them, these audits gain new checks — see `SY-09`:

| New check | Added by | Lives in |
|---|---|---|
| geometry holes and doorway cliffs | `BG-04` | `floor_connectivity_audit.gd` |
| soft-lock proof over keys, one-ways, puzzles and secrets | `RM-06` | `room_content_validator.gd` + the audit |
| every attack declares an `attackClass` | `EN-01` | `definition_health.gd` |
| every enemy declares an identity | `EN-10` | `definition_health.gd` |
| knockback values in band per archetype | `PH-01` | `combat_stats_audit.gd` |
| each mode populates its row of the HUD matrix | `HD-04` | `scene_sweep.gd` |
| generation rejection-reason histogram and floor scores | `RM-12`, `RM-18` | `procgen_seed_health.gd` |

**Warning — nine of these tools write the save.** `docs/CORE_GAMEPLAY_REVIEW.md` §172a documents
four of them; the §7 audit found five more. Every one of these creates, renames or overwrites a
character:

| Tool | What it does to the save |
|---|---|
| `capture_ui_screens`, `capture_world_screens`, `capture_hub_tents` | `set_character_profile("Capture Warden", …)` + autosave |
| `camera_zoom_audit` | instantiates `player.tscn`, which creates a character when none is selected |
| `perf_audit`, `draw_call_probe`, `village_perf_probe` | `set_character_profile("Perf Warden", …)` + autosave |
| `phase_walk` | `queue_boot_new_game()` — creates a character and consumes a roster slot (max 5) |
| `probe_creation_flow` | reads roster state; harmless, listed for completeness |

**Snapshot `user://characters/`, `user://backups/` and `user://character_roster.json` before running
any of them, and restore after.** This matters most for `perf_audit` and `draw_call_probe`, which
`VS-08` asks you to run at the start and end of every phase — see the §7 rows for the fix that makes
them read-only.

---

## 4. Definition of done, per workstream

| § | Done means |
|---|---|
| BG | A player cannot leave the world: every floor has bedrock under it, height transitions climb to the doorway they serve, an out-of-world player is returned within a frame, and an audit fails the build if any of that regresses. |
| EN | Every attack declares a class; the class is mechanically real; a shape as well as a colour states intent; enemies react to the player; the 54 enemies play as more than 8 fights, each biome's roster asks something the last one did not, and every floor has one elite worth fighting. |
| PH | Hits move bodies, with mass mattering; the victim recovers after the attacker; fast attacks cannot tunnel; projectiles arc correctly and can be stopped. |
| AN | Character motion is stepped at 12 fps; attacks have anticipation, a readable held frame, and follow-through; connecting recoils the attacker. |
| RM | The ten biomes generate visibly different floors; corridors give the floor a rhythm; arenas and boss rooms are round; every floor has at least one one-way route; locks are colour-legible in world, on the HUD and on the map; the validator proves no soft-lock across 32 seeds in 10 biomes; one room per floor locks you in; something ambushes you about once a floor; every doorway is a frame and every gate opens; and a floor that scores badly is re-rolled instead of shipped. |
| HD | All three modes populate the same HUD contract; one owner for the top-centre band; the pixel UI is actually on; a boss in waves has a boss bar; one line always says what to do next. |
| CB | Heavy attacks charge; poise breaks lead to executions; each of the eight weapon archetypes plays differently; the rules bus can express a build. |
| RG | Aiming changes the camera and shows the landing point; the quiver is a decision; arrows can be blocked and parried. |
| IV | A third of equipment changes behaviour; sets exist; ten talent keystones change verbs; loot drops are audible and visible by rarity. |
| AD | Every run starts with a stated contract; 8–12 build decisions per ten-floor run; the floor's theme is visible all floor; the results screen names what you are close to; every death names its cause. |
| AU | No placeholder cues; impacts carry material and force; the beats that matter are punctuated. |
| AX | Greyscale-legible telegraphs; full pad parity; no missing glyphs; no clipping at 1.5× text. |
| BS | Every floor boss has a phase that asks something new; the entrance is a moment you can skip; a phase change is visible on the body; hazards obey the colourblind system; every third floor has a miniboss. |
| UX | No screen that represents a structure renders it as a flat list; an item looks the same in every panel; every panel opens, closes and focuses identically; three simultaneous notifications are all legible. |
| MD | Wave 45 is a different fight from wave 5; the extraction choice shows what it risks; the Waning is visible in the world; a mid-tier player knows how far through it they are; unlocking a mode is an event. |
| VS | A capture's value histogram hits its target in every biome; a 4× zoom shows hard pixel edges; ten biomes are ten palettes; no unskinned mesh survives `scene_sweep`; five class silhouettes are five shapes; and every phase has a measured before/after frame time. |
| SY | Traps are a verb you use on purpose; an accepted quest progresses visibly during a run; the hub changes as you play; a class choice states how you fight; three words pick a frame rate; one save migration per phase; no English text in a Romanian dungeon; weather and time of day reach the places the player actually is; and every CRITICAL requirement has an audit that would catch its regression. |

---

## 5. Standing invariants — never break these

1. **Determinism.** Same seed → same floor, forever. Procgen uses only seeded RNG streams.
2. **Soundness.** A key is never behind its own lock; a one-way is never the only route; the boss and
   the stairs are always reachable. Proven by `RoomContentValidator`, audited by
   `floor_connectivity_audit`.
3. **Save compatibility.** New persisted fields go through a `SaveMigrator` step and a version bump.
4. **Optional-by-default content.** Every new JSON field defaults to today's behaviour, so a floor,
   an item or an enemy authored before your change still works.
5. **Facing.** Rig forward is `+basis.z`, always via `CombatFacing`.
6. **Movement.** `CharacterBody3D` + `move_and_slide()` only. No `RigidBody3D`, no direct
   `global_position` writes on a moving body.
7. **The HUD is owned by `combat_hud.gd`.** Run scenes call its public methods and draw nothing of
   their own that is "status".
8. **Tunables live in `content/`.**
9. **No CI, no Dependabot, no test files.** Verification is the debug scenes.
10. **Zero warnings.** `lint_scripts.tscn` must stay clean.

---

## 6. Coverage — every directory, and what covers it

The question "is everything covered?" should be answerable, not asserted. This table is generated
against the tree: 406 GDScript files in 38 directories, every one mapped to the items that touch it.
A directory with few items is not neglected — several are complete systems that need nothing, and
the note says which.

| Directory | Files | Items that touch it | Standing |
|---|---|---|---|
| `scripts/accessibility` | 1 | `AX-01` `EN-04` | Assists, colourblind remaps and motion scaling are done; only the telegraph shape channel is missing. |
| `scripts/app` | 16 | `AD-01` `AD-06` `AX-02` `RG-04` `SY-05` `SY-09` `UX-06` | Autoloads, input, flags, scene routing and lifecycle all work; touched only where a plan item needs a hook. |
| `scripts/art/characters` | 14 | `AN-01` `AN-02` `AN-03` `AN-04` `BS-03` `EN-06` `VS-05` `VS-06` | Rig, skin, voxel meshing and equipment models are complete; the work is motion and silhouette. |
| `scripts/art/lighting` | 3 | `VS-01` | Twelve authored profiles; the work is the value range they produce, not the system. |
| `scripts/art/pipeline` | 4 | `AN-01` `HD-03` `SY-05` `VS-01` `VS-02` | Correctly configured and switched off — see `HD-03`. |
| `scripts/art/props` | 4 | `RM-10` `RM-16` `VS-04` | Prop and weapon kits are complete; the work is using more of them. |
| `scripts/art/style` | 4 | `VS-03` | Palette and batching systems are complete; the work is per-biome identity. |
| `scripts/art/vfx` | 2 | `AX-01` `EN-03` `VS-07` | Pooled, budgeted and well factored; the work is coverage and priority. |
| `scripts/art/world` | 11 | `SY-08` | Day/night, weather, wind, skyline and crowd all run; the work is applying them indoors. |
| `scripts/audio` | 2 | `AU-03` | Adaptive four-layer mix works; the work is the samples and the cues. |
| `scripts/bosses` | 8 | `BS-01` `BS-03` `BS-04` | The phase controller is excellent; the fights are thin. |
| `scripts/camera` | 2 | `BS-02` `RG-01` `VS-09` | Reaction vocabulary is complete; set-piece vocabulary is missing. |
| `scripts/combat` | 24 | `AD-02` `AN-03` `AU-02` `BG-06` `BG-07` `BG-08` `CB-01` `CB-02` `CB-03` `CB-04` `CB-05` `CB-06` `CB-07` `CB-08` `EN-01` `EN-02` `EN-03` `HD-06` `HD-07` `PH-01` `PH-02` `PH-03` `PH-04` `RG-01` `RG-02` `RG-03` `RM-12` `RM-13` `RM-18` `SY-09` `SY-10` `VS-09` | The model is correct and largely invisible. The most-covered directory in the plan. |
| `scripts/combat/statuses` | 2 | `CB-08` | Deep build-up system; the player has no answer to it. |
| `scripts/content` | 7 | `SY-04` | Catalogue loaders are infrastructure and need no work. |
| `scripts/debug` | 5 | `SY-11` | Diagnostics; only the release gating matters. |
| `scripts/dialogue` | 3 | `UX-04` | Runner, catalogue and conditions all work; the presentation is a text box. |
| `scripts/dungeon` | 40 | `AD-02` `AD-03` `AD-08` `AN-04` `BG-01` `BG-02` `BG-03` `BG-04` `BG-05` `BS-02` `BS-04` `BS-05` `BS-06` `BS-07` `BS-08` `EN-12` `HD-01` `HD-05` `HD-08` `HD-09` `MD-01` `MD-02` `MD-03` `MD-04` `PH-04` `RM-01` `RM-02` `RM-03` `RM-04` `RM-05` `RM-06` `RM-07` `RM-08` `RM-09` `RM-10` `RM-11` `RM-12` `RM-13` `RM-14` `RM-15` `RM-16` `RM-17` `RM-18` `RM-19` `RM-20` `RM-21` `RM-22` `SY-01` `SY-07` `SY-08` `UX-05` `VS-04` | The largest and weakest area — §BG, §RM and §MD are all here. |
| `scripts/dungeon/castle` | 3 | `BG-02` `RM-01` `RM-16` `RM-19` `RM-22` | Blockout is where circular rooms and the stair fix land. |
| `scripts/dungeon/procgen` | 20 | `AN-04` `BS-06` `EN-12` `RM-01` `RM-02` `RM-03` `RM-04` `RM-05` `RM-06` `RM-07` `RM-08` `RM-12` `RM-13` `RM-14` `RM-15` `RM-17` `RM-18` `RM-19` `RM-20` `SY-01` `SY-10` | Algorithms are sound; inputs and shape variety are not. |
| `scripts/dungeon/room_content` | 14 | `HD-08` `RM-04` `RM-05` `RM-07` `SY-02` `SY-07` | Nine content types spawn correctly; presentation and prompts are inconsistent. |
| `scripts/dungeon/traps` | 4 | `BS-04` `SY-01` | Twelve traps with real timing; the player has no reason to use them. |
| `scripts/enemies` | 19 | `AU-04` `BS-01` `BS-03` `BS-08` `CB-04` `EN-01` `EN-02` `EN-03` `EN-04` `EN-05` `EN-06` `EN-07` `EN-08` `EN-09` `EN-10` `EN-12` `PH-01` `PH-02` `PH-05` `RM-08` `SY-02` | One real AI, 52 costumes, 6 empty boss shells. |
| `scripts/hub` | 13 | `AD-04` `AD-07` `HD-08` `MD-07` `SY-03` | A full village that does not change as you play. |
| `scripts/inventory` | 4 | `IV-02` `IV-04` `RG-04` | The best-built UI in the project; extended, not rewritten. |
| `scripts/items` | 3 | `IV-02` `IV-05` | Affixes, quality, upgrades, infusions and the forge are all complete. |
| `scripts/loot` | 5 | `IV-04` | Rolling and rarity are complete; the drop *moment* is not wired. |
| `scripts/meta` | 11 | `MD-05` `MD-06` `MD-07` `SY-03` | Every retention system exists and almost none are surfaced. |
| `scripts/net` | 3 | `SY-06` | Cloud outbox and API client work; online runs are deliberately out of scope. |
| `scripts/npc` | 2 | `SY-02` | Catalogue and base behaviour work; escort is the missing verb. |
| `scripts/platform` | 3 | `SY-06` `SY-11` | Crash logging and privacy are done; Steam is a documented stub. |
| `scripts/player` | 6 | `BG-08` `CB-02` `CB-06` `PH-01` `PH-02` `RM-09` | Locomotion, dodge, heal and reactions are correct; they need physical consequence. |
| `scripts/progression` | 2 | `AD-08` `IV-03` `UX-02` | XP, talents, endless depth and failure hotspots all work; the tree is a list. |
| `scripts/quests` | 4 | `SY-02` | 50 quests across 8 types, invisible during a run. |
| `scripts/save` | 6 | `SY-06` | The strongest system in the project. One migration per phase is all it needs. |
| `scripts/tools` | 34 | `AN-01` `BG-04` `EN-01` `EN-03` `RM-06` `RM-12` `RM-13` `RM-18` `SY-09` `SY-10` `VS-05` `VS-08` | 40 diagnostics; extended by `SY-09` rather than added to. |
| `scripts/ui` | 64 | `AD-01` `AD-03` `AD-04` `AD-05` `AD-06` `AD-07` `AD-08` `AX-02` `AX-03` `AX-04` `BS-02` `BS-07` `EN-04` `EN-09` `HD-01` `HD-02` `HD-03` `HD-04` `HD-05` `HD-06` `HD-07` `HD-08` `HD-09` `HD-10` `IV-05` `MD-02` `MD-03` `MD-04` `MD-05` `MD-06` `RG-01` `RG-02` `RM-05` `SY-02` `SY-04` `SY-05` `SY-07` `SY-10` `UX-01` `UX-02` `UX-03` `UX-04` `UX-05` `UX-06` `UX-07` `UX-08` `UX-09` `UX-10` | 64 scripts. The HUD and inventory are strong; four screens are list boxes. |

| `scenes/props` | 40 | `RM-21` | Every file is an empty node. The whole directory is one finding. |
| `scenes/rooms` | 100 | `RM-01` `RM-02` `RM-16` `RM-21` `RM-22` | Two authoring generations; normalised by `RM-22` before `RM-01` reshapes them. |
| `assets/shared` (shaders) | 7 | `VS-08` | Two carry the same per-vertex matrix inverse; see §7.3. |
| `packages/procedural` | 27 | `SY-10` | Not the gameplay path. Five defects recorded in §7.3, none scheduled. |
| `services/backend` | 34 | `SY-10` | One user-facing fix scheduled (CORS ordering); the rest recorded, not scheduled. |
| `apps/web/src` | 19 | `SY-10` | The browser half of the same CORS defect. |
| `tools/`, `scripts/` | 52 | `SY-09` `SY-10` `SY-12` | Two non-reproducible generators scheduled; the audit tooling is extended by `SY-09`. |

**Outside `scripts/`, covered explicitly:** `content/` (37 directories — every one is named by at
least one item; `EN-01`, `RM-13`, `IV-01`, `IV-03`, `AU-01` and `SY-07` are the largest content
jobs), `scenes/` (via `RM-01`, `RM-16`, `UX-01`, `SY-11`), `translations/` (`SY-07`),
`assets/` (`EN-04`, `VS-01`…`VS-06`, `AU-01`), `export_presets.cfg` (`SY-11`), `docs/` (`SY-06`,
`SY-10`, `SY-11`, `VS-08`), and the audit tooling under `scripts/tools/` (`SY-09`).

**Outside `apps/game/client/`, deliberately not covered:** `services/backend/`, `apps/web/`,
`packages/procedural/`, `packages/shared/`, `tools/icon-gen/`, `tools/voxel-import/`. The reasons are
in §8 and `SY-10`; the only required action is keeping
`docs/ADR/0002-procgen-authority-split.md` truthful once the floor definition changes.

---
## 7. Per-file audit — bugs, enhancements and optimisations

### 7.1 Method, and how complete this is

This section is a per-file audit of the project. It was produced two ways, and the difference
matters when you act on it:

**Manual review.** Files read in full and reasoned about. Everything in §7.3 came from this, and
every one of those findings was **verified against the code before it was written down** — several
promising leads were discarded during that check and are recorded in §7.5 so nobody re-derives them.

**Mechanical sweep.** `scripts/audit-sweep.mjs` *(new)* — added as part of this work — runs a battery
of static checks over the whole tree and can be re-run at any time:

```bash
node scripts/audit-sweep.mjs          # human-readable
node scripts/audit-sweep.mjs --json   # machine-readable
```

It reports; it never fails a build. That is the same contract every other diagnostic in this repo
has (`CLAUDE.md`), and it is why this audit does not rot the day after it is written.

**Statement of coverage.** The tree is 1,639 files: 372 GDScript (plus 34 in the vendored
`addons/godot_mcp`), 290 scenes, 7 shaders, 728 content JSON, 77 C#, 19 TypeScript, 52 tool scripts.

**Every layer has now been read.** The pass ran in three sittings. The first covered `dungeon/`,
`combat/`, `enemies/`, `player/` and `procgen/`. The second closed the 209 GDScript files it had
covered mechanically only. The third — recorded in the last six tables of §7.3 — closed everything
that was previously deferred: the seven shaders, the scenes read rather than merely resolved, the
27-file C# procgen package, the 34-file C# backend, the TypeScript site, the 52 tool scripts, the
content JSON against its schemas, and the root configuration. A fourth pass then closed what a
file-by-file inventory showed the third had still missed: `packages/shared` and `tools/procgen-cli`
(the nine C# files outside the two projects already read), the six `.res` animation libraries, both
`.tres` resources, the 394 character `.voxels.json` files and the `art-source/` tree behind them, the
web app's content and serving configuration, the deployment and build files, and
`translations/strings.csv` row by row.

**Nothing in the repository is unanalysed.** Every tracked file is accounted for by the table below.
The one deliberate exception is the vendored addon, and it is stated there.

| Layer | Files | Coverage |
|---|---|---|
| GDScript | 372 | **All read** across the four passes — but read once is not read closely. 239 are named somewhere in this plan; **133 are not**, and a sample of ~25 of those 133 produced six findings (see the last table in §7.3). Treat an unnamed file as *not yet audited*, not as *audited clean* — only a `CLEAN` row means that |
| Scenes | 290 | **All covered mechanically** — every `ext_resource` path and exported `NodePath` resolved, plus reachability — and the room, prop, hub and debug scenes then read. Two findings, both promoted to items (`RM-21`, `RM-22`) |
| Content JSON | 728 | **All covered** — 662 validate against the 63 schemas in `content/schemas/` plus nine cross-reference passes; the only uncovered files are five fixtures under `content/fixtures/` used by the debug scenes |
| Translations | 740 keys | **Fully covered** — all 338 `tr()` keys used in code are defined |
| Shaders | 7 | **All read.** Two carry the same per-vertex `inverse(MODEL_MATRIX)`; the rest are clean |
| C# (`packages/procedural`, `services/backend`) | 61 | **All read.** Five bugs in the procgen package, two in the backend — see §7.3 |
| TypeScript (`apps/web/src`) | 19 | **All read.** Two bugs, one of them the browser-side half of the backend CORS defect |
| Python/Node tooling | 52 | **All read.** Two non-reproducible asset generators; one dead pre-commit exclusion |
| Vendored `addons/godot_mcp` | 34 | **Excluded from every export preset and verified unreferenced by shipping code.** Not reviewed line by line — it is a third-party editor tool that cannot reach a player |
| Art source and binary assets | 448 | **All accounted for.** 162 `.vox`, 144 `.import` (no orphans), 115 `.ogg`, 26 `.png`, 6 `.res` animation libraries, 2 `.tres`, 1 `.ttf`. One real defect: `art-source/characters/` is a generation behind the shipped voxel set |
| Web content and serving config | 12 | **All read.** Six findings, all of them the public site describing a game that no longer matches |
| Build, deploy and repo config | 24 | **All read.** `Directory.Build.props`, `.editorconfig`, `.gdlintrc`, eslint, the two Dockerfiles, `docker-compose.yml`, `nginx.conf`, the `.ps1`/`.sh` wrappers, `.gitattributes`, `CODEOWNERS`, `global.json` |
| Documentation | 26 `.md` | **All read**, including the two ADRs; §1.3 records which claims in the older reviews are now stale |
| Translations | `strings.csv` | 740 keys × `en`/`ro`, no duplicates or empty cells; 110 talent-tree rows are untranslated |

A file appears below only when there was something to say about it — with one deliberate correction
to how that used to read. This section previously implied that any file without a row had been read
and found sound. It had not: 133 scripts are named nowhere in this plan, and opening a sample of
twenty-five of them produced six findings, two of them user-facing bugs. **Absence of a row means
nobody has written anything about that file, and nothing more.** `CLEAN` rows are the real signal:
they record a file read closely and found correct, so the next reader does not re-audit it.

Finishing the remaining ~108 is the cheapest unclaimed work in this document, and `SY-12` now owns
it. The list regenerates in one command:

```bash
comm -13 <(grep -o '[a-z_0-9]*\.gd' docs/MVP_DEPTH_PLAN.md | sort -u) \
         <(git ls-files '*.gd' | grep -v addons/ | xargs -n1 basename | sort -u)
```

### 7.2 Findings by kind

**58 bugs · 26 optimisations · 8 localisation gaps · 51 enhancements · 82 files verified clean.**

`BUG` is a defect a player can hit or a developer will be misled by. `PERF` is measurable waste on a
hot path. `L10N` is user-facing text that never reaches `tr()`. `ENH` is a real improvement with no
defect behind it. `CLEAN` records a file read closely and found correct.

The ten highest-severity findings, all verified against the code:

1. **`ui/ui_text_scale.gd` — the subtitle-scale and UI-text-scale settings do nothing.**
   `_registered` is never appended to; there is no `register()` anywhere in the project. Both
   sliders exist, both persist, and neither changes a single label.
2. **`net/api_config.gd` — `config/dev_api.json` is never read** (a `res://` path handed to a loader
   that resolves against the content root), so the base URL falls back to
   `https://api.aumbrye.example` — a documentation TLD that cannot resolve but passes the release
   HTTPS check. Boot then believes cloud is enabled and every request times out.
3. **The performance tools rename the player's character and autosave it** —
   `apps/game/client/scripts/tools/perf_audit.gd`, `draw_call_probe.gd` and `village_perf_probe.gd`.** `VS-08` asks you to run the first two at the start and end
   of every phase — following this plan as written would cost a developer their save.
4. **`app/display_service.gd`** — `set_hud_safe_area()` and three siblings call `apply_all()`,
   reconfiguring monitor, window mode, size, vsync and FPS to change one value; every setter also
   writes the save, so a slider writes once per drag step.
5. **`save/local_save.gd`** — `autosave()` defaults to `IMMEDIATE`, which serialises, writes, **reads
   back, re-parses and re-validates** synchronously. 19 modules call it directly rather than the
   debounced path that exists. Compounds with (4).
6. **`meta/progress_counters.gd`** — `shortfall()` returns the goal you are **furthest** from, so
   every "you are close to X" line in `AD-05` would advertise the least achievable target.
7. **`dungeon/traps/falling_trap.gd`** — the block is returned to the ceiling in the same frame it
   lands, so the trap reads as a flicker rather than a slam.
8. **`art/world/sky_birds.gd`** — mutates a **shared cached material** every frame, permanently
   flipping it to alpha transparency for every other user of that colour.
9. **Every biome prop scene is empty.** All 40 files under `apps/game/client/scenes/props/` are a
   bare `Node3D` with no mesh, no collision and no material, and all ten biome definitions reference
   them from a `propKit` block that no code reads. Rooms are dressed entirely by code-generated
   boxes. → `RM-21`.
10. **The web version gate cannot fire from a browser.** `VersionHeaderMiddleware` runs before
   `UseCors`, so its 426 carries no `Access-Control-Allow-Origin`; the browser drops the response,
   `client.ts` never sees the status, and the "this page is out of date" UI never renders.

### 7.3 Findings, by area

#### `scripts/dungeon`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/dungeon/biome_registry.gd` | **ENH** | `get_room_scenes()` silently `continue`s when a room scene does not exist, so a biome missing a kind (every biome is missing `_shop` — see `RM-20`) yields a scene table with a hole, and a typo in `assetFolder` yields an **empty** table that only surfaces later as `DungeonBuilder`'s "unknown template(s)" abort. Warn once per missing kind. |
| `apps/game/client/scripts/dungeon/biome_registry.gd` | **PERF** | `get_biome()` returns `duplicate(true)` on every call and a biome dictionary is large (enemy pool, boss pool, trap pool, loot tables, generator config, lighting, grade). `ProcgenPlacements` calls it per chest roll and `RoomContentAssigner` per room. Return a shared read-only dictionary and duplicate only at the two sites that mutate. |
| `apps/game/client/scripts/dungeon/castle_tier_difficulty.gd` | **BUG** | `behaviour_progress()` divides the floor by `RunFloorConfig.MAX_FLOORS` (10) — the **tier-1** floor count — but `RunFloorConfig.floors_for_tier(tier)` gives a tier-10 run 100 floors. Past floor 11 the floor term saturates and stops contributing, so enemy behaviour pressure stops scaling for 90 % of a deep tier. Divide by `floors_for_tier()`. |
| `apps/game/client/scripts/dungeon/doorway_socket.gd` | **ENH** | `get_world_facing()` finds its room with `get_parent().get_parent()`, a hardcoded two-level assumption. A socket nested one level deeper silently falls back to its own basis, which is the failure mode that produces doors facing the wrong way. Walk up to the first `RoomTemplate` instead. |
| `apps/game/client/scripts/dungeon/dungeon_catalog.gd` | **CLEAN** | Straight catalogue access with sensible per-dungeon defaults. |
| `apps/game/client/scripts/dungeon/dungeon_definition_validator.gd` | **CLEAN** | Schema version, required keys, unique room ids, template resolution, edge endpoints, entrance/boss/exit presence, lock solvability, room overlap and placement-in-room are all checked. The `<` strict rect test correctly treats two flush rooms as non-overlapping. |
| `apps/game/client/scripts/dungeon/dungeon_seed_service.gd` | **BUG** | `derive_tier_seed()` clamps the tier with `clampi(tier, 1, DungeonCatalog.count())` — the number of **dungeons**, not `RunFloorConfig.MAX_TIER` (10). The two happen to coincide today; adding or removing a dungeon silently changes every tier seed above the new count. Clamp to `RunFloorConfig.MAX_TIER`. |
| `apps/game/client/scripts/dungeon/dungeon_tier_service.gd` | **L10N** | `HUB_LABEL_PREFIX := "Aumbrye Dungeons — Depth "` is concatenated into the hub portal label and every entry-menu title. Route through `tr()` with a format argument. |
| `apps/game/client/scripts/dungeon/floor_definition_cache.gd` | **PERF** | `store_floor_cache()` and `get_floor_cache()` each `duplicate(true)` a whole floor definition (rooms, edges, all placements, room content) — two deep copies per floor transition of the largest dictionary in the game. Store the definition by reference and duplicate only if a caller mutates. |
| `apps/game/client/scripts/dungeon/floor_seed_mix.gd` | **CLEAN** | The 64-bit splitmix emulation over 32-bit halves is correct and is the determinism spine of the whole generator. Do not touch it without regenerating goldens. |
| `apps/game/client/scripts/dungeon/forgotten_castle_slice.gd` | **CLEAN** | A fixed authored slice; the hardcoded node paths are appropriate here. |
| `apps/game/client/scripts/dungeon/run_modifier_service.gd` | **L10N** | All sixteen entries in `DESCRIPTIONS` are English literals, and they are shown on the stair menu, the results screen and (after `AD-03`) the HUD. This is the largest single block of untranslated player-facing text in the game. |
| `apps/game/client/scripts/dungeon/waves_cash_out_portal.gd` | **L10N** | `DISPLAY_NAME := "The Summoner"` and `"%s — leave with one thing (%s)"` are English literals on the mode's single most important decision point. |
| `apps/game/client/scripts/dungeon/waves_cash_out_portal.gd` | **PERF** | `_process()` runs a breathing scale every frame for the whole intermission whether or not the portal is on screen. Gate on visibility or drive it from a `Tween` with `loops()`. |
| `apps/game/client/scripts/dungeon/waves_chest.gd` | **CLEAN** | Lid tween, transparency on open, proximity label and the flag-backed opened state are all correct. |
| `apps/game/client/scripts/dungeon/waves_spawn_marker.gd` | **CLEAN** | Exactly the tell the mode needs, and it is freed with the spawn. |

#### `scripts/dungeon/procgen`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/dungeon/procgen/procgen_loot_roller.gd` | **CLEAN** | Budget shares per chest role with bounded fill attempts; deterministic through the passed rng. |
| `apps/game/client/scripts/dungeon/procgen/procgen_placements.gd` | **CLEAN** | `_threat_cost_cache` is bounded by the number of enemy ids and is a pure memoisation of a file read. |
| `apps/game/client/scripts/dungeon/procgen/room_graph_geometry.gd` | **ENH** | `build_edges()` is 106 body lines covering realised edges, unrealised shortcuts and secrets in one pass. `RM-04` adds one-way edges to it. Split by edge kind first. |
| `apps/game/client/scripts/dungeon/procgen/room_graph_paths.gd` | **CLEAN** | Adjacency and distance caches are keyed on graph identity and replaced when the graph changes; bounded by room count. |

#### `scripts/dungeon/traps`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/dungeon/traps/falling_trap.gd` | **BUG** | On impact the FALLING branch sets `_block.position.y = 0.2`, disables damage, and then **immediately sets `_block.position.y = _rest_y` in the same frame** before entering RESET. The block therefore never visibly rests on the floor — it snaps back to the ceiling the instant it lands, so the trap reads as a flicker rather than a slam. Hold it at 0.2 for the RESET duration and raise it at the end. |
| `apps/game/client/scripts/dungeon/traps/falling_trap.gd` | **PERF** | Same idle-poll cost as `spike_trap.gd`. |
| `apps/game/client/scripts/dungeon/traps/hazard_trap.gd` | **ENH** | The SPENT branch calls `set_physics_process(false)` from **inside** `_physics_process`, so it costs one extra frame and reads as a state that disables itself. Disable it when entering SPENT. |
| `apps/game/client/scripts/dungeon/traps/hazard_trap.gd` | **PERF** | Same idle-poll cost, and `"cycle"` traps additionally re-enter the telegraph on a timer forever regardless of whether anything is nearby. |
| `apps/game/client/scripts/dungeon/traps/spike_trap.gd` | **BUG** | The telegraph material is a hardcoded `Color(1, 0.2, 0.2, 0.5)`; `falling_trap.gd` uses `Color(0.2, 0.2, 0.2, 0.6)`. Neither goes through `AccessibilitySettings.get_telegraph_class_color()`, so colourblind mode remaps enemy attacks and leaves the traps that kill you unchanged. Same defect as `BS-04`; fix all of them together. |
| `apps/game/client/scripts/dungeon/traps/spike_trap.gd` | **PERF** | `_physics_process` runs every frame in IDLE and calls `TrapTactics.trigger_present()`, which does `get_first_node_in_group("player")` and (for plate traps) a full `get_nodes_in_group("enemy")` walk. `ProcgenPlacements` places up to 6 traps per floor plus hazards, so that is 6+ group walks per physics tick, forever. Throttle the idle poll to ~6 Hz, or arm from the trap's own `Area3D` `body_entered` instead of polling. |
| `apps/game/client/scripts/dungeon/traps/trap_tactics.gd` | **CLEAN** | Hazard registration, per-target strike cooldowns, status build-up feeding and the `enemyDamageMultiplier` path are all correct — this is the module `SY-01` builds on. |

#### `scripts/combat`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/combat/hurtbox.gd` | **ENH** | `receive_hit()` is 114 body lines and is the single hottest function in combat — it runs the whole mitigation pipeline plus feedback dispatch plus event dispatch. Split the pipeline (`_resolve_mitigation`) from the presentation (`_emit_feedback`) so the order of operations is readable and so `PH-01` has an obvious place to insert knockback. |

#### `scripts/player`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/player/locomotion.gd` | **ENH** | `_physics_process()` is 130 body lines with four early-return branches that each duplicate the gravity/`move_and_slide`/animation tail. `PH-01` must add knockback to **every** branch; splitting the tail into one `_finish_move()` first makes that a one-line change instead of four. |

#### `scripts/app`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/app/content_loader.gd` | **BUG** | A missing file caches `{}` permanently, so a path that becomes readable later (content copied beside the binary after first probe) is never retried. `_missing_paths` is written and never read — either use it to retry once per session or delete it. |
| `apps/game/client/scripts/app/content_loader.gd` | **BUG** | `clear_all_caches()` clears 7 catalogues but misses `StatusCatalog`, `TrapCatalog`, `NpcCatalog`, `MerchantCatalog`, `RecipeCatalog`, `DungeonQuestCatalog`, `RoomLayoutCatalog`, `RoomTemplateCatalog`, `BiomeRegistry`, `AffixRoller`, `ItemQuality`, `RunModeCatalog`, `ChallengeService`, `HubGrowthService`, `DescentPactService` — all of which expose `clear_cache()`/`reload()`. A content reload leaves most of the game on stale data. |
| `apps/game/client/scripts/app/content_loader.gd` | **PERF** | `content_root()` re-reads a ProjectSetting and rebuilds a path on every `content_path()` call. Cache it in a `static var` resolved once. |
| `apps/game/client/scripts/app/content_loader.gd` | **PERF** | `load_json()` returns `result.duplicate(true)` on every call, including cache hits — a deep copy of the whole file per lookup. `StatusCatalog.get_definition()` is called per active status inside `_recalc_modifiers()`, and `EnemyCatalog`/`ItemCatalog` lookups sit on hot paths. Return an immutable reference (or cache one pre-duplicated copy) and duplicate only where a caller mutates. |
| `apps/game/client/scripts/app/content_schema_validator.gd` | **ENH** | Runs only under `OS.is_debug_build()`. Content shipped broken is found by players, not by the developer. Keep it debug-only for speed but add a full sweep to `definition_health.tscn` so it runs in an audit. |
| `apps/game/client/scripts/app/content_schema_validator.gd` | **ENH** | Validates four hardcoded path patterns against hardcoded key lists while `content/schemas/` holds 63 JSON Schema files that go unused. Drive validation from those schemas so adding a schema adds a check. |
| `apps/game/client/scripts/app/debounced_save.gd` | **BUG** | No flush on quit. A settings change made inside the debounce window is lost if the player exits — `LocalSave` handles `NOTIFICATION_WM_CLOSE_REQUEST` and this does not. Add a static `flush_all()` and call it from `LocalSave._notification`. |
| `apps/game/client/scripts/app/display_service.gd` | **BUG** | `set_hud_safe_area()` calls `apply_all()`, which re-applies monitor, window mode, window size, vsync and FPS cap — a full window reconfigure to change a HUD margin. Same for `set_monitor_index`/`set_vsync_mode`/`set_max_fps`, each of which only needs its own apply. |
| `apps/game/client/scripts/app/display_service.gd` | **PERF** | Every setter calls `save()` → `LocalSave.autosave()`, so dragging a slider writes the save once per step. Route through `DebouncedSave.request()` like the audio and accessibility modules already do. |
| `apps/game/client/scripts/app/display_service.gd` | **PERF** | `window_size_fits_any_monitor()` calls `DisplayServer.screen_get_usable_rect()` per screen, and `available_resolutions()` calls it per preset — O(presets × screens) display-server round trips per settings refresh. This is also the call in the stack of the `M-03` headless segfault in `docs/remaining_points.md`. Cache the usable rects once per `display_changed`. |
| `apps/game/client/scripts/app/game_facade.gd` | **BUG** | `_run_smoke_test()` reaches into `LocalSave` privates: `_active_character_id`, `_build_save_payload()`, `_write_save()`, `_active_save_path()`. Private cross-module API breaks silently on refactor and writes into the real `user://characters/`. Give `LocalSave` a public `write_probe_save()` for this. |
| `apps/game/client/scripts/app/game_facade.gd` | **ENH** | The six facade functions (`persistence()`, `progression()`, `inventory()`, `run()`, `presentation()`, `platform()`) have **no callers anywhere** — they are the abandoned autoload consolidation `docs/remaining_points.md` R-01 describes. Each allocates a Dictionary per call. Either adopt them or delete them; a facade nothing goes through is misleading documentation. |
| `apps/game/client/scripts/app/game_facade.gd` | **ENH** | The smoke test generates one floor of one biome (`forgotten_castle`, seed 12345). Extend to one floor per biome — ten generations is still under a second and would catch a biome-specific generator regression at boot. |
| `apps/game/client/scripts/app/player_input.gd` | **BUG** | `_blocked_groups` is a static bitmask with no reset path in use: `clear_group_blocks()` exists and **is called by nothing**. Any code path that blocks a group and is freed before unblocking leaves that input group dead for the rest of the session. Call it on scene change from `PlayerControls._on_scene_changed()`. |
| `apps/game/client/scripts/app/run_flow.gd` | **ENH** | `_restore_castle_run()` is 93 body lines. `RunFlow` is 1,875 lines and `docs/remaining_points.md` R-01 already names splitting it as accepted debt; this function is the natural first cut. |
| `apps/game/client/scripts/app/run_scene_router.gd` | **ENH** | The four status strings are English literals rather than `tr()` keys. Small, but it is on the loading screen — the most-seen text in the game. See `SY-07`. |

#### `scripts/save`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/save/character_service.gd` | **CLEAN** | Correct autosave discipline: `DEFERRED` for flags and gold gains, `IMMEDIATE` for `spend_gold()`. Spending money should be durable; that distinction is deliberate and right. |
| `apps/game/client/scripts/save/character_service.gd` | **ENH** | `_unregistered_flag_ids` is written in `set_flag()` and cleared in two places but **never read**. It was clearly meant to surface flags that bypass the `CharacterFlags` registry. Either report it (a warning once per unknown id, or a row in `definition_health`) or delete it. |
| `apps/game/client/scripts/save/local_save.gd` | **CLEAN** | The write itself is exemplary: temp file, read-back parse, `SaveValidator` check, backup rotation, atomic rename, Steam-cloud mirror, and a failure path that removes the temp file and reports through `CrashLogger`. Do not simplify it. |
| `apps/game/client/scripts/save/local_save.gd` | **PERF** | `autosave()` defaults to `SavePriority.IMMEDIATE`, which deep-copies the payload, serialises it, writes a temp file, **reads it back, re-parses it and re-validates it**, rotates backups and renames — synchronously. The debounced `request_autosave(DEFERRED)` path exists and 12 call sites use it; **19 modules still call `autosave()` directly**, including every settings module. Combined with `DisplayService` saving per slider step, dragging one slider performs a full serialise/write/read/parse/validate per pixel of travel. Move every settings and meta writer onto `request_autosave(DEFERRED)`. |

#### `scripts/ui`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/ui/achievement_toast.gd` | **BUG** | Each toast is its own node with a fixed position and a 3.3 s tween. Two achievements unlocking in the same frame render on top of each other. This is the concrete case for the toast lane in `UX-10`. |
| `apps/game/client/scripts/ui/appearance_catalog.gd` | **ENH** | Calls `PixelStyle._palette_theme_from_string()` — a private method — in four places. Make it public on `PixelDioramaStyle`. |
| `apps/game/client/scripts/ui/appearance_catalog.gd` | **PERF** | `unlocked_aspects()` rebuilds the filtered array on every call and `unlocked_aspect_label/theme/index_for_theme/count` each call it — so one appearance-panel refresh filters the list four times, and `is_unlocked()` does a `tree.root.get_node_or_null("CharacterService")` **per entry per call**. Use the `CharacterService` autoload directly and cache the filtered list, invalidating on `flags_changed`. |
| `apps/game/client/scripts/ui/appearance_row.gd` | **CLEAN** | Focus styling, chevron buttons with SFX wiring and wrap-around stepping are all correct. |
| `apps/game/client/scripts/ui/binding_capture_modal.gd` | **CLEAN** | Conflict/swap flow, echo and press filtering, and cancel handling are correct. |
| `apps/game/client/scripts/ui/boss_intro_ui.gd` | **CLEAN** | Correct as far as it goes — `BS-02` replaces it rather than fixing it. |
| `apps/game/client/scripts/ui/character_create_ui.gd` | **ENH** | `_build_detail_column()` is 111 body lines and `UX-08` adds the weapon-archetype row to it. |
| `apps/game/client/scripts/ui/class_card.gd` | **CLEAN** | Guarded `_build_ui()` so `setup()` before `_ready()` still works. |
| `apps/game/client/scripts/ui/class_icon_atlas.gd` | **CLEAN** | Correct `class_icons:` prefix handling with an `unknown` fallback. |
| `apps/game/client/scripts/ui/confirm_spec.gd` | **CLEAN** | Plain data holder. |
| `apps/game/client/scripts/ui/epilogue_card.gd` | **CLEAN** | Correct; `BS-07` gives it content. |
| `apps/game/client/scripts/ui/input_glyph_atlas.gd` | **CLEAN** | Thin facade over `UISymbolAtlas.shared`. |
| `apps/game/client/scripts/ui/input_glyph_service.gd` | **CLEAN** | The device-family texture cache keyed by `action:family`, the lazy bus wiring and `invalidate_caches()` on a symbol invalidation are all correct. |
| `apps/game/client/scripts/ui/input_glyph_service.gd` | **L10N** | `get_action_display_name()` returns fourteen English literals ("Dash", "Sprint", "Lock", "Inventory", "Interact", "Jump", "Pause", "Weapon art", …). These are the captions on the HUD control hints — the most-read text in the game after the resource bars. |
| `apps/game/client/scripts/ui/input_glyph_watcher.gd` | **PERF** | `_input()` fires for every event; on a joypad-motion event it calls `Input.get_joy_guid(device)` and runs six `in` substring searches. Sticks emit motion continuously, so this is a string allocation and six scans per frame per axis. Cache device → family on `joy_connection_changed` and look it up. |
| `apps/game/client/scripts/ui/inventory_ui.gd` | **ENH** | `_build_ui_shell()` is 128 body lines. `UX-03` extracts the item cell from this file; do the split as part of that item. |
| `apps/game/client/scripts/ui/inventory_ui_layout.gd` | **L10N** | `SLOT_LABELS` is nine English literals ("Head", "Chest", "Hands", …) shown on the inventory paperdoll. |
| `apps/game/client/scripts/ui/item_icon_atlas.gd` | **PERF** | `get_icon()` builds a **new** `AtlasTexture` and calls `load()` every time an item declares a standalone `iconPath`. The inventory grid calls this per cell per refresh. Cache standalone icons by path. |
| `apps/game/client/scripts/ui/item_list_presenter.gd` | **CLEAN** | Small, correct, and the one place `ItemList` rows are styled consistently. |
| `apps/game/client/scripts/ui/loadout_ui.gd` | **PERF** | `_refresh_list()` walks every weapon in the catalogue and calls `_is_weapon_unlocked()`, which runs `find_slots_where()` over **both** the inventory and the stash per item. That is items × slots × 2 on every open and after every equip. Build a set of held item ids once per refresh. |
| `apps/game/client/scripts/ui/locale_settings.gd` | **CLEAN** | Locale validation, apply, save and listener pruning are all correct. |
| `apps/game/client/scripts/ui/menu_shell.gd` | **BUG** | `show_confirmation()` defaults `confirm_text`/`cancel_text` to the English literals `"Confirm"`/`"Cancel"`, and its only caller passes more literals. `ConfirmSpec` is fully localised via `tr()`. This is the localisation gap in `SY-07` with a concrete home. |
| `apps/game/client/scripts/ui/menu_shell.gd` | **BUG** | `show_confirmation()` is a second, parallel confirmation system to `MenuStack.confirm(ConfirmSpec)`. It does not push `MenuStack`, so `ui_cancel` does not close it, it does not pause, and it does not restore focus. Delete it and route every caller through `MenuStack.confirm()`. |
| `apps/game/client/scripts/ui/menu_stack.gd` | **CLEAN** | Stack, pause ownership, mouse-mode save/restore, focus records and the confirm layer are all handled correctly, including the quit-from-inside-a-confirm case in `force_unpause()`. |
| `apps/game/client/scripts/ui/name_validator.gd` | **CLEAN** | Leet-folding, token matching and the reserved/blocked/shortReserved split are a genuinely careful implementation. |
| `apps/game/client/scripts/ui/name_validator.gd` | **ENH** | `_matches_charset()`'s single-character branch is unreachable: `MIN_LENGTH` is 2, so `validate()` rejects one-character names before it is called. Delete the branch or lower the minimum deliberately. |
| `apps/game/client/scripts/ui/quest_tracker_ui.gd` | **ENH** | `_refresh()` frees and rebuilds every row on every `quest_updated`. Fine at the current scale, but `SY-02` moves this into the HUD where it will refresh during combat — reuse rows instead. |
| `apps/game/client/scripts/ui/quest_tracker_ui.gd` | **L10N** | `_format_progress()` returns the literal `"Escape alive"` for escape quests while every other line goes through `tr()`. |
| `apps/game/client/scripts/ui/results_screen.gd` | **BUG** | `_load_leaderboard_panel()` does `await ApiClient.fetch_leaderboard(...)` and then writes `_leaderboard_label.text` with no `is_instance_valid()` re-check. The request can take seconds; pressing Continue in that window frees the screen and the write hits a freed instance. Guard after every `await` in a Control. |
| `apps/game/client/scripts/ui/run_outcome_confirm.gd` | **BUG** | `_find_ui_parent()` walks the tree depth-first and returns **the first visible `Control` it encounters** — effectively arbitrary. The "leave the dungeon?" prompt can end up parented to the HUD, the minimap or a status pip, inheriting its anchors and mouse filter. Parent it to a known CanvasLayer (`MenuStack._confirm_layer` already exists for exactly this). |
| `apps/game/client/scripts/ui/settings_row.gd` | **BUG** | `_on_slider_changed()` calls the row's `setter` on every value change (once per drag pixel) and the `commit` callable only on `drag_ended`. The split exists precisely so expensive work is deferred — and `DisplayService`'s setters ignore it, calling `apply_all()` + `save()` per step. Make every expensive setter cheap and put the apply/save in `commit`. |
| `apps/game/client/scripts/ui/settings_row.gd` | **BUG** | `reset_to_default()` for an `option` row only resolves the default when it is a `String` (`options.find(default_value)`); an integer-index default falls through to `0`. Silently resets the wrong option. |
| `apps/game/client/scripts/ui/settings_schema.gd` | **ENH** | `PAGES` declares six pages (`gameplay`, `display`, `audio`, `controls`, `accessibility`, `advanced`) and `entries()` returns one flat array — the page field is carried per row and the grouping is the consumer's job. `UX-07` should use this rather than invent tabs. |
| `apps/game/client/scripts/ui/settings_schema.gd` | **ENH** | `entries()` is 146 body lines returning one flat array of 40+ rows. `UX-07` needs it grouped by the `PAGES` it already declares; split into `_gameplay_rows()`, `_display_rows()`, … first. |
| `apps/game/client/scripts/ui/training_dummy_health_bar.gd` | **CLEAN** | One-line override so the dummy's bar survives death. |
| `apps/game/client/scripts/ui/ui_symbol_atlas.gd` | **BUG** | `_region_for_key()` calls `push_error` on every miss with no de-duplication. A missing glyph key on a per-frame refresh (the HUD rebuilds control hints on device change, the status row refreshes at 10 Hz) floods the log and tanks the frame in debug. Warn once per key, as `RoomGraphAssigner._fallback_warned` already does. |
| `apps/game/client/scripts/ui/ui_symbol_atlas.gd` | **CLEAN** | The shared-manifest cache keyed by `path|texture_override` is the right shape and correctly makes the colourblind status variant a separate entry. |
| `apps/game/client/scripts/ui/ui_text_scale.gd` | **BUG** | **The subtitle-scale and UI-text-scale settings do nothing.** `_registered` is an `Array[WeakRef]` that is **never appended to** — there is no `register()` function anywhere in the project — so `apply_all()`, called from `DisplayService:383` and `AccessibilitySettings:169`, iterates an empty array. `_apply_to_label()` is private and has no external caller. Both sliders are exposed in settings, both persist, and neither changes a single label. This is the accessibility defect behind `AX-04`: add `register(label)`, call it from `GameUISkin`'s label styling helpers (which every screen already goes through), and stamp `_ui_text_base_size` there. |
| `apps/game/client/scripts/ui/umbral_waves_menu.gd` | **CLEAN** | Consistent with the other portal menus. |
| `apps/game/client/scripts/ui/warden_preview_rig.gd` | **CLEAN** | Framing maths, the two-frame reframe with an `is_inside_tree()` guard after the awaits, and the outline pass are all correct. |

#### `scripts/meta`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/meta/mode_unlock_service.gd` | **CLEAN** | Content-driven gating, per-character announcement flags and the requirement-progress lines are all correct. |
| `apps/game/client/scripts/meta/progress_counters.gd` | **BUG** | `shortfall()` returns the condition with the **largest** gap (`worst_gap`), i.e. the goal you are furthest from. `AD-05` and every "you are close to X" line want the **nearest** one. Rename this to `largest_shortfall()` and add `nearest_shortfall()`, or callers will advertise the least achievable goal. |
| `apps/game/client/scripts/meta/progress_counters.gd` | **PERF** | `snapshot()` recomputes all eight counters, including `dungeons_cleared()` which loops `DungeonCatalog.ENTRIES` calling `is_difficulty_tier_cleared()` per dungeon. `meets()` and `shortfall()` call it whenever no counters are passed, and the hub calls those per portal per requirement. Cache one snapshot per frame, invalidated on `LocalSave` write. |
| `apps/game/client/scripts/meta/run_history_service.gd` | **PERF** | `get_runs()` re-reads `LocalSave.get_meta_data()` and rebuilds the array on every call; `run_count()`, `runs_for()`, `best_depth()`, `best_kills()`, `best_time()` and `recent_success_rate()` all call it independently. Rendering the results screen rebuilds the same 20-entry list five or more times. Cache and invalidate on `record()`. |

#### `scripts/hub`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/hub/hub_interactable.gd` | **CLEAN** | Highlight tween with material duplication and restore, deferred setup, and an `interact_id` guard that disables a misconfigured node rather than failing silently at interaction time. |
| `apps/game/client/scripts/hub/hub_interactable.gd` | **L10N** | `display_name` is an `@export` filled with English in the hub scene and `get_prompt()` formats it directly. `HD-08` unifies prompts; route the name through `tr()` at the same time. |

#### `scripts/dialogue`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/dialogue/dialogue_conditions.gd` | **ENH** | `evaluate()` is 92 body lines of a flat `match` over ~30 condition keys. `UX-04` needs it to report *why* a choice is gated; a dictionary of small handlers makes that possible. |

#### `scripts/audio`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/audio/audio_settings.gd` | **CLEAN** | The `apply_live` / `request_commit` / `DebouncedSave` split is exactly right — this is the model `DisplayService` should copy. |

#### `scripts/net`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/net/api_config.gd` | **BUG** | With no env var, no `user://api_config.json` and (per the bug above) no dev config, `_resolve_base_url()` falls through to `DEFAULT_BASE_URL = "https://api.aumbrye.example"` — a reserved documentation TLD that cannot resolve. It passes the release HTTPS check, so `cloud_calls_enabled()` returns **true**, boot attempts a session refresh that times out after 8 s, and `results_screen._load_leaderboard_panel()` awaits a doomed request. Default to `""` (cloud disabled) instead of a fake host. |
| `apps/game/client/scripts/net/api_config.gd` | **BUG** | `DEV_API_CONFIG_PATH` is `"res://config/dev_api.json"` and is passed to `ContentLoader.load_json()`, which resolves relative to `content_root()` — producing `<content_root>/res://config/dev_api.json`, a path that can never exist. **`apps/game/client/config/dev_api.json` (which sets `http://localhost:5000`) is therefore never read**, and every boot logs a missing-content error for it. Load it with `FileAccess`/`ResourceLoader` against `res://`, not through `ContentLoader`. |

#### `scripts/platform`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/platform/privacy_settings.gd` | **CLEAN** | Crash reporting is opt-in and defaults to off, which is the correct default. |

#### `scripts/art/characters`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/art/characters/character_rig_catalog.gd` | **CLEAN** | Manifest cache with negative caching for a missing archetype. |
| `apps/game/client/scripts/art/characters/material_flash.gd` | **CLEAN** | Per-mesh tween tracking through metadata, shader-uniform capability cache, and a colourblind path on the damage-type tint. |

#### `scripts/art/lighting`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/art/lighting/light_flicker.gd` | **CLEAN** | Small and correct; duplicates the material before mutating it, which is exactly what `sky_birds.gd` fails to do. |

#### `scripts/art/props`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/art/props/diorama_weapon_kit.gd` | **ENH** | `ARCHETYPE_ALIASES` hardcodes 28 item-id-to-archetype mappings in script while every one of those items already declares its archetype in `content/weapons/*.json` (the function even falls back to reading it). Drop the table and read the content; otherwise a new weapon needs an edit in two places. |

#### `scripts/art/style`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/art/style/pixel_diorama_hub_structures.gd` | **ENH** | `build_fountain()` is 90 body lines. |
| `apps/game/client/scripts/art/style/pixel_diorama_portal_accents.gd` | **ENH** | `add_accents()` is 121 body lines of procedural geometry in one function. |
| `apps/game/client/scripts/art/style/pixel_diorama_style.gd` | **ENH** | `PALETTES` is a ~250-line hardcoded `const Array` of `Color` values that duplicates `content/art/palettes.json`, which the file also loads. Keeping a fallback is reasonable; keeping 250 lines of it inline is not. Move the fallback to a `.tres` or trim it to one palette. |

#### `scripts/art/world`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/art/world/banner_vane.gd` | **CLEAN** | Angle approach with a max step; no allocation. |
| `apps/game/client/scripts/art/world/celestial.gd` | **CLEAN** | Real solar and lunar geometry — declination, hour angle, elongation, illuminated fraction, a lunar epoch chosen so day zero is a full moon. Genuinely careful, and the comments explain the two sign errors already fixed. |
| `apps/game/client/scripts/art/world/distant_skyline.gd` | **CLEAN** | `_window_material` is its own instance, not a shared cached one — the night-window fade mutates only its own material. (Checked because `sky_birds.gd` does the opposite.) |
| `apps/game/client/scripts/art/world/distant_skyline.gd` | **ENH** | `_build_fields()` (105) and `_build_walkers()` (129) are long procedural builders; both run at floor/hub load and are worth measuring against the `VS-08` budget. |
| `apps/game/client/scripts/art/world/night_lights.gd` | **PERF** | `bind()` connects `SceneTree.node_added`, which fires for **every node added anywhere**, and `_on_node_added()` runs a cast plus a group check on each. A floor build adds thousands of nodes (rooms, walls, props, enemies, chests), so this is a callback per node during the single most load-sensitive moment in the game. Adopt lights from the room build instead, or disconnect during the build and re-scan once at the end. |
| `apps/game/client/scripts/art/world/sky_birds.gd` | **BUG** | `modulate_children()` calls `PixelDioramaStyle.make_silhouette_material(BIRD_COLOR)`, which returns a **cached, shared** material, and then mutates its `albedo_color.a` and flips it to `TRANSPARENCY_ALPHA` **every frame**. Any other caller that asks for a silhouette material in that colour gets its transparency driven by the bird fade, permanently. Duplicate the material once in `_ready()` and mutate the copy. |
| `apps/game/client/scripts/art/world/sky_birds.gd` | **ENH** | `BAT_COLOR` is declared and never used — `_bird_material()` always uses `BIRD_COLOR`. Either wire the night variant up or delete the constant. |

#### `scripts/debug`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/debug/debug_overlay.gd` | **PERF** | `_process()` is 113 body lines and calls `get_nodes_in_group()` three times **per frame** (lines 138, 142, 143) to count debug meshes. It is gated by `show_debug` for the label but the group scans run regardless. Move the counting behind the same `show_debug` check and throttle it to 4 Hz. |

#### `scripts/tools`

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/tools/draw_call_probe.gd` | **BUG** | Same `set_character_profile("Perf Warden", …)` save write, and it is the second tool `VS-08` and `RM-11` ask you to run repeatedly. |
| `apps/game/client/scripts/tools/export_diorama_anim_libraries.gd` | **ENH** | Reachable from no scene, no preload and no `class_name` use — it can only be run by editing a scene to point at it. Give it a `scenes/debug/*.tscn` entry like every other tool, or document the invocation in `CLAUDE.md`. |
| `apps/game/client/scripts/tools/export_voxel_meshes.gd` | **ENH** | Same: no scene, no caller. See above. |
| `apps/game/client/scripts/tools/perf_audit.gd` | **BUG** | Calls `LocalSave.set_character_profile("Perf Warden", …)`, which **renames the player's currently selected character and autosaves it**. `docs/CORE_GAMEPLAY_REVIEW.md` §172a documents this hazard for the capture scenes and this tool is not on that list — yet `VS-08` asks you to run it at the start and end of every phase. Give the perf tools a read-only path (skip the profile write when a character is already selected), or the performance baseline costs the developer their save. |
| `apps/game/client/scripts/tools/phase_walk.gd` | **BUG** | Calls `LocalSave.queue_boot_new_game()` + `execute_boot()`, creating a character and consuming a roster slot (`MAX_CHARACTER_SLOTS` is 5). Running it a few times fills the roster. |
| `apps/game/client/scripts/tools/procgen_loop_report.gd` | **ENH** | Same: no scene, no caller, and it additionally calls a private `_method()` on `SeedHealthScript` across a module boundary. |
| `apps/game/client/scripts/tools/village_perf_probe.gd` | **BUG** | Same `set_character_profile("Perf Warden", …)` save write. |

#### Scenes

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scenes/ui/class_card.tscn` | **BUG** | Dead scene. `character_create_ui.gd` preloads `class_card.gd` and builds the cards in code; the `.tscn` is instantiated by nothing and ships in the export. Same class of defect as `C-35` in `docs/CORE_GAMEPLAY_REVIEW.md`. Delete it or use it. |

#### `assets/shared` — shaders

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/assets/shared/pixel_diorama_surface.gdshader` | **PERF** | The wind-sway branch computes `inverse(MODEL_MATRIX)` **per vertex** to bring a world-space push back into model space. A full 4×4 inverse per vertex is among the most expensive things a vertex shader can do, and every swaying surface in the hub and the waves arena pays it on every vertex of every frame. `MODEL_MATRIX` here is a rigid transform, so the inverse of its rotation is its transpose: replace `(inverse(MODEL_MATRIX) * vec4(push, 0.0)).xyz` with `push * mat3(MODEL_MATRIX)`, or publish the inverse as a uniform written once by the CPU. |
| `apps/game/client/assets/shared/pixel_diorama_emissive.gdshader` | **PERF** | Identical `inverse(MODEL_MATRIX)` per vertex in the same wind branch. Fix both together — they must stay visually in step or swaying geometry and its emissive trim will separate. |
| `apps/game/client/assets/shared/pixel_diorama_surface.gdshader` | **CLEAN** | `instance uniform` is used for flash, dissolve and skin tint precisely so every character and prop can share one `ShaderMaterial` rather than duplicating one per hit. The comment says so and the code holds to it — this is why `MaterialFlash` is cheap. |
| `apps/game/client/assets/shared/pixel_outline.gdshader` | **CLEAN** | Four-tap depth/normal edge detect; bounded loop, five texture fetches. |
| `apps/game/client/assets/shared/pixel_screen_finish.gdshader` | **CLEAN** | One bounded 8-iteration loop, four fetches — acceptable for a full-screen pass. Re-measure under `VS-08` at the low-res presets `HD-03` adds. |
| `apps/game/client/assets/shared/pixel_sky.gdshader` | **CLEAN** | No texture fetches, one bounded loop; procedural banded sky. |
| `apps/game/client/assets/shared/portal_ellipse.gdshader` | **CLEAN** | Small procedural shader, no fetches. |
| `apps/game/client/assets/shared/ui_vignette.gdshader` | **CLEAN** | Small procedural shader, no fetches. |
| `apps/game/client/assets/shared/pixel_diorama_finish.gdshaderinc` | **CLEAN** | Shared quantise/hash/triplanar helpers; the one place the banding maths lives, included by both surface shaders. |

#### Scenes — the deep pass

The mechanical sweep resolved every `ext_resource` path and `NodePath` in all 290 scenes. This is
what reading them turned up that a path check cannot see.

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scenes/props/*/{pillar,sconce,rubble_a,rubble_b}.tscn` (40 files) | **BUG** | Every one is a three-line file containing a bare `Node3D` and nothing else — no mesh, no collision, no material. All ten `content/biomes/*.json` reference them from a `propKit` block. Nothing reads `propKit`. Promoted to **`RM-21`**. |
| `apps/game/client/scenes/rooms/*/*.tscn` (100 files) | **ENH** | Two authoring generations with opposite door conventions: the 30 castle/crystal/swamp scenes author real door flags and 1–4 sockets, the 70 newer-biome scenes author two sockets and `door_north = door_south = false`. Neither is broken at run time — the builder closes and re-opens every door from the graph, and `_ensure_socket_completeness()` synthesises the missing sockets — but `RM-02` and `RM-16` both edit these files and two conventions is how a real mismatch gets introduced. Promoted to **`RM-22`**. |
| `apps/game/client/scenes/hub/hub.tscn` | **CLEAN** | 539 lines, the largest scene in the project, and every one of its ext_resources resolves. |
| `apps/game/client/scenes/debug/empty_world.tscn` | **CLEAN** | Deliberately scriptless — it is the blank stage the capture and perf scenes parent into. |

#### `packages/procedural` — the C# generator (27 files, 2,833 lines)

This package is **not** the gameplay path. `docs/ADR/0002-procgen-authority-split.md` names GDScript
`DungeonProcgen` authoritative and freezes this one to layout plus placements; it declares that in the
definition itself through `generatorCapabilities`. Read it anyway, because the backend serves floors
from it and `SY-10` proposes closing the gap.

| File | Kind | Finding |
|---|---|---|
| `packages/procedural/Layout/LayoutGraphGenerator.cs` | **BUG** | The grower only ever adds an edge to a **new** cell, so the graph it produces is a spanning tree: no loops, ever. The GDScript generator spends a `loopBudget` of 4 per floor adding shortcut edges scored by largest detour (`RM-15`, `room_graph_generator.gd`). A floor served from the backend therefore has no shortcuts, no `shortcut` edge kinds, and nothing for `room_shortcut_gate_content.gd` to build — the single most soulslike thing the floor does is absent on that path. Either port the loop pass or make the capability declaration say `layout_tree_only` so a client knows to add its own. |
| `packages/procedural/Layout/RoomPlacement.cs` | **BUG** | `BuildRooms` walks `adjacency[current]`, a `HashSet<string>`, and the **first** neighbour to claim a child fixes that child's yaw and position. `HashSet` enumeration order is not part of the .NET contract — it is an implementation detail of the bucket layout. The output of this method is hashed into `checksum` by `CanonicalJsonSerializer`, so a runtime upgrade that changes `HashSet` internals silently changes the checksum for every existing seed. Sort the neighbour list ordinally before the loop; it costs nothing at 30 rooms and it is the difference between "deterministic" and "deterministic on this runtime". |
| `packages/procedural/Assignment/RoomTypeAssigner.cs` | **BUG** | `PickSecretNodes` only considers a node whose neighbours **all** sit at a greater `GridX` — a dead end that opens west. On a graph the grower biases north (`if (dx != 0 && cz < 1) continue`), that set is frequently empty. When it is, and the biome sets `requiresSecret`, `ConnectivityValidator` fails the attempt and `DungeonGenerator` retries with a fresh seed — up to 48 times, discarding a fully valid layout each time over a constraint that has nothing to do with whether a secret room could be placed. Relax the predicate to "degree 1 and not entrance/boss". |
| `packages/procedural/Generation/DungeonGenerator.cs` | **BUG** | The retry loop catches `Exception` — every exception, 48 times. A `NullReferenceException` or an `ArgumentOutOfRangeException` from a genuine coding error is indistinguishable from "this seed produced an invalid layout", so a real bug surfaces as `Failed to generate dungeon … after 48 attempts` with the true cause buried in `InnerException`. Catch only the validation exception type this path is allowed to throw, and let everything else out. |
| `packages/procedural/Generation/DungeonGenerator.cs` | **BUG** | `Generate()` applies `DungeonSeedDeriver.MixFloorSeed(seed, floorIndex)` before generating; the public `TryGenerateOnce()` does not. Two callers asking for the same floor by the two entry points get different floors. `DungeonSeedDeriver.GenerationSeed()`, which composes both derivations correctly, is never called from anywhere. Make `TryGenerateOnce` internal, or have it take an already-derived seed and say so in the signature. |
| `packages/procedural/Assignment/RoomTypeAssigner.cs` | **ENH** | `PickSecretNode` (singular) is dead — superseded by `PickSecretNodes` and called by nothing. Delete it; it duplicates the filter above and will drift from it. |
| `packages/procedural/Assignment/RoomTypeAssigner.cs` | **PERF** | The edge projection calls `assigned.First(r => r.LayoutNodeId == e.From)` and again for `.To`, inside a `Select` over every edge — a linear scan per endpoint per edge. At 30 rooms this is invisible; it is called on the run-creation request path, so build the dictionary once outside the projection. |
| `packages/procedural/Placement/EnemyPlacer.cs` | **ENH** | The threat budget is `base + perTier*(tier-1) + playerLevel*5` with no ceiling, so a high-level character generates strictly more enemies per room on the same tier — the opposite of what `AD-06`'s difficulty curve wants, and unbounded. Cap the level term, or fold it into the tier term. The RNG-ordering comment above it is exactly right and should survive the change. |
| `packages/procedural/Random/SeededRandom.cs` | **CLEAN** | SplitMix64 with the modulo bias documented, justified and deliberately frozen as a cross-language contract. This is how a determinism decision should be recorded. |
| `packages/procedural/Serialization/CanonicalJsonSerializer.cs` | **CLEAN** | Sorted-key canonical form, checksum computed over the graph without the checksum field, and a comment explaining why the single-pass build is byte-identical to the two-pass one it replaced. |
| `packages/procedural/Validation/ConnectivityValidator.cs` | **CLEAN** | Entrance/boss existence, boss-not-adjacent, reachability and whole-graph connectivity, each with its own failure string. |

#### `services/backend` — the API (34 files, 4,654 lines)

The backend is the most carefully written code in the repository: constant-time login, app-id pinning
on Steam tickets, per-account rate-limit partitions ordered after authentication, forwarded headers
trusted only when a proxy is named, save quarantine rather than silent defaults, and run completion
validated against elapsed wall-clock, kill ceilings and a loot-instance-id union. Almost every
non-obvious decision carries a comment saying what would break without it. Four findings.

| File | Kind | Finding |
|---|---|---|
| `services/backend/src/Aumbrye.Api/Program.cs` | **BUG** | `app.UseMiddleware<VersionHeaderMiddleware>()` runs **before** `app.UseCors("web")`, so the 426 the version gate emits carries no `Access-Control-Allow-Origin` header. A browser drops that response and `fetch` rejects with a `TypeError` — `apps/web/src/api/client.ts` never sees `res.status === 426`, so `VersionMismatchError` is never thrown, `versionMismatch` is never set, and `VersionGate` never renders. The entire "this page is out of date, please reload" path is dead from a browser; only a non-browser client sees the 426. Move `UseCors` above the version middleware. |
| `services/backend/src/Aumbrye.Application/Services/SaveService.cs` | **BUG** | `PutCurrentAsync` is a read-modify-write with no concurrency token — no `[Timestamp]`, no `IsConcurrencyToken`, and `grep -rn "Concurrency\|RowVersion\|xmin"` over `Aumbrye.Domain` and the DbContext returns nothing. Two clients writing at once both read the same `UpdatedAt`, both pass the "server is newer" check, and the second silently overwrites the first. The same shape applies to `RunService.CompleteRunAsync`, where the `run.Status` guard is read outside any transaction, so a duplicated complete request can pass it twice and grant rewards twice. Add a concurrency token to `SaveBlob` and `Run` and map it to Postgres `xmin`. |
| `services/backend/src/Aumbrye.Api/Middleware/VersionHeaderMiddleware.cs` | **ENH** | The gate only fires when the header is **present** — omitting `X-Client-Version` entirely bypasses it. That is a reasonable choice for third-party callers and a bad one for the shipping game client, and nothing states which it is. Either document it as deliberate, or require the header on the endpoints the client uses. |
| `services/backend/src/Aumbrye.Application/Services/SaveService.cs` | **PERF** | `QuarantineAsync` de-duplicates with `AnyAsync(q => q.AccountId == accountId && q.RawJson == rawJson)` — an equality comparison against a full save blob, on a column with no index. It runs on exactly the path where the database is already unhappy. Compare a SHA-256 of the blob stored in an indexed column instead. |
| `services/backend/src/Aumbrye.Api/Program.cs` | **CLEAN** | The `--healthcheck` self-probe, the rate-limit partitions, the forwarded-headers gate and the authentication-before-rate-limiter ordering are all correct and all explained in comments. |
| `services/backend/src/Aumbrye.Infrastructure/Security/SteamAuthService.cs` | **CLEAN** | The web API key travels in the POST body so it never reaches an access log; the app id is pinned server-side by `AuthService.TryPinAppId` and the client's value is never forwarded; family sharing is rejected by comparing `ownersteamid`. |

#### `apps/web/src` — the marketing and account site (19 files, 2,588 lines)

| File | Kind | Finding |
|---|---|---|
| `apps/web/src/api/client.ts` | **BUG** | The 426 handling here is correct and unreachable — see the CORS ordering finding in `Program.cs` above. Fix the backend; then verify from a browser, because this is exactly the kind of bug that stays invisible to a `curl`-based check. |
| `apps/web/src/auth/AuthProvider.tsx` | **BUG** | `markSessionPresent` and `clearTokens` call `localStorage` unguarded. Safari private mode and any browser configured to block site data throw on access, which takes down `applyAuth` and therefore every sign-in. `VersionGate` in the same codebase wraps its `sessionStorage` access in `try/catch` and says why; this file needs the same treatment. |
| `apps/web/src/auth/AuthProvider.tsx` | **ENH** | `scheduleRefresh` computes `expiresAt - now - 60_000` and clamps at 0. An access token with a lifetime under a minute schedules an immediate refresh, whose response schedules another — a tight loop against the auth endpoint. Floor the delay at a few seconds, and ignore an `expiresAt` that does not parse rather than passing `NaN` to `setTimeout`. |
| `apps/web/src/api/client.ts` | **CLEAN** | `combineSignals` fixes a real bug (react-query's signal replacing the timeout signal, so a hung backend left queries pending forever) and the comment records it. Cookie transport for the refresh token is opted into per request and explained. |

#### Tooling — `tools/`, `scripts/` (30 Python, 22 Node)

| File | Kind | Finding |
|---|---|---|
| `tools/generate_weather_audio.py` | **BUG** | `np.random.default_rng(abs(hash(name)) % (2**32))` — Python randomises `str` hashing per process unless `PYTHONHASHSEED` is set, so every run of this generator produces **different audio for the same name**. Regenerating one weather sound silently rewrites all of them with new noise. Use a stable digest: `int.from_bytes(hashlib.sha256(name.encode()).digest()[:8], "little")`. |
| `tools/generate_music.py` | **BUG** | The same `abs(hash(name))` seeding at line 311, with the same consequence for every music stem. Fix both in one change — they are the only two sites; `generate_sfx.py` and `generate_foley.py` use fixed literals and are reproducible. |
| `.pre-commit-config.yaml` | **ENH** | The `gdformat`/`gdlint` hooks exclude `^apps/game/client/scripts/.*/addons/.*\.gd$`, but the vendored addon lives at `apps/game/client/addons/godot_mcp/`, which the `files:` pattern never matched in the first place. The exclusion is dead text that reads as protection. Either drop it or point it at the real path. |
| `scripts/validate-content/validate.mjs` | **CLEAN** | Validates 662 content files against the 63 schemas plus nine cross-reference passes (catalog ids, loot-table item ids, affix namespacing, xp-curve runtime keys, the narrative graph, audio bank distinctness). The only content JSON it does not cover are five files under `content/fixtures/`, which are test data for the debug scenes rather than shipped content. |
| `scripts/audit-sweep.mjs` | **CLEAN** | Added by this work. Reports, never fails a build — the same contract as every other diagnostic in `CLAUDE.md`. |

#### Content and project configuration

| File | Kind | Finding |
|---|---|---|
| `content/biomes/*.json` | **BUG** | The `propKit` block in all ten biome definitions points at 40 empty scenes and is read by no code. See **`RM-21`**. |
| `apps/game/client/project.godot` | **ENH** | `editor_plugins/enabled` lists `res://addons/godot_mcp/plugin.cfg`, and all three export presets exclude `addons/godot_mcp/*`. An exported build therefore names a plugin that is not in the package. Godot ignores `EditorPlugin` registrations outside the editor so nothing breaks, but it is a dangling reference in the one file a packaging problem would show up in. |
| `apps/game/client/project.godot` | **CLEAN** | ~40 GDScript warnings promoted to errors, shader globals declared for the wind and rain fields, 34 autoloads, integer stretch scaling. The autoload count is accepted debt, recorded in `docs/remaining_points.md` R-01. |
| `apps/game/client/export_presets.cfg` | **CLEAN** | All three presets exclude `addons/godot_mcp/*`, `scripts/tools/*` and `scenes/debug/*`, and **no shipping file references any excluded path** — verified by grep. The MCP server, which opens a TCP port in the editor, cannot ship. |
| `apps/game/client/scripts/debug/debug_console.gd` | **CLEAN** | Gated on `OS.is_debug_build()` in **both** `_ready()` and `_input()`, so it cannot be opened in a release build. `SY-11`'s concern about this is already satisfied; only the `content/` copy step and the exported-build smoke pass remain. |
| `.github/` | **CLEAN** | Contains `CODEOWNERS` and `PULL_REQUEST_TEMPLATE.md` and nothing else — no `workflows/`, no `dependabot.yml`. The standing decision in `CLAUDE.md` is being honoured. |

#### Art source, baked meshes and voxel assets

| File | Kind | Finding |
|---|---|---|
| `art-source/characters/` | **BUG** | The voxel art source is a full generation behind the shipped assets, in both directions. `tools/voxel-import/archetypes.py` builds its archetype list from `PLAYER_FRAMES` — `slight`, `lean`, `standard`, `stout`, `towering` — and `apps/game/client/scripts/save/character_appearance.gd` offers exactly those five. `apps/game/client/assets/characters/` correctly holds all five. But `art-source/characters/` still holds the **retired** stature×build grid: `player_warden_compact`, `_compact_heavy`, `_compact_lean`, `_heavy`, `_tall`, `_tall_heavy`, `_tall_lean` — 42 `.vox` files for frames the game does not offer — and holds **no source at all** for `slight`, `stout` or `towering`. Three of the five body types a player can pick cannot be re-authored or re-exported from source; anyone running `tools/voxel-import/cli.py` over `art-source/` today builds the wrong set. Delete the seven retired directories and author (or re-export) the three missing ones. |
| `apps/game/client/scripts/art/characters/voxel_mesh_builder.gd` | **BUG** | The baked-mesh recolour path can only ever produce white. `load_mesh` takes the baked branch when `not FileAccess.file_exists(source_path)`, sets `recolour_from_baked`, and then calls `_recolour_mesh(mesh_out, _theme_colour_for(source_path, theme))` — passing the path it just established does not exist. `_theme_colour_for` reads it, gets an empty string, and returns `Color.WHITE`, so every themed baked mesh is painted pure white instead of palette-snapped. **Latent today**: no baked `.tres` meshes are committed (the repo has exactly two `.tres` files, neither a mesh), so the branch never runs — it fires the first time anyone uses `scripts/tools/export_voxel_meshes.gd`. Read the colour from the baked resource, or keep the `.voxels.json` beside the bake. |
| `apps/game/client/scripts/art/characters/voxel_mesh_builder.gd` | **PERF** | `static var _cache` is keyed `path:theme` and never evicted or bounded. There are 394 source meshes and one entry per theme each; a long session that visits every biome accumulates all of them for the life of the process. Cap it, or clear it on run teardown alongside the other per-run caches. |
| `apps/game/client/assets/animations/diorama/*.res` (6 files) | **CLEAN** | Six distinct `AnimationLibrary` resources (verified by checksum — `brute` and `melee` are the same size but not the same file), each carrying position/rotation tracks for the rig's ten nodes plus an `AnimDirector` track. |
| `apps/game/client/assets/audio/default_bus_layout.tres` | **CLEAN** | Five buses — Master, Music, SFX, Ambience, UI — with no effects and 0 dB, which looks like an omission and is not: `scripts/audio/audio_director.gd` adds the reverb and compressor at run time so it can retune them per room. All four non-master buses are driven by `audio_settings.gd` and previewed by `settings_ui.gd`. Do not "fix" this by baking effects into the layout. |
| `apps/game/client/assets/ui/aumbrye_ui.tres` | **CLEAN** | 463 lines, wired as `theme/custom` in `project.godot`, one `FontFile` reference that resolves. Every `StyleBoxFlat` shares the same 8 px content margin and 2 px border, which is why the UI reads as one thing. `HD-02` and `UX-01` extend this file rather than adding per-scene overrides. |
| `.vox` / `.import` assets | **CLEAN** | 162 `.vox` and 144 `.import` files; every `.import` has its source file present, and no `.vox` is referenced from game code (they are importer input only, consumed by `tools/voxel-import/`). |

#### `packages/shared` and `tools/procgen-cli` — the remaining C#

| File | Kind | Finding |
|---|---|---|
| `packages/shared/Contracts/ApiVersions.cs` | **BUG** | `ExpectedClientVersion = "0.4.0"` is the fourth independent copy of the release version. The others are `apps/web/package.json` (`0.4.0`, compiled into `__APP_VERSION__` by `vite.config.ts`), `apps/game/client/project.godot` (`config/version="0.4.0"`) and `apps/game/client/scripts/net/api_config.gd:10` (`CLIENT_VERSION := "0.4.0"`). They agree **today**; the moment one moves, the version gate 426s every client of the other — and because of the CORS ordering defect in `Program.cs`, the browser will not even show the upgrade prompt. A fifth copy already disagrees: the newest patch note in `apps/web/content/patch-notes/` is `0.6.0`. Pick one source and derive the rest, or list all five in the release checklist. → `SY-11`. |
| `tools/procgen-cli/Program.cs` | **BUG** | The top-level `catch (Exception ex)` prints `ex.Message` and nothing else. `DungeonGenerator.Generate` deliberately wraps the last failure as `InnerException` after 48 attempts, so the CLI discards exactly the diagnostic the generator went out of its way to preserve, and prints `Failed to generate dungeon for biome 'x' after 48 attempts.` with no cause. Print `ex.ToString()`, or walk the inner chain. |
| `tools/procgen-cli/Program.cs` | **ENH** | `room-kit-specs` hardcodes nine kinds — entrance, stairs, courtyard, hall, treasure, secret, arena, boss, puzzle — and omits `corridor` and `shop`. Its output is `content/fixtures/room_kit_specs.json`, the C#↔GDScript parity fixture, so **corridor geometry has never been parity-checked** — which is worth knowing before `RM-14` starts selecting corridors. Derive the kind list from `RoomTemplateCatalog` instead of restating it. |
| `packages/shared/Contracts/*` | **CLEAN** | Six contract files, records only, shared by the API and consumed by `apps/web/src/api/schema.d.ts` through `packages/shared/openapi/aumbrye-api.v1.yaml`. `scripts/openapi-drift/check-routes.mjs` keeps the spec and the routes honest. |

#### The public site's content, and the deployment files

The web app's **code** was covered above. Its **content and serving configuration** are a separate
story: every one of these is a place where what the public is told has drifted from what the game is.

| File | Kind | Finding |
|---|---|---|
| `apps/web/src/content/biomes.json` | **BUG** | Lists five biomes — forgotten_castle, crystal_caverns, poison_swamp, frozen_fortress, dark_cathedral. The game ships **ten**: iron_vault, prism_depths, venom_mire, glacial_hollow and umbral_chapel are absent. This file is a hand-maintained copy of `content/biomes/*.json` with no check keeping the two in step. Generate it from the content directory during the web build, or add it to `scripts/validate-content/validate.mjs` as a cross-reference pass — that validator already does nine of exactly this kind. |
| `apps/web/content/wiki/biomes.md` | **BUG** | Same five-biome list in prose: "EA includes Forgotten Castle, Crystal Caverns, Poison Swamp, Frozen Fortress, and Dark Cathedral." Half the game's biomes are missing from its own wiki. |
| `apps/web/index.html` | **BUG** | The meta description — the text that appears in every search result and link preview — says "five deadly biomes". Ten ship. |
| `apps/web/content/wiki/controls.md` | **BUG** | The published control list is wrong in both directions. It advertises **"Q parry"**, and there is no `parry` action in `project.godot`'s input map at all. It omits `heavy_attack`, `weapon_art`, `two_hand`, `heal`, `sprint`, `jump`, `map`, `talents` and the five quick-slot actions — that is, most of the soulslike moveset this plan is built around. Regenerate the page from the `[input]` section and the `INPUT_*` translation keys so it cannot drift again. |
| `apps/web/public/sitemap.xml` | **BUG** | Every `<loc>` is a relative path (`<loc>/wiki</loc>`). The sitemaps protocol requires absolute URLs and crawlers discard relative ones, so the sitemap does nothing. `public/robots.txt` has the same defect on its `Sitemap:` line. Emit both from the deploy origin at build time. |
| `apps/web/public/sitemap.xml` | **ENH** | It advertises ten routes; `vite.config.ts` prerenders five (`/`, `/account`, `/patch-notes`, `/wiki`, `/leaderboards`). The five it does not prerender — both patch-note detail pages and all three wiki pages — are precisely the ones with content worth indexing, and they ship as an empty SPA shell. Add them to `staticRoutes`, driving both lists from one array. |
| `apps/web/public/robots.txt` | **ENH** | `Allow: /` includes `/account`, a signed-in page. Disallow it. |
| `apps/web/nginx.conf` | **BUG** | Eleven lines, and no `Cache-Control` anywhere. `index.html` is therefore served with nginx's default caching, which is the exact failure `VersionGate`'s cache-busting reload was written to work around — the comment in that file says a CDN serving stale HTML "cannot defeat it", and a stale `index.html` from this config can. Serve `/index.html` `no-cache` and the hashed `/assets/` bundle `immutable`. |
| `apps/web/nginx.conf` | **ENH** | No security headers at all: no `Content-Security-Policy`, `X-Content-Type-Options: nosniff`, `Referrer-Policy` or `frame-ancestors`. The app deliberately keeps the refresh token in an httpOnly cookie so that no injected script can read it (`AuthProvider.tsx` says so); a CSP is the other half of that defence and it is missing. |
| `apps/web/vite.config.ts` | **ENH** | `build.sourcemap: true` publishes readable sources for the production bundle. Harmless for a marketing site, deliberate or not — decide which, and say so. |
| `docker-compose.yml` | **ENH** | Postgres and Redis publish to the host on their default ports with a default development password, so `docker compose up` puts a reachable database on the developer's network interface. Bind them to `127.0.0.1` (`"127.0.0.1:${POSTGRES_PORT:-5432}:5432"`). The `api` and `web` services are correctly behind an `app` profile, and `Jwt__Secret` is `${JWT_SECRET:?…}` with no default — that part is right. |
| `apps/game/client/translations/strings.csv` | **L10N** | 740 keys, `en` and `ro`, no duplicates and no empty cells — but **146 rows have an identical `ro` and `en` value, and 110 of those are the talent tree** (`talent.branch.*`, `talent.arms_*`, `talent.guard_*`, `talent.aptitude_*`). The entire progression screen is English in the Romanian build. The remaining 36 are mostly loanwords that legitimately match ("Hub", "Seed", "Aspect"). Translate the talent block; it is one contiguous edit. → `SY-07`, `UX-02`. |
| `Directory.Build.props`, `.editorconfig`, `.gdlintrc`, `apps/web/eslint.config.js`, `appsettings.Development.json.example` | **CLEAN** | `TreatWarningsAsErrors` on every C# project, matching the ~40 GDScript warnings promoted to errors in `project.godot`; tabs for `.gd`/`.tscn` and spaces elsewhere; `jsx-a11y` and `react-hooks` both enforced in the web lint; the example appsettings carries a development connection string and no secret. |
| `apps/web/Dockerfile`, `services/backend/Dockerfile`, `services/backend/.dockerignore`, `.gitattributes`, `.gitignore`, `.github/CODEOWNERS`, `global.json`, `Directory.Packages.props`, the four `.ps1`/`.sh` wrappers | **CLEAN** | Read; nothing to report. |

#### Configuration files, schemas, and the guard that no longer exists

The fourth pass opened the last unread JSON: the two files under `apps/game/client/config/`, the 66
schemas, the 394 character asset files, and the handful at the repo root. Three of these are serious.

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/platform/steam_service.gd` | **BUG** | `config/platform.json` can never be read, for a different reason than `config/dev_api.json` and with a worse outcome. The file holds `{"steamAppId": 480}` — a JSON **number**. Godot parses that to `TYPE_FLOAT`, so `str(parsed.get("steamAppId", ""))` yields `"480.0"`, and `"480.0".is_valid_int()` is **false**. Verified empirically on Godot 4.7.2: `type=3 str=480.0 valid_int=false`. The branch silently falls through to `steam_appid.txt` (not tracked — only `steam_appid.txt.example` is) and then to `DEV_APP_ID`. `_initialize()` then sees `app_id == DEV_APP_ID` and calls `_init_stub()`. **A shipped Steam build runs in stub mode unless someone sets `AUMBRYE_STEAM_APP_ID` in the environment**, and nothing says so. Parse with `int(parsed.get("steamAppId", 0))` and reject 0, rather than round-tripping a number through a string. → `SY-11`. |
| `content/fixtures/schema_versions.json`, `content/schemas/MANIFEST.json` | **BUG** | Both files claim a guard that cannot exist. `schema_versions.json`'s own `$comment` says it is "the single source of truth for schema versions that both the backend and the Godot client stamp onto data" and that "`ClientVersionParityTests` asserts the GDScript constants still agree, **so the two cannot drift silently**". `MANIFEST.json` makes the same claim. `services/backend/tests/` does not exist — `CLAUDE.md` forbids test files anywhere in this repository, and the suite was removed. So the two **can** drift silently, and the file that would tell a maintainer to check says the opposite. Four more references to the deleted suite survive in `docs/ADR/0002-procgen-authority-split.md` and `docs/CORE_GAMEPLAY_REVIEW.md` (which still tabulates all 21 test class names). Rewrite the two content comments to name the manual check that replaces the guard, and add a line to `scripts/validate-content/validate.mjs` comparing `schema_versions.json` against the GDScript constants — that validator already runs nine cross-reference passes of exactly this kind, and it is the only mechanism this repo's rules allow. → `SY-12`. |
| `apps/game/client/config/dev_api.json` | **BUG** | The file exists and is correct — `{"apiBaseUrl": "http://localhost:5000"}`, which matches `launchSettings.json`'s `applicationUrl` exactly. It is still never read, for the reason already given in §7.2: `api_config.gd` hands `res://config/dev_api.json` to `ContentLoader.load_json()`, which resolves against the content root. Recorded here because seeing the file's contents makes the defect unambiguous — nobody needs to wonder whether the fallback to `https://api.aumbrye.example` was intentional. |
| `apps/game/client/assets/characters/**/*.json` (394 files) | **ENH** | Nothing validates them. `scripts/validate-content/validate.mjs:308` binds `character-rig.v1.json` to `content/characters/` — the 21 rig manifests — not to the 394 `.voxels.json` and `.mesh.json` files under `assets/` that actually drive every character and enemy silhouette. All 394 parse and their shapes are consistent, but a malformed `cells` array or a wrong `size` surfaces only as a visually broken character at run time. Point the existing `character-rig` binding at both trees, or add a `voxel-mesh.v1.json` schema. |
| `content/schemas/balance-export.v1.json`, `content/schemas/procgen-seed-health.v1.json` | **ENH** | Two of the 62 versioned schemas are bound to nothing — no validator reference, no consumer entry in `MANIFEST.json`, no producer that names them. They describe `reports/` artefacts from `scripts/balance/balance-cli.mjs` and the seed-health audit. Either wire them into those producers or move them to `content/schemas/retired/`, which is where this repo already puts schemas that no longer bind. |
| `content/schemas/{achievement-catalog,achievement-hooks,character-rig}.v1.json` | **ENH** | The only three object schemas of the 62 that omit `additionalProperties: false`, so a typo'd key in an achievement, a hook or a rig manifest validates clean and is then silently ignored by the loader. The other 59 all close their objects. Close these three too. |
| `content/schemas/MANIFEST.json` | **CLEAN** | Pins the current version of each multi-version schema, names every consumer by fully-qualified symbol, and explains why retired schemas are kept — `SaveMigrator` still has to reason about old saves. Four retired schemas sit in `content/schemas/retired/`, exactly as the manifest describes. Apart from the stale test-suite sentence above, this is the best-documented file in the repository. |
| `apps/game/client/config/platform.json`, `steam_appid.txt.example` | **CLEAN** | Both hold `480` — Valve's public Spacewar test id, which is the correct placeholder. The defect is that the game cannot read it, not the value. |
| `apps/game/client/assets/characters/**` — palette keys | **CLEAN** | 155 files carry `paletteSlots` and 85 carry `palette`, which reads like drift and is not: `voxel_mesh_builder.gd` handles both (lines 271 and 278) and `tools/generate_character_voxels.py` emits them deliberately — named material slots for theme-recolourable body parts, literal colour lists for faces, hair and garments. Leave it alone. |
| `services/backend/src/Aumbrye.Api/appsettings.json`, `appsettings.Testing.json`, `launchSettings.json`, `.config/dotnet-tools.json`, `tools/{item_bases,uniques,.generated-manifest}.json`, `project_structure.json`, `global.json`, `.mcp.json`, root `package.json` | **CLEAN** | Read; nothing to report. `appsettings.json` commits no secret and carries a `_comment` telling the operator to set `Jwt__Secret` from the environment. |

#### The 133 scripts the plan had never named

§7.1 used to say that a GDScript file without a row here "was read and found sound". That was too
strong a claim, and checking it is what this pass did: 133 of the 372 scripts are named nowhere in
this document. Roughly twenty-five of them were then opened, chosen by relevance to the three
CRITICALs — combat, the HUD, and the enemies. **Six findings came out of that sample**, so the
blanket has been withdrawn from §7.1 and replaced with what is actually true.

| File | Kind | Finding |
|---|---|---|
| `apps/game/client/scripts/player/dodge.gd` | **BUG** | `process_dodge_physics()` recomputes `iframes_active` from the dodge's own timing window every physics frame and assigns it unconditionally — it never consults `_external_iframes`. `_end_dash()`, ten lines further down, *does* check `_external_iframes` before clearing. One of those two is wrong, and it is the first: any invulnerability granted from outside is silently cancelled on the next frame that falls outside `[_iframe_start, iframe_end]`. The reachable path is the riposte: `weapon_controller.gd:542` grants external i-frames for the whole execution, `allows_cancel_into("dodge")` permits a dodge out of an attack's RECOVERY phase, and the dodge's first ~0.1 s is *before* its own i-frame window opens — so the player is briefly vulnerable in the exact moment the game promised invulnerability. The fix is one clause: `var iframes := _external_iframes or (elapsed >= … and elapsed <= …)`. **The stagger-rollout path is not affected** — `_cancel_stagger()` calls `_clear_wakeup_iframes()` properly; checked, and stated here so nobody re-traces it. |
| `apps/game/client/scripts/ui/status_pip.gd` | **BUG** | Line 67 is `tooltip_text = status_id`, so hovering a status effect shows the raw content id — `bleed`, `burn` — instead of a name. Every status in `content/statuses/*.json` already carries a `name` and a written `description` ("Wounds that will not close. Pressure them until the body gives."). All of that authored flavour reaches the player nowhere. `combat_hud.gd:438` instantiates these pips for real, so this is on screen in every fight. Look the definition up through the status catalogue and build the tooltip from `name` + `description`. → `HD-06`, `UX-03`. |
| `apps/game/client/scripts/enemies/{crystal_golem,crystal_guardian,crystal_slime,swamp_bogling,swamp_hag,swamp_leech,swamp_toad}.gd` | **ENH** | Seven of the nine enemy scripts are 10–15 lines and do exactly three things: return an id, apply a mesh tint, set a scale. There is no behavioural difference in code between a `swamp_leech` and a `crystal_golem` — everything else comes from `CastleEnemyBase` and the JSON definition. This is the strongest single piece of evidence for the diversity problem §EN is built around: it is not that the enemies are *similar*, it is that at the script level **there is nothing there to be different**. When `EN-05`…`EN-08` give enemies distinct behaviour, these seven files are where the per-archetype hooks belong; if they stay this thin, delete them and let the base class read the tint and scale from the definition JSON. |
| `apps/game/client/scripts/enemies/final_boss_crystal.gd` | **ENH** | Not an enemy. It is a 34-line `Area3D` pickup that bobs, spins, emits `collected` and frees itself — the only file in `scripts/enemies/` that does not extend `CastleEnemyBase`. Move it to `scripts/loot/` or `scripts/dungeon/`; a reader looking for the final boss finds a collectible. |
| `apps/game/client/scripts/combat/poise.gd` | **PERF** | `_physics_process` emits `poise_changed` on **every frame** while a bar is regenerating (line 60), for every enemy that has taken poise damage in the last two seconds. In a room of eight enemies mid-fight that is eight signal emissions per frame into whatever the HUD and boss bar have connected, and the node has no AI-LOD gate of any kind — unlike the enemy AI itself, which strides. Emit on a threshold (say each whole point, or at most 10 Hz), and skip the node entirely at distant LOD. |
| `apps/game/client/scripts/combat/poise.gd` | **ENH** | When a break ends, poise is restored to **full** instantly (`current = max_poise`), and `take_poise_damage` returns early for the whole break, so a staggered enemy is immune to poise damage and then comes back at 100 %. That makes the second stagger cost exactly as much as the first, which removes the pressure gradient a soulslike stagger economy runs on — there is no reward for staying on a big enemy. Restore to a fraction (60–70 % reads well) or regenerate from zero at an increased rate, and let poise damage land during the break so a follow-up commitment means something. → `CB-04`, `EN-06`. |
| `apps/game/client/scripts/ui/guard_indicator.gd` | **ENH** | Lines 25 and 30 call `TranslationServer.translate()` where every other UI script in the project calls `tr()`. It resolves the same key, but it bypasses the `Control`'s own translation domain and context, and it is the kind of inconsistency `SY-07`'s sweep exists to remove. Two-character change. |
| `apps/game/client/scripts/combat/combat_facing.gd` | **CLEAN** | Twenty lines, and one of the most valuable files in the project: it is the single place the project's facing convention lives — **rig forward is `+basis.z`, not `-Z`** — and every hitbox, VFX aim and telegraph heading goes through it so the convention cannot fork. Recorded as clean specifically so that nobody "corrects" it to `-Z` and silently reverses every attack in the game. |
| `apps/game/client/scripts/bosses/arena_boss.gd` | **CLEAN** | Shared arena-boss behaviour — stays inside its arena, announces its own defeat, restores to a full-health first phase when a save is reloaded with it still alive. Its comment records that Castle Knight, Crystal Sovereign and Swamp Hydra each carried a copy before this existed. This is the pattern the seven thin enemy scripts above should follow. |
| `apps/game/client/scripts/combat/damage_resolution.gd` | **CLEAN** | A 16-line data bag carrying the full outcome of one exchange — incoming, outgoing, poise on both sides, crit, backstab, blocked, parried, dodged, absorbed, damage type, hit region, and the per-stage breakdown. The reason the combat maths is auditable. |

### 7.4 Whole-tree checks that came back clean

These were run across every file of their kind and found **nothing**. Recorded because a clean result
is worth as much as a finding, and because these are the checks to re-run after any content change:

| Check | Scope | Result |
|---|---|---|
| JSON parses | 728 content files | 0 failures |
| Dangling id references — biome → enemy / boss / trap / final boss, loot table → item, class → starting and allowed weapons, merchant and recipe → item | all content | 0 dangling (one apparent hit, `forge_reroll_affix.json` → `"any"`, is a wildcard) |
| `ext_resource` paths resolve | 290 scenes | 0 broken |
| Exported `NodePath`s point at a node in the same scene | 290 scenes | 0 broken |
| `tr()` keys used in code are defined in `strings.csv` | 338 keys | 0 missing (740 keys defined, en + ro) |
| Scripts reachable from a scene, preload, `class_name` use or autoload | 372 scripts | 3 unreachable, all tooling — listed above |

### 7.5 Leads that were checked and dismissed

Recorded so they are not re-derived. Each looked like a defect and is not:

- **"UI panels connect to autoload signals without disconnecting."** 20 sites. In Godot 4 a freed
  object's connections are removed automatically, and every one of these connects inside `_ready()`,
  which runs once per instantiation. Not a leak and not a double-connect.
- **"`pixel_diorama_style.gd:_deg_to_rad_array` is 259 lines."** A naive function-length heuristic
  measuring to the next `func`; the span is the `PALETTES` const block. The function is three lines.
  (The const block itself is worth moving — recorded as an `ENH` above.)
- **"Unseeded `randi()` in `waves_run_service.gd` and `affix_roller.gd`."** Both are deliberate seed
  *sources* for a run or a roll that was given no seed, not RNG inside a seeded path.
- **"118 orphan scenes."** All but three are room scenes loaded by a constructed path in
  `BiomeRegistry.get_room_scenes()`, or debug scenes launched by hand. The sweep now excludes both.
- **"`DebugOverlay` ships enabled."** `show_debug` defaults to `OS.is_debug_build()`.
  `docs/GAME_FEEL_REVIEW.md`'s concern about this is stale; only `DebugConsole` still needs the same
  gate (`SY-11`).
- **"`character_flags.gd:139` loses saved integers."** The line reads
  `int(value) if str(value).is_valid_int() else int(default_for(flag_id))`, and a JSON float
  stringifies as `"5.0"`, which `is_valid_int()` rejects — the same trap that is a real bug in
  `steam_service.gd`. It is not one here: `value is float` is handled explicitly four lines earlier,
  so line 139 is only the last-resort branch for exotic types. Correct as written.
- **"The character assets use two different palette keys."** 155 files carry `paletteSlots` and 85
  carry `palette`. Both are emitted deliberately by `tools/generate_character_voxels.py` and both are
  read by `voxel_mesh_builder.gd` — slots for theme-recolourable body parts, literal colours for
  faces, hair and garments.
- **"The audio bus layout has no effects."** It has none, and it should not: `audio_director.gd` adds
  the reverb and compressor at run time so it can retune them per room.
- **"Every room scene in the seven newer biomes is sealed."** They author
  `door_north = door_south = false` and only two sockets, but `DungeonBuilder` closes and re-opens
  every door from the graph and `_ensure_socket_completeness()` synthesises the rest. The authored
  values are editor preview only. It is a consistency problem (`RM-22`), not a broken floor.

### 7.6 How to work through this section

The findings here are **not** a phase. They are small, independent and mostly cheap, and they belong
inside the phase that touches the same file:

- Fix a `BUG` when you next open that file for any reason, or immediately if it is one of the four in
  §9.2.
- Do a `PERF` item alongside `VS-08`, so the baseline is measured before and after.
- Do a `LONG`/`ENH` split **first** when a plan item is about to add to that function — several are
  called out for exactly that (`hurtbox.receive_hit` before `PH-01`, `locomotion._physics_process`
  before `PH-01`, `build_edges` before `RM-04`, `settings_schema.entries` before `UX-07`).
- Re-run `node scripts/audit-sweep.mjs` at the end of every phase and fold new hits into this section.

---

## 8. What this plan deliberately does not do

Recorded so the decisions are not silently revisited:

- **It does not rewrite the procgen stack.** The graph generator, lattice solver, lock placer and
  content assigner are correct. `RM-01` adds shape *inside* the reserved footprint precisely so the
  solver never learns about it.
- **It does not unify the C#/GDScript generator split.** That is `docs/remaining_points.md` R-02 and
  `docs/ADR/0002-procgen-authority-split.md`; it is accepted debt with a written contract and it does
  not block the MVP. The five defects the C# package does carry are recorded in §7.3 — including that
  its layout graph is a spanning tree with no shortcut loops at all — so that when parity is
  eventually closed, nobody starts by re-deriving them.
- **It does not harden the backend.** The missing optimistic-concurrency tokens on `SaveBlob` and
  `Run` are real and are recorded in §7.3, but no MVP player reaches them: online runs are off and
  saves are local. Two exceptions are scheduled under `SY-10` because they break shipping behaviour
  today.
- **It does not consolidate the 37 autoloads** (`remaining_points.md` R-01). Real debt, wrong time.
- **It does not add online runs, Steam, or OAuth** (R-07, R-08, R-10). All stubbed on purpose.
- **It does not touch the save/migration machinery** beyond adding steps for new fields.
- **It does not add a test suite**, per `CLAUDE.md`.
- **It does not bring the C# generator back into parity** — but `SY-10` requires the ADR to be
  updated to record that it has diverged, so nobody later assumes a parity that no longer holds.
