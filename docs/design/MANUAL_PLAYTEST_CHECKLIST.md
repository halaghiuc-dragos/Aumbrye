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

### Automated coverage map (formerly manual — reference test IDs)

| Former manual area | Now automated | Test IDs |
| ------------------ | ------------- | -------- |
| Kill enemies stay dead | Yes | `enemy.dies_at_zero_hp`, `enemy.no_stagger_revive`, `enemy.hitbox_disabled_on_death` |
| Shield stats | Yes | `content.shield_block_stats` |
| Continue disabled (no save) | Yes | `hub.continue_disabled_no_save` |
| Continue enabled (mid-run save) | Yes | `hub.continue_enabled_with_save`, `save.localsave_continuable_midrun` |
| Invalid/valid seed parsing | Yes | `seed.invalid_rejected`, `seed.valid_accepted` |
| Camera P toggle API | Yes | `camera.toggle_action`, `camera.first_person_api` |
| Camera preference save API | Yes | `camera.persisted_preference_roundtrip` |
| Lock reticle center / auto-advance | Yes | `lock_on.reticle_uses_center`, `lock_on.auto_advance_on_death` |
| F1 seed display code | Yes | `flow.debug_overlay_seed` |
| Training grunt in arena | Yes | `arena.training_grunt_present`, `arena.grunt_hp_bar` |
| Dungeon build / loot / enemies | Yes | `dungeon.rooms_instantiated`, `dungeon.enemies_spawned`, `dungeon.loot_placed` |
| Boss door / exit portal wiring | Yes | `dungeon.boss_door_wired`, `dungeon.exit_portal_wiring` |
| Offline procgen (no API) | Yes | `procgen.offline_no_api_in_run_flow`, `flow.offline_procgen` |

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

Bindings exist in `project.godot`; verify when controller hardware available. Tracked in [22-TESTING.md](../plan/systems/22-TESTING.md) (`TEST-M1-GPAD`).

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
| M2.deferred.castle_art | Blockout accepted; art pass when final assets land | M5/M6 content | [ ] |
| M2.deferred.save_json_integers | `quantity`/`x`/`y` sometimes serialize as floats; loads fine | M4 save hardening | [ ] |
| M2.deferred.corrupt_save_manual | Bad JSON → fresh start + starter sword (feel/UX) | M7 | [ ] |

---

## M3 — Server generation (closed 2026-07-30)

Implementation record: [M3_IMPLEMENTATION_LOG.md](M3_IMPLEMENTATION_LOG.md).  
**All structural M3 acceptance criteria are automated** (114 Godot tests + C# CI). No M3-specific manual gate remains.

### M3 carry-over → M7

Items below were scoped during M3 development; human verification deferred to EA polish:

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
| M7.cross_machine.seed | Same seed + build + `content/` → identical layout on two machines | [ ] |
| M7.procgen_cli.missing_ux | Procgen-cli missing → hub shows clear error | [ ] |
| M7.offline.no_hang | Playable with API stopped / no internet; no hang on new run | [ ] |

These IDs match `TestContext.MANUAL_REMAINING` in the validation report.

---

## M4 — Gameplay loop

_Add manual checks here when M4 milestones ship. Do not open a separate M4 playtest file._

| ID | Item | Status |
|----|------|--------|
| TEST-4.1 | Ten consecutive runs — no softlock; notes in `docs/design/m4_soak_notes.md` | [ ] |
| M2.deferred.corrupt_save_manual | Bad JSON → fresh start + starter sword (optional spot-check) | [ ] |

---

## M5 — Content pack A

| ID | Item | Status |
|----|------|--------|
| M5.theme.blind | Blind playtester names theme without UI label (spot check) | [ ] |
| M2.deferred.castle_art | Castle blockout art pass when final assets land | [ ] |

---

## M6 — Content pack B

| ID | Item | Status |
|----|------|--------|
| _TBD_ | _Multi-theme loop, progression feel_ | |

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
| M3 server generation (automated) | [x] | 2026-07-30 — `./scripts/run-all-validation.ps1` |
| M7 feel & UX (pending) | [ ] | Complete M7 section before EA ship |

---

## Maintenance rules

1. **Closing a phase:** Mark automated items done in validation suites; move any remaining human gates into the appropriate section above.
2. **New manual item:** Add a row with stable `ID` (e.g. `M4.hub.npc_dialogue_feel`); reference from `checklist_ref` in validation tests if partially automatable.
3. **Deleting phase playtest files:** When a phase closes, delete its dedicated playtest checklist (if any) and ensure all open items live here or in the phase implementation log’s deferred table.
