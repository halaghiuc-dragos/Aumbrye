extends RefCounted
class_name BiomeRegistry

## Client-side biome → room scenes, materials, lighting, audio (M5 + M7 expansion).

const BIOME_CASTLE := "forgotten_castle"
const BIOME_CRYSTAL := "crystal_caverns"
const BIOME_SWAMP := "poison_swamp"
const BIOME_FROZEN := "frozen_fortress"
const BIOME_CATHEDRAL := "dark_cathedral"
const BIOME_VAULT := "iron_vault"
const BIOME_PRISM := "prism_depths"
const BIOME_MIRE := "venom_mire"
const BIOME_HOLLOW := "glacial_hollow"
const BIOME_UMBRAL := "umbral_chapel"

const ALL_BIOMES: Array[String] = [
	BIOME_CASTLE, BIOME_CRYSTAL, BIOME_SWAMP, BIOME_FROZEN, BIOME_CATHEDRAL,
	BIOME_VAULT, BIOME_PRISM, BIOME_MIRE, BIOME_HOLLOW, BIOME_UMBRAL,
]


static func get_display_name(biome_id: String) -> String:
	match biome_id:
		BIOME_CRYSTAL:
			return "Crystal Caverns"
		BIOME_SWAMP:
			return "Poison Swamp"
		BIOME_FROZEN:
			return "Frozen Fortress"
		BIOME_CATHEDRAL:
			return "Dark Cathedral"
		BIOME_VAULT:
			return "Iron Vault"
		BIOME_PRISM:
			return "Prism Depths"
		BIOME_MIRE:
			return "Venom Mire"
		BIOME_HOLLOW:
			return "Glacial Hollow"
		BIOME_UMBRAL:
			return "Umbral Chapel"
		_:
			return "Forgotten Castle"


static func get_room_scenes(biome_id: String) -> Dictionary:
	match biome_id:
		BIOME_CRYSTAL:
			return _crystal_rooms()
		BIOME_SWAMP:
			return _swamp_rooms()
		BIOME_FROZEN:
			return _frozen_rooms()
		BIOME_CATHEDRAL:
			return _cathedral_rooms()
		BIOME_VAULT:
			return _vault_rooms()
		BIOME_PRISM:
			return _prism_rooms()
		BIOME_MIRE:
			return _mire_rooms()
		BIOME_HOLLOW:
			return _hollow_rooms()
		BIOME_UMBRAL:
			return _umbral_rooms()
		_:
			return _castle_rooms()


static func get_floor_material(biome_id: String) -> Material:
	return load(_material_path(biome_id, "mat_floor.tres"))


static func get_wall_material(biome_id: String) -> Material:
	return load(_material_path(biome_id, "mat_wall.tres"))


static func get_accent_material(biome_id: String) -> Material:
	return load(_material_path(biome_id, "mat_accent.tres"))


static func biome_from_template_id(template_id: String) -> String:
	var prefix := template_id.get_slice("_", 0)
	match prefix:
		"crystal":
			return BIOME_CRYSTAL
		"swamp":
			return BIOME_SWAMP
		"frozen":
			return BIOME_FROZEN
		"cathedral":
			return BIOME_CATHEDRAL
		"vault":
			return BIOME_VAULT
		"prism":
			return BIOME_PRISM
		"mire":
			return BIOME_MIRE
		"hollow":
			return BIOME_HOLLOW
		"umbral":
			return BIOME_UMBRAL
		_:
			return BIOME_CASTLE


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
		BIOME_FROZEN:
			return {
				"ambient_color": Color(0.5, 0.6, 0.75),
				"ambient_energy": 0.6,
				"fog_enabled": true,
				"fog_color": Color(0.7, 0.8, 0.9),
				"fog_density": 0.025,
			}
		BIOME_CATHEDRAL:
			return {
				"ambient_color": Color(0.2, 0.15, 0.28),
				"ambient_energy": 0.35,
				"fog_enabled": true,
				"fog_color": Color(0.08, 0.05, 0.12),
				"fog_density": 0.02,
			}
		BIOME_VAULT:
			return {
				"ambient_color": Color(0.4, 0.35, 0.32),
				"ambient_energy": 0.45,
				"fog_enabled": true,
				"fog_color": Color(0.12, 0.1, 0.08),
				"fog_density": 0.018,
			}
		BIOME_PRISM:
			return {
				"ambient_color": Color(0.42, 0.58, 0.82),
				"ambient_energy": 0.58,
				"fog_enabled": true,
				"fog_color": Color(0.15, 0.25, 0.42),
				"fog_density": 0.022,
			}
		BIOME_MIRE:
			return {
				"ambient_color": Color(0.28, 0.42, 0.22),
				"ambient_energy": 0.42,
				"fog_enabled": true,
				"fog_color": Color(0.08, 0.18, 0.06),
				"fog_density": 0.038,
			}
		BIOME_HOLLOW:
			return {
				"ambient_color": Color(0.58, 0.68, 0.82),
				"ambient_energy": 0.62,
				"fog_enabled": true,
				"fog_color": Color(0.75, 0.85, 0.95),
				"fog_density": 0.028,
			}
		BIOME_UMBRAL:
			return {
				"ambient_color": Color(0.18, 0.12, 0.26),
				"ambient_energy": 0.34,
				"fog_enabled": true,
				"fog_color": Color(0.06, 0.04, 0.1),
				"fog_density": 0.024,
			}
		_:
			return {
				"ambient_color": Color(0.45, 0.4, 0.5),
				"ambient_energy": 0.5,
				"fog_enabled": false,
				"fog_color": Color(0.2, 0.18, 0.22),
				"fog_density": 0.01,
			}


