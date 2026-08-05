# Hub

The hub (`AumbryeTower`) is the between-runs scene: six portals, four service tents, three NPCs, and a first-run tip sequence. `hub.gd` is 433 lines of proximity state and signal wiring; `hub_diorama.gd` is 757 lines of procedural dressing that rebuilds the scene's geometry and repositions most of its nodes at `_ready`.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scenes/hub/hub.tscn` | Scene: portals, tents, NPC instances, labels, and every hub UI as a child |
| `apps/game/client/scripts/hub/hub.gd` | Proximity flags, interact routing, run-start signal wiring, tip display |
| `apps/game/client/scripts/hub/hub_diorama.gd` | `HubDiorama.apply(hub)` — floor tiles, parapets, portal frames, tents, fountain, NPC bodies, node repositioning |
| `apps/game/client/scripts/hub/hub_interactable.gd` | `HubInteractable` — `Area3D` with `player_entered` / `player_exited` / `interacted` |
| `apps/game/client/scripts/hub/hub_tutorial_service.gd` | `HubTutorialService` — five hardcoded tips, persisted under `meta.hub_tutorial` |
| `apps/game/client/scripts/hub/forge_light_flicker.gd` | Per-frame flicker on the blacksmith forge light and its emissive mesh |
| `apps/game/client/scripts/npc/npc_base.gd` | The three hub NPCs; see [`npc-hub-services.md`](npc-hub-services.md) |

## How it works

### Scene contents
`hub.tscn` root is `Node3D` named `AumbryeTower` with the script attached (line 44-45). Direct children that matter:

| Node | Type | Notes |
|------|------|-------|
| `Floor` | `StaticBody3D` | 50 x 0.5 x 40 box mesh plus collision (lines 52-60); the mesh is hidden by the diorama |
| `LandmarkWalls` | `Node3D` | Four wall `MeshInstance3D`s, all hidden by the diorama (lines 62-86) |
| `Player` | instance of `player.tscn` | Placed at `(12, 0, 2)` in the scene (line 89) |
| `CastlePortal`, `UmbralEndlessPortal`, `UmbralWavesPortal`, `SkiesPortal`, `CathedralPortal` | `Node3D` | Each with `PortalFrame`, `PortalPad`, `InteractArea` (`HubInteractable`), `PortalLabel` |
| `ArenaDoor` | `Node3D` | Same shape; prompt `"Training Arena (E) · Weapon styles (Shift+E)"` (line 137) |
| `Blacksmith`, `Merchant`, `Storage`, `QuestBoard` | `Node3D` | `Building`/`Board` mesh, `InteractArea`, `Label` |
| `NpcAldric`, `NpcElara`, `NpcMira` | instances of `hub_npc.tscn` | `npc_id` set to `blacksmith_aldric`, `merchant_elara`, `warden_mira` (lines 246-256) |
| `MessageLabel`, `PromptLabel` | `Label3D` | Fixed at `(0, 3.5, 2)` and `(0, 2.2, 1.5)`, both billboarded |
| `CombatHUD`, `InventoryUI`, `DebugOverlay`, `CastleEntryMenu`, `DialogueUI`, `BlacksmithUI`, `MerchantUI`, `StorageUI`, `QuestBoardUI`, `UmbralEndlessMenu`, `UmbralWavesMenu` | Control / CanvasLayer | Every hub UI lives in the scene, not in an autoload |

All `InteractArea` nodes use `collision_layer = 0`, `collision_mask = 2` and a 4 x 4 x 4 `BoxShape3D`.

