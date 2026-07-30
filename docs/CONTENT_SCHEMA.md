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

## Current schemas

| Schema | File | Example content |
|--------|------|-----------------|
| DungeonDefinition v1 | `content/schemas/dungeon-definition.v1.json` | `content/fixtures/dungeon_definition_v1_minimal.json`, `content/fixtures/forgotten_castle_slice.json` |
| EnemyDefinition v1 | `content/schemas/enemy-definition.v1.json` | `content/enemies/training_grunt.json`, `content/enemies/castle_*.json` |
| WeaponDefinition v1 | `content/schemas/weapon-definition.v1.json` | `content/weapons/sword_basic.json` |
| ItemInstance v1 (M2) | `content/schemas/item-instance.v1.json` | `content/items/*.json` |
| Inventory v1 (M2) | `content/schemas/inventory.v1.json` | `content/fixtures/inventory_sample.v1.json` |

M2 status: [design/M2_IMPLEMENTATION_LOG.md](design/M2_IMPLEMENTATION_LOG.md)

Full contract reference: [docs/plan/05-DATA-CONTRACTS.md](plan/05-DATA-CONTRACTS.md).
