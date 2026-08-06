# ADR-0001: Client / Server Authority

## Status

Accepted (M0), amended 2026-08

## Context

Aumbrye is a single-player action roguelite with online persistence. We need clear boundaries between what the Godot client may decide locally and what the ASP.NET Core API must own to prevent cheating and content drift.

## Decision

1. **Backend owns (when online):** run records, dungeon definition storage, loot instance validation, affix rolls for server-granted loot, permanent progress writes, coarse run-result sanity checks.
2. **Godot client owns:** input, rendering, local prediction of movement/combat feel, presentation of dungeon layouts.
3. **Dungeon generation (current EA reality):** `RunFlow.USE_ONLINE_PROCgen` defaults to `false`. The client generates floors locally via `LocalProcgen` / GDScript `DungeonProcgen`. The C# `packages/procedural` library is authoritative for **backend** runs and parity tests; GDScript procgen is authoritative for **offline play**.
4. **When online procgen is enabled:** the client requests `CreateRun` / `GetDungeon` from the API and does not invent layout or loot rolls for that run.
5. **Combat** remains client-authoritative in EA; the API applies coarse validation on `CompleteRun` (outcome, elapsed time, boss flag, loot instance IDs against the stored definition).

## Consequences

- Two procgen paths exist until online procgen is the default: GDScript (client) and C# (server). `cross_stack_parity_suite` guards shared content contracts; layout algorithms may differ.
- Godot instantiates rooms via `DungeonBuilder` from whichever definition source is active.
- Run completion submits a `RunResult`; the API validates loot claims and outcome before applying rewards.
- Full deterministic combat simulation on the server is **out of EA scope**.

## References

- [ARCHITECTURE.md](../ARCHITECTURE.md) — sections 4 (dungeon assembly) and 9 (backend / web)
- [REFACTOR_OPTIMISE_BUGFIX.md](../../REFACTOR_OPTIMISE_BUGFIX.md) — `REF-02` tracks collapsing the two
  procgen implementations
- Code anchors: `apps/game/client/scripts/app/run_flow.gd` (`USE_ONLINE_PROCgen`),
  `packages/procedural/Generation/DungeonGenerator.cs`,
  `apps/game/client/scripts/validation/suites/cross_stack_parity_suite.gd`

> Verified 2026-08-06: `USE_ONLINE_PROCgen := false` (`run_flow.gd:29`), both generators present, and
> `cross_stack_parity_suite.gd` asserts seed-mix, kind-spec and biome-catalog parity only — not full
> layout equivalence, exactly as the Consequences section states.
