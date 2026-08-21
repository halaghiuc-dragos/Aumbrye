extends Node

## Generates floors and reports how many pass `DungeonDefinitionValidator`, with the error mix.
##
## `procgen_seed_health.gd` covers Phase 1 — the room graph — and stops there. Everything the
## validator checks is Phase 2: footprints, placements, lock solvability. Nothing measured that,
## which is how `entrance_present` and a degrees-for-radians footprint bug both failed every floor
## of every biome without appearing in any sweep.
##
## Usage:
##   godot --headless --path apps/game/client res://scenes/debug/definition_health.tscn -- --seeds=200

const DungeonProcgenScript := preload("res://scripts/dungeon/procgen/dungeon_procgen.gd")
const ValidatorScript := preload("res://scripts/dungeon/dungeon_definition_validator.gd")

const BIOMES: Array[String] = [
	"forgotten_castle", "crystal_caverns", "poison_swamp", "frozen_fortress", "dark_cathedral",
	"iron_vault", "prism_depths", "venom_mire", "glacial_hollow", "umbral_chapel",
]


func _ready() -> void:
	var seeds := 100
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--seeds="):
			seeds = maxi(1, int(str(arg).substr("--seeds=".length())))
	var total_ok := 0
	var total := 0
	var errors: Dictionary = {}
	print("%-20s %8s %8s  %s" % ["biome", "ok", "rate", "top errors"])
	for biome in BIOMES:
		var ok := 0
		var biome_errors: Dictionary = {}
		for i in seeds:
			var seed_value := 1 + i * 7919 + biome.hash()
			var gen: Dictionary = DungeonProcgenScript.generate(biome, seed_value, 1, 1, 1, false, false)
			total += 1
			if not gen.get("ok", false):
				_bump(biome_errors, "generate_failed")
				_bump(errors, "generate_failed")
				continue
			var result: Dictionary = ValidatorScript.validate(gen.get("definition", {}))
			if result.get("ok", false):
				ok += 1
				total_ok += 1
				continue
			for err in result.get("errors", []):
				_bump(biome_errors, str(err))
				_bump(errors, str(err))
		print("%-20s %8d %7.1f%%  %s" % [biome, ok, 100.0 * ok / float(seeds), _top(biome_errors)])
	print("\nTOTAL %d/%d (%.1f%%) pass" % [total_ok, total, 100.0 * total_ok / float(total)])
	print("error mix: %s" % _top(errors))
	get_tree().quit(0 if total_ok > 0 else 1)


func _bump(d: Dictionary, key: String) -> void:
	d[key] = int(d.get(key, 0)) + 1


func _top(d: Dictionary) -> String:
	var keys: Array = d.keys()
	keys.sort_custom(func(a, b): return int(d[a]) > int(d[b]))
	var parts: PackedStringArray = []
	for k in keys.slice(0, 4):
		parts.append("%s=%d" % [k, int(d[k])])
	return ", ".join(parts) if parts.size() > 0 else "-"
