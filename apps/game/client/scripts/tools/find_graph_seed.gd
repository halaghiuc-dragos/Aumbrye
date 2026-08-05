extends SceneTree

## Diagnostic: print whether a seed generates without fallback.
##   godot --path . --headless --script res://scripts/tools/find_graph_seed.gd [seed]

const RoomGraphGeneratorScript := preload("res://scripts/dungeon/procgen/room_graph_generator.gd")
const RoomGraphConfigScript := preload("res://scripts/dungeon/procgen/room_graph_config.gd")
const ProcgenBiomeLoaderScript := preload("res://scripts/dungeon/procgen/procgen_biome_loader.gd")


func _initialize() -> void:
	var seed := 42001
	var args := OS.get_cmdline_args()
	for arg in args:
		if arg.is_valid_int():
			seed = int(arg)
			break
	var biome := ProcgenBiomeLoaderScript.load("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var graph := RoomGraphGeneratorScript._try_generate_once(config, rng)
	if graph == null:
		print("seed %d FAIL: %s" % [seed, RoomGraphGeneratorScript._last_validate_reason])
	else:
		print(
			"seed %d OK main=%d" % [seed, RoomGraphGeneratorScript._count_main_slots(graph)]
		)
	quit()
