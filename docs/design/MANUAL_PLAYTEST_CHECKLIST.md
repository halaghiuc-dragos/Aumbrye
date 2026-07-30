# Manual playtest checklist (living document)

> **Single source of truth** for all human playtest and feel gates across M0–M7.  
> **Do not create per-phase playtest checklists** — add items here under the correct section as each milestone ships.

**Tester:** _____________  
**Date:** _____________  
**Build / commit:** _____________

---

## Before any manual sign-off

1. Run automated validation — must pass with **0 failures**:

```powershell
./scripts/run-all-validation.ps1
```

2. Review report: `reports/validation-summary.json` and [VALIDATION_PLATFORM.md](VALIDATION_PLATFORM.md) for automated coverage.

Manual items below cover **feel, UX, and integration paths** that automation cannot judge.

### Automated coverage map (reference test IDs)

| Area | Automated | Test IDs (sample) |
| ---- | --------- | ----------------- |
| Kill enemies stay dead | Yes | `enemy.dies_at_zero_hp`, `enemy.no_stagger_revive` |
| Dungeon build / loot / enemies | Yes | `dungeon.rooms_instantiated`, `dungeon.loot_placed` |
| Offline procgen default | Yes | `procgen.offline_no_api_in_run_flow`, `m5.net.online_path_optional` |
| Three biomes procgen + build | Yes | `m5.procgen.*`, `m5.dungeon.*` |
| Six damage types + resist | Yes | `m5.damage.six_types`, `m5.damage.resistance_pipeline` |
| Five statuses + HUD wiring | Yes | `m5.status.five_definitions`, `m5.status.hud_icon_row` |
| Five weapon archetypes (data) | Yes | `m5.weapon.*_json`, `m5.loadout.*` |
| Theme enemies + bosses (data) | Yes | `m5.enemy.*`, `m5.boss.theme_scenes` |
| Per-biome audio profiles | Yes | `m5.audio.profile_*`, `m5.audio.set_biome` |
| Save integer normalization | Yes | `m5.save.integer_normalization` |
| Epic+ affix counts | Yes | `m5.loot.epic_affix_counts`, C# `AffixRollerTests` |
| Hub M4 services | Yes | `hub_m4.*` suite |
| M4 progression / inventory | Yes | `progression.*`, `inventory.*` |

---

## M1 — Combat arena (KB/M signed off 2026-07-29)

Historical record: [M1_PLAYTEST_CHECKLIST.md](M1_PLAYTEST_CHECKLIST.md) (archived).

| ID | Item | Status |
|----|------|--------|
| M1.kbm.core_loop | WASD, mouse look, sprint, jump, dodge, LMB/RMB, parry/block, lock-on, hitboxes, dummy kill, **R** reset | [x] |
| M1.kbm.win_strategies | Roll / parry / spacing strategies vs training grunt | [x] |

### M1 carry-over → M7 (gamepad)

| ID | Item | Status |
|----|------|--------|
| M7.gamepad.arena_full_loop | Full combat arena duel completable gamepad-only (no mouse/KB) | [ ] |
| M7.gamepad.lock_on_switch | Lock-on + target switch (right stick while locked) | [ ] |
| M7.gamepad.hub_castle_loop | Full hub → castle → escape loop on gamepad | [ ] |

Bindings exist in `project.godot`; verify when controller hardware available.

---

## M2 — Vertical slice (signed off 2026-07-30)

Historical record: [M2_IMPLEMENTATION_LOG.md](M2_IMPLEMENTATION_LOG.md).

| ID | Item | Status |
|----|------|--------|
| M2.kbm.castle_loop | Hand-authored castle slice: combat, loot, boss, escape, hub return | [x] |

### M2 carry-over → later phases

| ID | Item | Target | Status |
|----|------|--------|--------|
| M2.deferred.external_playtest | Optional friend playtest feedback | M7 (`SHIP-7.1`) | [ ] |
| M2.deferred.castle_art | Blockout accepted; art pass when final assets land | M6 | [ ] |
| M2.deferred.corrupt_save_manual | Bad JSON → fresh start + starter sword (feel/UX) | M7 | [ ] |

---

