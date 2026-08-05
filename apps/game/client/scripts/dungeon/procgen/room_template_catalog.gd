class_name RoomTemplateCatalog
extends RefCounted

## Room kit dimensions and doorway masks (mirrors C# RoomTemplateCatalog).

const KIND_SPECS := {
	"entrance": {"width": 16.0, "depth": 12.0, "doors": RoomGraphSlot.DOOR_SOUTH},
	"stairs": {"width": 8.0, "depth": 16.0, "doors": RoomGraphSlot.DOOR_NORTH | RoomGraphSlot.DOOR_SOUTH},
	"corridor": {"width": 8.0, "depth": 12.0, "doors": RoomGraphSlot.DOOR_NORTH | RoomGraphSlot.DOOR_SOUTH},
	"courtyard": {
		"width": 20.0,
		"depth": 20.0,
		"doors": RoomGraphSlot.DOOR_NORTH | RoomGraphSlot.DOOR_SOUTH | RoomGraphSlot.DOOR_EAST | RoomGraphSlot.DOOR_WEST,
	},
	"hall": {"width": 16.0, "depth": 16.0, "doors": RoomGraphSlot.DOOR_EAST | RoomGraphSlot.DOOR_SOUTH | RoomGraphSlot.DOOR_WEST},
	"treasure": {"width": 10.0, "depth": 10.0, "doors": RoomGraphSlot.DOOR_NORTH},
	"secret": {"width": 8.0, "depth": 8.0, "doors": RoomGraphSlot.DOOR_EAST},
	"arena": {"width": 24.0, "depth": 24.0, "doors": RoomGraphSlot.DOOR_SOUTH | RoomGraphSlot.DOOR_WEST},
	"boss": {"width": 28.0, "depth": 28.0, "doors": RoomGraphSlot.DOOR_NORTH},
	"puzzle": {"width": 14.0, "depth": 14.0, "doors": RoomGraphSlot.DOOR_NORTH | RoomGraphSlot.DOOR_SOUTH},
}

const FALLBACK_KINDS := ["courtyard", "hall", "arena"]


static func template_prefix_for_biome(biome_id: String) -> String:
	match biome_id:
		"crystal_caverns": return "crystal"
		"poison_swamp": return "swamp"
		"frozen_fortress": return "frozen"
		"dark_cathedral": return "cathedral"
		"iron_vault": return "vault"
		"prism_depths": return "prism"
		"venom_mire": return "mire"
		"glacial_hollow": return "hollow"
		"umbral_chapel": return "umbral"
		_: return "castle"


static func kind_from_template_id(template_id: String) -> String:
	var parts := template_id.split("_", false, 1)
	if parts.size() < 2:
		return template_id
	return parts[1]


static func get_spec(template_id: String) -> Dictionary:
	var kind := kind_from_template_id(template_id)
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
	}


static func has_door(template_id: String, door_mask: int) -> bool:
	return (get_spec(template_id)["doors"] & door_mask) != 0


static func supports_doors(template_id: String, required_doors: int) -> bool:
	return (get_spec(template_id)["doors"] & required_doors) == required_doors


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


static func _yaw_to_align(from_door: int, to_door: int) -> float:
	return yaw_to_align_doors(from_door, to_door)


static func _door_yaw(door: int) -> float:
	if door == RoomGraphSlot.DOOR_NORTH:
		return 0.0
	if door == RoomGraphSlot.DOOR_EAST:
		return PI / 2.0
	if door == RoomGraphSlot.DOOR_SOUTH:
		return PI
	if door == RoomGraphSlot.DOOR_WEST:
		return -PI / 2.0
	return 0.0


static func pick_template_for_doors(
	preferred_template_id: String,
	required_doors: int,
	biome_templates: Array = []
) -> String:
	if supports_doors(preferred_template_id, required_doors):
		return preferred_template_id
	for template_id in biome_templates:
		if supports_doors(str(template_id), required_doors):
			return str(template_id)
	var prefix := template_prefix_for_biome("forgotten_castle")
	if not biome_templates.is_empty():
		prefix = str(biome_templates[0]).split("_", false)[0]
	for kind in FALLBACK_KINDS:
		var candidate := "%s_%s" % [prefix, kind]
		if supports_doors(candidate, required_doors):
			return candidate
	for kind in FALLBACK_KINDS:
		var castle_candidate := "castle_%s" % kind
		if supports_doors(castle_candidate, required_doors):
			return castle_candidate
	return "%s_courtyard" % prefix
