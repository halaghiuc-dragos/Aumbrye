extends Area3D
class_name Hitbox

signal hit_landed(target: Node)

const DEBUG_SCRIPT := preload("res://scripts/combat/combat_collision_debug.gd")
const WORLD_COLLISION_MASK := CombatLayers.WORLD_OCCLUDERS

@export var damage_amount := 10.0
@export var poise_damage := 15.0
@export var team: String = "player"

@export var rehit_interval := 0.0
## `RG-03`: set by `Projectile` on its own hitbox -- lets `Guard` tell a shot arrow apart from a
## melee swing when it intercepts the hit.
var is_projectile := false

var _owner_node: Node
var _combat_owner: Node
var _collision_shape: CollisionShape3D
var _hit_times: Dictionary = {}
var _los_clear_this_swing: Dictionary = {}
var _active := false
var _last_overlap_count := 0
var _damage_type := DamageInfo.TYPE_PHYSICAL
var _attack_class := "blockable"
var _knockback := 0.0
var _backstab_multiplier := 0.0
var _status_id := ""
var _status_stacks := 1
var _crit_chance := 0.0
var _crit_multiplier := 1.5
var _crit_rng := RandomNumberGenerator.new()
var _shape_query := PhysicsShapeQueryParameters3D.new()
var _castle_run: Node
var _execution_target: Node = null
var _execution_kind := ""
var _last_shape_transform := Transform3D.IDENTITY
var _has_swept_transform := false


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
	if _owner_node:
		_owner_node.tree_exiting.connect(disable)
	_crit_rng.seed = FloorSeedMix.mix(RunFlow.current_seed, hash(str(get_path())))
	DEBUG_SCRIPT.set_debug_draw(self, false, DEBUG_SCRIPT.HITBOX_COLOR)
	_shape_query.collide_with_areas = true
	_shape_query.collide_with_bodies = false
	_shape_query.exclude = [get_rid()]
	_castle_run = get_tree().get_first_node_in_group("castle_run")


func is_active() -> bool:
	return _active


func set_debug_draw(enabled: bool) -> void:
	DEBUG_SCRIPT.set_debug_draw(self, enabled, DEBUG_SCRIPT.HITBOX_COLOR)


func enable() -> void:
	_active = true
	monitoring = true
	set_physics_process(true)
	_has_swept_transform = false
	_scan_overlaps()


func disable() -> void:
	_active = false
	monitoring = false
	set_physics_process(false)
	_last_overlap_count = 0
	_hit_times.clear()
	_los_clear_this_swing.clear()
	_execution_target = null
	_execution_kind = ""
	_has_swept_transform = false


func set_execution(target: Node, kind: String) -> void:
	_execution_target = target
	_execution_kind = kind


func reset_swing() -> void:
	_hit_times.clear()
	_los_clear_this_swing.clear()


func set_attack_values(
	damage: float,
	poise: float,
	dmg_type: String = DamageInfo.TYPE_PHYSICAL,
	apply_status: String = "",
	status_stacks: int = 1,
	crit_chance: float = 0.0,
	crit_multiplier: float = 1.5,
	attack_class: String = "blockable",
	knockback: float = 0.0,
	backstab_multiplier: float = 0.0
) -> void:
	damage_amount = damage
	poise_damage = poise
	_damage_type = dmg_type
	_status_id = apply_status
	_status_stacks = status_stacks
	_crit_chance = crit_chance
	_crit_multiplier = crit_multiplier
	_attack_class = attack_class
	_knockback = knockback
	_backstab_multiplier = backstab_multiplier


func set_combat_owner(node: Node) -> void:
	_combat_owner = node


func _physics_process(_delta: float) -> void:
	if not _active:
		return
	_scan_overlaps()


func _on_area_entered(area: Area3D) -> void:
	_try_hit(area)


const MAX_OVERLAP_RESULTS := 32
## Below this fraction of the shape's own smallest extent, a static test is close enough -- the
## sweep only kicks in once the hitbox has travelled far enough between frames to plausibly have
## passed through something thinner than itself.
const SWEEP_TRAVEL_FRACTION := 0.5


