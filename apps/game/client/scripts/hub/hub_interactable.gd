extends Area3D
class_name HubInteractable


signal player_entered
signal player_exited
signal interacted

@export var display_name: String = "Interact"
@export var interact_id: String = ""
@export var enabled: bool = true
@export var enter_sound: StringName = &"ui_interact_near"
@export var highlight_target: NodePath
@export var label_path: NodePath

var _near_player := false
var _label: Label3D
var _highlight_node: Node3D
var _highlight_tween: Tween
const EMISSION_PARAM := &"emission_energy"
const FALLBACK_EMISSION := 1.6

var _base_emission: float = FALLBACK_EMISSION


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
	_resolve_label()
	_refresh_label()


func is_player_near() -> bool:
	return _near_player and enabled


func get_prompt() -> String:
	return "%s (%s)" % [display_name, interact_glyph()]


static func interact_glyph() -> String:
	var glyph := InputGlyphService.get_action_glyph("interact")
	return glyph if glyph != "" else "E"


func set_display_name(value: String) -> void:
	display_name = value
	_refresh_label()


func _resolve_label() -> void:
	if not label_path.is_empty():
		_label = get_node_or_null(label_path) as Label3D
	if _label != null:
		return
	var host := get_parent()
	if host == null:
		return
	for child in host.get_children():
		if child is Label3D:
			_label = child as Label3D
			return


func _refresh_label() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	_label.text = get_prompt() if is_player_near() else display_name


func get_interact_id() -> String:
	return interact_id


func get_focus_position() -> Vector3:
	for child in get_children():
		var shape := child as CollisionShape3D
		if shape != null:
			return shape.global_position
	return global_position


func trigger_interact() -> void:
	interacted.emit()


func set_enabled(value: bool) -> void:
	enabled = value
	monitoring = value
	monitorable = value
	if not value:
		_near_player = false
		_stop_highlight()
	_refresh_label()


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
		_refresh_label()
		player_entered.emit()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = false
		_stop_highlight()
		_refresh_label()
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
		_base_emission = _shader_emission_energy(mat as ShaderMaterial)
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


static func _shader_emission_energy(mat: ShaderMaterial) -> float:
	var value: Variant = mat.get_shader_parameter(EMISSION_PARAM)
	if value == null and mat.shader != null:
		value = RenderingServer.shader_get_parameter_default(mat.shader.get_rid(), EMISSION_PARAM)
	if value == null:
		return FALLBACK_EMISSION
	return float(value)


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
		mat.set_shader_parameter(EMISSION_PARAM, value)
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
