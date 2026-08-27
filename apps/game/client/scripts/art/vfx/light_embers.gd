extends RefCounted
class_name LightEmbers


const DEFAULT_COUNT := 7

const NODE_NAME := "LightEmbers"

static var _cache: Dictionary = {}


static func attach(
	parent: Node3D,
	pos: Vector3,
	tint: Color,
	count_scale: float = 1.0,
	spread_scale: float = 1.0
) -> GPUParticles3D:
	if PixelDioramaSettings.particle_quality <= 0:
		return null
	var assets := _assets(tint, spread_scale)
	var embers := GPUParticles3D.new()
	embers.name = NODE_NAME
	embers.position = pos
	embers.amount = maxi(
		2,
		int(DEFAULT_COUNT * count_scale * PixelDioramaSettings.particle_amount_scale())
	)
	embers.lifetime = 2.4
	embers.randomness = 0.7
	var reach := 0.8 * spread_scale
	embers.visibility_aabb = AABB(
		Vector3(-reach, -0.4, -reach), Vector3(reach * 2.0, 3.2 * spread_scale, reach * 2.0)
	)
	embers.draw_pass_1 = assets["mesh"]
	embers.process_material = assets["process"]
	parent.add_child(embers)
	return embers


static func clear_cache() -> void:
	_cache.clear()


const WIND_RESPONSE := 0.85

const HEAT_LIFT := 0.28


static func drive_wind(wind: Vector3) -> void:
	var gravity := Vector3(wind.x, 0.0, wind.z) * WIND_RESPONSE + Vector3(0.0, HEAT_LIFT, 0.0)
	for assets in _cache.values():
		var mat: ParticleProcessMaterial = assets["process"]
		mat.gravity = gravity


static func _assets(tint: Color, spread_scale: float) -> Dictionary:
	var key := "%s_%.2f" % [tint.to_html(false), spread_scale]
	if _cache.has(key):
		return _cache[key]
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.05, 0.05, 0.05) * spread_scale
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.11 * spread_scale
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 22.0
	mat.initial_velocity_min = 0.35
	mat.initial_velocity_max = 0.85
	mat.gravity = Vector3(0.0, HEAT_LIFT, 0.0)
	mat.damping_min = 0.2
	mat.damping_max = 0.6
	mat.scale_min = 0.5
	mat.scale_max = 1.1
	var ramp := Gradient.new()
	ramp.set_color(0, Color(tint.r, tint.g, tint.b, 0.95))
	ramp.set_color(1, Color(tint.r * 0.6, tint.g * 0.25, tint.b * 0.1, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	var ember_mat := StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.vertex_color_use_as_albedo = true
	ember_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ember_mat.disable_receive_shadows = true
	ember_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	chunk.material = ember_mat
	var assets := {"mesh": chunk, "process": mat}
	_cache[key] = assets
	return assets
