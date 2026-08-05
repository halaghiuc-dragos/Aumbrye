# Run portals

Hub modal menus that start or continue a dungeon, waves, or endless run, plus the in-run stair-lever menu that moves between floors. All three hub menus are scene children of `hub.tscn` and open on `interact` when the player is near the matching portal (`hub.gd:128-136`).

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/ui/castle_entry_menu.gd` | 215 lines; castle / tier dungeon entry, continue, seed |
| `apps/game/client/scenes/ui/castle_entry_menu.tscn` | authored `MainPanel` + `SeedPanel` tree |
| `apps/game/client/scripts/ui/umbral_waves_menu.gd` | 72 lines; waves new / continue |
| `apps/game/client/scenes/ui/umbral_waves_menu.tscn` | authored `MainPanel` |
| `apps/game/client/scripts/ui/umbral_endless_menu.gd` | 139 lines; endless new / continue / skip-floor |
| `apps/game/client/scenes/ui/umbral_endless_menu.tscn` | authored `MainPanel` + `SkipPanel` |
| `apps/game/client/scripts/ui/stair_menu.gd` | 105 lines; no `.tscn`; built in code |
| `apps/game/client/scripts/hub/hub.gd` | opens menus and forwards signals to `RunFlow` |
| `apps/game/client/scripts/dungeon/stair_lever.gd` | opens the stair menu via group `stair_menu` |
| `apps/game/client/scripts/dungeon/castle_run.gd` | instantiates `StairMenuScript` at `:113-114` |

## Castle entry (`castle_entry_menu.gd`)

### Control tree (scene)
```
CastleEntryMenu (Control, FULL_RECT, mouse_filter IGNORE until open)
├── Dimmer                         Color(0,0,0,0.55)
├── MainPanel                      ±220 × ±160
│   └── Margin → VBox
│       ├── Title                  filled from DungeonTierService.get_menu_title
│       ├── DungeonDropdown        OptionButton, unlocked dungeons only
│       ├── BiomeBox               visible = false (dead leftover)
│       ├── NewButton              "Start Run"
│       ├── ContinueButton         "Continue"
│       ├── SeedButton             "Play on Seed"
│       └── StatusLabel
└── SeedPanel                      hidden until Seed; ±220 × ±120
    └── Margin → VBox
        ├── SeedTitle              "Enter Base Run Seed"
        ├── SeedInput              LineEdit
        ├── SeedHintLabel
        ├── SeedStartButton
        └── SeedBackButton
```

`_ready` applies `GameUISkin.apply_modal_menu` twice — once for the root (default `MainPanel` / `Dimmer`) and once for `SeedPanel` (`:32-33`). `process_mode = ALWAYS` (`:30`).

### Signals → hub → RunFlow
| Signal | Hub handler | RunFlow call |
|--------|-------------|--------------|
| `dungeon_run_requested(dungeon_id)` | `_on_dungeon_run` `:275` | `start_new_run(dungeon_id)` |
| `continue_requested` | `_on_castle_continue` `:280` | `continue_castle_run()` |
| `seed_run_requested(seed)` | `_on_castle_seed_run` `:285` | `start_run_with_seed(get_selected_dungeon(), seed)` |
| `menu_closed` | not connected | — |

### Open / close
`open_menu` (`:73-80`) rebuilds the dropdown, refreshes continue state, shows the main panel, sets `MOUSE_FILTER_STOP`, releases the cursor, and `grab_focus` on `NewButton`. `close_menu` (`:83-87`) captures the mouse and emits `menu_closed`. `ui_cancel` returns from the seed panel to main, or closes (`:94-102`).

### Dropdown and gates
`_build_dungeon_dropdown` (`:46-62`) clears the list, sets the title from `DungeonTierService.get_menu_title(tier)`, and adds only dungeons where `is_dungeon_unlocked`. Metadata per item is the dungeon `id`. Default selection is index 0.

`_refresh_continue_state` (`:105-128`):
- Continue enabled iff `LocalSave.has_continuable_run()`.
- New disabled when equipped weapon id is `""`.
- Status text: continue summary (`Tier N — name floor F (seed S)`), or `"Clear 10 floors to unlock the next tier."`, then either overwritten by `"Equip a weapon..."` or appended with `| Weapon: name`.

`_on_new_pressed` re-checks the weapon and emits `dungeon_run_requested(_selected_dungeon)` (`:162-167`). Seed start (`_try_start_seed`, `:189-206`) validates digits `>= 1` and `DungeonSeedService.can_access_tier`, then emits only the seed integer — **no weapon check**.

## Waves entry (`umbral_waves_menu.gd`)

```
UmbralWavesMenu
├── Dimmer
└── MainPanel (±220 × ±120)
    └── Title "Aumbrye Outskirts" | StatusLabel | NewButton | ContinueButton
```

Signals: `waves_run_requested` → `RunFlow.start_waves_run()` (`hub.gd:303-304`); `continue_requested` → `continue_waves_run()` (`:308-309`). Continue enabled from `LocalSave.has_continuable_waves_run()`; status shows `"Continue waves run (wave %d)."` or `"Open 6 chests, survive 50 waves."` (`:52-59`). `NewButton.grab_focus` on open (`:30`). No seed, no dungeon dropdown, no weapon gate.

## Endless entry (`umbral_endless_menu.gd`)

```
UmbralEndlessMenu
├── Dimmer
├── MainPanel (±220 × ±140)
│   └── Title "Aumbrye Prison" | StatusLabel | NewButton | ContinueButton
└── SkipPanel (hidden)
    └── Title | SkipBox (dynamic buttons) | SkipStart | SkipNone | SkipBack
