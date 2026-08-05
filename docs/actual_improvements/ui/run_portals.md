# Run portals — improvement plan

## Current state
Three hub modals (`castle_entry_menu`, `umbral_waves_menu`, `umbral_endless_menu`) and one in-run stair menu start, continue, and floor-transition runs. They work on the live path through `hub.gd` and `RunFlow`, but each owns mouse mode with no `MenuStack`, seed start skips the weapon gate that New enforces, endless skip labels show raw item ids, and the stair menu never focuses a button. See [`../existing_codebase/ui/run_portals.md`](../existing_codebase/ui/run_portals.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| RPT-01 | P0 | Seed start does not require an equipped weapon, while New does. A player with an empty weapon slot can enter a dungeon from the seed panel. | `castle_entry_menu.gd:162-165` vs `_try_start_seed` `:189-206` |
| RPT-02 | P0 | Stair menu never calls `grab_focus`, so after opening on pad the player cannot activate Ascend / Descend / Retreat without a mouse. | `stair_menu.gd:65-78`; 0 `grab_focus` in file |
| RPT-03 | P1 | Endless skip buttons label raw `itemId` (`skip_10_floors`) instead of `ItemCatalog` display names. | `umbral_endless_menu.gd:99` |
| RPT-04 | P1 | Skip selection sets `button_pressed` on non-`toggle_mode` buttons, so the "selected" visual is unreliable. | `:108-112` |
| RPT-05 | P1 | Each portal menu and the stair menu write `Input.mouse_mode` directly and do not pause or register with a shared menu stack, so overlapping overlays and mouse restore race with pause / inventory. | open/close in all four scripts |
| RPT-06 | P1 | All portal and stair strings are hardcoded English; no `tr()` keys. | castle `:120-126`, waves `:57-59`, endless `:75-77`, stair `:59` |
| RPT-07 | P1 | Castle continue is offered whenever any continuable active run exists; the menu does not verify `runMode` is castle before enabling Continue (unlike endless, which checks `"endless"`). Selecting Continue on a non-castle save surfaces the hub message from `continue_castle_run` only after the menu has already closed. | `castle_entry_menu.gd:106`; `run_flow.gd:106-109`; endless check at `umbral_endless_menu.gd:71` |
| RPT-08 | P2 | `BiomeBox` is a dead scene node (`visible = false`, never read). | `castle_entry_menu.tscn` |
| RPT-09 | P2 | `menu_closed` is emitted but never connected; hub cannot refresh prompts on close. | `castle_entry_menu.gd:87`; `hub.gd` has no connect |
| RPT-10 | P2 | Waves and endless status copy hardcodes content numbers (`6` chests, `50` waves, `10` tiers) that can drift from service constants. | waves `:59`; endless `:77`; castle `:124` |

## Target design

### Shared portal modal
One `scenes/ui/run_portal_menu.tscn` shell (or three thin scenes sharing `RunPortalMenuBase`) registered with `MenuStack` from [`menu_shell_a11y.md`](menu_shell_a11y.md):

```
RunPortalMenu (MenuModal)
├── Dimmer
└── PanelContainer "MainPanel"
    └── ContentVBox
        ├── Label "TitleLabel"
        ├── Control "BodySlot"          # dropdown / status / skip list swapped by mode
        ├── HBoxContainer "Actions"
        │   ├── Button "PrimaryButton"
        │   └── Button "ContinueButton"
        └── Label "StatusLabel"
```

`MenuStack` owns mouse mode, `ui_cancel`, and pause-while-open so the four scripts stop writing `Input.mouse_mode` (RPT-05).

### Honest gates
- Castle New **and** seed start share `_require_weapon()`; seed start fails with the same status string as New (RPT-01).
- Castle Continue enabled only when `has_continuable_run()` and `runMode` is empty or `castle` (RPT-07), matching endless.
- Stair `_rebuild_buttons` ends with `first_enabled_button.grab_focus()` and wires `focus_neighbor_*` in order (RPT-02).

### Skip picker
Skip buttons use `MenuShell.make_menu_button`, `toggle_mode = true` in a `ButtonGroup`, and labels from `ItemCatalog.get_definition(item_id).get("name", item_id)` (RPT-03, RPT-04). Quantity from the skip entry is shown as `×N`.

### Copy from data
Status strings pull chest count / wave goal / tier step from `WavesRunService` / `RunFloorConfig` / `DungeonTierService` constants via format keys, not literals (RPT-10). Localization keys: `PORTAL_CASTLE_*`, `PORTAL_WAVES_*`, `PORTAL_ENDLESS_*`, `STAIR_*` (RPT-06).

Rejected alternative: keeping three fully independent menus with duplicated open/close. The open/close and skin paths are already copy-pasted; a base class removes the mouse-mode races without forcing one content layout.

## Work plan
1. **Weapon gate on seed** — call the same check as New before `seed_run_requested` (RPT-01).
2. **Castle continue mode filter** — mirror endless `runMode` check (RPT-07).
3. **Stair focus** — `grab_focus` + neighbors after `_rebuild_buttons` (RPT-02).
4. **Endless skip UX** — display names, `ButtonGroup`, `toggle_mode` (RPT-03, RPT-04).
5. **MenuStack registration** for all four menus; delete direct `Input.mouse_mode` writes (RPT-05).
6. **Localization + data-driven status numbers** (RPT-06, RPT-10).
7. **Delete `BiomeBox`; connect `menu_closed` to hub prompt refresh** (RPT-08, RPT-09).

## Data and schema changes
- `translations/strings.csv`: `PORTAL_*`, `STAIR_*` keys.
- No save-format change. Optional: expose `WavesRunService.LOBBY_CHEST_COUNT` / completion wave count as public consts if not already.

## Acceptance criteria
- [ ] Seed start with no equipped weapon leaves the menu open and shows the equip status; no scene change.
- [ ] Opening the stair menu focuses the first available action; pad can Ascend without a mouse.
- [ ] Castle Continue is disabled when the only saved run is `runMode == "endless"` or `"waves"`.
- [ ] Skip buttons show catalog display names and a single selected toggle in a group.
- [ ] No portal or stair script assigns `Input.mouse_mode`; `MenuStack` restores capture on close.
- [ ] `BiomeBox` is removed from `castle_entry_menu.tscn`.
- [ ] Hub refreshes its prompt when any portal menu emits `menu_closed`.

## Validation
- Extend `hub_suite.gd`: seed start without weapon does not call `RunFlow.start_run_with_seed`; continue disabled for endless-only save on castle menu.
- Extend `m7_suite.gd`: endless skip button text contains a catalog name, not only the raw id.
- Manual: pad-only stair ascend / retreat on a cleared floor.

## Related
- Existing: [`../existing_codebase/ui/run_portals.md`](../existing_codebase/ui/run_portals.md)
- [`run_flow_ui.md`](run_flow_ui.md) · [`run_outcome.md`](run_outcome.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`waves_hud.md`](waves_hud.md)
