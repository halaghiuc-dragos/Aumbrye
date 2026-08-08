extends RefCounted
class_name TrapTactics

## Shared trap behaviour: content lookup, hazard advertisement for anyone steering
## around a live volume, and a damage pass that treats every faction alike.

const HAZARD_GROUP := "trap_volume"
const ARMED_META := "hazard_armed"
const RADIUS_META := "hazard_radius"

static var _definitions: Dictionary = {}


static func trap_id_for(node: Node) -> String:
	var raw := String(node.name)
	var at := raw.find("@")
	if at > 0:
		raw = raw.substr(0, at)
	return raw.to_snake_case()


static func definition(trap_id: String) -> Dictionary:
	if trap_id == "":
		return {}
	if _definitions.has(trap_id):
		return _definitions[trap_id]
	var data: Dictionary = ContentLoader.load_json("content/traps/%s.json" % trap_id)
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


static func is_armed(node: Node3D) -> bool:
	return bool(node.get_meta(ARMED_META, false))


static func hazard_radius(node: Node3D) -> float:
	return float(node.get_meta(RADIUS_META, 0.0))


## Bodies near enough to be worth arming a trap for. Trigger modes decide whether
## enemies count, which is what makes a plate baitable and a proximity trap not.
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


## Applies damage and status build-up to every hurtbox inside `area` that is not
## part of the trap itself. Returns the number of non-player victims struck.
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
