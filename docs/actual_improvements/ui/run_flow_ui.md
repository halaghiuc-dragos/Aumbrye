# Run flow UI — improvement plan

## Current state
Portal menus, stair / cinematic overlays, and the results screen are wired to `RunFlow` and complete the live loop, but the results screen does not honor `waves_complete` / `waves_failed`, waves XP level-ups are zeroed in the payload, and every overlay owns mouse mode independently. See [`../existing_codebase/ui/run_flow_ui.md`](../existing_codebase/ui/run_flow_ui.md), plus surface plans in [`run_portals.md`](run_portals.md) and [`run_outcome.md`](run_outcome.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| RFU-01 | P0 | Results UI ignores `waves_failed` / `waves_complete`, so a failed waves run reads as success when returning to the hub. | `results_screen.gd:42-50`, `:87-91`; producers at `run_flow.gd:957`, `:980` |
| RFU-02 | P0 | No single owner for modal mouse mode / cancel across portal → run → results, so overlays race (portal close captures mouse while another UI may still be open). | portal/stair/results/pause each assign `Input.mouse_mode` |
| RFU-03 | P1 | `complete_waves_run` hardcodes `levels_gained: 0`, breaking the results level-up line for waves. | `run_flow.gd:961-962` |
| RFU-04 | P1 | Portal Continue / seed gates disagree with `RunFlow` mode and weapon rules (documented as RPT-01, RPT-07). | `castle_entry_menu.gd:106`, `:189-206`; `run_flow.gd:106-109` |
| RFU-05 | P1 | UI never listens to `run_ended` / `run_started`; presentation is scene-change-only, so a future in-hub summary or toast on retreat cannot reuse the same path. | 0 UI connects to those signals |
| RFU-06 | P2 | `quit_waves_run` and `retreat_to_hub` dump the player into the hub with only a `Label3D` message — no optional summary card — while death/escape always force a full results scene. Inconsistent off-ramps. | `run_flow.gd:491-509`, `:929-948` vs RESULTS_SCENE paths |

## Target design

### One results presenter
`ResultsScreen` becomes the only consumer of `last_run_results`, with an outcome table covering all four ids (see ROC-01/ROC-02). `RunFlow` keeps writing the dictionary and changing scene; the UI stops inferring success from "not died".

Optionally allow `return_to_hub` callers to pass `show_results: bool` later; for v1, keep retreat/quit as message-only but route their copy through the same localized string table so hub and results share wording (RFU-06).

### MenuStack across the run lifecycle
Portal menus, stair menu, pause, inventory, epilogue, and boss intro push/pop `MenuStack` (from [`menu_shell_a11y.md`](menu_shell_a11y.md)). Results screen pushes on `_ready` and pops before `return_to_hub`. Direct `Input.mouse_mode` writes are deleted from those scripts (RFU-02). Portal gate fixes land with RPT-* (RFU-04).

### Honest waves payload
```gdscript
var xp_result := ProgressionService.grant_xp(WAVES_COMPLETION_XP, "waves")
last_run_results = {
    "outcome": "waves_complete",
    ...
    "xp_gained": int(xp_result.get("gained", 0)),
    "levels_gained": int(xp_result.get("levels_gained", 0)),
    ...
}
```
(RFU-03).

### Signal bridge (light)
Hub connects `RunFlow.returned_to_hub` already. Add a thin `RunFlowUI` helper (or hub method) that maps `last_hub_message` keys to localized strings. Do **not** require UI to connect `run_ended` for the results scene path — keep scene change — but document `run_ended` as the extension point for non-scene summaries (RFU-05).

Rejected alternative: showing results as a hub overlay instead of a scene. That would complicate pause/autoload lifetime; the scene change is fine once copy is honest.

## Work plan
1. **Results outcome table** — land ROC-01/ROC-02/ROC-03 (RFU-01).
2. **Fix waves `levels_gained`** in `run_flow.gd` (RFU-03).
3. **Portal gate alignment** — RPT-01, RPT-07 (RFU-04).
4. **MenuStack adoption** for portal, stair, cinematic, results (RFU-02).
5. **Shared hub/results string keys** for retreat and quit messages (RFU-06).
6. **Document / optional hub listener** for `run_ended` summaries without changing the results scene path (RFU-05).

## Data and schema changes
- Localization keys shared with ROC/RPT plans.
- No save-format change. `last_run_results` gains no new required keys; waves must populate existing `levels_gained` correctly.

## Acceptance criteria
- [ ] `waves_failed` never shows a success title or `"Run complete!"` hub message.
- [ ] `waves_complete` has distinct title/message from castle escape.
- [ ] Waves XP that levels the player sets `levels_gained > 0` in `last_run_results`.
- [ ] Closing a portal menu while pause is closed leaves mouse captured exactly once (no double-toggle).
- [ ] Castle seed start and New share the weapon gate; castle Continue respects `runMode`.
- [ ] Flow suite (or new suite) asserts all four outcome strings appear in results handling.

## Validation
- `flow_suite.gd`: results script branches on all four outcomes; `run_flow.gd` waves complete copies `levels_gained` from `grant_xp`.
- Manual checklist: waves fail → results → hub message; waves win with enough XP to level → "Level up!"; retreat → hub without results scene.

## Related
- Existing: [`../existing_codebase/ui/run_flow_ui.md`](../existing_codebase/ui/run_flow_ui.md)
- [`run_portals.md`](run_portals.md) · [`run_outcome.md`](run_outcome.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`title_main_continue.md`](title_main_continue.md) · [`waves_hud.md`](waves_hud.md)
