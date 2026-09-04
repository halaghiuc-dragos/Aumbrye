class_name RoomTemplateCatalog
extends RefCounted


const ALL_DOORS := (
	RoomGraphSlot.DOOR_NORTH
	| RoomGraphSlot.DOOR_EAST
	| RoomGraphSlot.DOOR_SOUTH
	| RoomGraphSlot.DOOR_WEST
)

const KIND_SPECS := {
	"entrance": {
		"width": 16.0,
		"depth": 12.0,
		"doors": ALL_DOORS,
		"anchors": {
			"enemy":
			[
				Vector3(4, 0, 2),
				Vector3(-4, 0, -2),
				Vector3(0, 0, 0),
				Vector3(3, 0, -3),
				Vector3(-3, 0, 3),
				Vector3(5, 0, 1),
			],
			"cover":
			[Vector3(-3, 0, -2), Vector3(3, 0, 2), Vector3(0, 0, -3), Vector3(-2, 0, 3)],
			"chest": [Vector3(5, 0, 4), Vector3(-5, 0, 4)],
			"trap": [Vector3(0, 0, 3)],
		},
	},
	"stairs": {
		"width": 8.0,
		"depth": 16.0,
		"doors": ALL_DOORS,
		"anchors": {
			"enemy":
			[
				Vector3(0, 0, 0),
				Vector3(2, 0, 4),
				Vector3(-2, 0, -4),
				Vector3(2, 0, -3),
				Vector3(-2, 0, 3),
				Vector3(0, 0, -5),
			],
			"cover":
			[Vector3(-2, 0, -2), Vector3(2, 0, 2), Vector3(0, 0, -4), Vector3(1, 0, 4)],
			"chest": [Vector3(0, 0, 5), Vector3(-2, 0, 4)],
		},
	},
	"corridor": {
		"width": 8.0,
		"depth": 12.0,
		"doors": RoomGraphSlot.DOOR_NORTH | RoomGraphSlot.DOOR_SOUTH,
		# RM-14: a corridor is compression, not a fight -- lower ceiling than a room, and its own
		# "enemy" anchor list is capped at two rather than the usual six.
		"wallHeight": 4.5,
		"anchors": {
			"enemy": [Vector3(0, 0, 0), Vector3(0, 0, 3)],
			"cover": [Vector3(-2, 0, -1), Vector3(2, 0, 1), Vector3(0, 0, -3), Vector3(1, 0, 2)],
			"chest": [Vector3(0, 0, 3), Vector3(-2, 0, 2)],
			"trap": [Vector3(0, 0, 3)],
		},
	},
	"corridor_long": {
		"width": 8.0,
		"depth": 20.0,
		"doors": RoomGraphSlot.DOOR_NORTH | RoomGraphSlot.DOOR_SOUTH,
		"wallHeight": 4.5,
		"anchors": {
			"enemy": [Vector3(0, 0, -4), Vector3(0, 0, 4)],
			"cover": [Vector3(-2, 0, -5), Vector3(2, 0, -1), Vector3(-2, 0, 3), Vector3(2, 0, 7)],
			"chest": [Vector3(0, 0, 8), Vector3(-2, 0, 6)],
			"trap": [Vector3(0, 0, 0)],
		},
	},
	"corridor_bend": {
		"width": 12.0,
		"depth": 12.0,
		"doors": RoomGraphSlot.DOOR_NORTH | RoomGraphSlot.DOOR_EAST,
		"wallHeight": 4.5,
		"anchors": {
			"enemy": [Vector3(1, 0, 1), Vector3(-1, 0, -1)],
			"cover": [Vector3(2, 0, -2), Vector3(-2, 0, 2), Vector3(3, 0, 1), Vector3(1, 0, 3)],
			"chest": [Vector3(3, 0, 3), Vector3(2, 0, 4)],
			"trap": [Vector3(0, 0, 0)],
		},
	},
	# RM-19: a balcony is a plain rectangular footprint (walls/doors unchanged) split into two
	# floor heights internally -- `shape: "split"` is what tells `CastleBlockout` to build it that
	# way. North/south only, like `corridor`: the split runs along Z (raised half north, lower half
	# south), and a door on the east/west wall would sit exactly on the seam between the two
	# heights, which the geometry has no sane answer for.
	"balcony": {
		"width": 16.0,
		"depth": 20.0,
		"shape": "split",
		"doors": RoomGraphSlot.DOOR_NORTH | RoomGraphSlot.DOOR_SOUTH,
		"anchors": {
			"enemy":
			[
				Vector3(0, 3, -6),
				Vector3(4, 3, -4),
				Vector3(0, 0, 6),
				Vector3(-4, 0, 4),
				Vector3(4, 0, 4),
				Vector3(0, 0, 2),
			],
			"cover": [Vector3(-3, 0, 3), Vector3(3, 0, 5), Vector3(0, 0, 7)],
			"chest": [Vector3(-4, 3, -6), Vector3(4, 0, 7)],
			"trap": [Vector3(0, 0, 4)],
		},
	},
	"courtyard": {
		"width": 20.0,
		"depth": 20.0,
		"shape": "octagon",
		"maxDoors": 3,
		"doors": ALL_DOORS,
		"anchors": {
			"enemy":
			[
				Vector3(6, 0, 4),
				Vector3(-6, 0, -5),
				Vector3(0, 0, 0),
				Vector3(7, 0, -4),
				Vector3(-5, 0, 6),
				Vector3(4, 0, -3),
			],
			"cover":
			[Vector3(-4, 0, -3), Vector3(4, 0, 3), Vector3(0, 0, -6), Vector3(-3, 0, 5)],
			"chest": [Vector3(8, 0, 7), Vector3(-8, 0, 7)],
			"trap": [Vector3(0, 0, 5)],
		},
	},
	"hall": {
		"width": 16.0,
		"depth": 16.0,
		"doors": ALL_DOORS,
		"anchors": {
			"enemy":
			[
				Vector3(5, 0, 3),
				Vector3(-5, 0, -4),
				Vector3(0, 0, 0),
				Vector3(4, 0, -3),
				Vector3(-4, 0, 4),
				Vector3(3, 0, -2),
			],
			"cover":
			[Vector3(-3, 0, -2), Vector3(3, 0, 2), Vector3(0, 0, -4), Vector3(-2, 0, 3)],
			# Pulled in from x=(-)6 -- the hall's dressing pass lines both side walls with sconces at
			# x=(-)7.5 and a pillar at x=(-)7.2, z=0, and the old anchor at (6, 5) sat close enough to
			# the sconce at (7.5, 4.5) for a chest to read as crowded against the wall fixture rather
			# than placed in the room.
			"chest": [Vector3(4.5, 0, 4), Vector3(-4.5, 0, 4)],
			"trap": [Vector3(0, 0, 4)],
		},
	},
	"treasure": {
		"width": 12.0,
		"depth": 12.0,
		"doors": RoomGraphSlot.DOOR_NORTH,
		"anchors": {
			"enemy":
			[
				Vector3(3, 0, 2),
				Vector3(-3, 0, -2),
				Vector3(0, 0, 0),
				Vector3(4, 0, -1),
				Vector3(-4, 0, 1),
				Vector3(2, 0, -2),
			],
			"cover": [Vector3(-3, 0, -1), Vector3(3, 0, 1), Vector3(0, 0, -3), Vector3(-2, 0, 2)],
			"chest": [Vector3(0, 0, 0), Vector3(3, 0, 2)],
			"trap": [Vector3(0, 0, 3)],
		},
	},
	"secret": {
		"width": 8.0,
		"depth": 8.0,
		"doors": RoomGraphSlot.DOOR_EAST,
		"anchors": {
			"enemy":
			[
				Vector3(0, 0, 0),
				Vector3(2, 0, 1),
				Vector3(-2, 0, -1),
				Vector3(1, 0, -2),
				Vector3(-1, 0, 2),
				Vector3(0, 0, 2),
			],
			"cover": [Vector3(-1, 0, -1), Vector3(1, 0, 1), Vector3(0, 0, -2), Vector3(-1, 0, 1)],
			"chest": [Vector3(0, 0, 0), Vector3(1, 0, 1)],
			"trap": [Vector3(0, 0, 1)],
		},
	},
	"arena": {
		"width": 24.0,
		"depth": 24.0,
		"shape": "round",
		"maxDoors": 3,
		"doors": RoomGraphSlot.DOOR_NORTH | RoomGraphSlot.DOOR_SOUTH | RoomGraphSlot.DOOR_WEST,
		"anchors": {
			"enemy":
			[
				Vector3(7, 0, 5),
				Vector3(-7, 0, -6),
				Vector3(0, 0, 0),
				Vector3(8, 0, -5),
				Vector3(-6, 0, 7),
				Vector3(5, 0, -4),
			],
			"cover":
			[Vector3(-5, 0, -4), Vector3(5, 0, 4), Vector3(0, 0, -7), Vector3(-4, 0, 6)],
			"chest": [Vector3(9, 0, 8), Vector3(-9, 0, 8)],
			"trap": [Vector3(0, 0, 6)],
		},
	},
	"boss": {
		"width": 28.0,
		"depth": 28.0,
		"shape": "round",
		"doors": RoomGraphSlot.DOOR_NORTH,
		"anchors": {
			"enemy":
			[
				Vector3(8, 0, 6),
				Vector3(-8, 0, -7),
				Vector3(0, 0, 0),
				Vector3(9, 0, -6),
				Vector3(-7, 0, 8),
				Vector3(6, 0, -5),
			],
			"cover":
			[Vector3(-6, 0, -5), Vector3(6, 0, 5), Vector3(0, 0, -8), Vector3(-5, 0, 7)],
			"chest": [Vector3(10, 0, 9), Vector3(-10, 0, 9)],
			"trap": [Vector3(0, 0, 7)],
		},
	},
	"puzzle": {
		"width": 16.0,
		"depth": 16.0,
		"doors": ALL_DOORS,
		"anchors": {
			"enemy":
			[
				Vector3(5, 0, 3),
				Vector3(-5, 0, -3),
				Vector3(0, 0, 0),
				Vector3(4, 0, -2),
				Vector3(-4, 0, 3),
				Vector3(3, 0, -1),
			],
			"cover": [Vector3(-3, 0, -2), Vector3(3, 0, 2), Vector3(0, 0, -4), Vector3(-2, 0, 3)],
			"chest": [Vector3(6, 0, 5), Vector3(-6, 0, 5)],
			"trap": [Vector3(0, 0, 4)],
		},
	},
}

