# Castle room kit (ART-2.1)

Modular blockout templates for the Forgotten Castle vertical slice.

| Scene | `template_id` | Size (W×D) | Doors |
|-------|---------------|------------|-------|
| `castle_entrance.tscn` | `castle_entrance` | 16×12 | S |
| `castle_stairs.tscn` | `castle_stairs` | 8×16 | N, S |
| `castle_courtyard.tscn` | `castle_courtyard` | 20×20 | N, E, S, W (secret) |
| `castle_hall.tscn` | `castle_hall` | 16×16 | W, E, S (shortcut) |
| `castle_treasure.tscn` | `castle_treasure` | 10×10 | N |
| `castle_secret.tscn` | `castle_secret` | 8×8 | E |
| `castle_arena.tscn` | `castle_arena` | 24×24 | W, S |
| `castle_boss.tscn` | `castle_boss` | 28×28 | N |

Socket convention: `DoorwaySocket` markers (N/E/S/W). See `scripts/dungeon/doorway_socket.gd`.

Playable layout (editor fixture only, not on live play path): `scenes/dungeon/forgotten_castle_slice.tscn`. Production runs load `scenes/dungeon/castle_run.tscn` with procgen definitions; the slice fixture JSON is the default for `DungeonBuilder.build()` validation.
