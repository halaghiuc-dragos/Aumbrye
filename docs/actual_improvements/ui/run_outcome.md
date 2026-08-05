# Run outcome — improvement plan

## Current state
`RunFlow` writes four distinct `outcome` values into `last_run_results` (`escaped`, `died`, `waves_complete`, `waves_failed`), but `results_screen.gd` only special-cases `"died"`. Every other outcome — including **`waves_failed`** — gets the success title and the hub message `"Run complete! Your progress was saved."` (`:46-50`, `:87-91`). Loading, toast, epilogue, and boss intro are functional overlays with placeholder copy and no shared menu stack. See [`../existing_codebase/ui/run_outcome.md`](../existing_codebase/ui/run_outcome.md) and the P0 in [`../existing_codebase/00-GAME-LOOP.md`](../existing_codebase/00-GAME-LOOP.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| ROC-01 | P0 | `waves_failed` is shown as a successful run: success title path and `"Run complete! Your progress was saved."` on accept. | `results_screen.gd:42-50`, `:87-91`; producer `run_flow.gd:979-988` |
| ROC-02 | P0 | `waves_complete` has no dedicated title or hub message; it is indistinguishable from a castle escape on the results screen. | `:46-50`, `:90-91` vs `run_flow.gd:956-966` |
| ROC-03 | P1 | Results screen has no focused control — only `_unhandled_input` on accept/interact — so the dismiss affordance is invisible and easy to miss on pad. | `:80-91`; no Button in the scene for dismiss |
| ROC-04 | P1 | Epilogue and boss intro do not pause the run; combat and camera continue under the card. | `epilogue_card.gd:10-14`; `boss_intro_ui.gd:12-16`; no `get_tree().paused` |
| ROC-05 | P1 | Boss intro cannot be skipped; fixed ~3 s timeline. | `boss_intro_ui.gd:27-31` |
| ROC-06 | P1 | Achievement toasts do not queue; two unlocks overlap as separate root children. | `achievement_service.gd:110-114`; toast `queue_free` only self |
| ROC-07 | P1 | Loading screen burns `1.1` s before work and shows three fixed strings with no progress. | `loading_screen.gd:7`, `:51-60` |
| ROC-08 | P1 | All outcome UI strings are hardcoded English. | `results_screen.gd:45-77`; `epilogue_card.gd:39`; `castle_run.gd:482-483` |
| ROC-09 | P2 | `complete_waves_run` hardcodes `levels_gained: 0` after `grant_xp`, so a level-up from waves XP never shows `" — Level up!"`. | `run_flow.gd:961-962` |
| ROC-10 | P2 | Toast bypasses `GameUISkin`; visual language differs from every other modal. | `achievement_toast.gd` has no skin preload |
| ROC-11 | P2 | Epilogue body is a single hardcoded paragraph in `castle_run.gd`, not content data. | `castle_run.gd:482-483` |

## Target design

### Outcome table on the results screen
Replace the `"died"` vs else fork with an explicit match on `outcome`:

| `outcome` | Title key | Hub message key | Accent |
|-----------|-----------|-----------------|--------|
| `died` | `RESULTS_TITLE_DIED` | `RESULTS_HUB_DIED` | death |
| `escaped` | `RESULTS_TITLE_ESCAPED` / `RESULTS_TITLE_OATH` if `story_completed` | `RESULTS_HUB_ESCAPED` | success |
| `waves_complete` | `RESULTS_TITLE_WAVES_WIN` | `RESULTS_HUB_WAVES_WIN` | success |
| `waves_failed` | `RESULTS_TITLE_WAVES_FAIL` | `RESULTS_HUB_WAVES_FAIL` | failure |
| unknown / empty | `RESULTS_TITLE_UNKNOWN` | `RESULTS_HUB_UNKNOWN` | neutral |

XP / loot / rules rows stay data-driven from the dictionary. Add a visible `Button "ContinueButton"` that shares the accept handler and gets `grab_focus()` in `_ready` (ROC-01, ROC-02, ROC-03).

Rejected alternative: inferring success from `loot_kept`. Waves failure already sets `loot_kept: false`, but death also does — title and hub copy still need the outcome id.

### Overlay cadence
- Boss intro and epilogue register with `MenuStack` (or a lightweight `CinematicOverlay` that pauses processable gameplay nodes) so the world freezes for the card (ROC-04).
- Boss intro: `ui_accept` / `interact` / click skips to fade-out (ROC-05).
- `AchievementService` keeps a FIFO queue of display names; only one toast exists at a time (ROC-06). Toast goes through `GameUISkin.apply_modal_menu` or a dedicated toast style (ROC-10).

### Loading
Align with the loading redesign in [`title_main_continue.md`](title_main_continue.md): minimum total display, real progress, cancel before `execute_boot` (ROC-07). This topic owns the outcome-side acceptance that boot failure still returns to the main menu with a carried reason.

### Waves XP honesty
`complete_waves_run` must store `levels_gained` from the `grant_xp` result dictionary, same as escape/death (ROC-09). Epilogue text moves to content (`content/story/epilogue.json` or biome entry `epilogueText`) (ROC-11).

## Work plan
1. **Outcome match + Continue button** on `results_screen.gd` / `.tscn` (ROC-01, ROC-02, ROC-03).
2. **Waves `levels_gained` from `grant_xp`** in `run_flow.gd` (ROC-09) — small producer fix required for honest UI.
3. **Toast queue + skin** (ROC-06, ROC-10).
4. **Pause + skip for boss intro and epilogue** (ROC-04, ROC-05).
5. **Epilogue content data** (ROC-11).
6. **Localization sweep** for results / toast / intro / epilogue / loading (ROC-08).
7. **Loading progress** shared with entry-flow work (ROC-07).

## Data and schema changes
- `translations/strings.csv`: `RESULTS_*`, `TOAST_ACHIEVEMENT`, `EPILOGUE_*`, `BOSS_INTRO_*`, loading keys.
- Optional `content/story/epilogue.json` or field on dungeon/biome definitions; schema under `content/schemas/` if added.
- No save-format change.

## Acceptance criteria
- [ ] Completing a waves run shows a waves-specific victory title and hub message.
- [ ] Failing a waves run shows a failure title; accept returns with a failure hub message that does **not** say `"Run complete!"`.
- [ ] Death and escape titles/messages remain distinct from waves.
- [ ] Results screen focuses a Continue button on open.
- [ ] Two achievements unlocked in the same frame show sequentially, not overlapping.
- [ ] Boss intro can be skipped with accept; epilogue / intro pause gameplay while visible.
- [ ] Waves completion that grants a level shows `" — Level up!"` when `levels_gained > 0`.

## Validation
- Extend `flow_suite.gd` `_test_results_screen`: assert script contains `"waves_failed"` and `"waves_complete"` branches (or a shared outcome table).
- New validation: instantiate results with each of the four outcome dicts and assert title / hint / that accept would call `return_to_hub` with the matching message (mock or string table check).
- Manual: die in waves; confirm results do not read as a win.

## Related
- Existing: [`../existing_codebase/ui/run_outcome.md`](../existing_codebase/ui/run_outcome.md)
- [`run_flow_ui.md`](run_flow_ui.md) · [`run_portals.md`](run_portals.md) · [`title_main_continue.md`](title_main_continue.md) · [`waves_hud.md`](waves_hud.md)
- Game loop rollup: [`../../existing_codebase/00-GAME-LOOP.md`](../../existing_codebase/00-GAME-LOOP.md)
