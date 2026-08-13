# Roadmap — server-authoritative runs

Status: **planned**. `RunFlow.USE_ONLINE_PROCgen` is hardcoded `false` and the client generates and
self-reports everything (kills, boss flags, loot ids).

## Why this matters

Leaderboards and the weekly challenge are competitive surfaces. Today the backend accepts a
completion constrained only by loot-id membership and elapsed-time bounds, so a modified client can
report whatever it likes. Offline play must stay first-class, so the goal is not "always online" —
it is *knowing which runs were verified* and labelling them honestly.

## Prerequisites — landed

These were blockers and are now in place:

- Loot instance ids accumulate across every floor a run generates, so claims on floors 2+ validate.
- Floor indices are clamped and bounded to a lookahead window, so a client cannot walk the floor
  parameter to burn CPU or flood the cache.
- Completion is atomic and idempotent: a guarded status flip claims the run, and a retried POST
  replays the cached result instead of granting progression twice.
- The client sends the completed `floor` in the payload.
- Ranked time is the validated client-reported elapsed, bounded by the server wall clock.
- `generatorCapabilities` declares what a definition's generator actually produced
  (see [ADR 0002](ADR/0002-procgen-authority-split.md)).

## Milestone plan

### 1. Definition download per floor

`RunFlow._resolve_floor_definition` fetches `GET /runs/{id}/dungeon?floor=N` when online, caches it
locally per floor, and falls back to local procgen when the request fails.

On fallback, compare the local definition's checksum against the server's and log the mismatch as
telemetry. That gives a real number for parity drift in the wild before anything depends on it.

### 2. Generator provenance on the run record

Add `GeneratorKind` (`server` | `local`) to `Run`, set at creation. Combined with the existing
`DefinitionChecksum`, this is what makes a run auditable after the fact.

### 3. Leaderboard eligibility

`LeaderboardService.SubmitFromRunAsync` accepts a run only when
`run.DefinitionChecksum != null && run.GeneratorKind == Server`. Everything else is recorded but not
ranked.

### 4. Client-side labelling

Show a "ranked" badge only for eligible runs, and say plainly in the run summary when a run was
generated locally. Offline players keep full progression, loot and achievements; they simply do not
appear on competitive boards. This has to be visible *before* the run starts, not discovered at the
results screen.

### 5. Reconnection and refunds

Decide and implement what happens when the network drops mid-run:

- The run stays `Active` server-side; the client keeps playing on its cached definitions.
- On reconnect, completion replays through the existing cloud outbox.
- If the run can no longer be verified (definitions were regenerated locally), it downgrades to
  unranked rather than being rejected — losing an hour of play to a dropped connection is worse
  than an unranked entry.

## Not in scope

Full server-side simulation. The server verifies *inputs and outcomes against the definition it
issued*; it does not re-simulate combat. That is a much larger project and is not what leaderboard
integrity requires at this stage.
