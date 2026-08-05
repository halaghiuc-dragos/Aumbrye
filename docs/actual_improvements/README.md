# Actual improvements — master index

Source of truth: current repository code only. Prior deleted documentation is intentionally ignored.

Plans must start from current code paths, scenes, scripts, and data—not assumed systems. Use the [architecture map](../ARCHITECTURE.md) and the [existing-code inventory](../existing_codebase/README.md) to locate the implementation before extending or replacing it.

Short rollup: [_INDEX.md](_INDEX.md). UI detail: [ui/_INDEX.md](ui/_INDEX.md). Doc shape, gap-ID and severity rules: [../DOC-CONVENTIONS.md](../DOC-CONVENTIONS.md).

## Foundation and delivery
- [00-QUALITY-BAR.md](00-QUALITY-BAR.md) — extend replacement checks for current placeholder paths.
- [00-ADDICTION-AND-FUN.md](00-ADDICTION-AND-FUN.md) — replace placeholder feedback with testable hit, loot, and results honesty.
- [repository-root.md](repository-root.md) — extend repository documentation and path maintenance.
- [project-config-autoloads.md](project-config-autoloads.md) — replace stale autoload and input wiring.
- [packages.md](packages.md) — extend shared package and schema boundaries.
- [tools-scripts.md](tools-scripts.md) — replace manual content checks with tooling.
- [ci-cd.md](ci-cd.md) — extend current build and validation automation.
- [backend-api.md](backend-api.md) — replace incomplete backend integration paths.
- [website.md](website.md) — extend the current web presentation.
- [website-and-backend.md](website-and-backend.md) — coordinate website and backend replacements.
- [networking.md](networking.md) — extend local-first networking boundaries.
- [platform-and-net.md](platform-and-net.md) — replace platform and network stubs.

## Data, run state, and services
- [content-data.md](content-data.md) — replace drifting content data contracts.
- [content-catalog.md](content-catalog.md) — extend catalog validation and lookup paths.
- [run-flow.md](run-flow.md) — extend the current run transition flow.
- [world-state.md](world-state.md) — replace transient world flags with persisted state.
- [local-save.md](local-save.md) — extend local save and recovery paths.
- [save-migrator.md](save-migrator.md) — replace ad-hoc save upgrades with migrations.
- [character-service.md](character-service.md) — extend character currency and flag APIs.
- [character-appearance.md](character-appearance.md) — replace default character presentation.
- [character-authoring.md](character-authoring.md) — replace runtime box primitives with authored voxel characters.
- [progression-service.md](progression-service.md) — extend current progression state and unlocks.
- [achievements-meta.md](achievements-meta.md) — extend achievement and account metadata.
- [accessibility.md](accessibility.md) — replace settings that do not affect runtime behavior.
- [player-controls.md](player-controls.md) — replace outdated player-control integration.

## World, hub, and encounters
- [castle-run.md](castle-run.md) — extend current castle-run scenes and transitions.
- [waves-run.md](waves-run.md) — replace basic wave-run behavior with defined encounters.
- [hub.md](hub.md) — extend the hub scene and its services.
- [npc-hub-services.md](npc-hub-services.md) — replace static hub NPC interactions.
- [dialogue-quests.md](dialogue-quests.md) — extend dialogue and quest state paths.
- [dungeon-builder.md](dungeon-builder.md) — extend the existing dungeon construction pipeline.
- [local-procgen.md](local-procgen.md) — replace local generation fallbacks.
- [room-graph-procgen.md](room-graph-procgen.md) — extend room graph generation.
- [room-templates.md](room-templates.md) — replace generic rooms with reusable templates.
- [room-content.md](room-content.md) — extend room-content placement.
- [procgen-placements.md](procgen-placements.md) — replace unstructured spawn placement.
- [floor-shell.md](floor-shell.md) — extend floor shell assembly.
- [biome-registry.md](biome-registry.md) — replace scattered biome definitions.
- [dungeon-catalog-tiers.md](dungeon-catalog-tiers.md) — extend dungeon catalog selection.
- [boss-door-exit-portal.md](boss-door-exit-portal.md) — replace boss-door and exit portal flow.
- [stair-lever.md](stair-lever.md) — extend stair and lever interactions.
- [find-graph-seed.md](find-graph-seed.md) — extend graph-seed diagnostics.
- [dungeon-traps.md](dungeon-traps.md) — replace generic traps with configured trap behavior.

## Combat, player, and camera
- [combat-core.md](combat-core.md) — replace incomplete damage, defense, and poise handling.
- [weapons.md](weapons.md) — extend weapon definitions and attack behavior.
- [stamina-mana.md](stamina-mana.md) — replace partial resource handling.
- [guard.md](guard.md) — extend guard and parry state transitions.
- [dodge.md](dodge.md) — extend dodge timing and movement behavior.
- [lock-on.md](lock-on.md) — replace basic target selection with lock-on behavior.
- [hit-hurtboxes.md](hit-hurtboxes.md) — extend hit and hurtbox coordination.
- [hit-feedback.md](hit-feedback.md) — replace minimal hit response with synchronized feedback.
- [statuses-and-buffs.md](statuses-and-buffs.md) — extend status application and display state.
- [player-combat.md](player-combat.md) — replace partial player combat transitions.
- [enemies.md](enemies.md) — extend enemy archetype and AI behavior.
- [bosses.md](bosses.md) — replace basic boss flow with phase-aware behavior.
- [combat-hazards.md](combat-hazards.md) — extend hazard telegraph and damage paths.
- [combat-validation.md](combat-validation.md) — extend combat regression coverage.
- [locomotion.md](locomotion.md) — replace incomplete locomotion state handling.
- [lock-on-movement.md](lock-on-movement.md) — extend movement while a target is locked.
- [player-anim-director.md](player-anim-director.md) — replace scattered animation selection.
- [player-combat-reactions.md](player-combat-reactions.md) — extend player reaction animation paths.
- [player-heal.md](player-heal.md) — replace incomplete healing flow.
- [orbit-camera.md](orbit-camera.md) — extend current orbit-camera controls.
- [lock-on-camera.md](lock-on-camera.md) — replace lock-on camera framing behavior.

