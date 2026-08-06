extends Area3D
class_name TrapDamageArea

## Applies DamageInfo to hurtboxes entering the area (traps, hazards).

@export var damage := 15.0
@export var poise_damage := 10.0
@export var damage_type := "physical"
@export var team := "trap"
@export var hit_interval := 0.5

var _cooldowns: Dictionary = {}
var _collision_shape: CollisionShape3D


func _ready() -> void:
	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	area_entered.connect(_on_area_entered)
	monitoring = false


func set_damage_active(active: bool) -> void:
	monitoring = active
	if active:
		scan_overlapping_areas()


func scan_overlapping_areas() -> void:
	if not monitoring:
		return
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
			_try_hit(collider as Area3D)


func _on_area_entered(area: Area3D) -> void:
	_try_hit(area)


func _try_hit(area: Area3D) -> void:
	if not monitoring:
		return
	if not area.has_method("receive_hit"):
		return
	if area.get("team") == team:
		return
	var id := area.get_instance_id()
	var now := Time.get_ticks_msec() / 1000.0
	if _cooldowns.has(id) and now - _cooldowns[id] < hit_interval:
		return
	_cooldowns[id] = now
	var direction := (area.global_position - global_position).normalized()
	var info := DamageInfo.create(damage, poise_damage, self, damage_type, direction)
	area.call("receive_hit", info)
