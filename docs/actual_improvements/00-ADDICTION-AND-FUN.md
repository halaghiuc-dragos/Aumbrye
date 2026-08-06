# Player feedback and loop integrity

## Status: FINISHED

Cross-cutting improvements for honesty and feedback. Per-system pages own implementation detail. Conventions: [`../DOC-CONVENTIONS.md`](../DOC-CONVENTIONS.md).

**Companions:** [`../existing_codebase/00-ADDICTION-AND-FUN.md`](../existing_codebase/00-ADDICTION-AND-FUN.md), [`../existing_codebase/00-PLACEHOLDER-INVENTORY.md`](../existing_codebase/00-PLACEHOLDER-INVENTORY.md), [`../existing_codebase/00-GAME-LOOP.md`](../existing_codebase/00-GAME-LOOP.md), [`00-QUALITY-BAR.md`](00-QUALITY-BAR.md).

## Today (code)

- Combat skeleton exists (`scripts/combat/`, `scripts/player/`).
- Player, enemy bipeds, and hounds load authored voxel manifests via `build_from_manifest()` (`tools/voxel-import/`, `content/characters/`, `assets/characters/*.voxels.json`); appearance hood/trim/pauldrons are manifest extras toggled in `_apply_player_appearance()`.
- Combat SFX and biome/hub/menu ambience load from `assets/audio/`; generators are fallback-only when a stem file is absent (`audio_director.gd`).
- Loop-honesty items (results, quests, affix tiers, icons, hit feedback, boss catalog id, weapon art, character trim) are **FINISHED** — see Change table.
- Hub portals and vendors work; Skies/Cathedral portals are hidden (`hub.gd`).

## Change (priority by player impact)

Ordered so each step makes the current loop more honest or more readable before expanding content.

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | **Character silhouettes are real** — replace runtime `BoxMesh` bodies with authored voxel meshes on the existing pivot rig ([`character-authoring.md`](character-authoring.md) CHA-01..CHA-05) | **FINISHED** | `tools/voxel-import/` pipeline; manifests + `.voxels.json` assets; `player_warden` extras `Hood`/`BeltTrim`/`Pauldron`/`PauldronR` in `content/characters/player_warden.json`; `_apply_player_appearance()` visibility toggles only (`diorama_character_skin.gd:177-198`); `_build_humanoid` / `_build_quadruped` error-only (`:397-403`, `:620+`); `hub_m4_suite.gd` `appearance.skin_applies_every_key`. |
| 2 | **Audio is authored** — replace generator SFX/ambience with streams under `assets/audio/`; stop clobbering OGG via `_restore_generator_streams()` ([`audio-director.md`](audio-director.md)) | **FINISHED** | Combat SFX from `assets/audio/sfx/` via `_load_sfx_bank`; `set_biome()` + `_load_layer_stems()` for dungeon; `play_hub_ambience` / `play_menu_music` bind `umbral_chapel` / `dark_cathedral` OGG; `_ensure_layer_streams()` preserves file-backed streams (`audio_director.gd:473-477`). |
| 3 | **Results are honest** — `results_screen.gd` branches on waves complete/failed keys ([`ui/run_outcome.md`](ui/run_outcome.md)) | **FINISHED** | `OUTCOME_WAVES_COMPLETE` / `OUTCOME_WAVES_FAILED` in `_title_for_outcome` and `_hub_message_for_outcome` (`results_screen.gd:88-111`); `flow_suite.gd`. |
| 4 | **Quests are honest** — escape/fetch completion only on real events; wire `register_fetch` from inventory pickup ([`dialogue-quests.md`](dialogue-quests.md), RFL-01 in [`run-flow.md`](run-flow.md)) | **FINISHED** | `register_run_outcome(OUTCOME_ESCAPED)` only (`quest_service.gd:95-96`, `run_flow.gd`); `InventoryService.add_item` → `register_fetch` (`inventory_service.gd:38-39`). |
| 5 | **Loot rarity is honest** — `affix_roller.gd` respects rarity tier tables ([`loot-and-equipment.md`](loot-and-equipment.md)) | **FINISHED** | `_roll_tier_value` reads `tiers[rarity]` (`affix_roller.gd:176-196`); `itemTypes` + `weight` honored. |
| 6 | **Hit confirmation is readable** — reactions target the diorama skin; heal has dedicated anim/SFX; lunge is non-zero ([`hit-feedback.md`](hit-feedback.md), [`weapons.md`](weapons.md), [`player-heal.md`](player-heal.md)) | **FINISHED** | `_flash_diorama_body` → `Facing/DioramaVisual` (`hit_feedback.gd:205-210`); `play_heal` clip (`diorama_anim_library.gd:248`); heal SFX (`player_heal.gd:73-101`); lunge (`weapon_controller.gd:245-259`, `combat_suite.gd`). |
| 7 | **UI icons are authored** — replace Unicode/emoji inventory and status cells with `iconPath` / atlas cells ([`ui/inventory_ui.md`](ui/inventory_ui.md), [`ui/status_icon_atlas.md`](ui/status_icon_atlas.md)) | **FINISHED** | `ItemIconAtlas` in `inventory_ui.gd`; `StatusIconAtlas` in `combat_hud.gd:193-195`; atlases under `content/ui/`. |
| 8 | **Boss identity matches spawn** — placement IDs vs `get_enemy_id()` mismatches resolved ([`bosses.md`](bosses.md)) | **FINISHED** | `set_catalog_id` + `_catalog_id_override` (`castle_enemy_base.gd:94-108`); `dungeon_builder.gd` calls before `add_child` (`:489-490`, `:548-549`); `quality.boss.catalog_id_wired` in `quality_bar_suite.gd`. |
| 9 | **Weapon arts exist** — authored `art` JSON and real lunge motion, with validation coverage ([`weapons.md`](weapons.md)) | **FINISHED** | `art` in `weapon-definition.v1.json`; `sword_basic.json` `guard_break` art; `_try_weapon_art()` + art `lunge_distance` (`weapon_controller.gd:318-339`); `combat.weapon_art_authored` in `combat_suite.gd`. |

## Out of scope / ABSENT

Do not invent multiplayer, new hub districts, or account meta currencies that have no save/schema/service path today. Online procgen stays behind `USE_ONLINE_PROCgen` until parity suites are green.

## Related

- [`character-authoring.md`](character-authoring.md), [`audio-director.md`](audio-director.md), [`hit-feedback.md`](hit-feedback.md), [`weapons.md`](weapons.md)
- [`ui/inventory_ui.md`](ui/inventory_ui.md), [`ui/run_outcome.md`](ui/run_outcome.md), [`dialogue-quests.md`](dialogue-quests.md)
- [`validation-harness.md`](validation-harness.md)
