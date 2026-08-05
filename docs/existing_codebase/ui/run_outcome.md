# Run outcome

Post-run and transitional UI: the results screen after escape / death / waves end, the boot loading gate into the hub, achievement unlock toasts, the final-floor epilogue card, and the boss name intro. Results and loading are full scenes; toast / epilogue / intro are overlays spawned by other systems.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/ui/results_screen.gd` | 92 lines; post-run summary |
| `apps/game/client/scenes/ui/results_screen.tscn` | authored panel + labels |
| `apps/game/client/scripts/ui/loading_screen.gd` | 63 lines; boot gate to hub |
| `apps/game/client/scenes/ui/loading_screen.tscn` | empty script host; UI built in code |
| `apps/game/client/scripts/ui/achievement_toast.gd` | 21 lines; fade toast |
| `apps/game/client/scenes/ui/achievement_toast.tscn` | top-center panel + label |
| `apps/game/client/scripts/ui/epilogue_card.gd` | 59 lines; no scene |
| `apps/game/client/scripts/ui/boss_intro_ui.gd` | 53 lines; no scene |
| `apps/game/client/scripts/app/run_flow.gd` | writes `last_run_results` and changes to results |
| `apps/game/client/scripts/app/run_lifecycle.gd` | `build_escape_results` / `build_death_results` |
| `apps/game/client/scripts/meta/achievement_service.gd` | instantiates the toast |
| `apps/game/client/scripts/dungeon/castle_run.gd` | owns epilogue + boss intro |

## Results screen

### Control tree (`results_screen.tscn`)
```
ResultsScreen (Control, FULL_RECT)
└── Panel (±250 × ±150)
    └── Margin (24) → VBox (sep 12)
        ├── Title
        ├── TimeLabel
        ├── KillsLabel
        ├── LootLabel
        ├── XpLabel          (also created at runtime if missing — _ensure_ui_nodes)
        ├── RulesLabel
        └── HintLabel        "Press Enter to return to Aumbrye Tower"
