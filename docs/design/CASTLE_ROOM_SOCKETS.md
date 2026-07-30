# Castle Room Doorway Sockets (ART-2.1)

Hand-authored Forgotten Castle rooms use a fixed doorway socket convention so `DungeonBuilder` can align rooms from `DungeonDefinition` transforms and edges.

## Coordinate system

- Room origin is the **center of the floor** at `y = 0`.
- **North** = −Z, **South** = +Z, **East** = +X, **West** = −X (Godot world axes).
- Rooms connect when opposing sockets share the same world position (builder aligns `templateId` instances).

## Socket nodes

Each room scene contains `DoorwaySockets/` child markers using `DoorwaySocket` (`doorway_socket.gd`).

| Property | Rule |
|----------|------|
| Node name | `Socket_N`, `Socket_E`, `Socket_S`, `Socket_W` (or custom `socket_id`) |
| Position | Center of doorway on room edge, `y = 0` |
| Forward (−Z) | Points **outward** from the room (connection normal) |
| Width / height | `3 m` × `3 m` (`CastleRoomConstants.DOOR_WIDTH` / `DOOR_HEIGHT`) |
| Grid snap | Room width/depth are multiples of `4 m` (`GRID_UNIT`) |

### Edge placement

For room size `W × D` (playable interior):

| Direction | Local position |
|-----------|----------------|
| North | `(0, 0, −D/2)` |
| South | `(0, 0, D/2)` |
| East | `(W/2, 0, 0)` |
| West | `(−W/2, 0, 0)` |

South/East sockets rotate `180°` / `−90°` on Y so forward faces outward.

## Template IDs

Scene file → `template_id` on `RoomTemplate`:

| Scene | `template_id` | Type |
|-------|---------------|------|
| `castle_entrance.tscn` | `castle_entrance` | hub |
| `castle_stairs.tscn` | `castle_stairs` | corridor |
| `castle_courtyard.tscn` | `castle_courtyard` | combat |
| `castle_hall.tscn` | `castle_hall` | combat |
| `castle_treasure.tscn` | `castle_treasure` | treasure |
| `castle_secret.tscn` | `castle_secret` | secret |
| `castle_arena.tscn` | `castle_arena` | combat |
| `castle_boss.tscn` | `castle_boss` | boss |

Fixture `templateId` values must match these ids (see `content/fixtures/forgotten_castle_slice.json` in DUNGEON-2.2).

## Navigation bounds

Each room includes a `NavigationRegion3D` (built by `CastleBlockout`) covering the playable floor inset by `0.5 m` from walls. AI and future streaming use this region.

## Adjacent room placement

When hand-placing rooms, offset room B so:

```
B.position = A.position + (A.half_extent + B.half_extent) along the shared axis
```

Example: A south + B north on Z → `B.z = A.z + A.depth/2 + B.depth/2`.
