# UI documentation index

Paired with [`../../actual_improvements/ui/_INDEX.md`](../../actual_improvements/ui/_INDEX.md). Every topic below answers: what does this UI do in the code right now?

Files in this directory: `_INDEX.md`, `character_create.md`, `combat_hud.md`, `continue_menu.md`, `dialogue_quests.md`, `dialogue_quests_talents.md`, `display_settings.md`, `enemy_health_bar.md`, `game_ui_skin.md`, `hub_vendors.md`, `input_glyphs.md`, `inventory_ui.md`, `main_menu.md`, `menu_shell.md`, `menu_shell_a11y.md`, `minimap.md`, `pause_menu.md`, `run_flow_ui.md`, `run_outcome.md`, `run_portals.md`, `settings.md`, `status_icon_atlas.md`, `status_icons_glyphs.md`, `talents.md`, `title_main_continue.md`, `title_screen.md`, `waves_hud.md`.

| File | One-line description |
|------|----------------------|
| [`character_create.md`](character_create.md) | New Warden panel: class list, name, appearance dropdowns, preview. |
| [`combat_hud.md`](combat_hud.md) | In-world gameplay overlay: resources, XP, statuses, lock-on, boss bar, minimap host. |
| [`continue_menu.md`](continue_menu.md) | Warden roster picker with Play / Back / Delete on `MenuShell.build_modal`. |
| [`dialogue_quests.md`](dialogue_quests.md) | NPC dialogue panel and hub quest board UI. |
| [`dialogue_quests_talents.md`](dialogue_quests_talents.md) | Coordination across dialogue, quest board, and talents surfaces. |
| [`display_settings.md`](display_settings.md) | Static helper that applies `ui_scale` to the root viewport. |
| [`enemy_health_bar.md`](enemy_health_bar.md) | World-space billboard HP and telegraph bars for enemies. |
| [`game_ui_skin.md`](game_ui_skin.md) | Shared imperative styling helpers for menus, HUD, and overlays. |
| [`hub_vendors.md`](hub_vendors.md) | Merchant, blacksmith, and storage modal panels in the hub. |
| [`input_glyphs.md`](input_glyphs.md) | Action-name to text glyph labels by controller family. |
| [`inventory_ui.md`](inventory_ui.md) | Grid stash, paper-doll equipment, and weapon loadout modal. |
| [`main_menu.md`](main_menu.md) | Front-end hub: New Game, Continue, Settings, Quit. |
| [`menu_shell.md`](menu_shell.md) | Static modal scaffold and button factories (not a Godot Theme). |
| [`menu_shell_a11y.md`](menu_shell_a11y.md) | Focus, navigation, and accessibility gaps across menu UIs. |
| [`minimap.md`](minimap.md) | Drawn room-graph minimap fed only during castle runs. |
| [`pause_menu.md`](pause_menu.md) | In-run pause: Resume, Settings, Abandon, Quit to menu. |
| [`run_flow_ui.md`](run_flow_ui.md) | Coordination of portal, outcome, and `RunFlow` handoffs. |
| [`run_outcome.md`](run_outcome.md) | Results screen, loading gate, achievement toast, epilogue, boss intro. |
| [`run_portals.md`](run_portals.md) | Hub castle / waves / endless entry menus and in-run stair menu. |
| [`settings.md`](settings.md) | Shared settings overlay owned by `PlayerControls`. |
| [`status_icon_atlas.md`](status_icon_atlas.md) | Procedural 22×22 status icon generator used by the combat HUD. |
| [`status_icons_glyphs.md`](status_icons_glyphs.md) | Coordination of status icons and input glyph surfaces. |
| [`talents.md`](talents.md) | Flat talent `ItemList` panel for spending progression points. |
| [`title_main_continue.md`](title_main_continue.md) | Shared entry path: title → main menu → loading → hub. |
| [`title_screen.md`](title_screen.md) | Boot scene built in code; any input advances to the main menu. |
| [`waves_hud.md`](waves_hud.md) | Umbral Waves lobby / combat / prep / reward-pick UI. |

## Related
- Tree README: [`../README.md`](../README.md)
- Improvement twins: [`../../actual_improvements/ui/_INDEX.md`](../../actual_improvements/ui/_INDEX.md)
- Conventions: [`../../DOC-CONVENTIONS.md`](../../DOC-CONVENTIONS.md)
