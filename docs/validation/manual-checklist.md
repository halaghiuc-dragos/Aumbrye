# Manual validation checklist

Headless suites cannot cover these items.

> **Coverage is partial, and the automated check is inert.** Validation suites pass a checklist
> reference as the sixth positional argument to `ctx.timed_record()`; 229 distinct references are in use
> and only 52 have a heading below. `docs_suite._collect_checklist_refs_from_suites()` searches suite
> source for the literal token `checklist_ref`, which appears nowhere, so it always returns an empty list
> and the heading assertion always passes vacuously. Fix the collector to read the sixth argument, then
> either add the missing headings or stop emitting references that have none.

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
