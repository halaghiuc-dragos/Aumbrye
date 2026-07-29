# ADR-0001: Client / Server Authority

## Status

Accepted (M0)

## Context

Aumbrye is a single-player action roguelite with online persistence. We need clear boundaries between what the Godot client may decide locally and what the ASP.NET Core API must own to prevent cheating and content drift.

## Decision

1. **Backend owns:** seeds, dungeon graphs, loot rolls, affixes, run validation, permanent progress writes.
2. **Godot client owns:** input, rendering, local prediction of movement/combat feel, presentation of server definitions.
3. **Client never invents** dungeon layout or loot in production builds.
4. **Offline/dev** may use a local API process running the same `packages/procedural` library.

## Consequences

- Dungeon generation code lives only in `packages/procedural`, consumed by the API.
- Godot receives a `DungeonDefinition` JSON payload and instantiates rooms via `DungeonBuilder` (M2+).
- Run completion submits a `RunResult`; the API validates against the stored definition before applying rewards.
- Full deterministic combat simulation on the server is **out of EA scope**; coarse validation only.

## References

- [docs/plan/01-LOCKED-DECISIONS.md](../plan/01-LOCKED-DECISIONS.md) — DEC-B07, DEC-B08
- [docs/plan/04-ARCHITECTURE.md](../plan/04-ARCHITECTURE.md)
