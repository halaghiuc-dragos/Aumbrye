# Content Schema Guide

Content definitions live under `content/` and are validated in CI.

## Layout

| Path | Purpose |
|------|---------|
| `content/schemas/` | JSON Schema files |
| `content/fixtures/` | Minimal valid examples for CI |
| `content/biomes/` | Biome definitions (M5+) |
| `content/enemies/` | Enemy definitions (M1+) |
| `content/items/` | Item definitions (M2+) |

## Versioning

- Every document includes `"schemaVersion": <int>`.
- Breaking changes increment the version and require migration notes.

## Validation

```bash
cd scripts/validate-content
npm install
npm run validate
```

## Current schemas (M0)

| Schema | File | Fixture |
|--------|------|---------|
| DungeonDefinition v1 | `content/schemas/dungeon-definition.v1.json` | `content/fixtures/dungeon_definition_v1_minimal.json` |

Full contract reference: [docs/plan/05-DATA-CONTRACTS.md](plan/05-DATA-CONTRACTS.md).
