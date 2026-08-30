extends Node3D

## The tell before a wave arrives. A pulsing ring on the ground where something is about to stand,
## so the player can turn, reposition, or decide to meet it — the arena mode's whole readability
## rests on never being surprised from behind.

const RING_INNER := 0.75
const RING_OUTER := 1.35
const PULSE_HZ := 3.2
const BASE_ENERGY := 1.4
const PULSE_ENERGY := 2.6

var _material: StandardMaterial3D
var _elapsed := 0.0


func setup(tint: Color = Color(0.72, 0.45, 0.95)) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Ring"
	var torus := TorusMesh.new()
	torus.inner_radius = RING_INNER
	torus.outer_radius = RING_OUTER
	torus.rings = 24
	torus.ring_segments = 8
	mesh.mesh = torus
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


func _process(delta: float) -> void:
	if _material == null:
		return
	_elapsed += delta
	var pulse := (sin(_elapsed * PULSE_HZ * TAU) + 1.0) * 0.5
	_material.emission_energy_multiplier = lerpf(BASE_ENERGY, PULSE_ENERGY, pulse)
	_material.albedo_color.a = lerpf(0.45, 0.9, pulse)
