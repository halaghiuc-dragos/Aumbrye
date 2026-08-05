# Content Schema Guide

Content definitions live under `content/` and are validated in CI.

## Layout

| Path | Purpose |
|------|---------|
| `content/schemas/` | JSON Schema files |
| `content/fixtures/` | Minimal valid examples for CI |
| `content/biomes/` | Biome definitions — room templates, enemy pools, loot budgets |
| `content/enemies/` | Enemy definitions (stats, scene, threat cost) — single source of truth |
| `content/bosses/` | Boss enemy definitions (same schema as enemies) |
| `content/items/` | Item definitions by category (M2+) |
| `content/items/equipment/` | Equippable items (weapons, armor) — reference `content/weapons/` via `weaponId` |
| `content/items/consumables/` | Potions, buffs, and other status-altering items |
| `content/items/materials/` | Crafting materials and relics |
| `content/items/catalog.json` | Index of all item IDs by category (validated against category folders) |
| `content/weapons/` | Combat stats for equippable weapons (referenced by equipment items) |

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
| EnemyDefinition v1 | `content/schemas/enemy-definition.v1.json` | `content/enemies/training_grunt.json`, `content/enemies/castle_*.json`, `content/bosses/boss_castle_knight.json` |
| BiomeDefinition v1 | `content/schemas/biome-definition.v1.json` | `content/biomes/forgotten_castle.json` |
| WeaponDefinition v1 | `content/schemas/weapon-definition.v1.json` | `content/weapons/sword_basic.json` |
| ItemInstance v1 (M2) | `content/schemas/item-instance.v1.json` | `content/items/{equipment,consumables,materials}/*.json` |
| RelicDefinition v1 | `content/schemas/relic-definition.v1.json` | `content/relics/*.json` |
| ItemCatalog v1 | `content/schemas/item-catalog.v1.json` | `content/items/catalog.json` |
| Inventory v1 (M2) | `content/schemas/inventory.v1.json` | `content/fixtures/inventory_sample.v1.json` |

M2 inventory/items: [plan/phases/M2-VERTICAL-SLICE.md](plan/phases/M2-VERTICAL-SLICE.md)

## Enemy centralization

All enemies are defined once under `content/enemies/` and `content/bosses/`. Every run references enemies by `enemyId` only; stats and Godot scenes resolve at runtime.

| Layer | Source |
| ----- | ------ |
| Stats, scene path, threat cost | `content/enemies/*.json`, `content/bosses/*.json` |
| Spawn pool weights | `content/biomes/<biome>.json` → `enemyPool`, `bossPool` |
| Server procgen | `EnemyCatalog` + `BiomeCatalog` (C#) |
| Godot client | `EnemyCatalog` (GDScript class) + `dungeon_builder.gd` |

Dungeon placements carry `enemyId` only. HP bars are shown above all enemies via `EnemyHealthBar`.

## Item resolution

Item IDs are stable across saves, procgen, fixtures, and the Godot client. Loaders resolve by ID, not flat path:

- **Godot:** `ItemCatalog.get_definition(item_id)` scans `content/items/{equipment,consumables,materials}/`
- **C# procgen:** `ItemCatalog.GetLootValue(item_id)` reads the same JSON files
- **Weapons:** equipment items set `weaponId` to reference `content/weapons/<id>.json` for combat stats (no duplication of attack data)
- **Catalog index:** `content/items/catalog.json` lists all IDs by category; CI checks it matches the category folders

Full contract reference: [docs/plan/05-DATA-CONTRACTS.md](plan/05-DATA-CONTRACTS.md).

## Items vs relics

Both use the same **item pipeline** at runtime; relics are a specialized material type:

| Kind | Schema | Location | Runtime |
|------|--------|----------|---------|
| Equipment / consumable / material | `item-instance.v1.json` | `content/items/{equipment,consumables,materials}/` | `ItemCatalog.get_definition()` |
| Run relic (meta unlock) | `relic-definition.v1.json` | `content/relics/*.json` | `RelicCatalog.get_definition()` |
| Relic crafting material | `item-instance.v1.json` with `itemType: "material"` and optional `runRelicId` | `content/items/materials/*.json` | Grants relic unlock when consumed |

Materials with `runRelicId` bridge loot drops to relic unlocks. Relic JSON holds passive effects; item materials reference them by ID. CI validates both schemas independently; `cross_stack_parity_suite` guards shared content paths.
