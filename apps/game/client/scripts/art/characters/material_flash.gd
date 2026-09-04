extends RefCounted
class_name MaterialFlash


const FLASH_PARAM := &"flash_amount"
const FLASH_COLOR_PARAM := &"flash_color"
const FLASH_EMISSION_PARAM := &"flash_emission"
const FLASH_DURATION := 0.25
const DEFAULT_FLASH_EMISSION := 1.6
const RAMP_IN := 0.03
const CRIT_HOLD := 0.04
const DEFAULT_FALLOFF := 1.2
const MIN_LOCAL_STRENGTH := 0.35

const META_ACTIVE_TWEEN := &"material_flash_tween"

const PHASE_GLOW_ENERGY_PARAM := &"phase_glow_energy"
const PHASE_GLOW_COLOR_PARAM := &"phase_glow_color"

const FLASH_TINTS: Dictionary = {
	"physical": Color.WHITE,
	"fire": Color(1.0, 0.72, 0.42),
	"frost": Color(0.72, 0.90, 1.0),
	"poison": Color(0.78, 1.0, 0.62),
	"lightning": Color(1.0, 0.94, 0.55),
	"arcane": Color(0.86, 0.72, 1.0),
}

## The world-space damage-type cue, and the only one with a colourblind path — the floating
## number has its own, and `emphasise_telegraph_tint` deliberately preserves hue.
static func tint_for_damage_type(damage_type: String) -> Color:
	if AccessibilitySettings and AccessibilitySettings.colorblind_mode != "default":
		return AccessibilitySettings.get_damage_color(damage_type)
	return FLASH_TINTS.get(damage_type, Color.WHITE)


static var _shader_uniform_cache: Dictionary = {}


static func flash(node: Node3D, params: Variant = null) -> void:
	if node == null or not is_instance_valid(node):
		return
	var p := _normalize_params(params)
	for mesh in gather_meshes(node):
		_flash_mesh(mesh, p)


static func cancel(mesh: MeshInstance3D) -> void:
	if mesh == null or not is_instance_valid(mesh):
		return
	if mesh.has_meta(META_ACTIVE_TWEEN):
		var active_tween := mesh.get_meta(META_ACTIVE_TWEEN) as Tween
		if active_tween and active_tween.is_valid():
			active_tween.kill()
		mesh.remove_meta(META_ACTIVE_TWEEN)
	if _mesh_shader(mesh) != null:
		mesh.set_instance_shader_parameter(FLASH_PARAM, 0.0)


static func restore_all(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	for mesh in gather_meshes(node):
		cancel(mesh)
	clear_persistent_glow(node)


## `BS-03`: an onEnter `"emissive"` phase visual. Unlike `flash()`, this never tweens back down --
## it stays until the next phase overrides it or `clear_persistent_glow()` is called -- so a boss's
## escalating phases keep glowing through every hit-flash `flash()` plays on top of it.
static func set_persistent_glow(node: Node3D, color: Color, energy: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	for mesh in gather_meshes(node):
		if _mesh_shader(mesh) == null:
			continue
		var shader := _mesh_shader(mesh)
		if _shader_declares(shader, PHASE_GLOW_COLOR_PARAM):
			mesh.set_instance_shader_parameter(PHASE_GLOW_COLOR_PARAM, Vector3(color.r, color.g, color.b))
		if _shader_declares(shader, PHASE_GLOW_ENERGY_PARAM):
			mesh.set_instance_shader_parameter(PHASE_GLOW_ENERGY_PARAM, maxf(0.0, energy))


static func clear_persistent_glow(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	for mesh in gather_meshes(node):
		if _mesh_shader(mesh) != null:
			mesh.set_instance_shader_parameter(PHASE_GLOW_ENERGY_PARAM, 0.0)


static func _normalize_params(params: Variant) -> Dictionary:
	var out := {
		"strength": 1.0,
		"tint": Color.WHITE,
		"duration": FLASH_DURATION,
		"blocked": false,
		"crit": false,
		"epicenter": Vector3.ZERO,
		"falloff": DEFAULT_FALLOFF,
	}
	if params == null:
		return out
	if params is float:
		out["strength"] = float(params)
		return out
	if params is Dictionary:
		for key in params.keys():
			out[key] = params[key]
		return out
	return out


## Every MeshInstance3D under a node, including the node itself. Shared with `material_dissolve`.
static func gather_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(gather_meshes(child))
	return out


static func _mesh_shader(mesh: MeshInstance3D) -> Shader:
	var mat := mesh.material_override as ShaderMaterial
	if mat == null:
		mat = mesh.get_active_material(0) as ShaderMaterial
	if mat == null or mat.shader == null:
		return null
	if not _shader_declares(mat.shader, FLASH_PARAM):
		return null
	return mat.shader


static func _flash_mesh(mesh: MeshInstance3D, params: Dictionary) -> void:
	if mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		return

	var shader := _mesh_shader(mesh)
	if shader == null:
		return

	if not mesh.is_inside_tree():
		return
	var tree := mesh.get_tree()

	cancel(mesh)

	var strength := clampf(float(params.get("strength", 1.0)), 0.0, 1.0)
	if bool(params.get("blocked", false)):
		strength *= 0.5
	var epicenter: Vector3 = params.get("epicenter", Vector3.ZERO)
	if epicenter != Vector3.ZERO:
		var falloff := maxf(0.01, float(params.get("falloff", DEFAULT_FALLOFF)))
		var dist := mesh.global_position.distance_to(epicenter)
		strength *= clampf(1.0 - dist / falloff, MIN_LOCAL_STRENGTH, 1.0)
	if strength <= 0.0:
		return

	var tint: Color = params.get("tint", Color.WHITE)
	var duration := maxf(0.05, float(params.get("duration", FLASH_DURATION)))
	var crit := bool(params.get("crit", false))

	mesh.set_instance_shader_parameter(FLASH_PARAM, 0.0)
	if _shader_declares(shader, FLASH_COLOR_PARAM):
		mesh.set_instance_shader_parameter(FLASH_COLOR_PARAM, Vector3(tint.r, tint.g, tint.b))
	if _shader_declares(shader, FLASH_EMISSION_PARAM):
		mesh.set_instance_shader_parameter(FLASH_EMISSION_PARAM, DEFAULT_FLASH_EMISSION)

	var tween := tree.create_tween()
	mesh.set_meta(META_ACTIVE_TWEEN, tween)
	tween.tween_method(
		func(v: float) -> void:
			if is_instance_valid(mesh):
				mesh.set_instance_shader_parameter(FLASH_PARAM, v),
		0.0,
		strength,
		RAMP_IN
	)
	if crit:
		tween.tween_interval(CRIT_HOLD)
	tween.tween_method(
		func(v: float) -> void:
			if is_instance_valid(mesh):
				mesh.set_instance_shader_parameter(FLASH_PARAM, v),
		strength,
		0.0,
		duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(
		func() -> void:
			if not is_instance_valid(mesh):
				return
			mesh.set_instance_shader_parameter(FLASH_PARAM, 0.0)
			mesh.remove_meta(META_ACTIVE_TWEEN)
	)


static func _shader_declares(shader: Shader, uniform_name: StringName) -> bool:
	if shader == null:
		return false
	var path := shader.resource_path
	if path.is_empty():
		return false
	if not _shader_uniform_cache.has(path):
		var names: Array[StringName] = []
		for entry in shader.get_shader_uniform_list():
			names.append(entry.get("name", &""))
		_shader_uniform_cache[path] = names
	var uniforms: Array = _shader_uniform_cache[path]
	return uniform_name in uniforms