### `_ready` order (`hub.gd:41-82`)
1. `PixelDioramaBootstrap.prime()`, `HubDiorama.apply(self)`, and a deferred `PixelDioramaBootstrap.attach(self)`.
2. Ten `_wire_interactable` calls binding `player_entered` / `player_exited` to per-target `_near_*` flags.
3. `SkiesPortal.visible = false` and `CathedralPortal.visible = false` (lines 56-59) — their interact areas stay active.
4. Run-menu signals: `CastleEntryMenu.dungeon_run_requested` / `continue_requested` / `seed_run_requested`, `UmbralEndlessMenu.endless_run_requested` / `continue_requested`, `UmbralWavesMenu.waves_run_requested` / `continue_requested`, plus `DungeonTierService.tier_unlocked` -> `_refresh_castle_portal_label`.
5. Every node in the `hub_npc` group gets `dialogue_requested` -> `_on_npc_dialogue` and `shop_requested` -> `_on_npc_shop`.
6. `_show_return_message()`, `_refresh_castle_portal_label()`, `RunFlow.returned_to_hub` -> `_on_returned_to_hub`, `AudioDirector.play_hub_ambience()`, `HubTutorialService.load_from_save()`.
7. Deferred `_boot_save_and_services()` and deferred `_maybe_show_hub_tips()`.

### Boot and save (`hub.gd:85-94`)
`_boot_save_and_services` awaits `LocalSave.sync_from_cloud()`; if that returns false and a save exists it calls `LocalSave.load_into_services()`. When `CharacterService.class_id` is still empty it changes scene to `res://scenes/ui/main_menu.tscn`. Otherwise it auto-equips a starting weapon (`_auto_equip_starting_weapon`, falling back to `castle_sword` when the class is unknown), calls `LocalSave.autosave()`, and overwrites the message label with `"Welcome back, %s."`.

### Interaction model
There is no use of `HubInteractable.interacted` for hub landmarks. `hub.gd` keeps ten booleans and resolves them in a single `if / elif` chain in `_unhandled_input` (lines 120-168), gated on `_any_ui_open()`. Priority is fixed by the order of the chain: castle portal, endless, waves, skies, cathedral, arena, blacksmith, merchant, storage, quest board, then any `hub_npc` whose `is_player_near()` is true.

| Target | Action |
|--------|--------|
| Castle portal | `CastleEntryMenu.open_menu()` |
| Endless portal | `UmbralEndlessMenu.open_menu()` |
| Waves portal | `UmbralWavesMenu.open_menu()` |
| Skies portal | `show_hub_message("Aumbrye Skies is coming soon.")` |
| Cathedral portal | `show_hub_message("Aumbrye Cathedral is coming soon.")` |
| Arena door | `PlayerControls.open_loadout()` when Shift is held, otherwise `RunFlow.go_to_arena()` |
| Blacksmith / Merchant / Storage / Quest board | `open()` on the corresponding UI |
| NPC | `npc.trigger_interact()` |

`_process` calls `_update_prompt()` every frame (lines 171-172); the prompt text comes from `HubInteractable.get_prompt()`, or from `npc.get_node("InteractArea").get_prompt()` for NPCs, or `""`.

`_any_ui_open()` checks the eight scene UIs plus `PlayerControls.is_player_meta_ui_open()` (lines 212-223).

### Run start paths
| Signal | Handler | Calls |
|--------|---------|-------|
| `dungeon_run_requested(dungeon_id)` | `_on_dungeon_run` | `RunFlow.start_new_run(dungeon_id)` |
| `continue_requested` (castle) | `_on_castle_continue` | `RunFlow.continue_castle_run()` |
| `seed_run_requested(seed)` | `_on_castle_seed_run` | `RunFlow.start_run_with_seed(dungeon_id, seed)` with the id from `CastleEntryMenu.get_selected_dungeon()` when available, else `DungeonCatalog.DEFAULT_DUNGEON_ID` |
| `endless_run_requested(start_floor, skip_item_id)` | `_on_endless_run` | `RunFlow.start_endless_run(...)` |
| `continue_requested` (endless) | `_on_endless_continue` | `RunFlow.continue_endless_run()` |
| `waves_run_requested` | `_on_waves_run` | `RunFlow.start_waves_run()` |
| `continue_requested` (waves) | `_on_waves_continue` | `RunFlow.continue_waves_run()` |

Each handler then calls `_refresh_hub_message()`, which copies and clears `RunFlow.last_hub_message`.

### Diorama dressing (`hub_diorama.gd`)
`HubDiorama.apply(hub)` runs fifteen steps (lines 32-51). Notable behaviour:

