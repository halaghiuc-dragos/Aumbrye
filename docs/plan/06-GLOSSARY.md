# Glossary

| Term | Meaning |
|------|---------|
| Affix | Procedural modifier rolled onto an item instance |
| Biome / Theme | Visual+mechanical dungeon set (e.g. Forgotten Castle) |
| Boss phase | Discrete boss behavior graph segment (HP threshold or trigger) |
| Budget | Numeric allowance for threat/loot during generation |
| CharacterState | Permanent player progress document |
| Corridor | Edge connecting rooms in dungeon graph |
| DungeonBuilder | Godot system that instantiates a `DungeonDefinition` |
| DungeonDefinition | Server-authored complete runnable dungeon payload |
| Hub | Persistent handcrafted town / safe zone |
| Hyperarmor | Attack frames that resist poise break |
| i-frames | Invulnerability frames during dodge/roll |
| Lock-on | Camera/combat target sticky focus |
| Poise | Resistance to stagger |
| Posture / Guard | Block resource while guarding |
| Prefab / Room template | Hand-authored room scene referenced by `templateId` |
| Procgen | Procedural generation (server-side only in production) |
| Relic | Run-based or equipment power item |
| Run | Single dungeon attempt from enter to escape/death |
| RunResult | Client submission of run outcome for server validation |
| Secret | Optional room/edge with hidden access |
| Softlock | State where player cannot progress; generators must prevent |
| Telegraph | Visible/audio cue before attack active frames |
| Tier | Dungeon difficulty band |
| Vertical slice | Smallest playable end-to-end experience (M2) |
| Threat | Numeric enemy difficulty contribution to budget |