```

Continue requires `has_continuable_run()` **and** `runMode == "endless"` (`:69-71`). New with no skip items in inventory emits `endless_run_requested(1, "")` immediately (`:115-119`); otherwise opens `SkipPanel` and builds one button per `SkipFloorSvc.get_available_skips` labeled `"Use %s → floor %d"` with the raw `itemId` (`:91-105`). Selection sets `_selected_skip` by setting `button_pressed` on children that are not `toggle_mode` (`:108-112`). Hub forwards to `RunFlow.start_endless_run(start_floor, skip_item_id)` (`hub.gd:293-294`).

## Stair menu (`stair_menu.gd`)

Built entirely in `_build_ui` (`:43-62`): backdrop + center panel (`MENU_HALF_W+20` × `MENU_HALF_H+40`) with title `"Stair Lever"`. Added to group `stair_menu` (`:14`). `castle_run.gd:113-114` creates one instance per castle run.

`stair_lever.gd:48-50` on `interact` calls `open_for_lever(self)` when a group member exists. `_rebuild_buttons` (`:65-78`) reads private lever fields via `Object.get`:
- `_can_ascend` → `"Ascend floor"` → `_lever._use_lever("ascend")`
- `_can_descend` → `"Descend floor"`
- `_can_retreat` and `RunFlow.can_retreat_to_hub()` → `"Retreat to hub"` → `RunFlow.retreat_to_hub()`
- always `"Close"`

No `grab_focus` on any button. `ui_cancel` closes (`:99-104`).

## Contracts
| Contract | Detail |
|----------|--------|
| Hub node names | `$CastleEntryMenu`, `$UmbralEndlessMenu`, `$UmbralWavesMenu` (`hub.gd:20-22`) |
| Portal proximity | `_near_portal` / `_near_endless_portal` / `_near_waves_portal` gate `open_menu` |
| Save keys read | `LocalSave` active run: `dungeonId`/`biomeId`, `dungeonTier`, `currentFloor`, `seed`, `runMode`; waves: `currentWave` |
| Autoloads | `DungeonCatalog`, `DungeonTierService`, `DungeonSeedService`, `LocalSave`, `InventoryService`, `ItemCatalog`, `RunFlow`, `SkipFloorSvc` |
| Stair group | `"stair_menu"`; lever private fields `_can_ascend` / `_can_descend` / `_can_retreat` |
| Mouse mode | each menu sets `VISIBLE` on open and `CAPTURED` on close — no shared stack |

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Castle new / continue / seed → RunFlow | IMPLEMENTED | `castle_entry_menu.gd:162-206`; `hub.gd:275-290` |
| Waves / endless new / continue → RunFlow | IMPLEMENTED | `hub.gd:293-310` |
| Unlocked-dungeon dropdown | IMPLEMENTED | `castle_entry_menu.gd:46-62` |
| Weapon gate on castle New | IMPLEMENTED | `:112`, `:162-165` |
| Weapon gate on seed start | ABSENT — seed path never checks equipped weapon | `_try_start_seed` `:189-206` |
| Seed dungeon selection | IMPLEMENTED — hub reads `get_selected_dungeon()` | `hub.gd:285-289`; `:209-210` |
| Continue status for castle | IMPLEMENTED | `:113-122` |
| Endless skip-floor picker | PARTIAL — labels use raw `itemId`; selection sets `button_pressed` without `toggle_mode` | `umbral_endless_menu.gd:99`, `:108-112` |
| Stair ascend / descend / retreat | IMPLEMENTED when lever flags allow | `stair_menu.gd:72-78` |
| Stair focus | ABSENT — no `grab_focus` after rebuild | `:65-78` |
| MenuStack / pause | ABSENT — each menu owns mouse mode and does not pause the tree | open/close in all three hub menus |
| Localization | ABSENT — all strings hardcoded English | e.g. castle `:120-126`, waves `:57-59`, endless `:75-77`, stair `:59` |
| `BiomeBox` node | STUB — present in scene with `visible = false`, never referenced in script | `castle_entry_menu.tscn` BiomeBox |
| `menu_closed` | PARTIAL — emitted on close, never connected by hub | `castle_entry_menu.gd:87`; no connect in `hub.gd` |
| Skies / Cathedral portals | PLACEHOLDER — hub shows "coming soon" messages, menus not involved | `hub.gd:137-142` |

## Related
- Improvement plan: [`../actual_improvements/ui/run_portals.md`](../actual_improvements/ui/run_portals.md)
- Coordination: [`run_flow_ui.md`](run_flow_ui.md) · [`run_outcome.md`](run_outcome.md) · [`waves_hud.md`](waves_hud.md)
- [`menu_shell.md`](menu_shell.md) · [`game_ui_skin.md`](game_ui_skin.md) · [`hub_vendors.md`](hub_vendors.md)
- [`../run-flow.md`](../run-flow.md) · [`../hub.md`](../hub.md) · [`../stair-lever.md`](../stair-lever.md) · [`../dungeon-catalog-tiers.md`](../dungeon-catalog-tiers.md)
