# UI improvement index

Paired with [`../../existing_codebase/ui/_INDEX.md`](../../existing_codebase/ui/_INDEX.md). Every topic below answers: what is broken or missing, and what is the best way to finish it?

Files in this directory: `_INDEX.md`, `character_create.md`, `combat_hud.md`, `continue_menu.md`, `dialogue_quests.md`, `dialogue_quests_talents.md`, `display_settings.md`, `enemy_health_bar.md`, `game_ui_skin.md`, `hub_vendors.md`, `input_glyphs.md`, `inventory_ui.md`, `main_menu.md`, `menu_shell.md`, `menu_shell_a11y.md`, `minimap.md`, `pause_menu.md`, `run_flow_ui.md`, `run_outcome.md`, `run_portals.md`, `settings.md`, `status_icon_atlas.md`, `status_icons_glyphs.md`, `talents.md`, `title_main_continue.md`, `title_screen.md`, `waves_hud.md`.

| File | One-line description |
|------|----------------------|
| [`character_create.md`](character_create.md) | Finish New Warden focus, preview honesty, and localization. |
| [`combat_hud.md`](combat_hud.md) | Rebuild combat HUD layout, authored scene coverage, and hint accuracy. |
| [`continue_menu.md`](continue_menu.md) | Make roster focus, delete confirm, and slot details pad-complete. |
| [`dialogue_quests.md`](dialogue_quests.md) | Honest quest board / dialogue actions and readable quest state. |
| [`dialogue_quests_talents.md`](dialogue_quests_talents.md) | Align dialogue, quests, and talents as one progression UI story. |
| [`display_settings.md`](display_settings.md) | Expand beyond `ui_scale` or rename; stop duplicate apply calls. |
| [`enemy_health_bar.md`](enemy_health_bar.md) | Replace per-pixel regen bars with atlas-backed readable billboards. |
| [`game_ui_skin.md`](game_ui_skin.md) | Move toward a real Theme and consistent spacing tokens. |
| [`hub_vendors.md`](hub_vendors.md) | Iconized vendor rows, focus, and shared confirm paths. |
| [`input_glyphs.md`](input_glyphs.md) | Real glyph art and coverage for every prompted action. |
| [`inventory_ui.md`](inventory_ui.md) | Icon grid, tooltips, and waves/loadout consistency. |
| [`main_menu.md`](main_menu.md) | Authored scene, focus, and front-end overlay gating. |
| [`menu_shell.md`](menu_shell.md) | Evolve the scaffold into a reusable modal / stack API. |
| [`menu_shell_a11y.md`](menu_shell_a11y.md) | Deliver `MenuStack`, focus neighbors, and cancel ownership. |
| [`minimap.md`](minimap.md) | Readable graph, fog rules, and non-castle no-op clarity. |
| [`pause_menu.md`](pause_menu.md) | Pause only in valid contexts; fix abandon / settings handoff. |
| [`run_flow_ui.md`](run_flow_ui.md) | Close portal↔results↔`RunFlow` honesty gaps (waves outcomes, MenuStack). |
| [`run_outcome.md`](run_outcome.md) | Branch results on all four outcomes; toast queue; cinematic pause/skip. |
| [`run_portals.md`](run_portals.md) | Weapon/seed gates, stair focus, skip labels, shared modal stack. |
| [`settings.md`](settings.md) | Context-aware hints, real display options, localization. |
| [`status_icon_atlas.md`](status_icon_atlas.md) | Replace procedural pixels with an authored atlas. |
| [`status_icons_glyphs.md`](status_icons_glyphs.md) | Unified icon/glyph atlas plan across HUD and prompts. |
| [`talents.md`](talents.md) | Real talent tree, selection sync, gating off the front end. |
| [`title_main_continue.md`](title_main_continue.md) | Single boot service, transitions, overlay isolation. |
| [`title_screen.md`](title_screen.md) | Authored title art, focus, and input handoff polish. |
| [`waves_hud.md`](waves_hud.md) | Fix reward pick integrity, focus, live prep/enemy counters. |

## Related
- Tree README: [`../README.md`](../README.md)
- Existing twins: [`../../existing_codebase/ui/_INDEX.md`](../../existing_codebase/ui/_INDEX.md)
- Conventions: [`../../DOC-CONVENTIONS.md`](../../DOC-CONVENTIONS.md)
- Quality bar: [`../00-QUALITY-BAR.md`](../00-QUALITY-BAR.md)
