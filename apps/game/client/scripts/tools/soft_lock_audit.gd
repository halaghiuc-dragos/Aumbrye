extends Node3D

const WeaponControllerScript := preload("res://scripts/combat/weapon_controller.gd")
const WeaponScene := preload("res://scenes/player/player.tscn")

var _failures := 0
var _weapon: WeaponController
var _body: CharacterBody3D


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("Soft lock audit: %s" % message)


func _make_target(id: String, location: Vector3, radius: float = 0.4) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = id
	body.position = location
	body.add_to_group(CombatGroups.LOCKABLE)
	var shape_node := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	shape_node.shape = shape
	body.add_child(shape_node)
	add_child(body)
	return body


func _make_wall() -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = "OccludingWall"
	wall.position = Vector3(0.0, 1.0, -1.5)
	wall.collision_layer = CombatLayers.WORLD_OCCLUDERS
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 2.0, 0.25)
	shape_node.shape = shape
	wall.add_child(shape_node)
	add_child(wall)
	return wall


func _ready() -> void:
	_body = CharacterBody3D.new()
	_body.name = "SoftLockPlayer"
	var facing := Node3D.new()
	facing.name = "Facing"
	_body.add_child(facing)
	var camera := Node3D.new()
	camera.name = "CameraPivot"
	_body.add_child(camera)
	_weapon = WeaponControllerScript.new() as WeaponController
	_weapon.name = "WeaponController"
	_body.add_child(_weapon)
	add_child(_body)
	_weapon._weapon_data = {"hitbox": {"radius": 2.0}, "lunge_distance": 0.0}
	await get_tree().physics_frame
	_weapon._lock_on = null
	_weapon._body = _body
	camera.global_basis = Basis.IDENTITY
	# Camera forward is -Z. The nearer off-axis target must not beat the aligned threat.
	var aligned := _make_target("Aligned", Vector3(0.0, 0.0, -3.0))
	var off_axis := _make_target("OffAxis", Vector3(1.0, 0.0, -1.0))
	await get_tree().physics_frame
	_check(_weapon._find_soft_lock_target() == aligned, "aim alignment must outrank a nearer off-axis target")
	off_axis.queue_free()
	aligned.queue_free()
	await get_tree().physics_frame

	var in_reach := _make_target("InReach", Vector3(0.0, 0.0, -4.0))
	var outside_reach := _make_target("OutsideReach", Vector3(0.0, 0.0, -4.01))
	await get_tree().physics_frame
	_check(_weapon._find_soft_lock_target() == in_reach, "weapon reach must bound soft-target acquisition")
	in_reach.queue_free()
	outside_reach.queue_free()
	await get_tree().physics_frame

	var low := _make_target("Low", Vector3(0.0, 2.5, -3.0))
	var high := _make_target("High", Vector3(0.0, 2.51, -3.0))
	await get_tree().physics_frame
	var elevation_pick := _weapon._find_soft_lock_target()
	_check(elevation_pick == low, "targets beyond the vertical limit must not steer an attack (got %s; low=%s high=%s)" % [str(elevation_pick.name) if elevation_pick else "none", low.global_position, high.global_position])
	low.queue_free()
	await get_tree().physics_frame
	_check(_weapon._find_soft_lock_target() == null, "an elevated target alone must not steer an attack")
	high.queue_free()
	await get_tree().physics_frame

	var blocked := _make_target("Blocked", Vector3(0.0, 0.0, -3.0))
	var visible_competitor := _make_target("VisibleCompetitor", Vector3(1.2, 0.0, -3.8))
	var wall := _make_wall()
	await get_tree().physics_frame
	_check(_weapon._find_soft_lock_target() == visible_competitor, "a closer hidden target must lose to a farther visible target")
	wall.queue_free()
	await get_tree().physics_frame
	_check(_weapon._find_soft_lock_target() == blocked, "aim alignment must select the previously occluded target when its path clears")
	blocked.queue_free()
	visible_competitor.queue_free()
	await get_tree().physics_frame
	print("SOFT LOCK RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
