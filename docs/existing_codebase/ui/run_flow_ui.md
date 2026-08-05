# Run flow UI — coordination

How hub portal menus, in-run stair / boss / epilogue overlays, the results screen, and `RunFlow` hand off to each other. Individual surfaces live in [`run_portals.md`](run_portals.md) and [`run_outcome.md`](run_outcome.md); this topic records the shared dictionary, scene graph, and the places where UI and flow disagree.

Authority for scene changes and result payloads: `apps/game/client/scripts/app/run_flow.gd` (autoload). Scene paths come from `RunSceneRouter` (`HUB_SCENE`, `CASTLE_RUN_SCENE`, `WAVES_RUN_SCENE`, `RESULTS_SCENE`).

## Scene graph of a run
```
hub.tscn
  interact near portal → CastleEntryMenu / UmbralWavesMenu / UmbralEndlessMenu
        │  signals (hub.gd:61-68, :275-310)
        ▼
  RunFlow.start_* / continue_*
        ├─ castle / endless → CASTLE_RUN_SCENE   (_enter_run :289-325)
        └─ waves            → WAVES_RUN_SCENE    (_start_waves_run :907-926)
                │
                ├─ stair_menu (castle only) → RunFlow.ascend_floor / descend_floor / retreat_to_hub
                ├─ boss_intro_ui on first boss room
                ├─ epilogue_card on final-floor castle boss kill
                ├─ complete_run_via_portal / on_player_died
                └─ complete_waves_run / on_waves_failed / quit_waves_run
                        │
                        ▼  (except quit_waves_run and retreat — those skip results)
                results_screen.tscn
                        │  ui_accept / interact
                        ▼
                RunFlow.return_to_hub(message) → hub.tscn
```

Front-end entry into the hub (title → main menu → loading → hub) is documented in [`title_main_continue.md`](title_main_continue.md). Loading is shared infrastructure; results return bypasses it.

## Who opens what
| UI | Opened by | Starts / ends |
|----|-----------|---------------|
| `CastleEntryMenu` | `hub.gd:130` on castle portal interact | `start_new_run`, `continue_castle_run`, `start_run_with_seed` |
| `UmbralWavesMenu` | `hub.gd:136` | `start_waves_run`, `continue_waves_run` |
| `UmbralEndlessMenu` | `hub.gd:133` | `start_endless_run`, `continue_endless_run` |
| `stair_menu` | `stair_lever.gd:48-50` via group | `ascend_floor`, `descend_floor`, `retreat_to_hub` |
| `boss_intro_ui` | `castle_run.gd:128-135` | display only |
| `epilogue_card` | `castle_run.gd:477-484` | display only; sets `story_completed` before show |
| `results_screen` | `RunFlow` `_goto_scene(RESULTS_SCENE)` | `return_to_hub` |
| `achievement_toast` | `AchievementService._show_toast` | display only |
| `loading_screen` | `main_menu.gd` after boot queue | `LocalSave.execute_boot` → hub |

## `last_run_results` contract
Written by `RunFlow` before changing to results. Shape from `RunLifecycle` for castle outcomes and inline dicts for waves:

| Key | Escape | Death | Waves complete | Waves failed |
|-----|--------|-------|----------------|--------------|
| `outcome` | `"escaped"` | `"died"` | `"waves_complete"` | `"waves_failed"` |
| `time_seconds` | yes | yes | yes | yes |
| `kills` | yes | yes | `WavesRunService.get_kill_count()` | same |
| `loot` | collected ids | collected ids | chosen reward ids | `[]` |
| `xp_gained` | from `grant_xp` | death fraction | from `grant_xp(500, "waves")` | `0` |
| `levels_gained` | from `grant_xp` | from `grant_xp` | **hardcoded `0`** | `0` |
| `loot_kept` | `true` | `false` | `true` | `false` |
| `rules_summary` | escape blurb | death blurb | waves keep blurb | waves fail blurb |

