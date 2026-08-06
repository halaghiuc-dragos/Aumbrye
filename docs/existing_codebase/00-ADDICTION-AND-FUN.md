# Player feedback and loop integrity

Cross-cutting honesty and feedback surfaces on the live play path: combat reactions, run outcomes, quests, loot tiers, UI icons, boss identity, weapon art, audio, and character silhouettes. Per-system detail lives in linked docs below.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/art/characters/diorama_character_skin.gd` | Voxel manifest bodies; appearance extras (`Hood`, `BeltTrim`, `Pauldron`); box fallback only on missing manifest |
| `apps/game/client/scripts/audio/audio_director.gd` | File-backed combat SFX and biome ambience |
| `apps/game/client/scripts/ui/results_screen.gd` | Run outcome titles and hub messages |
| `apps/game/client/scripts/quests/quest_service.gd` | Escape/fetch quest completion gates |
| `apps/game/client/scripts/inventory/inventory_service.gd` | `register_fetch` on item pickup |
| `apps/game/client/scripts/loot/affix_roller.gd` | Rarity-tier affix rolls |
| `apps/game/client/scripts/combat/hit_feedback.gd` | Diorama body flash on hit |
| `apps/game/client/scripts/combat/weapon_controller.gd` | Weapon art lunge |
| `apps/game/client/scripts/ui/inventory_ui.gd` | `ItemIconAtlas` |
| `apps/game/client/scripts/ui/combat_hud.gd` | `StatusIconAtlas` |
| `apps/game/client/scripts/enemies/castle_enemy_base.gd` | Boss `set_catalog_id` |
| `content/characters/player_warden*.json` | Player rig manifests with appearance extras |

## How it works

1. **Characters** — `build_player_body()` / `build_enemy_body()` call `build_from_manifest()` for mapped archetypes. Player hood, belt trim, and pauldrons ship as manifest `extras` on `player_warden` (shared by height variants); `_apply_player_appearance()` toggles `visible` only (`diorama_character_skin.gd:177-198`). Missing manifest logs `push_error` and falls back to `_build_humanoid` / `_build_quadruped`.
2. **Audio** — `AudioDirector` loads OGG stems from `assets/audio/`; `_ensure_layer_streams()` preserves file-backed streams.
3. **Results** — `results_screen.gd` branches on `OUTCOME_WAVES_COMPLETE` / `OUTCOME_WAVES_FAILED` and escape keys.
4. **Quests** — Escape completes only on `OUTCOME_ESCAPED`; fetch via `InventoryService.add_item` → `QuestService.register_fetch`.
5. **Loot** — `affix_roller.gd` reads `tiers[rarity]`.
6. **Hit feedback** — `HitFeedback._flash_diorama_body` targets `Facing/DioramaVisual`; heal clip and SFX wired.
7. **UI icons** — Atlases under `content/ui/` replace Unicode cells.
8. **Boss identity** — `dungeon_builder.gd` calls `set_catalog_id` before `add_child`.
9. **Weapon art** — `weapon-definition.v1.json` `art` blocks; `_try_weapon_art()` applies lunge.

## Contracts

- Appearance extra node names: `Visor`, `Hood`, `BeltTrim`, `Pauldron`, `PauldronR` (`APPEARANCE_EXTRAS` in `diorama_character_skin.gd`).
- Outcome keys consumed by `results_screen.gd` and `quest_service.gd` must match `run_flow.gd` emissions.
- Boss catalog id set before enemy enters tree.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Voxel character silhouettes | IMPLEMENTED | `build_from_manifest()`; 25 manifests; appearance extras in `player_warden.json` |
| Box body fallback | PARTIAL | `_build_humanoid` / `_build_quadruped` on missing manifest only (`diorama_character_skin.gd:397-403`, `:620+`) |
| Face / class armour overlays | PLACEHOLDER | Runtime `PixelStyle.add_box` in `_apply_face` / `_apply_class_armor` (`:277-371`) |
| Authored combat audio | IMPLEMENTED | `assets/audio/sfx/` + `_load_sfx_bank` |
| Honest results / quests / loot | IMPLEMENTED | `results_screen.gd`, `quest_service.gd`, `affix_roller.gd` |
| Hit / heal / lunge feedback | IMPLEMENTED | `hit_feedback.gd`, `diorama_anim_library.gd`, `weapon_controller.gd` |
| UI icon atlases | IMPLEMENTED | `inventory_ui.gd`, `combat_hud.gd` |
| Boss catalog id | IMPLEMENTED | `castle_enemy_base.gd:94-108` |
| Weapon art JSON | IMPLEMENTED | `weapon_controller.gd:318-339` |

## Related

- Improvement plan: [`../actual_improvements/00-ADDICTION-AND-FUN.md`](../actual_improvements/00-ADDICTION-AND-FUN.md)
- [`00-GAME-LOOP.md`](00-GAME-LOOP.md), [`00-PLACEHOLDER-INVENTORY.md`](00-PLACEHOLDER-INVENTORY.md)
- [`character-authoring.md`](character-authoring.md), [`audio-director.md`](audio-director.md), [`hit-feedback.md`](hit-feedback.md)
