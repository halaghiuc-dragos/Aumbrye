# Bugs & Enhancements Backlog

Last checked against the code: 2026-10-01. Every item below describes what the code does today; an
item is deleted when it is fully implemented (see `.github/PULL_REQUEST_TEMPLATE.md`), and an item
that is only partly done says what is left.

**Item format:** Problem, then Action, Location, How, Links. Links name other items in this file.

**Tags:** priority `P0` breaks the game or a release, `P1` is wrong behaviour players notice, `P2` is
quality or cost. Evidence: `[data]` measured from content or assets, `[code]` found by reading.

**Repo rule:** no test suites and no CI. Verify with the diagnostics in `CLAUDE.md`; section 7 says how
to write a temporary probe.

## Open items by area

| Area | Items |
|---|---|
| Audio | AUDIO-5, SIM-2, A-01, A-03 |
| Platform | REL-2 |
| Dungeons and rooms | V-07, G-09 |
| Combat and animation | G-01, G-05, G-06, AN-5, FUN-2, FUN-3, FUN-6 |
| Progression | FUN-5, SIM-18 |
| Simplification | SIM-1, SIM-9, SIM-11, SIM-12, SIM-14, SIM-23, SIM-28 |

Owner decisions on record: the backend and web stay (frozen behind `ApiConfig.ONLINE_ENABLED`), the
save stack and autoload list are not being rewritten, the hub stays as it is.

---

## 1. Audio

**AUDIO-5 `P1` `[data]` Every sound in the game was synthesized**
- **Problem:** Music, SFX, foley, weather, voices and animal sounds were generated with oscillators, noise and filters, not samples; that, not the playback code, is why the audio sounds basic. The generators are deleted and `sfx.json` is the one cue table, so the shipped files are now fixed assets with no recorded or licensed source behind them.
- **Action:** Replace the bank with recorded or licensed samples, layered per event.
- **Location:** `apps/game/client/assets/audio/`, `content/audio/sfx.json`
- **How:**
  - Source CC0 or licensed packs (for example the Sonniss GDC bundles, Kenney, or CC0 Freesound), and layer each combat event: transient + body + tail, with 3–5 variations and pitch/volume jitter.
  - Commission or license a small music set: per biome one explore loop plus one combat layer on the same tempo, and one boss track with phases (AUDIO-4, A-01).
- **Links:** A-01, A-03, SIM-2.

**SIM-2 Synthesised biome accent**
- **Problem:** `sfx.json` is the single cue table and a missing cue is a debug warning and silence. The one synthesis left is `AudioDirector.play_biome_accent`, a synthesised chirp that every biome ambience emitter plays.
- **Action:** Replace the accent with recorded samples listed in `sfx.json`, then delete the synthesis.
- **Location:** `apps/game/client/scripts/audio/audio_director.gd` (`play_biome_accent`), `apps/game/client/scripts/audio/biome_ambience_emitter.gd`
- **Links:** AUDIO-5.

**A-01 Music is placeholder**
- **Problem:** The biome loops and boss themes are generated placeholders.
- **Action:** Real four-stem sets of equal tempo and length per biome, with `AudioStreamInteractive` for the boss.
- **Location:** `apps/game/client/assets/audio/`
- **Links:** AUDIO-5.

**A-03 Enemies have no voice**
- **Problem:** No enemy defines a `voice`, and `sfx.json` holds only the generic `windup_<class>` and `death` cues.
- **Action:** Per-enemy barks named `windup_<voice>_<class>`, `hurt_<voice>` and `death_<voice>`.
- **Location:** `content/audio/sfx.json`, `content/enemies/*.json`
- **Links:** AUDIO-5.

---

## 2. Platform