static func apply_run_presentation(parent: Node3D, biome_id: String, run_mode: String = "") -> WorldEnvironment:
	var lighting := get_lighting_profile(biome_id)
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = lighting.get("ambient_color", Color(0.4, 0.4, 0.45))
	environment.ambient_light_energy = lighting.get("ambient_energy", 0.5)
	environment.fog_enabled = bool(lighting.get("fog_enabled", false))
	environment.fog_light_color = lighting.get("fog_color", Color(0.2, 0.2, 0.25))
	environment.fog_density = lighting.get("fog_density", 0.01)

	var needs_arena_boost := run_mode == RunModeConfig.MODE_WAVES or run_mode == RunModeConfig.MODE_ENDLESS
	if needs_arena_boost:
		environment.background_color = Color(0.12, 0.1, 0.18)
		environment.ambient_light_color = Color(0.48, 0.42, 0.62)
		environment.ambient_light_energy = maxf(float(environment.ambient_light_energy), 0.72)
		environment.fog_enabled = false
	else:
		var ambient: Color = environment.ambient_light_color
		environment.background_color = ambient.lerp(Color(0.12, 0.11, 0.16), 0.55)

	PixelDioramaSettings.configure_environment(environment)
	env_node.environment = environment
	parent.add_child(env_node)

	var sun := parent.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun and needs_arena_boost:
		sun.light_energy = 1.35
		sun.light_color = Color(0.95, 0.92, 1.0)
		sun.shadow_enabled = true

	if needs_arena_boost and parent.get_node_or_null("ArenaFillLight") == null:
		var fill := OmniLight3D.new()
		fill.name = "ArenaFillLight"
		fill.light_color = Color(0.72, 0.68, 0.9)
		fill.light_energy = 0.55
		fill.omni_range = 28.0
		fill.position = Vector3(0, 10, 0)
		parent.add_child(fill)

	AudioDirector.set_biome(biome_id)
	return env_node


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
		BIOME_FROZEN:
			return "res://assets/frozen/%s" % file_name
		BIOME_CATHEDRAL:
			return "res://assets/cathedral/%s" % file_name
		BIOME_VAULT:
			return "res://assets/vault/%s" % file_name
		BIOME_PRISM:
			return "res://assets/prism/%s" % file_name
		BIOME_MIRE:
			return "res://assets/mire/%s" % file_name
		BIOME_HOLLOW:
			return "res://assets/hollow/%s" % file_name
		BIOME_UMBRAL:
			return "res://assets/umbral/%s" % file_name
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
		"castle_puzzle": preload("res://scenes/rooms/castle/castle_puzzle.tscn"),
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


static func _frozen_rooms() -> Dictionary:
	return {
		"frozen_entrance": preload("res://scenes/rooms/frozen/frozen_entrance.tscn"),
		"frozen_stairs": preload("res://scenes/rooms/frozen/frozen_stairs.tscn"),
		"frozen_courtyard": preload("res://scenes/rooms/frozen/frozen_courtyard.tscn"),
		"frozen_hall": preload("res://scenes/rooms/frozen/frozen_hall.tscn"),
		"frozen_treasure": preload("res://scenes/rooms/frozen/frozen_treasure.tscn"),
		"frozen_secret": preload("res://scenes/rooms/frozen/frozen_secret.tscn"),
		"frozen_arena": preload("res://scenes/rooms/frozen/frozen_arena.tscn"),
		"frozen_boss": preload("res://scenes/rooms/frozen/frozen_boss.tscn"),
		"frozen_puzzle": preload("res://scenes/rooms/frozen/frozen_puzzle.tscn"),
	}


static func _cathedral_rooms() -> Dictionary:
	return {
		"cathedral_entrance": preload("res://scenes/rooms/cathedral/cathedral_entrance.tscn"),
		"cathedral_stairs": preload("res://scenes/rooms/cathedral/cathedral_stairs.tscn"),
		"cathedral_courtyard": preload("res://scenes/rooms/cathedral/cathedral_courtyard.tscn"),
		"cathedral_hall": preload("res://scenes/rooms/cathedral/cathedral_hall.tscn"),
		"cathedral_treasure": preload("res://scenes/rooms/cathedral/cathedral_treasure.tscn"),
		"cathedral_secret": preload("res://scenes/rooms/cathedral/cathedral_secret.tscn"),
		"cathedral_arena": preload("res://scenes/rooms/cathedral/cathedral_arena.tscn"),
		"cathedral_boss": preload("res://scenes/rooms/cathedral/cathedral_boss.tscn"),
		"cathedral_puzzle": preload("res://scenes/rooms/cathedral/cathedral_puzzle.tscn"),
	}


