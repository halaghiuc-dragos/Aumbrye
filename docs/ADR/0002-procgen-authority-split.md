# ADR 0002 — Procgen authority split between GDScript and C#

- Status: Accepted
- Date: 2026-08-12
- Supersedes: nothing
- Related: [ADR 0001 — client/server authority](0001-client-server-authority.md)

## Context

Two procedural dungeon generators exist:

- `apps/game/client/scripts/dungeon/procgen/` (GDScript) — runs in the game, drives what the player
  actually plays. It assigns room content, lock/key gating and puzzles on top of layout and
  placements.
- `packages/procedural/` (C#) — runs in the backend and the `procgen-cli`, used for server-issued
  definitions, checksums and CLI baselines. It emits `roomContent`, `locks` and `puzzles` as empty
  arrays.

Both write the same `dungeon-definition` schema, so nothing in the payload distinguished "this
generator does not assign room content" from "this floor genuinely has no room content". A
consumer reading a server-issued definition would therefore describe a different dungeon than the
client plays, and any future flip to server-authoritative runs would inherit that divergence
silently rather than failing loudly.

## Decision

**The C# generator is frozen to `layout` + `placements`.** It is a parity and verification path,
not a second gameplay generator. The GDScript generator remains authoritative for everything the
player experiences.

**The split is declared in the payload.** Every definition carries a `generatorCapabilities`
array naming the sections its generator populated:

| Generator | `generatorCapabilities` |
| --- | --- |
| C# (`packages/procedural`) | `["layout", "placements"]` |
| GDScript (client) | `["layout", "placements", "roomContent", "locks", "puzzles"]` |

Consumers must branch on this array rather than on emptiness. A client that receives a definition
without `roomContent` capability runs its own content pass over the server's layout; it must not
treat the missing sections as an authoritative "empty".

The constants live in `GeneratorCapability` (`packages/procedural/Models/DungeonDefinition.cs`).

## Consequences

- Server-issued definitions are usable today for layout and placements without pretending to be
  complete, which is what the online-run milestone actually needs first.
- The divergence is now a typed, inspectable field instead of tribal knowledge in a doc comment.
- The C# path stays cheap to maintain: porting ~900 lines of `room_content_assigner.gd` is not
  required for parity work, only for full server authority.
- Anything that compares the two generators must compare only the capabilities they share.

## The path to closing the gap

Full server-authoritative runs (see the roadmap in `docs/ROADMAP-online-runs.md`) require the C#
side to gain the remaining three capabilities:

1. Port `room_content_assigner.gd`, the room-graph lock/key logic and puzzle assignment into
   `packages/procedural/Assignment/` as pure functions of `(biome, graph, SeededRandom)`, reusing
   the SplitMix64 stream discipline so the two languages consume RNG identically.
2. Extend `ClientVersionParityTests` to run both generators across a fixed seed matrix and diff the
   canonical JSON field by field, restricted to shared capabilities.
3. Only once the C# capability set matches the GDScript one may `generatorCapabilities` be widened
   — and that widening is the signal that server-authoritative runs are viable.

Until then, treat any code that assumes the two generators agree on room content as a bug.
