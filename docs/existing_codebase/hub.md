# Hub

The hub (`AumbryeTower`) is the between-runs scene: portals, service tents, three NPCs, and a content-driven first-run tip sequence. `hub.gd` routes interaction by `interact_id` through `INTERACT_HANDLERS`; `hub_diorama.gd` dresses geometry without repositioning authored scene transforms.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scenes/hub/hub.tscn` | Scene: portals, tents, NPCs, player-anchored labels, hub UIs |
| `apps/game/client/scripts/hub/hub.gd` | `INTERACT_HANDLERS`, event-driven prompts, tip display on `save_loaded` |
| `apps/game/client/scripts/hub/hub_diorama.gd` | Procedural dressing; interact feedback wiring |
| `apps/game/client/scripts/hub/hub_interactable.gd` | `Area3D` with `interact_id`, `enabled`, enter sound, highlight |
| `apps/game/client/scripts/hub/hub_tutorial_service.gd` | Tips from `content/hub/tips.json`; glyph substitution; `seen` ids |
| `content/hub/tips.json` | Tip catalog with `{action}` placeholders |
| `apps/game/client/scripts/npc/npc_base.gd` | NPCs with `interact_id = npc:<id>` |

## How it works

### Interaction

`_nearby: Dictionary` maps `interact_id` → `HubInteractable`. `INTERACT_HANDLERS` maps ids to handler method names (`hub.gd:7-20`). `_unhandled_input` resolves the nearest enabled interactable and dispatches the handler. Tips are handled first in `_unhandled_input` with `set_input_as_handled()` so they do not double-fire with interact.

Skies and Cathedral portal areas are disabled in `hub.tscn` (`enabled = false` on `HubInteractable`).

### Tips

`HubTutorialService.load_catalog()` reads `content/hub/tips.json`. `get_current_tip()` substitutes `{action}` tokens via `InputGlyphService`. State persists under `meta.hub_tutorial` as `{enabled, completed, seen[]}`; `LocalSave.patch_meta()` + `request_autosave(DEFERRED)` on changes. Tips display on `Player/MessageAnchor/TipLabel`; welcome text uses `MessageLabel` on the same anchor. `load_from_save()` runs on `LocalSave.save_loaded`.

`SaveMigrator._normalize_meta()` calls `HubTutorialService.migrate_index_to_seen()` for legacy `index` fields.

### Diorama

`HubDiorama.apply(hub)` builds floor tiles, parapets, portal frames, tents, and NPC stand-ins. Scene-node transforms are authoritative — portal, player, and service positions are no longer overwritten at runtime.

## Contracts

- **Interact ids:** `portal:castle`, `portal:endless`, `portal:waves`, `portal:skies`, `portal:cathedral`, `arena`, `blacksmith`, `merchant`, `storage`, `quest_board`, `npc:<npc_id>`.
- **Save keys:** `meta.hub_tutorial.enabled`, `meta.hub_tutorial.completed`, `meta.hub_tutorial.seen`.
- **Autoloads:** `LocalSave`, `RunFlow`, `CharacterService`, `InputGlyphService`, `AudioDirector`, etc.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Id-based interact routing | IMPLEMENTED | `hub.gd:7-20`, `:250-253` |
| Content-driven tips + glyphs | IMPLEMENTED | `content/hub/tips.json`, `hub_tutorial_service.gd` |
| Separate tip / welcome labels | IMPLEMENTED | `hub.tscn` `Player/MessageAnchor/*` |
| Per-character tip state | IMPLEMENTED | `save_loaded` handler, `reset_for_character()` |
| Disabled hidden portals | IMPLEMENTED | `hub.tscn` Skies/Cathedral `enabled = false` |
| Player-anchored messages | IMPLEMENTED | labels under `Player/MessageAnchor` |
| Scene-authoritative layout | IMPLEMENTED | `hub_diorama.gd` no longer repositions portals/NPCs |
| Event-driven prompts | IMPLEMENTED | `_update_prompt()` on enter/exit, not every frame |
| Interact enter feedback | IMPLEMENTED | `hub_interactable.gd` sound + highlight |
| Deferred tip autosave | IMPLEMENTED | `patch_meta()` + `request_autosave(DEFERRED)` |
| Skies / Cathedral gameplay | PLACEHOLDER | areas disabled; content not shipped |

## Related

- Improvement plan: [`../actual_improvements/hub.md`](../actual_improvements/hub.md) — **FINISHED**
- [`npc-hub-services.md`](npc-hub-services.md), [`dialogue-quests.md`](dialogue-quests.md), [`local-save.md`](local-save.md), [`ui/input_glyphs.md`](ui/input_glyphs.md)
