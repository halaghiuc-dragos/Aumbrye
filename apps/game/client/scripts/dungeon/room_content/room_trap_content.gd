extends "res://scripts/dungeon/room_content/room_content_base.gd"

const FALLBACK_TRAP := preload("res://scenes/traps/spike_trap.tscn")


func configure(entry: Dictionary, definition: Dictionary) -> void:
	var biome_id := str(get_meta("biome_id", definition.get("biomeId", "")))
	var room_id := str(entry.get("roomId", ""))
	var trap_id := _roll_trap_id(biome_id, definition, room_id)
	var scene := _resolve_trap_scene(trap_id)
	if scene == null:
		return
	var trap: Node3D = scene.instantiate() as Node3D
	if trap == null:
		return
	trap.position = _anchor(0).position + Vector3(
		float(entry.get("x", 0.0)),
		float(entry.get("y", 0.0)),
		float(entry.get("z", 2.0))
	)
	trap.set_meta("biome_id", biome_id)
	trap.set_meta("trap_id", trap_id)
	_content_root().add_child(trap)


func _roll_trap_id(biome_id: String, definition: Dictionary, room_id: String) -> String:
	var biome := BiomeRegistry.get_biome(biome_id)
	var pool: Variant = biome.get("trapPool", [])
	if not pool is Array or (pool as Array).is_empty():
		return "spike_trap"
	var total := 0.0
	for row in (pool as Array):
		if row is Dictionary:
			total += maxf(0.0, float((row as Dictionary).get("weight", 0.0)))
	if total <= 0.0:
		return str((pool as Array)[0].get("trapId", "spike_trap"))
	var salt := absi(room_id.hash()) % 1_000_000 + 3
	var rng := RandomNumberGenerator.new()
	rng.seed = FloorSeedMix.mix(maxi(1, int(definition.get("seed", 1))), salt)
	var roll := rng.randf() * total
	var acc := 0.0
	for row in (pool as Array):
		if not row is Dictionary:
			continue
		acc += maxf(0.0, float((row as Dictionary).get("weight", 0.0)))
		if roll < acc:
			return str((row as Dictionary).get("trapId", "spike_trap"))
	return str((pool as Array)[0].get("trapId", "spike_trap"))


func _resolve_trap_scene(trap_id: String) -> PackedScene:
	var path := TrapCatalog.get_scene_path(trap_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("RoomTrapContent: unknown trap id '%s'" % trap_id)
		return FALLBACK_TRAP
	return load(path) as PackedScene
