extends Projectile
class_name ThrowableProjectile

## `RG-04`: a quick-slot throwable is a `Projectile` (same launch arc, same hitbox) that explodes
## into a small AoE instead of just landing a single hit -- configured right after `instantiate()`,
## before `launch()`, so `_explode()` has everything it needs by the time either impact hook fires.

var _status_id := ""
var _status_stacks := 1
var _status_duration := 6.0
var _impact_radius := 4.0
var _explode_damage := 0.0
var _explode_damage_type := DamageInfo.TYPE_PHYSICAL
var _lure := false
var _exploded := false


func configure(
	status_id: String,
	status_stacks: int,
	status_duration: float,
	impact_radius: float,
	explode_damage: float,
	explode_damage_type: String,
	lure: bool
) -> void:
	_status_id = status_id
	_status_stacks = maxi(1, status_stacks)
	_status_duration = status_duration
	_impact_radius = maxf(0.5, impact_radius)
	_explode_damage = explode_damage
	_explode_damage_type = explode_damage_type
	_lure = lure


func _on_world_impact() -> void:
	_explode()
	queue_free()


func _on_hit_landed(target: Node) -> void:
	_explode()
	super._on_hit_landed(target)


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	var origin := global_position
	var tree := get_tree()
	if tree == null:
		return
	if _lure:
		_draw_aggro(tree, origin)
	var radius_sq := _impact_radius * _impact_radius
	var hit_anything := false
	for node in tree.get_nodes_in_group("enemy"):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and enemy.call("is_dead"):
			continue
		if enemy.global_position.distance_squared_to(origin) > radius_sq:
			continue
		hit_anything = true
		if _explode_damage > 0.0:
			var hurtbox := enemy.get_node_or_null("Hurtbox")
			if hurtbox and hurtbox.has_method("receive_hit"):
				var offset := enemy.global_position - origin
				var dir := (
					offset.normalized() if offset.length_squared() > 0.0001 else Vector3.FORWARD
				)
				var info := DamageInfo.create(
					_explode_damage, 0.0, _owner_node, _explode_damage_type, dir
				)
				hurtbox.call("receive_hit", info)
		if _status_id != "":
			var controller := enemy.get_node_or_null("StatusController") as StatusController
			if controller:
				controller.apply_status(_status_id, _status_stacks, _status_duration)
	if VfxService:
		if hit_anything or _lure:
			VfxService.play_rune_flare(origin)
		else:
			VfxService.play_hit_spark(origin)


## `RG-04`: the lure item's identity trait -- redirects nearby patrolling enemies to investigate
## the impact point, the same public hook `CastleEnemyBase._broadcast_alert()` already uses for
## one enemy noticing another's alert.
func _draw_aggro(tree: SceneTree, origin: Vector3) -> void:
	for node in tree.get_nodes_in_group("enemy"):
		if node == null or not is_instance_valid(node) or not (node is Node3D):
			continue
		if node.has_method("is_dead") and node.call("is_dead"):
			continue
		if (node as Node3D).global_position.distance_squared_to(origin) > _impact_radius * _impact_radius:
			continue
		if node.has_method("notice_ally_alert"):
			node.call("notice_ally_alert", origin)
