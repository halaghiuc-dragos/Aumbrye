# Debug arenas — improvement plan

## Current state

The hub training arena works as a sandbox: six authored dummies, procedural diorama, local death reset, hub return, and a useful F1–F3 overlay. Spawn constants in `combat_arena.gd` drift from the `.tscn`, the overlay tracks only one dummy HP, and satellite scenes (`empty_world`, `shadow_probe`, `mcp_validation.gd` alias) are weakly documented or unused. See [`../existing_codebase/debug-arenas.md`](../existing_codebase/debug-arenas.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| DBG-01 | P2 | `DUMMY_SPAWNS` unused — dummies only in `.tscn`; const can drift | `combat_arena.gd:5-12`; positions in `combat_arena.tscn` |
| DBG-02 | P2 | Overlay `enemy_path` shows one grunt HP while six dummies exist | `debug_overlay.gd:85-88`; `combat_arena.tscn` |
| DBG-03 | P2 | `empty_world.tscn` has no script and no references — purpose unclear | scene file; grep under `apps/game/client` empty |
| DBG-04 | P2 | `shadow_probe` not registered in validation suites; env-only | `shadow_probe.gd`; suites omit it |
| DBG-05 | P2 | Dual validation entry: `mcp_validation.gd` alias vs scene using `validation_runner.gd` | `mcp_validation.gd`; `mcp_validation.tscn:4` |
| DBG-06 | P2 | `go_to_arena` sets no run lifecycle flags — intentional, but no explicit "sandbox mode" marker for systems that assume a run | `run_flow.gd:328-329` |

## Target design

### Single source for dummy layout (DBG-01)

Chosen: spawn dummies from `DUMMY_SPAWNS` in `_ready` (clear any editor placeholders, or remove placeholder instances from the tscn and instantiate `training_grunt.tscn` in a loop). Scene keeps HubReturn / HUD / overlay only.

```gdscript
for pos in DUMMY_SPAWNS:
    var dummy := preload("res://scenes/enemies/training_grunt.tscn").instantiate()
    dummy.position = pos
    add_child(dummy)
```

Rejected: deleting the const and trusting the tscn — breaks `debug_overlay` preload of spawn constants and invites silent drift.

### Overlay multi-dummy readout (DBG-02)

Show aggregate "Dummies alive: N/6" (already partially counted) and optional focused target: locked-on enemy if any, else nearest dummy, else TrainingGruntA. Keep one detail HP line to avoid overlay spam.

### Scene inventory hygiene (DBG-03, DBG-04, DBG-05)

| Scene | Decision |
|-------|----------|
| `empty_world.tscn` | Delete, or add a one-line root script comment + README note "MCP/manual blank level" and reference from a tools doc — prefer **delete** if unused for 1+ release |
| `shadow_probe.tscn` | Add a validation suite assertion that loads the scene and checks shader compile / no error spam, or document under `tools-scripts` as manual-only |
| `mcp_validation.gd` | Point the `.tscn` script at the alias **or** delete the alias and keep `validation_runner.gd` only — one entry path |

### Sandbox mode flag (DBG-06)

`RunFlow.go_to_arena` sets `run_mode = "arena"` (or a bool `sandbox_active`) cleared on `return_to_hub`, so audio/UI/quest hooks can skip run assumptions without treating arena as a failed run. Do not write `activeRun`.

## Work plan

1. **Code-spawn dummies from `DUMMY_SPAWNS`; strip duplicate instances from tscn** — `combat_arena.gd` / `.tscn`. Closes DBG-01.
2. **Overlay focus target = lock-on or nearest dummy** — `debug_overlay.gd`. Closes DBG-02.
3. **Single validation entry path** — delete alias or retarget scene. Closes DBG-05.
4. **Resolve empty_world + shadow_probe** — delete or wire/document. Closes DBG-03, DBG-04.
5. **Sandbox marker on `go_to_arena`** — `run_flow.gd`. Closes DBG-06.

## Data and schema changes

None. No content JSON. No save migrator.

## Acceptance criteria

- [ ] Moving a value in `DUMMY_SPAWNS` moves the corresponding dummy after reload; tscn has zero authored grunt instances. (DBG-01)
- [ ] Locking onto dummy B shows B's HP in the overlay detail line. (DBG-02)
- [ ] Exactly one script path runs headless validation from `mcp_validation.tscn`. (DBG-05)
- [ ] `empty_world` either removed or referenced from a tools entry with a stated purpose. (DBG-03)
- [ ] `RunFlow` exposes an is-sandbox / arena query true only while combat_arena is loaded. (DBG-06)

## Validation

| Assertion id | Checks |
|--------------|--------|
| `arena.dummies.from_const` | After ready, dummy count == `DUMMY_SPAWNS.size()` and positions match |
| `arena.overlay.focus_lock` | Set lock-on to dummy, assert overlay HP equals that Health |
| `arena.validation.single_entry` | Scene script path equals the documented runner |
| `arena.sandbox.flag` | After `go_to_arena`, sandbox query true; after `return_to_hub`, false |

Existing `arena_suite.gd` already checks six dummies, hub return, walls, reset APIs — extend rather than replace.

## Related

- Existing state: [`../existing_codebase/debug-arenas.md`](../existing_codebase/debug-arenas.md)
- [`validation-harness.md`](validation-harness.md), [`validation-suites.md`](validation-suites.md), [`run-flow.md`](run-flow.md), [`tools-scripts.md`](tools-scripts.md)
