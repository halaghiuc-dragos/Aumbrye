extends Node3D

## Swamp cleanse window — safe zone during poison phase (BOSS-5.2).

@export var cleanse_duration := 4.0
@export var cleanse_radius := 2.5

@onready var _zone_mesh: MeshInstance3D = $ZoneMesh

var _timer := 0.0


func _ready() -> void:
	_timer = cleanse_duration


func _physics_process(delta: float) -> void:
	_timer -= delta
	_clear_poison_on_player()
	if _timer <= 0.0:
		queue_free()
	elif _zone_mesh:
		var alpha := clampf(_timer / cleanse_duration, 0.2, 1.0)
		var mat := _zone_mesh.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			mat = mat.duplicate()
			mat.albedo_color.a = alpha * 0.5
			_zone_mesh.set_surface_override_material(0, mat)


func is_cleanse_active() -> bool:
	return _timer > 0.0


func _clear_poison_on_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var offset := player.global_position - global_position
	offset.y = 0.0
	if offset.length() > cleanse_radius:
		return
	var status_ctrl := player.get_node_or_null("StatusController") as StatusController
	if status_ctrl:
		for entry in status_ctrl.get_active_statuses():
			if entry.get("id", "") == "poison":
				status_ctrl.clear_all()
				return