**REL-2 `P1` `[code]` Steam is always stubbed**
- **Problem:** `steamAppId` is 480 (Valve's test app), and there's no GodotSteam extension in `addons/`. Steam achievements and ticket sign-in never reach Steam, while the exports still ship `steam_api64.dll`.
- **Location:**
  - `apps/game/client/config/platform.json`
  - `apps/game/client/scripts/platform/steam_service.gd`


---

## 3. Dungeons and rooms

**V-07 Rooms are flat**
- **Problem:** Every generated room shares one walkable elevation: `room_graph_config.gd` forces `max_height_level = 0`, although the biome files author `maxHeightLevel` 1 or 2. Reading the biome value instead changes nothing visible, since `room_graph_geometry.gd` writes `"heightLevel": 0` for every room it emits (the generator computes slot heights, but they never reach the room definition), and 0 holes and 0 cliffs on 400 floors in `floor_connectivity_audit` therefore proves nothing about raised rooms.
- **Action:** Carry the slot's height into the room definition, place raised rooms and the stairs between them in the blockout, write the probe that builds full floors and checks navigation across stairs and drops, then read `maxHeightLevel` from the biome.
- **Location:** `apps/game/client/scripts/dungeon/procgen/room_graph_config.gd`, `apps/game/client/scripts/dungeon/procgen/room_graph_geometry.gd`, `apps/game/client/scripts/dungeon/dungeon_builder.gd`

**G-09 Non-combat stakes**
- **Problem:** Trap rooms are no-hit gauntlets (a relic offer for crossing unhurt), 30 % of reward rooms are cursed caches and 20 % are timed caches that seal 30 s after you enter. The floor's biggest pack fight is a sealed arena. Still open: a puzzle that gates a chest (puzzle rooms are parked: their weight in `content/progression/room_pacing.json` is 0).
- **Action:** One puzzle that opens a chest.
- **Location:** `apps/game/client/scripts/dungeon/room_content/`

---

## 4. Combat and animation

**G-01 Bosses as the curriculum**
- **Problem:** Every boss has two or three phases with their own attack lists (`content/bosses/*.json`, run by `boss_phase_controller.gd`). The phases escalate (more attacks, faster) rather than each testing one skill. The training arena re-fights any boss the character has beaten (`defeated_boss_ids` in `combat_arena.gd`).
- **Action:** Author each boss's phases around one skill (flank, guard-break, dodge the delayed swing), and tune them in the rematch arena.
- **Location:** `content/bosses/*.json`, `apps/game/client/scripts/bosses/boss_phase_controller.gd`, `apps/game/client/scripts/practice/combat_arena.gd`
- **Links:** G-05.

**G-05 More telegraphed attacks per enemy**
- **Problem:** The 51 enemies have 174 attacks in 13 attack clips (`ATTACKS` in `diorama_anim_library.gd`). 30 attacks hold their wind-up (`hold_fraction` 0.3-0.35) and the blockable and parryable ones among them feint 20 % of the time. Area denial exists on four attacks and grabs on one. A held swing or a feint plays the clip of its base attack, and none of this has been play-tested.
- **Action:** A distinct clip per attack kind, and a play-test of the held swings against the dodge window.
- **Location:** `apps/game/client/scripts/art/characters/diorama_anim_library.gd`, `content/enemies/*.json`
- **Links:** FUN-3, FUN-6.

**G-06 Visible power growth; XP during the run**
- **Problem:** Run XP is paid per kill by threat, plus `bossBonusXp` for each boss defeated (every floor has one, and a floor is only marked cleared when its boss dies). A level the kills have earned is announced mid-run, and the curve is about 77 runs to the cap (`runsToLevelCap` in `reports/balance_export.json`). The median enemy takes 5.0-5.6 hits to kill the player in every dungeon, and the player's effective health is the same from dungeon 2 to 10, because `balance-cli` holds every dungeon's median inside a 5-7 hit band.
- **Action:** Decide whether later dungeons should hit harder, and if so give `balance-cli` a band per dungeon order.
- **Location:** `scripts/balance/balance-cli.mjs`, `apps/game/client/scripts/dungeon/difficulty_profile.gd`
- **Links:** FUN-5.

**AN-5 No animation layering**
- **Problem:** `DioramaAnimController` plays one clip at a time on an `AnimationPlayer` with a priority rule; there is no `AnimationTree`, so locomotion and an upper-body action cannot play together.
- **Action:** An `AnimationTree` with a BlendSpace2D for locomotion and an upper-body OneShot.
- **Location:** `apps/game/client/scripts/art/characters/diorama_anim_controller.gd`
- **Links:** G-05.

**FUN-2 Fix the fight before adding anything**
- **Problem:** The training arena offers five practice exercises (parry, dodge, guard break, poise break, recovery) against six training grunts, plus boss rematches. There is no lab where every enemy can be spawned.
- **Action:** A combat lab in the arena that can spawn any enemy, used to play-test only the combat: telegraphs match animations, hits land with a local freeze (`hit_feedback.gd`), dodges and parries read cleanly.
- **Location:** `apps/game/client/scripts/practice/combat_arena.gd`
- **Links:** G-05, FUN-6.

**FUN-3 Fewer, sharper enemies**
- **Problem:** Every biome pool is at most four regulars; elites are a regular with a multiplier and one of four affixes (`content/combat/elite_affixes.json`). The enemies a pool no longer uses stay in `content/enemies/` where a boss, a wave or a quest still uses them. Enemies share the clips listed under G-05.
- **Action:** Give each remaining enemy its own attack clips, and delete enemies nothing references.
- **Location:** `content/enemies/*.json`, `content/biomes/*.json`
- **Links:** G-05.

**FUN-6 Feel and readability pass**
- **Problem:** Hits freeze only the bodies involved (a local hit-stop) and wind-up bars are coloured by attack class. Still generic: the audio bank (AUDIO-5), the 13 shared attack clips, and the wind-up VFX shared by every enemy.
- **Action:** Per-attack animation and sound, impact layers, class-coloured telegraphs on the ground.
- **Location:** `apps/game/client/scripts/art/vfx/vfx_service.gd`, `apps/game/client/scripts/combat/hit_feedback.gd`
- **Links:** AUDIO-5, G-05, SIM-2.

---

## 5. Progression

**FUN-5 Build variety inside a run, not in menus**
- **Problem:** Every floor opens with a pick-one-of-three relic offer, every boss adds one, and carrying two or three relics of one build family (guard, dodge, critical, execution, status) switches on a set-bonus rule from `content/progression/relic_synergies.json`. Meta progression has two parts: the talent tree (stats plus keystone rules, `content/talents/tree.json`) and the vault (`content/progression/vault.json`: 20 relics, 6 items and 2 pacts unlocked by triggers). No weapon or enemy is unlocked by meta progression.
- **Action:** Unlock new weapons and enemy variants through the vault, not through raw stats.
- **Location:** `content/talents/tree.json`, `content/progression/vault.json`, `apps/game/client/scripts/meta/vault_service.gd`
- **Links:** G-06, SIM-11.

**SIM-18 Unlock-condition evaluators**
- **Problem:** The vault and the mode gates now share `ProgressCounters.trigger_progress()` / `trigger_met()`, next to the hub-growth counters. Still separate: achievements (hook counters), `DialogueConditions` (23 predicates, used by dialogue, quests and hub tips), and one announcement queue per system in character flags.
- **Action:** One `UnlockConditions.meets(cond)` / `progress(cond)` over one set of counters, plus one announcement queue. `DialogueConditions` is the most complete and already validated against content shape, so extend it (add `progress()`) rather than write a sixth.
- **Location:**
  - `apps/game/client/scripts/meta/progress_counters.gd`
  - `apps/game/client/scripts/meta/hub_growth_service.gd`
  - `apps/game/client/scripts/meta/achievement_service.gd`
  - `apps/game/client/scripts/dialogue/dialogue_conditions.gd`
- **Links:** FUN-5.

---

## 6. Simplification

The target is a simple, fun roguelite with soulslike combat: one mechanism per job, no fallbacks that hide missing content, no systems the core loop does not need.

**SIM-1 Two floor generators**
- **Problem:** `packages/procedural` (C#) with `tools/procgen-cli` generates floors for the backend and has drifted from the GDScript generator the game uses (`dungeon/local_procgen.gd`).
- **Action:** The backend stays, so the C# generator stays frozen with it. Revisit if the server ever has to verify or replay a run: it would run the GDScript generator headless, and the C# one and the CLI would be deleted.
- **Location:** `packages/procedural/`, `tools/procgen-cli/`
- **Links:** none.

**SIM-9 Save stack sized for a live service**
- **Problem:** `local_save.gd` (1,965 lines) and `save_migrator.gd` (946) carry a save-set journal, pre-migration snapshots, five rotating backups, the frozen HTTP cloud sync, account scope and a roster, for a single-player offline game. The owner chose not to rewrite it while saves are in use.
- **Action:** One file per character plus a roster; atomic write; three rotating backups; a schema version with small migrations.
- **Location:** `apps/game/client/scripts/save/`
- **Links:** none.

**SIM-11 Too many item axes**
- **Problem:** Equipment is helmet, chest, weapon, off-hand, ring and relic; rarity rolls 0-2 affixes; upgrade levels multiply a piece's stats by 6 % per level, or follow the recipe's stat table. Still on items: two-hand stance, weight class, salvage, storage .
- **Action:** Decide whether the ring and relic slots stay, and whether two-hand stance and weight class earn their place.
- **Location:** `apps/game/client/scripts/items/`
- **Links:** FUN-5.

**SIM-12 34 autoloads**
- **Problem:** `project.godot` registers 34 autoloads with init-order coupling between them. `ApiConfig` is inert behind `ONLINE_ENABLED`, and `MCPRuntimeProbe` is registered by the editor plugin and does nothing without a debugger. The owner chose to leave the list as it is.
- **Action:** Group into about six (`Game`, `Content`, `Save`, `Audio`, `Input`, `Vfx`) if init-order coupling ever bites.
- **Location:** `apps/game/client/project.godot` `[autoload]`
- **Links:** none.

**SIM-14 Hub engine cost versus role**
- **Problem:** The hub is a menu space with its own set dressing and simulation: `hub_diorama.gd` (1,081 lines), `distant_skyline.gd` (944), `village_crowd.gd` (728), `village_plan.gd` (666), plus weather, day/night, birds and strays. The owner chose to keep the hub as it is.
- **Action:** If the cost matters, freeze the scope to one lit, readable space with the portals, merchant, blacksmith, storage and quest board.
- **Location:** `apps/game/client/scripts/hub/`, `apps/game/client/scripts/art/world/`
- **Links:** SIM-28.

**SIM-23 A Tetris-style inventory where every item is 1×1**
- **Problem:** The bag is an ordered list with a fixed capacity (`GridInventory.capacity()`); a slot's cell is its position, and dragging reorders the list. Saves still write each slot's `x` and `y`, derived from its position, because the backend's `SaveStateValidator.cs` and `content/schemas/inventory.v2.json` require them. The inventory UI still draws a grid of cells.
- **Action:** Drop the derived `x` and `y` (a save-schema bump with a migrator step, a schema change and the matching C# validator change) and draw the bag as a plain list.
- **Location:** `apps/game/client/scripts/inventory/grid_inventory.gd`, `apps/game/client/scripts/ui/inventory_ui.gd`, `content/schemas/inventory.v2.json`, `services/backend/src/Aumbrye.Application/Services/SaveStateValidator.cs`
- **Links:** SIM-11, SIM-9.

**SIM-28 A hub rebuilt from code on every load**
- **Problem:** `HubDiorama.apply()` (`hub_diorama.gd`) places the whole hub set from code on every hub entry, with the tent and building meshes from `pixel_diorama_hub_structures.gd` and the skyline town from `village_plan.gd` (through `distant_skyline.gd`). Only the growth props depend on save state, and `reconcile_growth_props()` already rebuilds those separately. Moving a bench means editing a constant and relaunching.
- **Action:** Bake the static dressing into `hub.tscn` once and keep code only for the save-dependent growth props.
- **Location:** `apps/game/client/scripts/hub/hub_diorama.gd`, `apps/game/client/scripts/art/style/pixel_diorama_hub_structures.gd`, `apps/game/client/scripts/art/world/village_plan.gd`
- **How:** Run `HubDiorama.apply()` once in the editor through an `@tool` bake script and save the result as a sub-scene. `_merge_static_dressing` folds each area's models into merged meshes with runtime materials, so a baked scene would store those meshes inline: measure the saved file first. The environment, fauna and NPC placement (`_dress_npcs`, `_position_npcs_from_content`) are also done in code and would stay.
- **Links:** SIM-14.

---

## 7. Writing a probe

The in-engine diagnostics live in `apps/game/client/scenes/debug/` (`CLAUDE.md` lists them). For a
question none of them answers, put a temporary scene in `apps/game/client/.godot/claude_probe/`
(git-ignored) and delete it afterwards:

```bash
godot --headless --path apps/game/client res://.godot/claude_probe/<scene>.tscn
```

- A probe whose script fails to parse does not exit: read the log for `SCRIPT ERROR` before raising the timeout.
- Quit with `get_tree().quit()` when it is done.
- `LocalProcgen.generate(biome, seed, floor, mode, tier, level, debug, bypass, final_floor_index, inputs)` returns a wrapper; the floor is `result.definition`. Pass `0` as `final_floor_index`, since any other value makes a short final-floor arena.
- Probes that only generate floors or spawn enemies in an empty scene do not touch saves; audits that start runs or call `LocalSave` write the real saves in `~/.local/share/godot/app_userdata/Aumbrye`.