const FALLBACK_KINDS := ["courtyard", "hall", "arena"]


static func template_prefix_for_biome(biome_id: String) -> String:
	var biome := BiomeRegistry.get_biome(biome_id)
	if biome.is_empty():
		return ""
	return str(biome.get("templatePrefix", ""))


static func kind_from_template_id(template_id: String) -> String:
	var parts := template_id.split("_", false, 1)
	if parts.size() < 2:
		return template_id
	return parts[1]


## `template_id` is usually `"<prefix>_<kind>"`, but `CastleBlockout._apply_kind_spec()` (via its
## own `kind` export) can call this with an already-bare kind instead -- and since RM-14/RM-19 a
## kind name can itself contain an underscore ("corridor_long", "corridor_bend"), re-running
## `kind_from_template_id()` on one of those corrupts it (`"corridor_long"` -> `"long"`, treating
## "corridor" as if it were a biome prefix). Checking `KIND_SPECS` directly first, before assuming
## the input still needs a prefix stripped, handles both callers correctly.
static func get_spec(template_id: String) -> Dictionary:
	var kind := template_id if KIND_SPECS.has(template_id) else kind_from_template_id(template_id)
	if not KIND_SPECS.has(kind):
		push_error("Unknown room template kind '%s' for '%s'" % [kind, template_id])
		return KIND_SPECS["courtyard"]
	var base: Dictionary = KIND_SPECS[kind]
	return {
		"width": base["width"],
		"depth": base["depth"],
		"doors": base["doors"],
		"half_width": float(base["width"]) * 0.5,
		"half_depth": float(base["depth"]) * 0.5,
		"shape": str(base.get("shape", "rect")),
		"max_doors": int(base.get("maxDoors", 4)),
		"wall_height": float(base.get("wallHeight", CastleRoomConstants.WALL_HEIGHT)),
	}


