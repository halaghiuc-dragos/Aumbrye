extends Node


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
	var enemy_content_failures := _check_enemy_content()
	get_tree().quit(0 if total_ok > 0 and enemy_content_failures == 0 else 1)


## EN-01: every attack entry in every enemy and boss definition must author `attackClass`, or the
## telegraph a player learns to trust silently falls back to the old poise-derived guess, which
## only ever produces `blockable`/`unblockable` -- `parryable` and `grab` never appear.
##
## EN-03: the invariant is that the telegraph must never be smaller than the attack. A missing
## `telegraph_radius` derives one from `max_range` at runtime, so this only warns (does not fail)
## when an *authored* radius is more than 25% smaller than `max_range` -- a tell that under-
## promises is a trap, not a tell.
func _check_enemy_content() -> int:
	var class_failures := 0
	var radius_warnings := 0
	for sub_dir in ["content/enemies", "content/bosses"]:
		var dir_path := ContentLoader.content_root().path_join(sub_dir)
		var dir := DirAccess.open(dir_path)
		if dir == null:
			push_error("definition_health: could not open '%s'" % dir_path)
			class_failures += 1
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				var counts := _check_enemy_file("%s/%s" % [sub_dir, file_name])
				class_failures += counts[0]
				radius_warnings += counts[1]
			file_name = dir.get_next()
		dir.list_dir_end()
	if class_failures > 0:
		print("ATTACK CLASS: %d attack(s) missing attackClass" % class_failures)
	else:
		print("ATTACK CLASS: every attack entry authors attackClass")
	if radius_warnings > 0:
		print("TELEGRAPH RADIUS: %d attack(s) under-promise their reach" % radius_warnings)
	else:
		print("TELEGRAPH RADIUS: no authored radius under-promises its attack's reach")
	return class_failures


func _check_enemy_file(relative_path: String) -> Array:
	var data: Dictionary = ContentLoader.load_json(relative_path)
	if data.is_empty():
		return [0, 0]
	var missing := 0
	var under_promising := 0
	var owner_id := str(data.get("id", relative_path))
	for attack in data.get("attacks", []):
		var counts := _check_attack_entry(owner_id, attack, data)
		missing += counts[0]
		under_promising += counts[1]
	for phase in data.get("phases", []):
		for attack in phase.get("attacks", []):
			var counts := _check_attack_entry(owner_id, attack, data)
			missing += counts[0]
			under_promising += counts[1]
	return [missing, under_promising]


func _check_attack_entry(owner_id: String, attack: Dictionary, root: Dictionary) -> Array:
	var missing := 0
	var under_promising := 0
	if str(attack.get("attackClass", "")) == "":
		print("  missing attackClass: %s/%s" % [owner_id, str(attack.get("id", "?"))])
		missing += 1
	if attack.has("telegraph_radius"):
		var max_range := float(attack.get("max_range", root.get("max_range", 0.0)))
		var radius := float(attack.get("telegraph_radius"))
		if max_range > 0.0 and radius < max_range * 0.75:
			print(
				(
					"  under-promising telegraph: %s/%s radius=%.2f vs max_range=%.2f"
					% [owner_id, str(attack.get("id", "?")), radius, max_range]
				)
			)
			under_promising += 1
	for combo in attack.get("combo_followups", []):
		var counts := _check_attack_entry(owner_id, combo, root)
		missing += counts[0]
		under_promising += counts[1]
	return [missing, under_promising]


func _bump(d: Dictionary, key: String) -> void:
	d[key] = int(d.get(key, 0)) + 1


func _top(d: Dictionary) -> String:
	var keys: Array = d.keys()
	keys.sort_custom(func(a, b): return int(d[a]) > int(d[b]))
	var parts: PackedStringArray = []
	for k in keys.slice(0, 4):
		parts.append("%s=%d" % [k, int(d[k])])
	return ", ".join(parts) if parts.size() > 0 else "-"
