extends Node3D

## The tell before a wave arrives. A pulsing ring on the ground where something is about to stand,
## so the player can turn, reposition, or decide to meet it — the arena mode's whole readability
## rests on never being surprised from behind.

const RING_INNER := 0.75
const RING_OUTER := 1.35
const PULSE_HZ := 3.2
const BASE_ENERGY := 1.4
const PULSE_ENERGY := 2.6

static var _shared_ring_mesh: TorusMesh
static var _shared_role_meshes: Dictionary = {}

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
	mesh.mesh = _get_shared_ring_mesh()
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
	_role_icon.mesh = _get_shared_role_mesh(key)
	if _icon_material:
		_icon_material.albedo_color = tint
		_icon_material.emission = tint
	_role_icon.visible = true


static func _get_shared_role_mesh(role: String) -> Mesh:
	if _shared_role_meshes.has(role):
		return _shared_role_meshes[role] as Mesh
	var mesh: Mesh
	match role:
		"ranged":
			var orb := SphereMesh.new()
			orb.radius = 0.32
			orb.height = 0.64
			orb.radial_segments = 6
			orb.rings = 3
			mesh = orb
		"fast":
			var spike := PrismMesh.new()
			spike.size = Vector3(0.62, 0.8, 0.46)
			mesh = spike
		"control":
			var guard := BoxMesh.new()
			guard.size = Vector3(0.72, 0.62, 0.28)
			mesh = guard
		"boss":
			var crown := SphereMesh.new()
			crown.radius = 0.48
			crown.height = 0.78
			crown.radial_segments = 5
			crown.rings = 2
			mesh = crown
		_:
			var blade := CapsuleMesh.new()
			blade.radius = 0.22
			blade.height = 0.82
			mesh = blade
	_shared_role_meshes[role] = mesh
	return mesh


static func _get_shared_ring_mesh() -> TorusMesh:
	if _shared_ring_mesh == null:
		_shared_ring_mesh = TorusMesh.new()
		_shared_ring_mesh.inner_radius = RING_INNER
		_shared_ring_mesh.outer_radius = RING_OUTER
		_shared_ring_mesh.rings = 24
		_shared_ring_mesh.ring_segments = 8
	return _shared_ring_mesh


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
