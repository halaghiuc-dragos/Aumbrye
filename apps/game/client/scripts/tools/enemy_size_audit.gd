extends Node3D

const Fixtures := [
	[preload("res://scenes/enemies/crystal_bat.tscn"), 0.28, 1.2],
	[preload("res://scenes/enemies/crystal_slime.tscn"), 0.34, 1.45],
	[preload("res://scenes/enemies/crystal_golem.tscn"), 0.54, 2.3],
	[preload("res://scenes/enemies/swamp_toad.tscn"), 0.46, 1.6],
	[preload("res://scenes/enemies/swamp_leech.tscn"), 0.3, 0.75],
]

var _failures := 0


func _ready() -> void:
	for fixture in Fixtures:
		await _check_fixture(fixture[0] as PackedScene, float(fixture[1]), float(fixture[2]))
	await _check_narrow_door_clearance()
	print("ENEMY SIZE RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_fixture(scene: PackedScene, expected_radius: float, expected_height: float) -> void:
	_add_floor()
	var enemy := scene.instantiate() as CharacterBody3D
	enemy.position.y = expected_height * 0.5 + 0.05
	add_child(enemy)
	await get_tree().physics_frame
	var body_shape := (enemy.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	var hurt_shape := (enemy.get_node("Hurtbox/CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	var hit_shape_node := enemy.get_node("AttackPivot/Hitbox/CollisionShape3D") as CollisionShape3D
	_check(enemy.scale.is_equal_approx(Vector3.ONE), "%s keeps a unit-scale physics root" % enemy.name)
	_check(is_equal_approx(body_shape.radius, expected_radius), "%s has its authored body radius" % enemy.name)
	_check(is_equal_approx(body_shape.height, expected_height), "%s has its authored body height" % enemy.name)
	_check(
		is_equal_approx(hurt_shape.size.x, expected_radius * 2.0)
		and is_equal_approx(hurt_shape.size.y, expected_height),
		"%s keeps hurtbox dimensions aligned with its physical body" % enemy.name
	)
	_check(
		hit_shape_node.global_transform.basis.get_scale().is_equal_approx(Vector3.ONE),
		"%s visual scale cannot silently enlarge attack reach" % enemy.name
	)
	var aim_point: Vector3 = enemy.call("get_lock_aim_point")
	var hp_bar_height := float(enemy.call("get_hp_bar_height"))
	_check(
		aim_point.y > enemy.global_position.y + 0.1
		and enemy.global_position.y + hp_bar_height > aim_point.y,
		"%s exposes a usable body-relative lock aim and health-bar height" % enemy.name
	)
	_check(
		enemy.move_and_collide(Vector3.DOWN) != null,
		"%s physical capsule contacts the floor at its authored height" % enemy.name
	)
	enemy.queue_free()
	_clear_floor()
	await get_tree().physics_frame


func _check_narrow_door_clearance() -> void:
	# The 0.75m opening is traversable by the bat's 0.28m radius but not by the golem's
	# 0.54m radius. This catches a regression back to visual/root scaling, where both bodies
	# would retain the inherited 0.4m collision capsule.
	_add_door_frame(0.75)
	await get_tree().physics_frame
	var bat := await _spawn_for_clearance(preload("res://scenes/enemies/crystal_bat.tscn"), 0.6)
	var bat_hit := bat.move_and_collide(Vector3(0.0, 0.0, 4.0))
	_check(bat_hit == null, "small enemy traverses a narrow doorway with its authored radius")
	bat.queue_free()
	await get_tree().physics_frame
	var golem := await _spawn_for_clearance(preload("res://scenes/enemies/crystal_golem.tscn"), 1.15)
	var golem_hit := golem.move_and_collide(Vector3(0.0, 0.0, 4.0))
	_check(golem_hit != null, "large enemy cannot traverse a doorway narrower than its body")
	golem.queue_free()
	_clear_door_frame()


func _spawn_for_clearance(scene: PackedScene, ground_y: float) -> CharacterBody3D:
	var enemy := scene.instantiate() as CharacterBody3D
	enemy.position = Vector3(0.0, ground_y, -2.0)
	add_child(enemy)
	await get_tree().physics_frame
	return enemy


func _add_door_frame(gap: float) -> void:
	var half_gap := gap * 0.5
	_add_wall("AuditDoorLeft", Vector3(-2.2, 1.4, 0.0), Vector3(4.4 - gap, 2.8, 0.3), -half_gap - (4.4 - gap) * 0.5)
	_add_wall("AuditDoorRight", Vector3(2.2, 1.4, 0.0), Vector3(4.4 - gap, 2.8, 0.3), half_gap + (4.4 - gap) * 0.5)


func _add_floor() -> void:
	var audit_floor := StaticBody3D.new()
	audit_floor.name = "AuditFloor"
	audit_floor.position = Vector3(0.0, -0.1, 0.0)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 0.2, 20.0)
	collision.shape = box
	audit_floor.add_child(collision)
	add_child(audit_floor)


func _clear_floor() -> void:
	var audit_floor := get_node_or_null("AuditFloor")
	if audit_floor:
		audit_floor.queue_free()


func _add_wall(node_name: String, position_seed: Vector3, size: Vector3, x: float) -> void:
	var wall := StaticBody3D.new()
	wall.name = node_name
	wall.position = position_seed
	wall.position.x = x
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	wall.add_child(collision)
	add_child(wall)


func _clear_door_frame() -> void:
	for child in get_children():
		if child.name in ["AuditDoorLeft", "AuditDoorRight"]:
			child.queue_free()


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(label)
