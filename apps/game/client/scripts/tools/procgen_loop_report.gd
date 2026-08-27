extends SceneTree


const RoomGraphGeneratorScript := preload("res://scripts/dungeon/procgen/room_graph_generator.gd")
const RoomGraphConfigScript := preload("res://scripts/dungeon/procgen/room_graph_config.gd")

const SeedHealthScript := preload("res://scripts/tools/procgen_seed_health.gd")

const BIOME_IDS: PackedStringArray = [
	"forgotten_castle",
	"crystal_caverns",
	"poison_swamp",
	"frozen_fortress",
	"dark_cathedral",
	"iron_vault",
	"prism_depths",
	"venom_mire",
	"glacial_hollow",
	"umbral_chapel",
]


func _initialize() -> void:
	var from := 1
	var count := 200
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) == "--from" and i + 1 < args.size():
			from = int(args[i + 1])
		elif str(args[i]) == "--count" and i + 1 < args.size():
			count = int(args[i + 1])
	print("Biome              Seeds  loopless  mean loops  mean detour  max detour")
	var total_loopless := 0
	for biome_id in BIOME_IDS:
		var biome := _fetch_biome(biome_id)
		var config := RoomGraphConfigScript.from_biome(biome)
		var loopless := 0
		var loop_total := 0
		var detour_total := 0
		var detour_max := 0
		for offset in count:
			var report := RoomGraphGeneratorScript.generate_reported(config, from + offset)
			if not report.ok or report.graph == null:
				continue
			var loops: Array = report.graph.loop_edges
			if loops.is_empty():
				loopless += 1
			loop_total += loops.size()
			for edge in loops:
				var detour := int(edge.get("detour", 0))
				detour_total += detour
				detour_max = maxi(detour_max, detour)
		total_loopless += loopless
		var mean_loops := float(loop_total) / maxf(1.0, float(count))
		var mean_detour := float(detour_total) / maxf(1.0, float(loop_total))
		print(
			"%-18s %5d %9d %11.2f %12.1f %11d"
			% [biome_id, count, loopless, mean_loops, mean_detour, detour_max]
		)
	print()
	print("loopless layouts overall: %d of %d" % [total_loopless, count * BIOME_IDS.size()])
	quit(0)


static func _fetch_biome(biome_id: String) -> Dictionary:
	return SeedHealthScript._fetch_biome(biome_id)