func _scan_overlaps() -> void:
	_last_overlap_count = 0
	if _collision_shape == null or _collision_shape.shape == null:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	_shape_query.shape = _collision_shape.shape
	_shape_query.collision_mask = collision_mask
	var current_transform := _collision_shape.global_transform
	var results: Array
	var did_sweep := false
	if _has_swept_transform:
		var travel := current_transform.origin - _last_shape_transform.origin
		var min_extent := _shape_min_extent(_collision_shape.shape)
		if travel.length() > min_extent * SWEEP_TRAVEL_FRACTION:
			results = _sweep(space, _last_shape_transform, travel)
			did_sweep = true
	if not did_sweep:
		_shape_query.transform = current_transform
		_shape_query.motion = Vector3.ZERO
		results = space.intersect_shape(_shape_query, MAX_OVERLAP_RESULTS)
	for result in results:
		var collider = result.get("collider")
		if collider is Area3D:
			_last_overlap_count += 1
			_try_hit(collider as Area3D)
	_last_shape_transform = current_transform
	_has_swept_transform = true


## `PH-03`: verified directly against this engine build -- `intersect_shape()` does **not** honour
## `PhysicsShapeQueryParameters3D.motion`; a query built with a non-zero `motion` returns exactly
## the same result as a static test at `transform`. `cast_motion()` is the call that actually
## respects it: it returns the safe/unsafe fraction of `motion` the shape can travel before
## touching something, so the sweep is a `cast_motion()` to find *where* contact happens, then one
## `intersect_shape()` at that point to enumerate *what* was touched there.
func _sweep(space: PhysicsDirectSpaceState3D, from_transform: Transform3D, motion: Vector3) -> Array:
	_shape_query.transform = from_transform
	_shape_query.motion = motion
	var cast := space.cast_motion(_shape_query)
	var unsafe: float = clampf(float(cast[1]) if cast.size() > 1 else 1.0, 0.0, 1.0)
	var contact_transform := from_transform
	contact_transform.origin = from_transform.origin + motion * unsafe
	_shape_query.transform = contact_transform
	_shape_query.motion = Vector3.ZERO
	return space.intersect_shape(_shape_query, MAX_OVERLAP_RESULTS)


func _shape_min_extent(shape: Shape3D) -> float:
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		return minf(size.x, minf(size.y, size.z))
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).radius * 2.0
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius * 2.0
	return 0.3


func _try_hit(area: Area3D) -> void:
	if not is_instance_valid(_owner_node):
		return
	if not _active or area == self:
		return
	if not area.has_method("receive_hit"):
		return
	if area.get("team") == team:
		return
	if _execution_target != null and _body_of(area) != _execution_target:
		return
	if _is_cross_boss_boundary(area):
		return
	var target_id := area.get_instance_id()
	if not _los_clear_this_swing.get(target_id, false):
		if not _has_clear_line_to(area):
			return
		_los_clear_this_swing[target_id] = true
	var now := Time.get_ticks_msec() / 1000.0
	if _hit_times.has(target_id):
		if rehit_interval <= 0.0:
			return
		if now - float(_hit_times[target_id]) < rehit_interval:
			return
	_hit_times[target_id] = now
	var direction := Vector3.ZERO
	if _owner_node:
		direction = (area.global_position - _owner_node.global_position).normalized()
	var final_damage := damage_amount
	var is_crit := false
	if _crit_chance > 0.0 and _crit_rng.randf() < _crit_chance:
		final_damage *= _crit_multiplier
		is_crit = true
	var info := DamageInfo.create(
		final_damage,
		poise_damage,
		_owner_node,
		_damage_type,
		direction,
		_status_id,
		_status_stacks,
		_attack_class
	)
	info.crit = is_crit
	info.knockback = _knockback
	info.backstab_multiplier_override = _backstab_multiplier
	info.is_projectile = is_projectile
	if _execution_kind != "":
		info.execution = _execution_kind
		info.ignore_guard = true
	area.call("receive_hit", info)
	hit_landed.emit(area)
	var mana_restore := ClassPerks.arcane_focus_mana_on_hit(_owner_node)
	if mana_restore > 0.0:
		var mana := _owner_node.get_node_or_null("Mana") as Mana
		if mana:
			mana.restore(mana_restore)


func _body_of(area: Area3D) -> Node:
	var node: Node = area
	while node:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return area.get_parent()


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
	if _castle_run == null or not is_instance_valid(_castle_run):
		_castle_run = get_tree().get_first_node_in_group("castle_run")
	if _castle_run and _castle_run.has_method("is_cross_boss_boundary"):
		return _castle_run.call("is_cross_boss_boundary", attacker, target_body)
	return false


func _has_clear_line_to(target: Area3D) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var from := global_position
	var to := target.global_position
	if _collision_shape:
		from = _collision_shape.global_position
	var target_shape := target.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if target_shape:
		to = target_shape.global_position
	const MIN_LOS_HEIGHT := 0.75
	from.y = maxf(from.y, MIN_LOS_HEIGHT)
	to.y = maxf(to.y, MIN_LOS_HEIGHT)
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
