# Coding Standards

Short rules for Aumbrye implementation. Full locks live in [docs/plan/01-LOCKED-DECISIONS.md](plan/01-LOCKED-DECISIONS.md).

## General

- Prefer ≤300 lines per file, ≤40 lines per function.
- Composition over inheritance.
- No magic numbers — use named constants or data files.
- One feature → one folder.
- Data-driven enemies, items, biomes, dialogue.

## Rule 1 — Extend, do not replace

**If something works, do not change it — only extend it.**

This applies to **all** systems: gameplay, UI, API, CI, content pipelines, tooling, docs, and anything else that is verified working. Do not refactor, rebind, or rewrite working behavior to add unrelated features.

**Allowed:** add new files, nodes, endpoints, schemas, methods, or bindings that build on what exists.

**Not allowed without explicit user request or a reported bug:** modify behavior that already passes acceptance criteria or user playtest.

When you must touch a working file, make the smallest possible diff and preserve existing behavior.

Full wording also in [00-AGENT-README.md](plan/00-AGENT-README.md#rule-1--extend-do-not-replace). Log non-trivial changes in `docs/design/`.

## Fluid gameplay (feel)

**Small interaction details are not polish — they are core design.** The game must feel responsive and fluid, not clunky.

Prioritize:

- **Simultaneous actions:** move while attacking; move while blocking; neither walk nor attacks cancel the other unless a milestone explicitly requires it.
- **Tap inputs over holds** where the design calls for commitment windows (e.g. tap Q → parry window → timed block, not hold Q).
- **Immediate feedback:** debug visuals (F2 hitboxes), HUD, hitstop, and telegraphs must visibly work when toggled.
- **Iterate in small steps:** when feel is wrong, adjust constants and state timing — do not rip out working systems.

Document feel changes in `docs/design/M1_IMPLEMENTATION_LOG.md` (or the relevant design log).

## Godot (GDScript)

- GDScript only in `apps/game/client/`.
- Gameplay systems do not import UI implementation details; UI listens to signals/state.
- Texture filter: Nearest for pixel textures.

## Backend (C#)

- Layering: Api → Application → Domain; Infrastructure implements persistence.
- Procedural generation lives in `packages/procedural` only.
- Versioned REST under `/api/v1`.

## Content

- Source of truth: `content/**/*.json` validated by JSON Schema in CI.
- Every top-level document includes `schemaVersion`.

## Authority

See [ADR-0001](ADR/0001-client-server-authority.md).

## M1 combat

**Authoritative controls (permanently locked — M1 closed 2026-07-29):** [design/M1_CONTROLS.md](design/M1_CONTROLS.md)

Do not rebind or change lock-on / dodge / guard movement behavior without explicit user request (`DEC-G07`–`DEC-G10` in [plan/01-LOCKED-DECISIONS.md](plan/01-LOCKED-DECISIONS.md)).

Implementation log: [design/M1_IMPLEMENTATION_LOG.md](design/M1_IMPLEMENTATION_LOG.md)