## M3 — Server generation (closed 2026-07-30)

Implementation record: [M3_IMPLEMENTATION_LOG.md](M3_IMPLEMENTATION_LOG.md).  
**Structural M3 acceptance criteria are automated** (`procgen_suite`, C# procgen tests). Manual items below are spot-checks automation cannot replace.

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M3.automated | Procgen determinism, CLI JSON strip, dungeon build, offline default | [x] | `./scripts/run-all-validation.ps1` |
| M3.seed.spot_check | Enter seed `42001` twice → identical room layout in-game | [ ] | F1 shows seed; compare room positions |
| M3.procgen_cli.runtime | `dotnet build tools/procgen-cli/ProcgenCli.csproj` then hub new run works | [ ] | Clear error if CLI missing |
| M3.offline.play_session | API stopped / no internet → new run + continue playable, no hang | [ ] | Also `M7.offline.no_hang` |
| M3.cross_machine.seed | Same seed + build + `content/` → identical layout on two machines | [ ] | Optional if second PC available |

### M3 carry-over → M7 (feel polish)

| ID | Item | Status |
|----|------|--------|
| M7.movement.feel | Walk full procgen run — rooms connect, no falling off map | [ ] |
| M7.movement.boss_path | Boss path reachable from entrance without soft-lock | [ ] |
| M7.combat.hp_bar_visual | HP bars: black bar, red depletes R→L, occluded by walls, gone on death | [ ] |
| M7.combat.shield_feel | Shield-bearer frontal block feels right in live combat | [ ] |
| M7.loot.interact_feel | Open chests with **E** — items appear in inventory grid | [ ] |
| M7.traps.damage_feel | Traps damage the player | [ ] |
| M7.boss.door_flow | Boss door: **E** open → cross threshold → door seals | [ ] |
| M7.results.escape_flow | Defeat boss → exit portal → results → hub message updates | [ ] |
| M7.camera.toggle_feel | **P** toggles 1P/3P; F1 shows `camera: 1P` or `3P` | [ ] |
| M7.camera.relaunch_persistence | Camera preference persists after quit/relaunch | [ ] |
| M7.lock_on.fp_readability | Lock reticle readable in first person | [ ] |
| M7.hub.interaction_feel | **E** at portal; **Esc** closes; seed **Back** returns; invalid seed feedback | [ ] |
| M7.continue.full_playthrough | Mid-run quit restore; boss-room quit; death disables Continue; complete disables Continue | [ ] |
| M7.debug.overlay_runtime | F1 shows entered seed during run; cleared after hub return | [ ] |
| M7.arena.combat_feel | Hub arena: hit, stagger, parry/block, grunt death, **R** reset | [ ] |
| M7.procgen_cli.missing_ux | Procgen-cli missing → hub shows clear error | [ ] |

---

## M4 — Gameplay loop (closed 2026-07-30)

Close record: [M4_IMPLEMENTATION_LOG.md](M4_IMPLEMENTATION_LOG.md). Automated validation covers hub services, affixes, XP/talents, relics, inventory UX, cloud save API, economy (`hub_m4_suite`, `progression_suite`, `inventory_suite`).

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M4.automated | Full gameplay loop structural coverage | [x] | `./scripts/run-all-validation.ps1` |
| M4.TEST-4.1 | Ten consecutive runs — no softlock; notes in [m4_soak_notes.md](m4_soak_notes.md) | [ ] | Soak gate before M6 content volume |
| M4.cloud_e2e | Cloud save round-trip on second device/session with API running | [ ] | Also M7 `STEAM-7.3` |
| M2.deferred.corrupt_save_manual | Bad JSON → fresh start + starter sword (optional spot-check) | [ ] | |

### M4 carry-over → later phases

| ID | Item | Target | Status |
|----|------|--------|--------|
| M4.deferred.gamepad_loop | Gamepad-only hub → castle → escape | M7 `POLISH-7.1` | [ ] |

---

## M5 — Content pack A (closed 2026-07-30)

Automated validation covers biomes, procgen, combat depth, weapons, bosses, loot, audio profiles (`m5_suite` + C# theme tests). **Prerequisite:** `./scripts/run-all-validation.ps1` passes with 0 failures.

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M5.automated | All M5 structural milestones | [x] | `m5_suite` + C# `M5BiomeGeneratorTests` |
| M5.biome.e2e | Complete a full run in **each** biome (castle, crystal, swamp) → boss → escape | [ ] | Portal biome buttons |
| M5.weapons.feel | Hub **Tab** loadout — try greatsword, dagger, spear, bow vs arena grunt | [ ] | Unlock spear Lv5+, bow Lv8+ |
| M5.status.feel | Burn/bleed/poison/freeze/stun readable in combat; F8 debug burn works | [ ] | Swamp poison pools fair |
| M5.boss.crystal | Crystal Sovereign fight — phase telegraphs, winnable | [ ] | Miniboss guardian optional |
| M5.boss.swamp | Swamp Hydra fight — poison cleanse zones, winnable | [ ] | Miniboss hag optional |
| M5.audio.crossfade | Each biome ambience distinct; boss music crossfades cleanly | [ ] | Generator-tone stubs OK for M5 |
| M5.theme.blind | Blind playtester names theme without UI label (spot check) | [ ] | Silhouette/lighting/audio only |

### M5 carry-over → M6/M7

| ID | Item | Target | Status |
|----|------|--------|--------|
| M5.deferred.final_art | Pixel-diorama room art, OGG audio, status icons | M6/M7 | [ ] |
| M5.deferred.mythic_uniques | Per-item Mythic unique rules | M6 | [ ] |
| M5.deferred.item_roster | Full ~80-item roster | M6 `ITEM-6.1` | [ ] |
| M5.deferred.online_default | Enable online procgen when API stable | M7 | [ ] |

---

## M6 — Content pack B

| ID | Item | Status |
|----|------|--------|
| _TBD_ | Frozen Fortress + Dark Cathedral themes; roster expansion | |

---

## M7 — EA polish & ship

Gate: [07-EA-DEFINITION-OF-DONE.md](../plan/07-EA-DEFINITION-OF-DONE.md), [M7-EA-POLISH.md](../plan/phases/M7-EA-POLISH.md).

### Closed playtest (`SHIP-7.1`)

| ID | Item | Status |
|----|------|--------|
| M7.ship.external_playtest | ≥20 external playtesters completed full loop | [ ] |
| M7.ship.crash_rate | Crash rate within defined threshold | [ ] |
| M7.ship.qualitative | Playtesters remember combat/bosses/exploration over “the algorithm” | [ ] |

### Performance

| ID | Item | Status |
|----|------|--------|
| M7.perf.1080p60 | Mid-range PC: 1080p ≥60 FPS in typical combat rooms | [ ] |
| M7.perf.softlock_smoke | No softlocks in 50 automated seed smoke tests (also in CI) | [ ] |

### Controller polish (`POLISH-7.1`)

See **M1 carry-over → M7 (gamepad)** above.

---

## Sign-off (current phase)

| Area | Pass | Notes |
| ---- | ---- | ----- |
| M1 KB/M combat arena | [x] | 2026-07-29 |
| M2 castle vertical slice | [x] | 2026-07-30 |
| M3 server generation (automated) | [x] | 2026-07-30 |
| M4 gameplay loop (automated) | [x] | 2026-07-30 |
| M5 content pack A (automated) | [x] | 2026-07-30 — `m5_suite` |
| M3 manual spot-checks | [ ] | Seed, offline, procgen-cli |
| M4 TEST-4.1 soak (manual) | [ ] | 10-run log in `m4_soak_notes.md` |
| M5 manual playtest (feel) | [ ] | Biomes, weapons, bosses, audio |
| M7 feel & UX (pending) | [ ] | Complete M7 section before EA ship |

---

## Maintenance rules

1. **Closing a phase:** Mark automated items done in validation suites; move remaining human gates into the appropriate section above.
2. **New manual item:** Add a row with stable `ID` (e.g. `M5.hub.npc_dialogue_feel`); reference from `checklist_ref` in validation tests if partially automatable.
3. **Deleting phase playtest files:** When a phase closes, delete its dedicated playtest checklist (if any) and ensure all open items live here or in the phase implementation log’s deferred table.
