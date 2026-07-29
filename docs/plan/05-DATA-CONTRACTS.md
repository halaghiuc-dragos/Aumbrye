# Data Contracts

> Single source of truth for cross-service payloads.
> Schema version bumps require migration notes in `docs/ADR/` or `content/CHANGELOG.md`.

---

## Versioning rules

- Every top-level document includes `"schemaVersion": int`.
- Breaking changes increment version; API rejects unsupported client versions.
- Godot and API must negotiate: `X-Content-Version` / `X-Client-Version` headers (introduced M3).

---

## Core documents

### DungeonDefinition

```json
{
  "schemaVersion": 1,
  "runId": "uuid",
  "seed": 123456789,
  "biomeId": "forgotten_castle",
  "tier": 1,
  "playerLevelSnapshot": 5,
  "rooms": [
    {
      "id": "r0",
      "templateId": "castle_hall_a",
      "type": "combat",
      "transform": { "x": 0, "y": 0, "z": 0, "yaw": 0 },
      "tags": []
    }
  ],
  "edges": [{ "from": "r0", "to": "r1", "kind": "corridor" }],
  "placements": {
    "enemies": [],
    "loot": [],
    "puzzles": [],
    "traps": [],
    "secrets": [],
    "boss": null,
    "exit": null,
    "entrance": "r0"
  },
  "budgets": { "enemyThreat": 100, "lootValue": 50 },
  "checksum": "optional-hash"
}
```

### ItemInstance

```json
{
  "schemaVersion": 1,
  "instanceId": "uuid",
  "itemDefId": "iron_sword",
  "rarity": "rare",
  "affixes": [{ "affixId": "flat_phys", "value": 12 }],
  "durability": 100,
  "bound": false,
  "rollSeed": 42
}
```

### CharacterState

```json
{
  "schemaVersion": 1,
  "accountId": "uuid",
  "level": 1,
  "xp": 0,
  "talents": {},
  "equipment": {},
  "inventory": { "width": 10, "height": 6, "cells": [] },
  "storage": { "width": 10, "height": 10, "cells": [] },
  "recipes": [],
  "flags": {},
  "currencies": { "gold": 0 }
}
```

### RunResult

```json
{
  "schemaVersion": 1,
  "runId": "uuid",
  "outcome": "escaped|died|abandoned",
  "elapsedSeconds": 600,
  "bossDefeated": true,
  "kills": {},
  "lootClaimedInstanceIds": [],
  "clientChecksum": "opaque"
}
```

### EnemyDefinition (content)

Required fields: `id`, `displayName`, `archetype`, `stats`, `damageType`, `behaviors` (patrol/chase/investigate/attack/retreat/idle params), `lootTableId`, `telegraphProfileId`.

### WeaponDefinition (content)

Required fields: `id`, `archetype`, `movesetId`, `staminaCosts`, `damage`, `poiseDamage`, `blockReduction`, `requirements`.

### BiomeDefinition (content)

Required fields: `id`, `roomTemplateIds`, `enemyPool`, `lootTables`, `lightingProfileId`, `audioProfileId`, `bossPool`, `puzzlePool`.

---

## Rarity enum

`common | magic | rare | epic | legendary | mythic`

## Equipment slots

`helmet | chest | gloves | boots | weapon | secondary | ring | amulet | relic`

## Damage types

`physical | fire | frost | poison | lightning | arcane`

## Status effects

`burn | bleed | poison | freeze | stun | curse`

---

## Contract milestones

| ID | Deliverable | Phase |
|----|-------------|-------|
| SCHEMA-0.1 | JSON Schema folder + CI validator stub | M0 |
| SCHEMA-0.2 | `DungeonDefinition` v1 frozen for fixtures | M0 |
| SCHEMA-2.1 | `ItemInstance` + inventory grid schema | M2 |
| SCHEMA-3.1 | OpenAPI published from API | M3 |
| SCHEMA-3.2 | Version headers enforced | M3 |
| SCHEMA-4.1 | `CharacterState` + talents schema | M4 |
| SCHEMA-4.2 | Affix definition schema | M4 |
| SCHEMA-7.1 | Save migration version matrix documented | M7 |

Detailed acceptance criteria live in phase files and [systems/00-SETUP-CI.md](systems/00-SETUP-CI.md).
