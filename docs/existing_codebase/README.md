# Existing codebase index

Source of truth: current repository code only. Prior deleted documentation is intentionally ignored.

Related repository references: [architecture](../ARCHITECTURE.md) and [improvement catalog](../actual_improvements/README.md).

Doc shape, evidence rules, and status tags are defined in [../DOC-CONVENTIONS.md](../DOC-CONVENTIONS.md).

## Orientation and repository
- [README.md](README.md) — This complete documentation index.
- [_INDEX.md](_INDEX.md) — Compact category rollup.
- [00-GAME-LOOP.md](00-GAME-LOOP.md) — Documented game-loop flow.
- [00-PLACEHOLDER-INVENTORY.md](00-PLACEHOLDER-INVENTORY.md) — Recorded placeholder inventory.
- [repository-root.md](repository-root.md) — Repository layout and entry points.
- [project-config-autoloads.md](project-config-autoloads.md) — Godot project configuration and autoloads.
- [packages.md](packages.md) — Shared and procedural packages.
- [tools-scripts.md](tools-scripts.md) — Repository tooling scripts.
- [ci-cd.md](ci-cd.md) — Continuous-integration configuration.
- [backend-api.md](backend-api.md) — Backend API surface.
- [website.md](website.md) — Website application.
- [website-and-backend.md](website-and-backend.md) — Website and backend integration.
- [networking.md](networking.md) — Client networking services.
- [platform-and-net.md](platform-and-net.md) — Platform and network configuration.

## Content, application, and progression
- [content-data.md](content-data.md) — Content data formats.
- [content-catalog.md](content-catalog.md) — Content catalog and validation.
- [run-flow.md](run-flow.md) — Run transitions and services.
- [world-state.md](world-state.md) — Run-world state.
- [castle-run.md](castle-run.md) — Castle run scenes and flow.
- [waves-run.md](waves-run.md) — Waves run service and UI flow.
- [hub.md](hub.md) — Hub scene interactions.
- [npc-hub-services.md](npc-hub-services.md) — Hub NPC services.
- [dialogue-quests.md](dialogue-quests.md) — Dialogue and quest services.
- [progression-service.md](progression-service.md) — Experience, levels, and talents.
- [achievements-meta.md](achievements-meta.md) — Achievements and leaderboard metadata.
- [accessibility.md](accessibility.md) — Accessibility settings.
- [local-save.md](local-save.md) — Local save data.
- [save-migrator.md](save-migrator.md) — Save-data migrations.
- [character-service.md](character-service.md) — Character state service.
- [character-appearance.md](character-appearance.md) — Character appearance data.
- [character-authoring.md](character-authoring.md) — How character art is produced: runtime box primitives, no authored assets.

## Player, combat, and inventory
- [player-controls.md](player-controls.md) — Player control integration.
- [locomotion.md](locomotion.md) — Movement and facing.
- [player-anim-director.md](player-anim-director.md) — Player animation direction.
- [player-combat.md](player-combat.md) — Player combat integration.
- [player-combat-reactions.md](player-combat-reactions.md) — Combat reaction states.
- [player-heal.md](player-heal.md) — Player healing action.
- [combat-core.md](combat-core.md) — Health, poise, damage, and modifiers.
- [weapons.md](weapons.md) — Weapon controllers and data.
- [stamina-mana.md](stamina-mana.md) — Stamina and mana systems.
- [guard.md](guard.md) — Blocking, parrying, and ripostes.
- [dodge.md](dodge.md) — Dodge behavior.
- [lock-on.md](lock-on.md) — Target lock system.
- [lock-on-movement.md](lock-on-movement.md) — Locked-target movement.
- [hit-hurtboxes.md](hit-hurtboxes.md) — Hitbox and hurtbox components.
- [hit-feedback.md](hit-feedback.md) — Hit feedback effects.
- [statuses-and-buffs.md](statuses-and-buffs.md) — Status and run-buff systems.
- [enemies.md](enemies.md) — Enemy base classes and variants.
- [bosses.md](bosses.md) — Boss encounters.
- [combat-hazards.md](combat-hazards.md) — Combat hazards and projectiles.
- [combat-validation.md](combat-validation.md) — Combat validation suites.
- [dungeon-traps.md](dungeon-traps.md) — Dungeon trap behavior.
- [orbit-camera.md](orbit-camera.md) — Orbit camera behavior.
- [lock-on-camera.md](lock-on-camera.md) — Lock-on camera behavior.
- [inventory-service.md](inventory-service.md) — Inventory and equipment service.
- [loot-and-equipment.md](loot-and-equipment.md) — Loot and equipment data.

