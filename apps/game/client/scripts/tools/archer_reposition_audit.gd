extends Node3D

const ArcherScene := preload("res://scenes/enemies/castle_archer.tscn")

var _failures := 0


func _ready() -> void:
	await _check_open_retreat()
	await _check_lateral_escape()
	await _check_cornered_hold()
	print("ARCHER REPOSITION RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_open_retreat() -> void:
	var archer := await _spawn_archer()
	var target: Vector3 = archer.call("_choose_reposition_target", Vector3(0.0, 0.0, 2.0))
	_check(target != Vector3.INF and target.z < -2.0, "archer chooses a clear rear retreat")
	archer.queue_free()
	await get_tree().physics_frame


func _check_lateral_escape() -> void:
	var archer := await _spawn_archer()
	_add_wall(Vector3(0.0, 0.7, -1.6), Vector3(1.2, 1.4, 1.4))
	await get_tree().physics_frame
	var target: Vector3 = archer.call("_choose_reposition_target", Vector3(0.0, 0.0, 2.0))
	_check(target != Vector3.INF and absf(target.x) > 0.5, "blocked rear route chooses a lateral escape")
	archer.queue_free()
	_clear_walls()
	await get_tree().physics_frame


func _check_cornered_hold() -> void:
	var archer := await _spawn_archer()
	_add_wall(Vector3(0.0, 0.7, -1.5), Vector3(10.0, 1.4, 2.0))
	await get_tree().physics_frame
	var target: Vector3 = archer.call("_choose_reposition_target", Vector3(0.0, 0.0, 2.0))
	_check(target == Vector3.INF, "cornered archer holds instead of pushing through a wall")
	archer.queue_free()
	_clear_walls()


func _spawn_archer() -> CharacterBody3D:
	var archer := ArcherScene.instantiate() as CharacterBody3D
	archer.position = Vector3.ZERO
	add_child(archer)
	await get_tree().physics_frame
	return archer


func _add_wall(position_value: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.name = "AuditWall"
	wall.position = position_value
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)


func _clear_walls() -> void:
	for child in get_children():
		if child.name == "AuditWall":
			child.queue_free()


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(label)