```

`_ready` skins the panel, then `_display_from_run_flow` (`:16-20`, `:38-77`). `process_mode = ALWAYS`.

### Outcomes `RunFlow` actually writes
| Source | `outcome` value | Evidence |
|--------|-----------------|----------|
| `complete_run_via_portal` | `"escaped"` | `run_lifecycle.gd:15` |
| `on_player_died` | `"died"` | `run_lifecycle.gd:36` |
| `complete_waves_run` | `"waves_complete"` | `run_flow.gd:956-966` |
| `on_waves_failed` | `"waves_failed"` | `run_flow.gd:979-988` |

Results are also mirrored to `root` meta `"run_results"` (`run_flow.gd:386`, `:427`, `:970`, `:992`). The screen reads `RunFlow.last_run_results`, falling back to that meta (`results_screen.gd:39-41`).

### What the UI branches on
`_display_from_run_flow` treats **only** `"died"` as special (`:44-50`, `:69-73`):

| `outcome` | Title | XP line | Accept → hub message |
|-----------|-------|---------|----------------------|
| `"died"` | `"{name} — Echo Returned"` | `XP gained: N (50% of M)` | `"Returned to Aumbrye Tower. Permanent XP saved."` |
| anything else (including `"escaped"`, `"waves_complete"`, `"waves_failed"`) | `"{name} — Oath Fulfilled"` if `story_completed`, else `"… — Run Complete"` | `XP gained: N` (+ `" — Level up!"` if `levels_gained > 0`) | `"Run complete! Your progress was saved."` |

So **`waves_failed` is presented as a successful run**: success title, no failure framing, and the hub toast claims progress was saved (`:46-50`, `:87-91`). That matches the P0 called out in [`../00-GAME-LOOP.md`](../00-GAME-LOOP.md).

Loot line respects `loot_kept` (`:64-67`). Rules text is whatever string `RunFlow` put in `rules_summary`. Empty results show `--` placeholders (`:51-56`).

Accept / interact (`:80-91`) always calls `RunFlow.return_to_hub` with one of the two messages above. No button focus; keyboard/gamepad only via `_unhandled_input`.

## Loading screen

Built in code (`:19-44`): full-rect dark `ColorRect`, centered panel 320×120, title `"Entering Aumbrye Tower"`, status label. `_run_boot` (`:47-62`):
1. Await `MIN_DISPLAY_SEC = 1.1`
2. `LocalSave.execute_boot()`
3. On failure: status message, await 1.2 s, `change_scene_to_file` main menu
4. On success: `"Opening the hub..."`, change to `hub.tscn`

Entered from `main_menu.gd` after new game / continue. Also documented under [`title_main_continue.md`](title_main_continue.md).

## Achievement toast

`AchievementService._show_toast` instantiates `achievement_toast.tscn`, adds it to `root`, and calls `show_achievement(display_name)` (`achievement_service.gd:110-114`). The toast sets `"Achievement: %s"`, fades in 0.3 s, holds 2.5 s, fades out 0.5 s, then `queue_free` (`:13-20`). No `GameUISkin`, no stacking / queue if multiple unlocks fire close together.

## Epilogue card

`castle_run.gd:109-112` creates one instance. On final-floor castle boss defeat (`:477-484`) it sets `story_completed` and awaits `show_epilogue(text)` with a hardcoded paragraph. The card builds a backdrop + 520×300 panel titled `"The Oath Fulfilled"`, fades in 0.5 s, and returns `tween.finished`. `ui_accept` / `interact` hides it immediately (`:53-58`) without killing the tween, so the await still completes when the fade finishes. Does not pause the tree. No dismiss button focus.

## Boss intro

Created alongside the epilogue (`castle_run.gd:109-110`). On first entry to `BOSS_ROOM_ID` (`:128-135`), `show_intro(boss_id)` reads `EnemyCatalog` for `title`/`name` and `loreText`, fades in 0.35 s, holds 2.2 s, fades out 0.45 s (`boss_intro_ui.gd:19-31`). No skip, no pause, no focus. Default boss id if placement missing: `"boss_castle_knight"` (`castle_run.gd:131`).

## Contracts
| Contract | Detail |
|----------|--------|
| Results dictionary keys | `outcome`, `time_seconds`, `kills`, `loot`, `xp_gained`, `xp_full_would_be`, `levels_gained`, `loot_kept`, `rules_summary` |
| Scene path | `RunSceneRouter.RESULTS_SCENE` → `res://scenes/ui/results_screen.tscn` |
| Hub return | `RunFlow.return_to_hub(message)` sets `last_hub_message` |
| Toast scene | `res://scenes/ui/achievement_toast.tscn` preloaded by `AchievementService` |
| Epilogue / intro lifetime | children of the castle run node; destroyed with the run scene |

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Escape / death results display | IMPLEMENTED for `"escaped"` / `"died"` | `results_screen.gd:44-76`; `run_lifecycle.gd:14-46` |
| Waves complete presentation | PARTIAL — uses generic success title; no waves-specific copy | `:46-50` vs `run_flow.gd:957` |
| Waves failed presentation | BROKEN — treated as success title + `"Run complete! Your progress was saved."` | `:46-50`, `:87-91`; outcome `"waves_failed"` at `run_flow.gd:980` |
| Results input | PARTIAL — accept works via actions; no focused Button | `:80-91` |
| Loading boot path | IMPLEMENTED | `loading_screen.gd:47-62` |
| Loading progress | PLACEHOLDER — three fixed strings, leading 1.1 s delay | `:7`, `:41`, `:52`, `:60` |
| Achievement toast | IMPLEMENTED as a one-shot fade | `achievement_toast.gd:13-20` |
| Toast stacking | ABSENT — concurrent unlocks overlap as sibling root children | `achievement_service.gd:110-114` |
| Epilogue on final castle boss | IMPLEMENTED | `castle_run.gd:477-484`; `epilogue_card.gd:17-23` |
| Epilogue copy | PLACEHOLDER — single hardcoded English paragraph | `castle_run.gd:482-483` |
| Boss intro | IMPLEMENTED auto-card | `boss_intro_ui.gd:19-31` |
| Boss intro skip | ABSENT | no input handler in `boss_intro_ui.gd` |
| Localization | ABSENT across all five surfaces | hardcoded strings in each file |
| Results `levels_gained` for waves | FAKE from producer — `complete_waves_run` always sets `levels_gained: 0` even after `grant_xp` | `run_flow.gd:961-962` |

## Related
- Improvement plan: [`../actual_improvements/ui/run_outcome.md`](../actual_improvements/ui/run_outcome.md)
- Coordination: [`run_flow_ui.md`](run_flow_ui.md) · [`run_portals.md`](run_portals.md) · [`title_main_continue.md`](title_main_continue.md) · [`waves_hud.md`](waves_hud.md)
- [`game_ui_skin.md`](game_ui_skin.md) · [`menu_shell.md`](menu_shell.md)
- [`../00-GAME-LOOP.md`](../00-GAME-LOOP.md) · [`../run-flow.md`](../run-flow.md) · [`../achievements-meta.md`](../achievements-meta.md) · [`../bosses.md`](../bosses.md)
