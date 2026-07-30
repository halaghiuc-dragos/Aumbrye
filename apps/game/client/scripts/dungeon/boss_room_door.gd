extends Node3D

## Boss arena door — press E to open, then cross the thin barrier.

signal door_opened
signal door_sealed

var _barrier: StaticBody3D
var _barrier_shape: CollisionShape3D
var _barrier_mesh: MeshInstance3D
var _interact_area: Area3D
var _label: Label3D
var _near_player := false
var _opened := false
var _sealed := false


func _ready() -> void:
	_barrier = get_node("Barrier") as StaticBody3D
	_barrier_shape = _barrier.get_node("BarrierShape") as CollisionShape3D
	_barrier_mesh = _barrier.get_node_or_null("MeshInstance3D") as MeshInstance3D
	_interact_area = get_node("InteractArea") as Area3D
	_label = get_node("Label3D") as Label3D
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_interact_area.body_entered.connect(_on_body_entered)
	_interact_area.body_exited.connect(_on_body_exited)
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _near_player:
		return
	if _sealed:
		return
	if not _opened:
		open_door()
		get_viewport().set_input_as_handled()


func is_opened() -> bool:
	return _opened


func is_sealed() -> bool:
	return _sealed


func open_door() -> void:
	if _opened:
		return
	_opened = true
	_barrier_shape.disabled = true
	if _barrier_mesh:
		_barrier_mesh.visible = false
	_update_label()
	door_opened.emit()


func seal_door() -> void:
	if _sealed:
		return
	_sealed = true
	_opened = false
	_barrier_shape.disabled = false
	if _barrier_mesh:
		_barrier_mesh.visible = true
	_update_label()
	door_sealed.emit()


func release_door() -> void:
	_sealed = false
	_opened = true
	_barrier_shape.disabled = true
	if _barrier_mesh:
		_barrier_mesh.visible = false
	_label.visible = false


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = true
		_update_label()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = false
		_update_label()


func _update_label() -> void:
	if _opened or _sealed or not _near_player:
		_label.visible = false
		return
	_label.text = "Press E"
	_label.visible = true