## Inventory and presentation
- [inventory-service.md](inventory-service.md) — extend inventory persistence and item operations.
- [loot-and-equipment.md](loot-and-equipment.md) — replace basic equipment and loot resolution.
- [pixel-diorama-pipeline.md](pixel-diorama-pipeline.md) — extend the current diorama asset pipeline.
- [pixel-diorama-settings.md](pixel-diorama-settings.md) — replace scattered diorama configuration.
- [pixel-camera-snap.md](pixel-camera-snap.md) — extend pixel camera snapping.
- [pixel-style.md](pixel-style.md) — replace temporary visual assets with a consistent style.
- [diorama-character-skin.md](diorama-character-skin.md) — extend character skin presentation.
- [diorama-anim-library.md](diorama-anim-library.md) — replace missing animation-library entries.
- [diorama-anim-controller.md](diorama-anim-controller.md) — extend diorama animation control.
- [diorama-viewmodel.md](diorama-viewmodel.md) — replace incomplete viewmodel setup.
- [diorama-weapon-kit.md](diorama-weapon-kit.md) — extend weapon meshes and presentation.
- [diorama-room-dressing.md](diorama-room-dressing.md) — replace generic room dressing.
- [material-dissolve.md](material-dissolve.md) — extend dissolve material usage.
- [material-flash.md](material-flash.md) — extend material hit-flash behavior.
- [visual-lighting.md](visual-lighting.md) — replace flat lighting with scene-configured lighting.
- [vfx-service.md](vfx-service.md) — extend effect spawning and lifetime management.
- [portal-ellipse-shader.md](portal-ellipse-shader.md) — replace basic portal rendering.
- [character-floor-snap.md](character-floor-snap.md) — extend character floor alignment.
- [audio-director.md](audio-director.md) — replace placeholder audio dispatch with directed playback.

## Validation and debugging
- [validation-harness.md](validation-harness.md) — extend the current validation runner.
- [validation-suites.md](validation-suites.md) — replace gaps in named validation suites.
- [debug-arenas.md](debug-arenas.md) — extend debug scenes for repeatable checks.
- [export-tools.md](export-tools.md) — extend asset export tooling.

## UI
These plans replace or extend scripts under `apps/game/client/scripts/ui/`.

- [ui/_INDEX.md](ui/_INDEX.md) — UI category index.
- [ui/combat_hud.md](ui/combat_hud.md) — replace `combat_hud.gd` presentation paths.
- [ui/minimap.md](ui/minimap.md) — extend `minimap.gd` navigation display.
- [ui/game_ui_skin.md](ui/game_ui_skin.md) — replace `game_ui_skin.gd` theme setup.
- [ui/status_icon_atlas.md](ui/status_icon_atlas.md) — extend `status_icon_atlas.gd` icon lookup.
- [ui/status_icons_glyphs.md](ui/status_icons_glyphs.md) — coordinate existing icon and glyph scripts.
- [ui/inventory_ui.md](ui/inventory_ui.md) — replace `inventory_ui.gd` interaction layout.
- [ui/character_create.md](ui/character_create.md) — extend `character_create_ui.gd`.
- [ui/pause_menu.md](ui/pause_menu.md) — replace `pause_menu.gd` menu handling.
- [ui/settings.md](ui/settings.md) — extend `settings_ui.gd` runtime settings.
- [ui/display_settings.md](ui/display_settings.md) — extend `display_settings.gd` display controls.
- [ui/title_screen.md](ui/title_screen.md) — replace `title_screen.gd` entry flow.
- [ui/main_menu.md](ui/main_menu.md) — extend `main_menu.gd` navigation.
- [ui/continue_menu.md](ui/continue_menu.md) — extend `continue_menu.gd` save selection.
- [ui/title_main_continue.md](ui/title_main_continue.md) — coordinate title, main-menu, and continue scripts.
- [ui/enemy_health_bar.md](ui/enemy_health_bar.md) — extend `enemy_health_bar.gd`.
- [ui/menu_shell.md](ui/menu_shell.md) — replace common `menu_shell.gd` behavior.
- [ui/menu_shell_a11y.md](ui/menu_shell_a11y.md) — extend menu-shell focus and accessibility.
- [ui/input_glyphs.md](ui/input_glyphs.md) — extend `input_glyph_service.gd`.
- [ui/hub_vendors.md](ui/hub_vendors.md) — coordinate merchant, blacksmith, and storage UI scripts.
- [ui/dialogue_quests.md](ui/dialogue_quests.md) — extend `dialogue_ui.gd` and `quest_board_ui.gd`.
- [ui/dialogue_quests_talents.md](ui/dialogue_quests_talents.md) — coordinate dialogue, quest, and talent UI paths.
- [ui/talents.md](ui/talents.md) — extend `talents_ui.gd`.
- [ui/run_portals.md](ui/run_portals.md) — replace current run-entry UI flow.
- [ui/run_outcome.md](ui/run_outcome.md) — extend results, loading, and end-screen scripts.
- [ui/run_flow_ui.md](ui/run_flow_ui.md) — coordinate run-flow UI scripts.
- [ui/waves_hud.md](ui/waves_hud.md) — extend `waves_run_ui.gd` and `waves_inventory_ui.gd`.
