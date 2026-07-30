extends RefCounted
class_name BiomeRegistry

## Client-side biome → room scenes, materials, lighting, audio (M5).

const BIOME_CASTLE := "forgotten_castle"
const BIOME_CRYSTAL := "crystal_caverns"
const BIOME_SWAMP := "poison_swamp"

const ALL_BIOMES: Array[String] = [BIOME_CASTLE, BIOME_CRYSTAL, BIOME_SWAMP]

static func get_display_name(biome_id: String) -> String:
	match biome_id:
		BIOME_CRYSTAL:
			return "Crystal Caverns"
		BIOME_SWAMP:
			return "Poison Swamp"
		_:
			return "Forgotten Castle"


static func get_room_scenes(biome_id: String) -> Dictionary:
	match biome_id:
		BIOME_CRYSTAL:
			return _crystal_rooms()
		BIOME_SWAMP:
			return _swamp_rooms()
		_:
			return _castle_rooms()


static func get_floor_material(biome_id: String) -> Material:
	return load(_material_path(biome_id, "mat_floor.tres"))


static func get_wall_material(biome_id: String) -> Material:
	return load(_material_path(biome_id, "mat_wall.tres"))


static func get_lighting_profile(biome_id: String) -> Dictionary:
	match biome_id:
		BIOME_CRYSTAL:
			return {
				"ambient_color": Color(0.35, 0.5, 0.75),
				"ambient_energy": 0.55,
				"fog_enabled": true,
				"fog_color": Color(0.12, 0.2, 0.35),
				"fog_density": 0.02,
			}
		BIOME_SWAMP:
			return {
				"ambient_color": Color(0.25, 0.35, 0.2),
				"ambient_energy": 0.4,
				"fog_enabled": true,
				"fog_color": Color(0.1, 0.15, 0.08),
				"fog_density": 0.035,
			}
		_:
			return {
				"ambient_color": Color(0.45, 0.4, 0.5),
				"ambient_energy": 0.5,
				"fog_enabled": false,
				"fog_color": Color(0.2, 0.18, 0.22),
				"fog_density": 0.01,
			}


static func get_audio_profile_path(biome_id: String) -> String:
	return "content/audio_profiles/%s.json" % biome_id


static func resolve_biome_id(definition: Dictionary, fallback: String = BIOME_CASTLE) -> String:
	var biome_id: String = str(definition.get("biomeId", fallback))
	if biome_id == "":
		return fallback
	return biome_id


static func _material_path(biome_id: String, file_name: String) -> String:
	match biome_id:
		BIOME_CRYSTAL:
			return "res://assets/crystal/%s" % file_name
		BIOME_SWAMP:
			return "res://assets/swamp/%s" % file_name
		_:
			return "res://assets/castle/%s" % file_name


static func _castle_rooms() -> Dictionary:
	return {
		"castle_entrance": preload("res://scenes/rooms/castle/castle_entrance.tscn"),
		"castle_stairs": preload("res://scenes/rooms/castle/castle_stairs.tscn"),
		"castle_courtyard": preload("res://scenes/rooms/castle/castle_courtyard.tscn"),
		"castle_hall": preload("res://scenes/rooms/castle/castle_hall.tscn"),
		"castle_treasure": preload("res://scenes/rooms/castle/castle_treasure.tscn"),
		"castle_secret": preload("res://scenes/rooms/castle/castle_secret.tscn"),
		"castle_arena": preload("res://scenes/rooms/castle/castle_arena.tscn"),
		"castle_boss": preload("res://scenes/rooms/castle/castle_boss.tscn"),
	}


static func _crystal_rooms() -> Dictionary:
	return {
		"crystal_entrance": preload("res://scenes/rooms/crystal/crystal_entrance.tscn"),
		"crystal_stairs": preload("res://scenes/rooms/crystal/crystal_stairs.tscn"),
		"crystal_courtyard": preload("res://scenes/rooms/crystal/crystal_courtyard.tscn"),
		"crystal_hall": preload("res://scenes/rooms/crystal/crystal_hall.tscn"),
		"crystal_treasure": preload("res://scenes/rooms/crystal/crystal_treasure.tscn"),
		"crystal_secret": preload("res://scenes/rooms/crystal/crystal_secret.tscn"),
		"crystal_arena": preload("res://scenes/rooms/crystal/crystal_arena.tscn"),
		"crystal_boss": preload("res://scenes/rooms/crystal/crystal_boss.tscn"),
		"crystal_puzzle": preload("res://scenes/rooms/crystal/crystal_puzzle.tscn"),
	}


static func _swamp_rooms() -> Dictionary:
	return {
		"swamp_entrance": preload("res://scenes/rooms/swamp/swamp_entrance.tscn"),
		"swamp_stairs": preload("res://scenes/rooms/swamp/swamp_stairs.tscn"),
		"swamp_courtyard": preload("res://scenes/rooms/swamp/swamp_courtyard.tscn"),
		"swamp_hall": preload("res://scenes/rooms/swamp/swamp_hall.tscn"),
		"swamp_treasure": preload("res://scenes/rooms/swamp/swamp_treasure.tscn"),
		"swamp_secret": preload("res://scenes/rooms/swamp/swamp_secret.tscn"),
		"swamp_arena": preload("res://scenes/rooms/swamp/swamp_arena.tscn"),
		"swamp_boss": preload("res://scenes/rooms/swamp/swamp_boss.tscn"),
		"swamp_puzzle": preload("res://scenes/rooms/swamp/swamp_puzzle.tscn"),
	}