- **Floor**: hides `Floor/MeshInstance3D`, then builds a `DioramaTiles` node with `25 x 20 = 500` alternating boxes at `TILE_SIZE = 2.0` over `FLOOR_WIDTH = 50` by `FLOOR_DEPTH = 40` (lines 64-93), plus a centre accent path and one door pad per service tent.
- **Walls**: hides every `MeshInstance3D` under `LandmarkWalls`, frees any existing `TowerParapet`, and builds four parapet runs with merlons, four corner turrets, two banners, and a fresh `WallCollision` `StaticBody3D` with four box shapes at `z = -20 / 18` and `x = +/-24` (lines 205-291).
- **Portals**: `_dress_portal` hides legacy meshes and builds an eleven-box arch plus `PixelDioramaStyle.add_portal_interior` and an `OmniLight3D` named `PortalGlow`, themed by the string `castle` / `umbral` / `training` / `skies` / `cathedral` (lines 397-436). `_add_portal_theme_accents` adds theme-specific boxes (lines 467-489).
- **Repositioning**: `_position_portals` overwrites the transforms of `CastlePortal`, `UmbralEndlessPortal`, `UmbralWavesPortal`, and `ArenaDoor` to `x = 12 - i * 6`, `z = -17`, and the two hidden portals to `x = -12` and `x = -18` (lines 160-181). `_position_player_spawn` sets the player to `PLAYER_SPAWN_POS = (12, 0, 2)` facing the portal wall (lines 184-196). `_position_service_npcs` moves `NpcAldric`, `NpcElara`, and `NpcMira` relative to hardcoded service positions (lines 699-722).
- **Tents**: `_dress_blacksmith`, `_dress_merchant`, `_dress_storage`, `_dress_quest_board` each call `PixelDioramaStyle.add_hub_tent`, add prop boxes and an `OmniLight3D`, add a billboarded `RidgeSign` `Label3D`, and call `_position_door_interact`, which moves the tent's `InteractArea` in front of the door and resizes its `BoxShape3D` (lines 492-696).
- **NPC bodies**: `_style_npc` hides the `Body` mesh and builds a three-box stand-in (torso, head, feet) coloured from `NPC_COLORS`, keyed by `npc_id` with a grey fallback (lines 725-757).

Service positions are hardcoded twice: in `hub_diorama.gd:135-145` (`_service_world_position`) and in the `hub.tscn` transforms for `Blacksmith` `(-18, 0, -4)`, `Merchant` `(-12, 0, 14)`, `Storage` `(0, 0, 14)`, `QuestBoard` `(12, 0, 14)`. The two currently agree.

### Forge flicker (`forge_light_flicker.gd`)
`setup(light, emissive_mesh)` caches the base light energy, duplicates the mesh's `material_override` (handling both `ShaderMaterial` via the `emission_energy` parameter and `StandardMaterial3D` via `emission_energy_multiplier`), and stores the base emission. `_process` computes `flick = 0.88 + sin(t * 8) * 0.06 + sin(t * 13) * 0.04` and writes it to both every frame.

### Hub tips (`hub_tutorial_service.gd`)
Five tips in a `static var TIPS` array (lines 12-18). State is three `static var`s — `tips_enabled`, `tips_completed`, `current_tip_index` — persisted under `LocalSave.get_meta_data()["hub_tutorial"]` as `{"enabled", "completed", "index"}` (lines 21-36). `advance_tip()` increments, marks completed past the end, saves, and returns the next tip; `skip_all()` sets both completed and disabled and saves. Every one of these calls `LocalSave.autosave()`.

`hub.gd:413-420` writes `"%s (Esc to skip tips)" % tip` into `MessageLabel`. `hub.gd:423-432` handles `ui_cancel` to skip all, and `ui_accept` or `interact` to advance — without marking the event handled.

The five tip strings, checked against `apps/game/client/project.godot`:

