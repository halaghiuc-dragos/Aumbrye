extends Area3D
class_name HubInteractable

## Reusable hub interact zone — press E / gamepad to trigger (HUB-4.1).

signal player_entered
signal player_exited
signal interacted

@export var prompt_text: String = "Interact (E)"
@export var interact_id: String = ""
@export var enabled: bool = true
@export var enter_sound: StringName = &"ui_interact_near"
@export var highlight_target: NodePath

var _near_player := false
var _highlight_node: Node3D
var _highlight_tween: Tween
var _base_emission: float = 1.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	call_deferred("_finalize_setup")


func _finalize_setup() -> void:
	if interact_id.is_empty():
		push_warning("HubInteractable: empty interact_id on %s" % get_path())
		set_enabled(false)
		return
	if not enabled:
		set_enabled(false)
	_resolve_highlight_target()


func is_player_near() -> bool:
	return _near_player and enabled


func get_prompt() -> String:
	return prompt_text


func get_interact_id() -> String:
	return interact_id


func trigger_interact() -> void:
	interacted.emit()


func set_enabled(value: bool) -> void:
	enabled = value
	monitoring = value
	monitorable = value
	if not value:
		_near_player = false
		_stop_highlight()


func _resolve_highlight_target() -> void:
	if highlight_target.is_empty():
		return
	_highlight_node = get_node_or_null(highlight_target) as Node3D


func _on_body_entered(body: Node3D) -> void:
	if not enabled:
		return
	if body.is_in_group("player"):
		_near_player = true
		if enter_sound != StringName():
			AudioDirector.play_sfx(str(enter_sound), global_position)
		_start_highlight()
		player_entered.emit()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = false
		_stop_highlight()
		player_exited.emit()


func _start_highlight() -> void:
	if _highlight_node == null:
		return
	_stop_highlight()
	var mesh := _highlight_node as MeshInstance3D
	if mesh == null:
		for child in _highlight_node.get_children():
			if child is MeshInstance3D:
				mesh = child
				break
	if mesh == null:
		return
	var mat := mesh.material_override
	if mat == null:
		return
	mat = mat.duplicate()
	mesh.material_override = mat
	if mat is ShaderMaterial:
		_base_emission = float(mat.get_shader_parameter("emission_energy"))
	elif mat is StandardMaterial3D:
		_base_emission = mat.emission_energy_multiplier
	_highlight_tween = create_tween()
	_highlight_tween.set_loops()
	_highlight_tween.tween_method(
		_apply_highlight_energy, _base_emission, _base_emission * 1.45, 0.55
	)
	_highlight_tween.tween_method(
		_apply_highlight_energy, _base_emission * 1.45, _base_emission, 0.55
	)


func _apply_highlight_energy(value: float) -> void:
	if _highlight_node == null:
		return
	var mesh := _highlight_node as MeshInstance3D
	if mesh == null:
		return
	var mat := mesh.material_override
	if mat == null:
		return
	if mat is ShaderMaterial:
		mat.set_shader_parameter("emission_energy", value)
	elif mat is StandardMaterial3D:
		mat.emission_energy_multiplier = value


func _stop_highlight() -> void:
	if _highlight_tween != null and _highlight_tween.is_valid():
		_highlight_tween.kill()
	_highlight_tween = null
	if _highlight_node == null:
		return
	var mesh := _highlight_node as MeshInstance3D
	if mesh == null:
		return
	var mat := mesh.material_override
	if mat == null:
		return
	_apply_highlight_energy(_base_emission)
