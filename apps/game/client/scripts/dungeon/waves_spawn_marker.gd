extends Node3D

## The tell before a wave arrives. A pulsing ring on the ground where something is about to stand,
## so the player can turn, reposition, or decide to meet it — the arena mode's whole readability
## rests on never being surprised from behind.

const PULSE_HZ := 3.2
const BASE_ENERGY := 1.4
const PULSE_ENERGY := 2.6

var _material: StandardMaterial3D
var _icon_material: StandardMaterial3D
var _role_icon: MeshInstance3D
var _role_icon_key := ""
var _elapsed := 0.0
var _remaining := 0.0
var _countdown: Label3D


func setup(
	tint: Color = Color(0.72, 0.45, 0.95), duration: float = 0.0, role: String = "melee"
) -> void:
	_elapsed = 0.0
	_remaining = maxf(0.0, duration)
	if _material != null:
		visible = true
		set_process(true)
		_material.albedo_color = tint
		_material.albedo_color.a = 0.75
		_material.emission = tint
		_material.emission_energy_multiplier = BASE_ENERGY
		_set_role_icon(role, tint)
		if _countdown != null:
			_countdown.modulate = tint
		_update_countdown()
		return
	var mesh := MeshInstance3D.new()
	mesh.name = "Ring"
	mesh.mesh = PropLibrary.bare_mesh("waves/marker_ring")
	_material = StandardMaterial3D.new()
	_material.albedo_color = tint
	_material.emission_enabled = true
	_material.emission = tint
	_material.emission_energy_multiplier = BASE_ENERGY
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color.a = 0.75
	mesh.material_override = _material
	mesh.position.y = 0.06
	add_child(mesh)
	_role_icon = MeshInstance3D.new()
	_role_icon.name = "RoleIcon"
	_role_icon.position.y = 0.78
	_icon_material = StandardMaterial3D.new()
	_icon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_icon_material.emission_enabled = true
	_icon_material.emission_energy_multiplier = 1.8
	_role_icon.material_override = _icon_material
	add_child(_role_icon)
	_set_role_icon(role, tint)
	_countdown = Label3D.new()
	_countdown.name = "Countdown"
	_countdown.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_countdown.font_size = 48
	_countdown.outline_size = 8
	_countdown.modulate = tint
	_countdown.position = Vector3(0.0, 1.45, 0.0)
	add_child(_countdown)
	_update_countdown()


func deactivate() -> void:
	_remaining = 0.0
	visible = false
	set_process(false)


func _set_role_icon(role: String, tint: Color) -> void:
	if _role_icon == null:
		return
	var key := role if role in ["melee", "ranged", "fast", "control", "boss"] else "melee"
	_role_icon_key = key
	_role_icon.mesh = PropLibrary.bare_mesh("waves/marker_%s" % key)
	if _icon_material:
		_icon_material.albedo_color = tint
		_icon_material.emission = tint
	_role_icon.visible = true


func _process(delta: float) -> void:
	if _material == null:
		return
	_elapsed += delta
	_remaining = maxf(0.0, _remaining - delta)
	_update_countdown()
	var pulse := (sin(_elapsed * PULSE_HZ * TAU) + 1.0) * 0.5
	_material.emission_energy_multiplier = lerpf(BASE_ENERGY, PULSE_ENERGY, pulse)
	_material.albedo_color.a = lerpf(0.45, 0.9, pulse)


func _update_countdown() -> void:
	if _countdown == null:
		return
	_countdown.text = "%.1f" % _remaining
