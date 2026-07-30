extends Area3D
class_name Hitbox

const DEBUG_SCRIPT := preload("res://scripts/combat/combat_collision_debug.gd")
const WORLD_COLLISION_MASK := 1

@export var damage_amount := 10.0
@export var poise_damage := 15.0
@export var team: String = "player"

var _owner_node: Node
var _combat_owner: Node
var _collision_shape: CollisionShape3D
var _hit_targets: Array[int] = []
var _active := false
var _last_overlap_count := 0
var _damage_type := DamageInfo.TYPE_PHYSICAL
var _status_id := ""
var _status_stacks := 1


func _ready() -> void:
	add_to_group("combat_hitbox")
	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision_shape == null:
		push_error("Hitbox %s is missing a CollisionShape3D child" % get_path())
	area_entered.connect(_on_area_entered)
	monitoring = false
	monitorable = false
	set_physics_process(false)
	_owner_node = _find_combat_owner()
	DEBUG_SCRIPT.set_debug_draw(self, false, DEBUG_SCRIPT.HITBOX_COLOR)


func is_active() -> bool:
	return _active


func get_last_overlap_count() -> int:
	return _last_overlap_count


func set_debug_draw(enabled: bool) -> void:
	DEBUG_SCRIPT.set_debug_draw(self, enabled, DEBUG_SCRIPT.HITBOX_COLOR)


func enable() -> void:
	_active = true
	monitoring = true
	set_physics_process(true)
	_scan_overlaps()


func disable() -> void:
	_active = false
	monitoring = false
	set_physics_process(false)
	_last_overlap_count = 0


func reset_swing() -> void:
	_hit_targets.clear()


func set_attack_values(
	damage: float,
	poise: float,
	dmg_type: String = DamageInfo.TYPE_PHYSICAL,
	apply_status: String = "",
	status_stacks: int = 1
) -> void:
	damage_amount = damage
	poise_damage = poise
	_damage_type = dmg_type
	_status_id = apply_status
	_status_stacks = status_stacks


func set_combat_owner(node: Node) -> void:
	_combat_owner = node


func _physics_process(_delta: float) -> void:
	if _active:
		_scan_overlaps()


func _on_area_entered(area: Area3D) -> void:
	_try_hit(area)


func _scan_overlaps() -> void:
	_last_overlap_count = 0
	if _collision_shape == null or _collision_shape.shape == null:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _collision_shape.shape
	params.transform = _collision_shape.global_transform
	params.collision_mask = collision_mask
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.exclude = [get_rid()]
	for result in space.intersect_shape(params, 16):
		var collider = result.get("collider")
		if collider is Area3D:
			_last_overlap_count += 1
			_try_hit(collider as Area3D)


func _try_hit(area: Area3D) -> void:
	if not _active or area == self:
		return
	if not area.has_method("receive_hit"):
		return
	if area.get("team") == team:
		return
	if _is_cross_boss_boundary(area):
		return
	if not _has_clear_line_to(area):
		return
	var target_id := area.get_instance_id()
	if target_id in _hit_targets:
		return
	_hit_targets.append(target_id)
	var direction := Vector3.ZERO
	if _owner_node:
		direction = (area.global_position - _owner_node.global_position).normalized()
	var info := DamageInfo.create(
		damage_amount,
		poise_damage,
		_owner_node,
		_damage_type,
		direction,
		_status_id,
		_status_stacks
	)
	area.call("receive_hit", info)
	var feedback := _owner_node.get_node_or_null("HitFeedback")
	if feedback and feedback.has_method("on_hit"):
		feedback.on_hit(area.get_parent(), damage_amount)


func _find_combat_owner() -> Node:
	var node: Node = self
	while node:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return get_parent()


func _get_attacker_node() -> Node:
	if _combat_owner:
		return _combat_owner
	return _owner_node


func _is_cross_boss_boundary(target: Area3D) -> bool:
	var attacker := _get_attacker_node()
	var target_body := target.get_parent()
	if attacker == null or target_body == null:
		return false
	var castle_run := get_tree().get_first_node_in_group("castle_run")
	if castle_run and castle_run.has_method("is_cross_boss_boundary"):
		return castle_run.call("is_cross_boss_boundary", attacker, target_body)
	return false


func _has_clear_line_to(target: Area3D) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var from := global_position
	var to := target.global_position
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = WORLD_COLLISION_MASK
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var excludes: Array[RID] = []
	if _owner_node is CollisionObject3D:
		excludes.append((_owner_node as CollisionObject3D).get_rid())
	var target_parent := target.get_parent()
	if target_parent is CollisionObject3D:
		excludes.append((target_parent as CollisionObject3D).get_rid())
	params.exclude = excludes
	return space.intersect_ray(params).is_empty()