| Tip | Claim | Actual binding |
|-----|-------|----------------|
| 1 | "Dash with Space to dash through attacks" | `dodge` is Space (`project.godot:155-159`) — correct |
| 2 | "Block with right-click; a well-timed parry staggers enemies" | `block` is `Q` plus a joypad trigger axis (`project.godot:173-177`) — wrong |
| 3 | "Defeat the floor boss, then use the stair lever to ascend" | Matches [`stair-lever.md`](stair-lever.md) |
| 4 | "Secret rooms hide extra loot — listen for hidden passages" | No audio cue for hidden rooms found; searched `apps/game/client/scripts/audio/` and `room_content/` |
| 5 | "Press Esc to open inventory and equip better gear" | `inventory` is Tab (`project.godot:250-255`); the in-scene label reads `"Inventory (Tab)"` (`hub.tscn:343`) — wrong |

## Contracts
**Node paths `hub.gd` requires** (`@onready`, lines 7-27): `CastlePortal/PortalLabel`, `CastlePortal/InteractArea`, `UmbralEndlessPortal/InteractArea`, `UmbralWavesPortal/InteractArea`, `SkiesPortal/InteractArea`, `CathedralPortal/InteractArea`, `ArenaDoor/InteractArea`, `Blacksmith/InteractArea`, `Merchant/InteractArea`, `Storage/InteractArea`, `QuestBoard/InteractArea`, `MessageLabel`, `PromptLabel`, `CastleEntryMenu`, `UmbralEndlessMenu`, `UmbralWavesMenu`, `DialogueUI`, `BlacksmithUI`, `MerchantUI`, `StorageUI`, `QuestBoardUI`. Any missing node is a hard `_ready` failure.

**Node names `hub_diorama.gd` requires:** `Floor`, `Floor/MeshInstance3D`, `LandmarkWalls`, `LandmarkWalls/WallCollision`, `Player`, `Player/Facing`, `PlazaFountain` (absence expected), the six portal roots, the four service roots, each service `InteractArea/CollisionShape3D` and `Label`, and `NpcAldric` / `NpcElara` / `NpcMira`. All are guarded with `get_node_or_null` and skipped silently when absent.

**Groups:** `hub_npc` (iterated at `hub.gd:70`, `163`, `251` and `hub_diorama.gd:727`), `player` (checked by `HubInteractable._on_body_entered`).

**Autoload dependencies:** `PixelDioramaBootstrap`, `VisualLighting`, `AudioDirector`, `RunFlow`, `LocalSave`, `CharacterService`, `InventoryService`, `PlayerControls`, `DungeonTierService`, plus the static classes `PixelDioramaStyle`, `ClassCatalog`, `DungeonCatalog`, `LockOnMovement`, `HubTutorialService`.

**Signals consumed:** `HubInteractable.player_entered` / `player_exited`, `NpcBase.dialogue_requested` / `shop_requested`, `RunFlow.returned_to_hub`, `DungeonTierService.tier_unlocked`, and the seven run-menu signals.

**Save keys:** `meta.hub_tutorial.enabled`, `meta.hub_tutorial.completed`, `meta.hub_tutorial.index`.

**Duck-typed calls:** `ui.is_open()` (`hub.gd:209`), `npc.is_player_near()` / `npc.trigger_interact()` (`hub.gd:164-166`), `_castle_menu.get_selected_dungeon()` (`hub.gd:287-288`), `npc.get_npc_id()` or the `npc_id` property (`hub_diorama.gd:734-737`).

