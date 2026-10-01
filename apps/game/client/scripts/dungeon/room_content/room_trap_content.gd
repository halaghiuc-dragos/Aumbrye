extends "res://scripts/dungeon/room_content/room_content_base.gd"

const FALLBACK_TRAP := preload("res://scenes/traps/spike_trap.tscn")
const CHEST_SCENE := preload("res://scenes/loot/loot_chest.tscn")

## A trap room is a gauntlet: its chest sits at the far end, and crossing the room without losing
## health turns opening it into a relic offer on top of the loot.
var _chest: Node3D
var _watching: Health
var _last_health := 0.0
var _hurt := false


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
	trap.set_meta("room_id", room_id)
	_content_root().add_child(trap)
	var params: Variant = entry.get("params", {})
	if params is Dictionary and str((params as Dictionary).get("risk", "")) == "gauntlet":
		_build_gauntlet_chest(entry)


func get_chests() -> Array[Node3D]:
	return [_chest] if _chest != null else []


func _build_gauntlet_chest(entry: Dictionary) -> void:
	_chest = CHEST_SCENE.instantiate() as Node3D
	_chest.name = "GauntletChest"
	_chest.position = _anchor(1).position
	_content_root().add_child(_chest)
	if _chest.has_method("configure"):
		_chest.call("configure", {"items": entry.get("items", [])})
	_chest.connect("opened", _on_chest_opened)
	watch_room_entry(_on_player_entered)


func _on_player_entered(body: Node3D) -> void:
	_watching = body.get_node_or_null("Health") as Health
	if _watching == null:
		return
	_last_health = _watching.current
	_watching.health_changed.connect(_on_health_changed)


func _on_health_changed(current: float, _max_value: float) -> void:
	if current < _last_health:
		_hurt = true
	_last_health = current


func _on_chest_opened() -> void:
	if _hurt:
		return
	var offer_ui := get_tree().get_first_node_in_group("relic_offer_ui")
	if offer_ui and offer_ui.has_method("open_offer"):
		offer_ui.call("open_offer", "gauntlet:%d:%s" % [RunFlow.current_floor, name])
	RunFlow.run_warning.emit(tr("ROOM_GAUNTLET_CLEAN"))


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
