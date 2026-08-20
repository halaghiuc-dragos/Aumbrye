# Manual validation checklist

Items no automated check covers.

> **The suites this was written against no longer exist.** The in-engine harness — 58 suites, 28,631
> lines — was removed; see `CORE_GAMEPLAY_REVIEW.md` §119. The note that used to stand here described
> a vacuous heading assertion inside `docs_suite.gd`, which went with it.
>
> What replaced it, and what this checklist now complements:
>
> - **CI** (`.github/workflows/ci.yml`) — content validation, DOC-01 path check, `dotnet test`,
>   `ruff` + voxel-import tests, the Godot smoke test, and the web lint/test/build.
> - **Release** (`.github/workflows/release.yml`) — exports, stages `content/` beside the binary, and
>   smoke-tests **the exported build**, which is the only way to exercise the export content path.
> - **`scripts/tools/procgen_seed_health.gd`** — Phase 1 room-graph sweep (and it says so; see C-256).
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
