# Manual validation checklist

Items no automated check covers.

## VS-08 — Performance budget

Baseline taken before the MVP depth plan's P1 work, so later regressions are attributable. Budget:
**16.7 ms/frame** (60 fps) at the Balanced preset — `perf_audit.gd`'s own budget constant. Re-measure
at the end of each phase and append a row.

Two of the four numbers the plan asks for (draw calls, particle count) need a real display —
`res://scenes/debug/perf_audit.tscn` and `draw_call_probe.tscn` report `draws=0, prims_k=0.0,
objects=0` when run `--headless`, exactly as the repo's own working rules warn
("needs a display; headless reports no GPU cost"). This session is headless throughout, so those two
columns are marked accordingly rather than filled with fabricated numbers — the next person with a
display attached should fill them in and can reuse this table's shape.

Method: `godot --headless --path apps/game/client res://scenes/debug/perf_audit.tscn` and
`res://scenes/debug/draw_call_probe.tscn`.

| Phase | Scene | avg ms | p95 ms | fps | draws | nodes | visible meshes | shadow casters |
|---|---|---|---|---|---|---|---|---|
| Before P1 (post-P0) | hub | 6.90 | 8.57 | 145 | n/a (headless) | 4484 | n/a | n/a |
| Before P1 (post-P0) | combat_arena | 6.91 | 8.93 | 145 | n/a (headless) | 1896 | n/a | n/a |
| Before P1 (post-P0) | castle_slice | 6.90 | 8.15 | 145 | n/a (headless) | 1253 | n/a | n/a |
| Before P1 (post-P0) | castle_run | 6.90 | 8.54 | 145 | n/a (headless) | 3992 | 832 | 830 (475 small) |
| Post P1-P5 pass (2026-09-04) | hub | 6.90 | 8.18 | 145 | n/a (headless) | 4477 | n/a | n/a |
| Post P1-P5 pass (2026-09-04) | combat_arena | 6.90 | 8.69 | 145 | n/a (headless) | 1904 | n/a | n/a |
| Post P1-P5 pass (2026-09-04) | castle_slice | 6.90 | 8.12 | 145 | n/a (headless) | 1330 | n/a | n/a |
| Post P1-P5 pass (2026-09-04) | castle_run | 6.90 | 8.54 | 145 | n/a (headless) | 4290 | n/a (headless) | n/a (headless) |

All four scenes measured inside the 16.7 ms budget (script/process time only, no GPU cost
included — see caveat above). `castle_run`'s occluder count at this baseline: 36 occluders in the
floor; occlusion culling is off by project setting, and `draw_call_probe`'s on/off comparison shows
`-0.1%` frame time / `0.0%` objects either way under `--headless` for the same reason.

**Post P1-P5 pass note.** Taken after implementing essentially all of §RM/§RG/§BS/§IV, most of §UX
and §AD, and part of §VS/§AX (see session chapters in this checklist's owning conversation for the
exact item list). Script/process time and fps are unchanged from the P0 baseline to two decimal
places despite the substantial amount of new logic (equipment sets, boss phase capabilities, HUD
readouts, camera framings, an input-glyph audit, etc.) — the node counts shifted with the new prop
scenes and content but the frame budget shows no regression. Draw calls, visible meshes and shadow
casters still need a real display to re-measure; this session was headless throughout.

> **The suites this was written against no longer exist.** The in-engine harness — 58 suites, 28,631
> lines — was removed; see `CORE_GAMEPLAY_REVIEW.md` §119. The note that used to stand here described
> a vacuous heading assertion inside `docs_suite.gd`, which went with it.
>
> What replaced it, and what this checklist now complements:
>
> - **`scripts/validate.mjs`** — the local runner: dotnet build, content validation, `ruff`, and the
>   Godot headless smoke test. Run by hand; this project has no hosted CI and will not have one.
> - **`scripts/check-doc-paths.mjs`** — DOC-01, every cited repo path.
> - **`scripts/tools/procgen_seed_health.gd`** — Phase 1 room-graph sweep (and it says so; see C-256).
> - **`scenes/debug/combination_audit.tscn`** — every character-option combination, structurally.
>
> Everything below is still manual because none of those can reach it. The list is not exhaustive:
> the whole of `CORE_GAMEPLAY_REVIEW.md` was implemented without a controller in hand, so anything
> touching feel — dodge, guard, telegraphs, poise readouts, the forge screen — wants a play session.

## M3.seed.spot_check

## M3.procgen_cli.runtime

## M3.offline.play_session

## M3.cross_machine.seed

## M4.TEST-4.1

## M4.cloud_e2e

## M5.theme.blind

## M5.weapons.feel

## M5.status.feel

## M5.boss.crystal

## M5.boss.swamp

## M5.audio.crossfade

## M5.biome.e2e

## M7.movement.feel

## M7.combat.hp_bar_visual

## M7.combat.shield_feel

## M7.loot.interact_feel

## M7.traps.damage_feel

## M7.boss.door_flow

## M7.results.escape_flow

## M7.camera.toggle_feel

## M7.camera.relaunch_persistence

## M7.lock_on.fp_readability

## M7.hub.interaction_feel

## M7.continue.full_playthrough

## M7.debug.overlay_runtime

## M7.arena.combat_feel

## M7.cross_machine.seed

## M7.procgen_cli.missing_ux

## M7.offline.no_hang

## M1.hub.main_scene

## M1.combat.health

## M1.combat.stamina

## M1.combat.poise

## M1.combat.guard

## M1.combat.teams

## M1.combat.dodge

## M1.combat.weapon

## M1.combat.pipeline

## M1.combat.status

## M2.combat.death

## M2.combat.shield_stats

## M2.content.enemies

## M2.content.items

## M4.flow.economy

## M4.prog.talents

## M5.bal.doc

## M5.net.offline

## M5.combat.weapon

## CI-7.1

## SHIP-7.1

## SCHEMA-7.1
