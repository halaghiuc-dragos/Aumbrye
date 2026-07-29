# System: Dungeon Runtime

## Major milestones

| Major | Title | Phase |
|-------|-------|-------|
| DUNGEON-2 | Handcrafted slice | M2 |
| BUILDER-2 | Definition → scenes | M2 |
| DUNGEON-3 | Generated runs playable | M3 |
| DUNGEON-6 | Five-biome runtime polish | M6 |

## Minor milestones

| ID | Title | Phase |
|----|-------|-------|
| ART-2.1 | Castle room kit blockout | M2 |
| DUNGEON-2.1 | Hand-authored layout | M2 |
| DUNGEON-2.2 | Fixture definition mirror | M2 |
| BUILDER-2.1 | DungeonBuilder | M2 |
| TRAP-2.1 | Spike + falling traps | M2 |
| FLOW-2.1 | Escape + results | M2 |
| FLOW-3.1 | Play generated castle E2E | M3 |
| FLOW-4.1 | Death/escape economy | M4 |

## Runtime responsibilities

- Instance rooms by `templateId`
- Spawn placements (enemies, loot, puzzles, traps)
- Stream/load adjacent rooms (PERF)
- Track run flags (boss defeated, secrets found)

## Agent rules

- Builder consumes only `DungeonDefinition` (+ content ids).
- Do not procedurally invent rooms on client.
