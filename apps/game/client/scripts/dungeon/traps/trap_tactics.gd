extends RefCounted
class_name TrapTactics


const HAZARD_GROUP := "trap_volume"
const ARMED_META := "hazard_armed"
const RADIUS_META := "hazard_radius"

static var _definitions: Dictionary = {}


static func trap_id_for(node: Node) -> String:
	var explicit := str(node.get("trap_id")) if node.get("trap_id") != null else ""
	if explicit != "":
		return explicit
	var raw := String(node.name)
	var at := raw.find("@")
	if at > 0:
		raw = raw.substr(0, at)
	var from_scene := _id_for_scene_path(node.scene_file_path)
	if from_scene != "":
		return from_scene
	var derived := raw.to_snake_case()
	if not _warned_derived.has(derived):
		_warned_derived[derived] = true
		push_warning(
			(
				"TrapTactics: '%s' has no `trap_id`; deriving '%s' from the node name. Renaming the"
				+ " node will silently change which content file it loads."
			)
			% [node.name, derived]
		)
	return derived


static var _warned_derived: Dictionary = {}

static var _scene_to_id: Dictionary = {}
static var _scene_map_built := false


static func _id_for_scene_path(scene_path: String) -> String:
	if scene_path == "":
		return ""
	if not _scene_map_built:
		_scene_map_built = true
		var dir := DirAccess.open(ContentLoader.content_path("content/traps"))
		if dir:
			dir.list_dir_begin()
			var entry := dir.get_next()
			while entry != "":
				if entry.ends_with(".json"):
					var data: Dictionary = ContentLoader.load_json("content/traps/%s" % entry)
					var scene := str(data.get("scene", ""))
					if scene != "":
						_scene_to_id[scene] = str(data.get("id", entry.get_basename()))
				entry = dir.get_next()
			dir.list_dir_end()
	return str(_scene_to_id.get(scene_path, ""))


static func definition(trap_id: String) -> Dictionary:
	if trap_id == "":
		return {}
	if _definitions.has(trap_id):
		return _definitions[trap_id]
	var data: Dictionary = ContentLoader.load_json("content/traps/%s.json" % trap_id)
	if data.is_empty():
		push_warning("TrapTactics: no content/traps/%s.json — trap runs on scene defaults" % trap_id)
	_definitions[trap_id] = data
	return data


static func clear_cache() -> void:
	_definitions.clear()


static func register_hazard(node: Node3D, radius: float) -> void:
	if not node.is_in_group(HAZARD_GROUP):
		node.add_to_group(HAZARD_GROUP)
	node.set_meta(RADIUS_META, radius)
	node.set_meta(ARMED_META, false)


static func set_armed(node: Node3D, armed: bool) -> void:
	node.set_meta(ARMED_META, armed)


static func hazard_radius(node: Node3D) -> float:
	return float(node.get_meta(RADIUS_META, 0.0))


static func trigger_present(
	node: Node3D, radius: float, include_player: bool, include_enemies: bool
) -> bool:
	var tree := node.get_tree()
	if tree == null:
		return false
	var radius_sq := radius * radius
	var origin := node.global_position
	if include_player:
		var player := tree.get_first_node_in_group("player") as Node3D
		if player != null and player.global_position.distance_squared_to(origin) <= radius_sq:
			return true
	if include_enemies:
		for entry in tree.get_nodes_in_group("enemy"):
			var enemy := entry as Node3D
			if enemy == null or not is_instance_valid(enemy):
				continue
			if enemy.global_position.distance_squared_to(origin) <= radius_sq:
				return true
	return false


static func strike(area: Area3D, source: Node3D, cfg: Dictionary, cooldowns: Dictionary) -> int:
	if not area.monitoring:
		return 0
	var now := Time.get_ticks_msec() / 1000.0
	var interval := float(cfg.get("hitInterval", 0.5))
	var caught := 0
	for other in area.get_overlapping_areas():
		var hurtbox := other as Hurtbox
		if hurtbox == null or not is_instance_valid(hurtbox):
			continue
		if hurtbox.team == "trap":
			continue
		var id := hurtbox.get_instance_id()
		if cooldowns.has(id) and now - float(cooldowns[id]) < interval:
			continue
		cooldowns[id] = now
		var multiplier := 1.0
		if hurtbox.team != "player":
			multiplier = float(cfg.get("enemyDamageMultiplier", 1.0))
			caught += 1
		var damage := float(cfg.get("damage", 0.0)) * multiplier
		if damage > 0.0:
			var direction := (hurtbox.global_position - area.global_position).normalized()
			(
				hurtbox
				. receive_hit(
					DamageInfo.create(
						damage,
						float(cfg.get("poiseDamage", 0.0)) * multiplier,
						source,
						str(cfg.get("damageType", "physical")),
						direction
					)
				)
			)
		_feed_build_up(hurtbox, cfg)
	if caught > 0 and RunBuffs:
		RunBuffs.note_trap_catch(caught)
	return caught


static func _feed_build_up(hurtbox: Hurtbox, cfg: Dictionary) -> void:
	var status_id := str(cfg.get("statusId", ""))
	if status_id == "":
		return
	var controller := _resolve_controller(hurtbox)
	if controller == null:
		return
	controller.add_build_up(status_id, float(cfg.get("statusBuildUp", 0.0)))


static func _resolve_controller(hurtbox: Hurtbox) -> StatusController:
	var node: Node = hurtbox
	for _step in 4:
		node = node.get_parent()
		if node == null:
			return null
		var found := node.get_node_or_null("StatusController") as StatusController
		if found != null:
			return found
	return null


## A trigger radius wide enough to cover the trap's own hitbox, whatever shape it was authored with.
## The trap's authored radius wins when it is already the larger of the two.
static func trigger_radius_for_hitbox(hitbox: Node, authored_radius: float) -> float:
	if hitbox == null:
		return authored_radius
	var shape_node := hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		return authored_radius
	var horizontal := 0.0
	var shape := shape_node.shape
	if shape is BoxShape3D:
		horizontal = maxf((shape as BoxShape3D).size.x, (shape as BoxShape3D).size.z) * 0.5
	elif shape is CapsuleShape3D:
		horizontal = (shape as CapsuleShape3D).radius
	elif shape is CylinderShape3D:
		horizontal = (shape as CylinderShape3D).radius
	return maxf(authored_radius, horizontal + 0.5)