static func _vault_rooms() -> Dictionary:
	return {
		"vault_entrance": preload("res://scenes/rooms/vault/vault_entrance.tscn"),
		"vault_stairs": preload("res://scenes/rooms/vault/vault_stairs.tscn"),
		"vault_courtyard": preload("res://scenes/rooms/vault/vault_courtyard.tscn"),
		"vault_hall": preload("res://scenes/rooms/vault/vault_hall.tscn"),
		"vault_treasure": preload("res://scenes/rooms/vault/vault_treasure.tscn"),
		"vault_secret": preload("res://scenes/rooms/vault/vault_secret.tscn"),
		"vault_arena": preload("res://scenes/rooms/vault/vault_arena.tscn"),
		"vault_boss": preload("res://scenes/rooms/vault/vault_boss.tscn"),
		"vault_puzzle": preload("res://scenes/rooms/vault/vault_puzzle.tscn"),
	}


static func _prism_rooms() -> Dictionary:
	return {
		"prism_entrance": preload("res://scenes/rooms/prism/prism_entrance.tscn"),
		"prism_stairs": preload("res://scenes/rooms/prism/prism_stairs.tscn"),
		"prism_courtyard": preload("res://scenes/rooms/prism/prism_courtyard.tscn"),
		"prism_hall": preload("res://scenes/rooms/prism/prism_hall.tscn"),
		"prism_treasure": preload("res://scenes/rooms/prism/prism_treasure.tscn"),
		"prism_secret": preload("res://scenes/rooms/prism/prism_secret.tscn"),
		"prism_arena": preload("res://scenes/rooms/prism/prism_arena.tscn"),
		"prism_boss": preload("res://scenes/rooms/prism/prism_boss.tscn"),
		"prism_puzzle": preload("res://scenes/rooms/prism/prism_puzzle.tscn"),
	}


static func _mire_rooms() -> Dictionary:
	return {
		"mire_entrance": preload("res://scenes/rooms/mire/mire_entrance.tscn"),
		"mire_stairs": preload("res://scenes/rooms/mire/mire_stairs.tscn"),
		"mire_courtyard": preload("res://scenes/rooms/mire/mire_courtyard.tscn"),
		"mire_hall": preload("res://scenes/rooms/mire/mire_hall.tscn"),
		"mire_treasure": preload("res://scenes/rooms/mire/mire_treasure.tscn"),
		"mire_secret": preload("res://scenes/rooms/mire/mire_secret.tscn"),
		"mire_arena": preload("res://scenes/rooms/mire/mire_arena.tscn"),
		"mire_boss": preload("res://scenes/rooms/mire/mire_boss.tscn"),
		"mire_puzzle": preload("res://scenes/rooms/mire/mire_puzzle.tscn"),
	}


static func _hollow_rooms() -> Dictionary:
	return {
		"hollow_entrance": preload("res://scenes/rooms/hollow/hollow_entrance.tscn"),
		"hollow_stairs": preload("res://scenes/rooms/hollow/hollow_stairs.tscn"),
		"hollow_courtyard": preload("res://scenes/rooms/hollow/hollow_courtyard.tscn"),
		"hollow_hall": preload("res://scenes/rooms/hollow/hollow_hall.tscn"),
		"hollow_treasure": preload("res://scenes/rooms/hollow/hollow_treasure.tscn"),
		"hollow_secret": preload("res://scenes/rooms/hollow/hollow_secret.tscn"),
		"hollow_arena": preload("res://scenes/rooms/hollow/hollow_arena.tscn"),
		"hollow_boss": preload("res://scenes/rooms/hollow/hollow_boss.tscn"),
		"hollow_puzzle": preload("res://scenes/rooms/hollow/hollow_puzzle.tscn"),
	}


static func _umbral_rooms() -> Dictionary:
	return {
		"umbral_entrance": preload("res://scenes/rooms/umbral/umbral_entrance.tscn"),
		"umbral_stairs": preload("res://scenes/rooms/umbral/umbral_stairs.tscn"),
		"umbral_courtyard": preload("res://scenes/rooms/umbral/umbral_courtyard.tscn"),
		"umbral_hall": preload("res://scenes/rooms/umbral/umbral_hall.tscn"),
		"umbral_treasure": preload("res://scenes/rooms/umbral/umbral_treasure.tscn"),
		"umbral_secret": preload("res://scenes/rooms/umbral/umbral_secret.tscn"),
		"umbral_arena": preload("res://scenes/rooms/umbral/umbral_arena.tscn"),
		"umbral_boss": preload("res://scenes/rooms/umbral/umbral_boss.tscn"),
		"umbral_puzzle": preload("res://scenes/rooms/umbral/umbral_puzzle.tscn"),
	}
