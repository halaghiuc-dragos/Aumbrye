# Waves run — improvement plan

## Current state

Umbral Waves is a complete alternate loop (lobby chests → 50 formula-driven waves → reward pick), but wave data is hardcoded in `WavesRunService`, milestone rolls can request `miniboss_castle_captain` which never spawns, and completion results hardcode `levels_gained: 0` after granting XP — the results screen never shows a level-up. Failure results omit `run_relics_lost`. See [`../existing_codebase/waves-run.md`](../existing_codebase/waves-run.md). Cross-cutting with RFL-03 / RFL-11.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| WAV-01 | P0 | `complete_waves_run` sets `levels_gained: 0` instead of `grant_xp(...).levels_gained` | `run_flow.gd:961-962`; `results_screen.gd:74-75` |
| WAV-02 | P1 | `on_waves_failed` omits `run_relics_lost`; schema drifts from death results | `run_flow.gd:979-988` vs `run_lifecycle.gd:44` |
| WAV-03 | P1 | Milestone rolls `miniboss_castle_captain` but `ENEMY_SCENES` has no entry — silent no-spawn | `waves_run_service.gd:295-296`; `waves_run.gd:5-12`, `:186-188` |
| WAV-04 | P2 | `prep_active` set when entering a milestone wave, but prep UI only after clear — continue restore can mis-set walls | `waves_run_service.gd:217-218`; `waves_run.gd:166` |
| WAV-05 | P2 | Results screen has no `waves_complete` / `waves_failed` titles | `results_screen.gd:44-50` |
| WAV-06 | P2 | Wave composition, chests, milestones are code consts — designers cannot author without a GDScript edit | `waves_run_service.gd:8-37`, `:280-297` |
| WAV-07 | P2 | Victory confirm allows 0 selected rewards (XP still granted) | `waves_run_ui.gd` reward confirm path |

## Target design

### Honest results (WAV-01, WAV-02, WAV-05)

Route waves outcomes through `RunLifecycle.build_results` (same as RFL-03 / RFL-11):

```gdscript
var xp_result := ProgressionService.grant_xp(WAVES_COMPLETION_XP, "waves")
last_run_results = RunLifecycle.build_results(
    RunLifecycle.OUTCOME_WAVES_COMPLETE,
    elapsed,
    WavesRunService.get_kill_count(),
    rewards.duplicate(),
    xp_result,
    WAVES_COMPLETION_XP,
    "Waves cleared: kept up to 3 chosen items.",
    {"run_relics_lost": false, "loot_kept": true}
)
```

Failure uses `OUTCOME_WAVES_FAILED` with `run_relics_lost` explicit (false unless waves ever shared `RunBuffs` — today relics are not used in waves; key still present). `results_screen` maps those outcomes to "Waves Cleared" / "Waves Failed".

### Milestone spawn map (WAV-03)

Add to `ENEMY_SCENES`:

```gdscript
"miniboss_castle_captain": preload("res://scenes/enemies/castle_knight.tscn"),
```

And call `set_catalog_id("miniboss_castle_captain")` when BOS-05 lands so 350 HP captain stats apply. Until then, map to knight scene **and** stop rolling the missing id, or only roll `boss_castle_knight`.

Chosen short-term: map the scene + catalog override; keeps milestone variety.

### Authored wave tables (WAV-06)

Best end state: `content/waves/umbral_waves.json` (or per-biome) with:

```json
{
  "id": "umbral_waves",
  "milestones": [5, 10, 20, 50],
  "count": { "base": 2, "per_half_wave": 1, "cap": 12, "milestone_bonus": 2 },
  "roster_unlocks": [{ "wave": 5, "ids": ["castle_knight"] }],
  "base_roster": ["castle_grunt", "castle_archer", "castle_shield", "castle_hound"],
  "milestone_bosses": ["boss_castle_knight", "miniboss_castle_captain"],
  "chests": [ ... ]
}
```

Schema under `content/schemas/waves-definition.v1.json`. Service loads once; formula becomes data. Rejected: keeping formula forever — untestable by content validators and invisible to designers.

Land JSON after honesty + spawn fixes so the loop is correct before the data move.

### Prep flag (WAV-04)

`prep_active` true only while the 5s countdown runs (`enter_prep` / `leave_prep`), never as a side effect of `advance_wave` into a milestone. Continue restore uses a separate `in_milestone_combat` if needed.

### Reward confirm (WAV-07)

Require at least one selected item when any waves-inventory item exists; allow empty only if inventory was empty. Copy: "Pick at least one reward" disable confirm otherwise.

## Work plan

1. **Honest waves results via `RunLifecycle.build_results`** — `run_flow.gd`, `run_lifecycle.gd`, `results_screen.gd`. Closes WAV-01, WAV-02, WAV-05. Align with RFL-03.
2. **Map `miniboss_castle_captain` in `ENEMY_SCENES` (+ catalog id when available)** — `waves_run.gd`. Closes WAV-03.
3. **Fix `prep_active` lifecycle** — `waves_run_service.gd`, `waves_run.gd`. Closes WAV-04.
4. **Reward confirm minimum selection** — `waves_run_ui.gd`. Closes WAV-07.
5. **Introduce `content/waves/*.json` + schema; service reads tables** — new content + `waves_run_service.gd`. Closes WAV-06.

## Data and schema changes

| Change | Detail |
|--------|--------|
| `content/waves/umbral_waves.json` | New; schema `waves-definition.v1.json` |
| Save | Waves save schema v1 unchanged unless chest/wave fields move; bump waves save version if snapshot keys change |
| Results | Runtime only; no `save_migrator` |

## Acceptance criteria

- [ ] Completing waves after crossing a level threshold shows "Level up!" and `levels_gained >= 1`. (WAV-01)
- [ ] Failed waves results dictionary contains `run_relics_lost`. (WAV-02)
- [ ] Every milestone wave 5/10/20/50 spawns one boss/miniboss instance (count enemies after spawn ≥ formula count). (WAV-03)
- [ ] Continuing mid-milestone-combat does not leave prep walls up. (WAV-04)
- [ ] Results titles distinguish waves complete vs failed. (WAV-05)
- [ ] Changing milestone list in JSON (after step 5) changes in-game prep pauses without editing GDScript. (WAV-06)
- [ ] Confirm disabled when inventory has items but selection is empty. (WAV-07)

## Validation

| Assertion id | Checks |
|--------------|--------|
| `wav.results.levels_honest` | Grant XP to near level-up, complete waves, assert `levels_gained >= 1` |
| `wav.results.failed_keys` | Fail waves, assert key set includes `run_relics_lost` |
| `wav.spawn.milestone_captain` | Seed that rolls captain, assert instance exists after `_start_wave` |
| `wav.prep.flag_only_during_countdown` | Advance into milestone combat, assert `prep_active == false` |
| `wav.content.schema` | Load JSON against schema; service returns same counts as fixture |

## Related

- Existing state: [`../existing_codebase/waves-run.md`](../existing_codebase/waves-run.md)
- [`run-flow.md`](run-flow.md) (RFL-03, RFL-11), [`ui/run_outcome.md`](ui/run_outcome.md), [`bosses.md`](bosses.md) (BOS-05)