**Environment variable:** `AUMBRYE_NO_ENV` skips `VisualLighting.apply_hub` (`hub_diorama.gd:59-60`).

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Ten proximity interactables with prompts | IMPLEMENTED | `hub.gd:45-54`, `hub.gd:226-255` |
| Three run-mode entry menus wired to `RunFlow` | IMPLEMENTED | `hub.gd:61-68`, `hub.gd:275-310` |
| Arena entry and Shift+E loadout | IMPLEMENTED | `hub.gd:143-149` |
| Blacksmith / merchant / storage / quest board UIs | IMPLEMENTED | `hub.gd:179-192`; services documented in [`npc-hub-services.md`](npc-hub-services.md) |
| NPC dialogue and shop routing | IMPLEMENTED | `hub.gd:351-362`, `npc_base.gd:44-62` |
| Procedural diorama dressing | IMPLEMENTED | `hub_diorama.gd:32-51` |
| Forge light flicker | IMPLEMENTED | `forge_light_flicker.gd:33-41` |
| Castle portal tier label | IMPLEMENTED | `hub.gd:258-260` via `DungeonTierService.get_hub_portal_label()` |
| Hub tips content source | PLACEHOLDER | `hub_tutorial_service.gd:12-18` is a hardcoded GDScript array; nothing under `content/` describes tips |
| Hub tip accuracy | BROKEN | Tip 2 names right-click for `block`, which is bound to `Q` (`project.godot:173-177`); tip 5 names Esc for the inventory, which is bound to Tab (`project.godot:250-255`) |
| Hub tip visibility | BROKEN | `_maybe_show_hub_tips` is deferred at `hub.gd:82` and writes `MessageLabel`, but the deferred `_boot_save_and_services` resumes after its `await` and overwrites the same label with `"Welcome back, %s."` (`hub.gd:94`) |
| Hub tip input | BROKEN | `hub.gd:423-432` never calls `set_input_as_handled`, so one `interact` press both advances the tip and triggers the nearby interactable in `_unhandled_input` |
| Hub tip state scoping | BROKEN | `HubTutorialService.load_from_save()` runs at `hub.gd:80`, before the deferred `_boot_save_and_services` loads the character (`hub.gd:81`), so tips are read from whatever `_cached_state` held first — on a character switch that is the previous character's meta |
| Hub tip glyph awareness | ABSENT | Tips are literal key names; no use of the input glyph helper (see [`ui/input_glyphs.md`](ui/input_glyphs.md)) |
| `HubInteractable.interact_id` | FAKE | Exported at `hub_interactable.gd:11`; grep of the whole repository finds no other reference and no `.tscn` sets it |
| `HubInteractable.interacted` for landmarks | PARTIAL | Emitted by `trigger_interact` and used only by `NpcBase` (`npc_base.gd:23`); the ten hub landmarks bypass it in favour of ten booleans |
| Skies and Cathedral portals | PLACEHOLDER | Hidden at `hub.gd:56-59` while their interact areas remain enabled, so an invisible area still produces a "coming soon" message |
| Message and prompt placement | PARTIAL | `MessageLabel` is fixed at world `(0, 3.5, 2)` (`hub.tscn:259`) while the player spawns at `(12, 0, 2)` (`hub_diorama.gd:29`), so hub messages appear 12 m to the side |
| Scene transforms for portals and the arena door | FAKE | `hub.tscn` places `CastlePortal` at `(-12, 0, -17)` and `ArenaDoor` at `(20.17, 0, 12.31)`; `_position_portals` overwrites all four to the north wall (`hub_diorama.gd:160-173`) |
| Service positions | PARTIAL | Duplicated between `hub_diorama.gd:135-145` and the `hub.tscn` transforms; they agree today with nothing enforcing it |
| Per-frame prompt recompute | PARTIAL | `_process` calls `_update_prompt` every frame (`hub.gd:171-172`), which iterates the `hub_npc` group and reassigns `Label3D.text` even when nothing changed |
| Hub interactable audio or highlight feedback | ABSENT | `HubInteractable` emits signals only; no sound, outline, or tween on enter — searched `hub_interactable.gd` and `hub.gd` |
| Autosave on entering the hub | IMPLEMENTED | `hub.gd:93` |
| Appearance mirror or respec station in the hub | ABSENT | No such node in `hub.tscn`; respec is reached through the blacksmith (`blacksmith_service.gd:104-110`) |

## Related
- Improvement plan: [`../actual_improvements/hub.md`](../actual_improvements/hub.md)
- [`npc-hub-services.md`](npc-hub-services.md), [`dialogue-quests.md`](dialogue-quests.md), [`run-flow.md`](run-flow.md), [`local-save.md`](local-save.md), [`character-service.md`](character-service.md), [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md), [`pixel-style.md`](pixel-style.md), [`visual-lighting.md`](visual-lighting.md), [`audio-director.md`](audio-director.md), [`ui/hub_vendors.md`](ui/hub_vendors.md), [`ui/run_portals.md`](ui/run_portals.md), [`ui/input_glyphs.md`](ui/input_glyphs.md)
