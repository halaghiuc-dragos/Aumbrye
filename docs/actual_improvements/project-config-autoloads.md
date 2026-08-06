# Project config and autoloads — improvement plan

## Status: FINISHED

## Current state

`apps/game/client/project.godot` declares 22 autoloads (including `InputRebindService`), 35 input actions, explicit display/MSAA settings, physics layers 1–8 named, Godot 4.7.0 pinned via `.godot-version`, and Romanian locale support. CI and release workflows read the pinned version. See [`../existing_codebase/project-config-autoloads.md`](../existing_codebase/project-config-autoloads.md).

## Gaps

| ID | Sev | Gap | Evidence | Status |
|----|-----|-----|----------|--------|
| CFG-01 | P0 | Engine version skew | `project.godot` vs workflows | **FINISHED** — `.godot-version` + CI/release read it |
| CFG-02 | P0 | No input rebinding | scripts | **FINISHED** — `InputRebindService` + settings Controls tab |
| CFG-03 | P1 | `talents` / `heal` gamepad collision | `project.godot` | **FINISHED** — heal on D-pad right (button 14) |
| CFG-04 | P1 | `lock_on` / `ui_accept` Enter collision | `project.godot` | **FINISHED** — Enter removed from lock_on |
| CFG-05 | P1 | zoom / ui D-pad collision | `project.godot` | **FINISHED** — zoom wheel-only defaults |
| CFG-06 | P1 | No explicit vsync / MSAA | `project.godot` | **FINISHED** — explicit display + rendering keys |
| CFG-07 | P2 | Partial autoload validation | `setup_suite.gd` | **FINISHED** — all 22 autoloads asserted |
| CFG-08 | P2 | Unnamed physics layers 5–32 | `project.godot` | **FINISHED** — layers 5–8 named |
| CFG-09 | P2 | `godot_mcp` enabled in repo | `project.godot` | **FINISHED** — plugin present but not enabled |
| CFG-10 | P2 | Single locale | translations | **FINISHED** — `ro` column + `LocaleSettings` |

## Target design

Implemented as specified in the original plan: pinned engine version, `InputRebindService` with context groups, explicit display settings, expanded autoload validation, and locale preference in save meta.

## Work plan

All ten steps completed. See git history and `setup_suite.gd` tests `setup.engine_version_pin`, `input.no_intra_group_conflicts`, `input.rebind_roundtrip`, `setup.autoloads`.

## Acceptance criteria

- [x] `apps/game/client/.godot-version` matches `config/features`
- [x] CI and release install pinned Godot version
- [x] No intra-group input conflicts (automated)
- [x] Explicit display / MSAA project settings
- [x] Physics layers 1–8 named
- [x] Rebind roundtrip (automated)
- [x] Conflict reporting (automated)
- [x] All autoloads validated
- [x] `godot_mcp` not enabled in committed project

## Validation

`setup_suite.gd` covers CFG-01 through CFG-09. Manual: physical gamepad default feel.

## Related

- Existing behavior: [`../existing_codebase/project-config-autoloads.md`](../existing_codebase/project-config-autoloads.md)
- [`ci-cd.md`](ci-cd.md)
- [`ui/settings.md`](ui/settings.md)
- [`accessibility.md`](accessibility.md)
