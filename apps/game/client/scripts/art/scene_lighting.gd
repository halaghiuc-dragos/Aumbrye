class_name SceneLighting
extends RefCounted

## Shared world lighting presets for hub, arena, and other dressed scenes.


static func apply_hub(root: Node3D) -> void:
	_apply_preset(
		root,
		{
			"background": Color(0.52, 0.44, 0.38),
			"ambient": Color(0.72, 0.58, 0.42),
			"ambient_energy": 0.58,
			"fog_color": Color(0.68, 0.52, 0.38),
			"fog_density": 0.018,
			"fog_aerial": 0.35,
			"sun_color": Color(1.0, 0.86, 0.62),
			"sun_energy": 1.42,
			"sun_rotation": Vector3(-0.45, 0.35, 0.0),
			"fill_color": Color(0.58, 0.68, 0.88),
			"fill_energy": 0.24,
			"fill_rotation": Vector3(-0.25, -2.1, 0.0),
		}
	)


static func apply_arena(root: Node3D) -> void:
	_apply_preset(
		root,
		{
			"background": Color(0.36, 0.4, 0.5),
			"ambient": Color(0.64, 0.6, 0.72),
			"ambient_energy": 0.54,
			"fog_color": Color(0.46, 0.5, 0.6),
			"fog_density": 0.011,
			"fog_aerial": 0.42,
			"sun_color": Color(0.96, 0.9, 0.78),
			"sun_energy": 1.58,
			"sun_rotation": Vector3(-0.52, 0.65, 0.0),
			"fill_color": Color(0.72, 0.78, 0.96),
			"fill_energy": 0.3,
			"fill_rotation": Vector3(-0.2, -1.35, 0.0),
		}
	)


static func _apply_preset(root: Node3D, preset: Dictionary) -> void:
	var env_node := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node == null:
		env_node = WorldEnvironment.new()
		env_node.name = "WorldEnvironment"
		root.add_child(env_node)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = preset.get("background", Color(0.45, 0.48, 0.55))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = preset.get("ambient", Color(0.6, 0.58, 0.55))
	env.ambient_light_energy = float(preset.get("ambient_energy", 0.5))
	env.fog_enabled = true
	env.fog_light_color = preset.get("fog_color", Color(0.55, 0.55, 0.6))
	env.fog_density = float(preset.get("fog_density", 0.015))
	env.fog_aerial_perspective = float(preset.get("fog_aerial", 0.35))
	PixelDioramaSettings.configure_environment(env)
	env.glow_enabled = true
	env_node.environment = env

	var sun := root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "DirectionalLight3D"
		root.add_child(sun)
	sun.light_color = preset.get("sun_color", Color.WHITE)
	sun.light_energy = float(preset.get("sun_energy", 1.3))
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 48.0
	var sun_rot: Vector3 = preset.get("sun_rotation", Vector3(-0.45, 0.35, 0.0))
	sun.rotation = sun_rot

	var fill := root.get_node_or_null("FillLight") as DirectionalLight3D
	if fill == null:
		fill = DirectionalLight3D.new()
		fill.name = "FillLight"
		root.add_child(fill)
	fill.light_color = preset.get("fill_color", Color(0.65, 0.72, 0.9))
	fill.light_energy = float(preset.get("fill_energy", 0.22))
	fill.shadow_enabled = false
	var fill_rot: Vector3 = preset.get("fill_rotation", Vector3(-0.25, -2.0, 0.0))
	fill.rotation = fill_rot