Mirrored to `root` meta `"run_results"` for the results scene (`run_flow.gd:386`, `:427`, `:970`, `:992`). Results UI reads the autoload first (`results_screen.gd:39-41`).

## Paths that skip results
| Path | Behavior |
|------|----------|
| `retreat_to_hub` | Saves active run, hub message `"Retreated to Aumbrye Tower..."`, no results (`run_flow.gd:491-509`) |
| `quit_waves_run` | Clears waves save, optional early-exit item transfer, `return_to_hub` directly (`:929-948`) |
| `abandon_active_run` | Strips run loot, clears active run, hub with abandon message (`:344-352`) |
| Bonfire death with checkpoint | `_bonfire_death_respawn` reloads castle scene — no results (`:395-402`, `:815-847`) |

## UI / flow disagreements (verified)
1. **Waves outcomes ignored by results** — `results_screen.gd` only branches on `"died"`; `"waves_failed"` and `"waves_complete"` share the success title and `"Run complete!"` hub message (`:44-50`, `:87-91`). Producer correctly sets the outcome strings (`run_flow.gd:957`, `:980`).
2. **Waves level-up never shown** — `complete_waves_run` sets `levels_gained: 0` after calling `grant_xp` (`:961-962`), so the results `" — Level up!"` suffix cannot fire for waves.
3. **Seed weapon gate** — portal New blocks empty weapons; seed start does not (`castle_entry_menu.gd:162-165` vs `:189-206`). Flow itself does not check weapons.
4. **Castle continue vs mode** — menu enables Continue for any continuable active run; `continue_castle_run` rejects non-castle modes only after the menu has closed (`run_flow.gd:106-109`).
5. **Mouse mode ownership** — portal menus, stair menu, inventory, pause, and results each set mouse mode independently; there is no single stack across the run lifecycle.

## Signals the UI can listen to
| Signal | Emitter | Typical consumer today |
|--------|---------|------------------------|
| `run_started` | `RunFlow` | none in UI scripts |
| `run_ended(results)` | `RunFlow` | `QuestService` (not UI) |
| `returned_to_hub(message)` | `RunFlow` | `hub.gd:78` → `_on_returned_to_hub` |
| `dungeon_run_requested` etc. | portal menus | `hub.gd` only |

No UI script connects to `run_started` or `run_ended` for presentation; results rely on the scene change + dictionary.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Portal → RunFlow → run scene | IMPLEMENTED | `hub.gd:275-310`; `run_flow.gd:_enter_run`, `_start_waves_run` |
| Escape / death → results → hub | IMPLEMENTED | `complete_run_via_portal`, `on_player_died`; `results_screen.gd:80-91` |
| Waves → results dictionary | IMPLEMENTED at producer | `complete_waves_run`, `on_waves_failed` |
| Waves → honest results UI | BROKEN | `results_screen.gd:42-50`, `:87-91` |
| Retreat / quit / abandon skip results | IMPLEMENTED by design | `run_flow.gd:344-352`, `:491-509`, `:929-948` |
| Shared menu / mouse stack across run UI | ABSENT | each script writes `Input.mouse_mode` |
| UI listening to `run_ended` for presentation | ABSENT | results use scene + static dict only |
| `levels_gained` for waves | FAKE | `run_flow.gd:961-962` |

## Related
- Improvement plan: [`../actual_improvements/ui/run_flow_ui.md`](../actual_improvements/ui/run_flow_ui.md)
- [`run_portals.md`](run_portals.md) · [`run_outcome.md`](run_outcome.md) · [`waves_hud.md`](waves_hud.md) · [`title_main_continue.md`](title_main_continue.md) · [`pause_menu.md`](pause_menu.md)
- [`../00-GAME-LOOP.md`](../00-GAME-LOOP.md) · [`../run-flow.md`](../run-flow.md) · [`../hub.md`](../hub.md) · [`../waves-run.md`](../waves-run.md)
