extends Node3D

const SHADER_PATH := "res://assets/shared/pixel_diorama_surface.gdshader"

const MINIMAL := """
shader_type spatial;
void fragment() { ALBEDO = vec3(0.62, 0.56, 0.5); }
"""

const MINIMAL_LIGHT := """
shader_type spatial;
void fragment() { ALBEDO = vec3(0.62, 0.56, 0.5); }
void light() { DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0) / PI; }
"""

const SPEC_OFF := """
shader_type spatial;
render_mode specular_disabled;
void fragment() { ALBEDO = vec3(0.62, 0.56, 0.5); ROUGHNESS = 1.0; METALLIC = 0.0; SPECULAR = 0.0; }
"""


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.7, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	if OS.has_environment("PROBE_TUNE"):
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 24.0
		sun.shadow_bias = 0.01
		sun.shadow_normal_bias = 0.2
	add_child(sun)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 9.0, 14.0)
	cam.rotation = Vector3(-0.5, 0.0, 0.0)
	cam.current = true
	add_child(cam)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.1, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.05
	env_node.environment = env
	add_child(env_node)

	var mat := _standard_material() if OS.has_environment("PROBE_STD") else _project_material()
	var wide := OS.has_environment("PROBE_WIDE")
	var cols := 25 if wide else 3
	var rows := 20 if wide else 8
	_build_field(mat, cols, rows)


func _project_material() -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	mat.set_shader_parameter("color_base", Color(0.62, 0.56, 0.5))
	mat.set_shader_parameter("color_shadow", Color(0.42, 0.38, 0.34))
	mat.set_shader_parameter("color_accent", Color(0.8, 0.6, 0.3))
	mat.set_shader_parameter("surface_kind", 0)
	return mat


func _code_material(code: String) -> Material:
	var shader := Shader.new()
	shader.code = code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func _standard_material() -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.56, 0.5)
	return mat


func _build_field(mat: Material, cols: int, rows: int) -> void:
	var origin_x := -cols * 1.0 + 1.0
	var origin_z := -rows * 1.0 + 1.0
	for row in rows:
		for col in cols:
			var tile := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(1.96, 0.12, 1.96)
			tile.mesh = box
			tile.material_override = mat
			tile.position = Vector3(origin_x + col * 2.0, 0.06, origin_z + row * 2.0)
			if OS.has_environment("PROBE_NOCAST"):
				tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(tile)
	for i in 3:
		var caster := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(1.0, 3.0, 1.0)
		caster.mesh = cbox
		caster.material_override = mat
		caster.position = Vector3(-4.0 + i * 4.0, 1.6, 0.0)
		add_child(caster)