static func anchors_for(template_id: String, role: String) -> Array:
	var kind := kind_from_template_id(template_id)
	var base: Dictionary = KIND_SPECS.get(kind, KIND_SPECS["courtyard"])
	var anchors: Dictionary = base.get("anchors", {})
	var list: Array = anchors.get(role, [])
	if list.is_empty():
		return [Vector3.ZERO]
	return list


static func has_door(template_id: String, door_mask: int) -> bool:
	return (get_spec(template_id)["doors"] & door_mask) != 0


static func supports_doors(template_id: String, required_doors: int) -> bool:
	var doors := int(get_spec(template_id)["doors"])
	if (doors & required_doors) == required_doors:
		return true
	return primary_door_mask(doors) != 0 and primary_door_mask(required_doors) != 0


static func doors_for_step(dx: int, dz: int) -> Array:
	if dx == 0 and dz == -1:
		return [RoomGraphSlot.DOOR_NORTH, RoomGraphSlot.DOOR_SOUTH]
	if dx == 0 and dz == 1:
		return [RoomGraphSlot.DOOR_SOUTH, RoomGraphSlot.DOOR_NORTH]
	if dx == 1 and dz == 0:
		return [RoomGraphSlot.DOOR_EAST, RoomGraphSlot.DOOR_WEST]
	if dx == -1 and dz == 0:
		return [RoomGraphSlot.DOOR_WEST, RoomGraphSlot.DOOR_EAST]
	push_error("Invalid grid step (%d, %d)" % [dx, dz])
	return [0, 0]