## Dungeon generation and world interaction
- [local-procgen.md](local-procgen.md) — Local procedural-generation entry point.
- [room-graph-procgen.md](room-graph-procgen.md) — Room graph generation.
- [room-templates.md](room-templates.md) — Room template data.
- [room-content.md](room-content.md) — Room content assignment.
- [procgen-placements.md](procgen-placements.md) — Procedural placements.
- [dungeon-builder.md](dungeon-builder.md) — Dungeon scene assembly.
- [floor-shell.md](floor-shell.md) — Floor-shell construction.
- [diorama-room-dressing.md](diorama-room-dressing.md) — Room dressing.
- [biome-registry.md](biome-registry.md) — Biome registry.
- [dungeon-catalog-tiers.md](dungeon-catalog-tiers.md) — Dungeon catalog and tiers.
- [boss-door-exit-portal.md](boss-door-exit-portal.md) — Boss-door and exit-portal flow.
- [stair-lever.md](stair-lever.md) — Stair and lever interactions.
- [find-graph-seed.md](find-graph-seed.md) — Graph-seed search tool.

## Rendering, audio, and effects
- [pixel-diorama-pipeline.md](pixel-diorama-pipeline.md) — Pixel-diorama rendering pipeline.
- [pixel-diorama-settings.md](pixel-diorama-settings.md) — Pixel-diorama settings.
- [pixel-camera-snap.md](pixel-camera-snap.md) — Pixel camera snapping.
- [pixel-style.md](pixel-style.md) — Pixel-art styling helpers.
- [diorama-character-skin.md](diorama-character-skin.md) — Diorama character skin.
- [diorama-anim-library.md](diorama-anim-library.md) — Diorama animation library.
- [diorama-anim-controller.md](diorama-anim-controller.md) — Diorama animation controller.
- [diorama-viewmodel.md](diorama-viewmodel.md) — Diorama viewmodel.
- [diorama-weapon-kit.md](diorama-weapon-kit.md) — Diorama weapon kit.
- [material-dissolve.md](material-dissolve.md) — Dissolve material.
- [material-flash.md](material-flash.md) — Flash material.
- [visual-lighting.md](visual-lighting.md) — Lighting configuration.
- [vfx-service.md](vfx-service.md) — Visual-effects service.
- [portal-ellipse-shader.md](portal-ellipse-shader.md) — Portal shader.
- [character-floor-snap.md](character-floor-snap.md) — Character floor snapping.
- [audio-director.md](audio-director.md) — Audio buses and profiles.

## Debugging and validation
- [validation-harness.md](validation-harness.md) — Validation runner and reporting.
- [validation-suites.md](validation-suites.md) — Validation-suite catalog.
- [debug-arenas.md](debug-arenas.md) — Debug arena scenes.
- [export-tools.md](export-tools.md) — Animation export tooling.

## User interface
- [ui/_INDEX.md](ui/_INDEX.md) — UI documentation index.
- [ui/character_create.md](ui/character_create.md) — Character-creation interface.
- [ui/combat_hud.md](ui/combat_hud.md) — Combat HUD.
- [ui/continue_menu.md](ui/continue_menu.md) — Continue-menu interface.
- [ui/dialogue_quests.md](ui/dialogue_quests.md) — Dialogue and quest interfaces.
- [ui/display_settings.md](ui/display_settings.md) — Display-settings interface.
- [ui/enemy_health_bar.md](ui/enemy_health_bar.md) — Enemy health-bar interface.
- [ui/game_ui_skin.md](ui/game_ui_skin.md) — Shared UI skin.
- [ui/hub_vendors.md](ui/hub_vendors.md) — Hub vendor interfaces.
- [ui/input_glyphs.md](ui/input_glyphs.md) — Input glyph service.
- [ui/inventory_ui.md](ui/inventory_ui.md) — Inventory interface.
- [ui/main_menu.md](ui/main_menu.md) — Main-menu interface.
- [ui/menu_shell.md](ui/menu_shell.md) — Shared menu shell.
- [ui/minimap.md](ui/minimap.md) — Minimap interface.
- [ui/pause_menu.md](ui/pause_menu.md) — Pause-menu interface.
- [ui/run_outcome.md](ui/run_outcome.md) — Results, loading, and toast interfaces.
- [ui/run_portals.md](ui/run_portals.md) — Run-portal interfaces.
- [ui/settings.md](ui/settings.md) — Settings interface.
- [ui/status_icon_atlas.md](ui/status_icon_atlas.md) — Status-icon atlas.
- [ui/talents.md](ui/talents.md) — Talent interface.
- [ui/title_screen.md](ui/title_screen.md) — Title-screen interface.
- [ui/waves_hud.md](ui/waves_hud.md) — Waves HUD.
