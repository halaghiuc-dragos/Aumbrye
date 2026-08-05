# Actual improvements — category index

Start from the current code path described in [README.md](README.md), the [architecture map](../ARCHITECTURE.md), and the [existing-code inventory](../existing_codebase/README.md). Doc shape, gap-ID, and severity rules: [../DOC-CONVENTIONS.md](../DOC-CONVENTIONS.md).

## Replacement criteria
- [00-QUALITY-BAR.md](00-QUALITY-BAR.md) — checks for replacing active placeholders.
- [00-ADDICTION-AND-FUN.md](00-ADDICTION-AND-FUN.md) — player-feedback improvements grounded in current interactions.

## Largest single gap
- [character-authoring.md](character-authoring.md) — every character is a runtime box assembly; no authored art exists. Replace with authored voxel models on the existing pivot rig.

## Data and platform
- [content-data.md](content-data.md), [content-catalog.md](content-catalog.md), [local-save.md](local-save.md), [save-migrator.md](save-migrator.md)
- [repository-root.md](repository-root.md), [project-config-autoloads.md](project-config-autoloads.md), [packages.md](packages.md), [tools-scripts.md](tools-scripts.md)
- [ci-cd.md](ci-cd.md), [backend-api.md](backend-api.md), [networking.md](networking.md), [platform-and-net.md](platform-and-net.md), [website.md](website.md), [website-and-backend.md](website-and-backend.md)

## Run, world, and progression
- [run-flow.md](run-flow.md), [world-state.md](world-state.md), [castle-run.md](castle-run.md), [waves-run.md](waves-run.md)
- [hub.md](hub.md), [npc-hub-services.md](npc-hub-services.md), [dialogue-quests.md](dialogue-quests.md)
- [character-service.md](character-service.md), [character-appearance.md](character-appearance.md), [progression-service.md](progression-service.md), [achievements-meta.md](achievements-meta.md), [accessibility.md](accessibility.md), [player-controls.md](player-controls.md)

## Combat and movement
- [combat-core.md](combat-core.md), [weapons.md](weapons.md), [stamina-mana.md](stamina-mana.md), [guard.md](guard.md), [dodge.md](dodge.md), [lock-on.md](lock-on.md)
- [hit-hurtboxes.md](hit-hurtboxes.md), [hit-feedback.md](hit-feedback.md), [statuses-and-buffs.md](statuses-and-buffs.md), [player-combat.md](player-combat.md)
- [enemies.md](enemies.md), [bosses.md](bosses.md), [combat-hazards.md](combat-hazards.md), [dungeon-traps.md](dungeon-traps.md), [combat-validation.md](combat-validation.md)
- [locomotion.md](locomotion.md), [lock-on-movement.md](lock-on-movement.md), [player-anim-director.md](player-anim-director.md), [player-combat-reactions.md](player-combat-reactions.md), [player-heal.md](player-heal.md), [orbit-camera.md](orbit-camera.md), [lock-on-camera.md](lock-on-camera.md)

## Dungeon and content presentation
- [dungeon-builder.md](dungeon-builder.md), [local-procgen.md](local-procgen.md), [room-graph-procgen.md](room-graph-procgen.md), [room-templates.md](room-templates.md), [room-content.md](room-content.md), [procgen-placements.md](procgen-placements.md)
- [floor-shell.md](floor-shell.md), [biome-registry.md](biome-registry.md), [dungeon-catalog-tiers.md](dungeon-catalog-tiers.md), [boss-door-exit-portal.md](boss-door-exit-portal.md), [stair-lever.md](stair-lever.md), [find-graph-seed.md](find-graph-seed.md)
- [inventory-service.md](inventory-service.md), [loot-and-equipment.md](loot-and-equipment.md)
- [pixel-diorama-pipeline.md](pixel-diorama-pipeline.md), [pixel-diorama-settings.md](pixel-diorama-settings.md), [pixel-camera-snap.md](pixel-camera-snap.md), [pixel-style.md](pixel-style.md)
- [character-authoring.md](character-authoring.md), [diorama-character-skin.md](diorama-character-skin.md), [diorama-anim-library.md](diorama-anim-library.md), [diorama-anim-controller.md](diorama-anim-controller.md), [diorama-viewmodel.md](diorama-viewmodel.md), [diorama-weapon-kit.md](diorama-weapon-kit.md), [diorama-room-dressing.md](diorama-room-dressing.md)
- [material-dissolve.md](material-dissolve.md), [material-flash.md](material-flash.md), [visual-lighting.md](visual-lighting.md), [vfx-service.md](vfx-service.md), [portal-ellipse-shader.md](portal-ellipse-shader.md), [character-floor-snap.md](character-floor-snap.md), [audio-director.md](audio-director.md)

## Verification and UI
- [validation-harness.md](validation-harness.md), [validation-suites.md](validation-suites.md), [debug-arenas.md](debug-arenas.md), [export-tools.md](export-tools.md)
- [ui/_INDEX.md](ui/_INDEX.md) — improvements for existing `apps/game/client/scripts/ui/` scripts.