static func primary_door_mask(doors: int) -> int:
	if doors == 0:
		return 0
	if (doors & (doors - 1)) == 0:
		return doors
	return 0


static func yaw_rad_for_incoming_door(template_id: String, incoming_door: int) -> float:
	if incoming_door == 0:
		return 0.0
	var doors: int = int(get_spec(template_id)["doors"])
	var primary: int = primary_door_mask(doors)
	if primary == 0:
		return 0.0
	return yaw_to_align_doors(primary, incoming_door)


static func yaw_rad_for_entrance(template_id: String, required_doors: int) -> float:
	var primary: int = primary_door_mask(int(get_spec(template_id)["doors"]))
	if primary == 0:
		return 0.0
	var required := first_set_door(required_doors)
	if required == 0:
		return 0.0
	return yaw_to_align_doors(primary, required)


static func first_set_door(mask: int) -> int:
	for door in [
		RoomGraphSlot.DOOR_NORTH,
		RoomGraphSlot.DOOR_EAST,
		RoomGraphSlot.DOOR_SOUTH,
		RoomGraphSlot.DOOR_WEST,
	]:
		if mask & door:
			return door
	return 0


static func yaw_to_align_doors(from_door: int, to_door: int) -> float:
	return _door_yaw(to_door) - _door_yaw(from_door)


static func half_extent_x(spec: Dictionary, yaw_rad: float) -> float:
	var hw: float = spec["half_width"]
	var hd: float = spec["half_depth"]
	return hw * absf(cos(yaw_rad)) + hd * absf(sin(yaw_rad))


static func half_extent_z(spec: Dictionary, yaw_rad: float) -> float:
	var hw: float = spec["half_width"]
	var hd: float = spec["half_depth"]
	return hw * absf(sin(yaw_rad)) + hd * absf(cos(yaw_rad))


