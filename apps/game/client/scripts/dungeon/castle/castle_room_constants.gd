class_name CastleRoomConstants

## Shared blockout dimensions for Forgotten Castle room kit (ART-2.1).

const GRID_UNIT := 4.0
const DOOR_WIDTH := 3.0
const DOOR_HEIGHT := 3.0
const WALL_HEIGHT := 4.0
const WALL_THICKNESS := 0.5
const FLOOR_THICKNESS := 0.5

enum Direction { NORTH, EAST, SOUTH, WEST }

const SOCKET_NAMES := {
	Direction.NORTH: "Socket_N",
	Direction.EAST: "Socket_E",
	Direction.SOUTH: "Socket_S",
	Direction.WEST: "Socket_W",
}
