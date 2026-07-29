# Coding Standards

Short rules for Aumbrye implementation. Full locks live in [docs/plan/01-LOCKED-DECISIONS.md](plan/01-LOCKED-DECISIONS.md).

## General

- Prefer ≤300 lines per file, ≤40 lines per function.
- Composition over inheritance.
- No magic numbers — use named constants or data files.
- One feature → one folder.
- Data-driven enemies, items, biomes, dialogue.

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