## Where a doorway sits on a wall.
##
## `lateral` slides the door along that wall, which is what lets two rooms of different sizes share
## a doorway at all: the lattice places them flush and the door is cut wherever they actually
## overlap, rather than at each room's own centre.
static func socket_wall_position(
	direction: CastleRoomConstants.Direction,
	half_width: float,
	half_depth: float,
	lateral: float = 0.0
) -> Vector3:
	# North and south walls run along x, so the door slides in x; east and west run along z.
	match direction:
		CastleRoomConstants.Direction.NORTH:
			return Vector3(lateral, 0.0, -half_depth)
		CastleRoomConstants.Direction.SOUTH:
			return Vector3(lateral, 0.0, half_depth)
		CastleRoomConstants.Direction.EAST:
			return Vector3(half_width, 0.0, lateral)
		CastleRoomConstants.Direction.WEST:
			return Vector3(-half_width, 0.0, lateral)
	return Vector3.ZERO


## Yaw that rotates a room's local -Z (north) axis to face `door`'s world direction.
##
## Matches Godot's actual Y-rotation direction (verified: rotation.y=+PI/2 turns local -Z into
## world -X, i.e. west) -- EAST and WEST are not a mirror-symmetric ±PI/2 swap of each other in the
## naive sense, this is the sign Godot's basis actually produces.
static func _door_yaw(door: int) -> float:
	if door == RoomGraphSlot.DOOR_NORTH:
		return 0.0
	if door == RoomGraphSlot.DOOR_EAST:
		return -PI / 2.0
	if door == RoomGraphSlot.DOOR_SOUTH:
		return PI
	if door == RoomGraphSlot.DOOR_WEST:
		return PI / 2.0
	return 0.0


## Kinds that carry a floor-unique marker or prop (the stairs ramp and lever, the boss's authored
## geometry and exit portal) rather than plain room dressing. Handing one of these to an unrelated
## slot as a door-mask fallback plants its marker in a room that has no business having it -- a
## second "stairs" room the player can see, or a second boss arrangement in a combat encounter.
const KIND_SINGLE_USE := ["stairs", "boss"]

static func pick_template_for_doors(
	preferred_template_id: String,
	required_doors: int,
	biome_templates: Array = [],
	rng: RandomNumberGenerator = null,
	required_kind: String = ""
) -> String:
	var candidates: Array[String] = []
	if preferred_template_id != "" and supports_doors(preferred_template_id, required_doors):
		candidates.append(preferred_template_id)
	for template_id in biome_templates:
		var tid := str(template_id)
		if tid == preferred_template_id:
			continue
		var tid_kind := kind_from_template_id(tid)
		if tid_kind in KIND_SINGLE_USE and tid_kind != required_kind:
			continue
		if supports_doors(tid, required_doors):
			candidates.append(tid)
	if candidates.is_empty():
		var prefix := template_prefix_for_biome("forgotten_castle")
		if not biome_templates.is_empty():
			prefix = str(biome_templates[0]).split("_", false)[0]
		for fallback_kind in FALLBACK_KINDS:
			var candidate := "%s_%s" % [prefix, fallback_kind]
			if supports_doors(candidate, required_doors):
				candidates.append(candidate)
		for fallback_kind in FALLBACK_KINDS:
			var castle_candidate := "castle_%s" % fallback_kind
			if supports_doors(castle_candidate, required_doors):
				candidates.append(castle_candidate)
	if required_kind != "":
		var filtered: Array[String] = []
		for candidate in candidates:
			if kind_from_template_id(candidate) == required_kind:
				filtered.append(candidate)
		candidates = filtered
		if candidates.is_empty():
			return ""
	if candidates.is_empty():
		var fallback_prefix := template_prefix_for_biome("forgotten_castle")
		if not biome_templates.is_empty():
			fallback_prefix = str(biome_templates[0]).split("_", false)[0]
		return "%s_courtyard" % fallback_prefix
	if rng != null and candidates.size() > 1:
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	return candidates[0]
