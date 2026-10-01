# Castle room kit

One scene per room kind, each a `CastleRoomScene` with a `CastleBlockout` and a `DoorwaySocket` marker
on every wall (N/E/S/W, see `scripts/dungeon/doorway_socket.gd`). Every scene ships with all four door
flags off: a generated floor opens only the doorways its graph asks for.

A room's size and the doors its kind allows come from `KIND_SPECS` in
`scripts/dungeon/procgen/room_template_catalog.gd`, not from the scene:

| Scene | Kind | Size (W×D) | Doors the kind allows |
|-------|------|------------|-----------------------|
| `castle_entrance.tscn` | `entrance` | 16×12 | all |
| `castle_stairs.tscn` | `stairs` | 8×16 | all |
| `castle_corridor.tscn` | `corridor` | 8×12 | N, S |
| `castle_corridor_long.tscn` | `corridor_long` | 8×20 | N, S |
| `castle_corridor_bend.tscn` | `corridor_bend` | 12×12 | N, E |
| `castle_balcony.tscn` | `balcony` | 16×20 | N, S |
| `castle_courtyard.tscn` | `courtyard` | 20×20 | all |
| `castle_hall.tscn` | `hall` | 16×16 | all |
| `castle_treasure.tscn` | `treasure` | 12×12 | N |
| `castle_secret.tscn` | `secret` | 8×8 | E |
| `castle_arena.tscn` | `arena` | 24×24 | N, S, W |
| `castle_boss.tscn` | `boss` | 28×28 | N |
| `castle_puzzle.tscn` | `puzzle` | 16×16 | all |

Stair ramps and secret cue panels are placed by code (`castle_room_scene.gd`) from Blender models, so
the scenes hold empty `StairRamp` and `SecretCuePanel` nodes.

`scenes/dungeon/forgotten_castle_slice.tscn` is an editor fixture driven by
`content/fixtures/forgotten_castle_slice.json`; the diagnostics use it. Production runs load
`scenes/dungeon/castle_run.tscn` with a generated definition.
