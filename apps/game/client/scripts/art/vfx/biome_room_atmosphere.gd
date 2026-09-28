extends RefCounted
class_name BiomeRoomAtmosphere

static var _sprite_cache: Dictionary = {}

## A room-scale foreground layer.  The low particle count is intentional: it makes each realm
## feel active at the pixel scale without turning combat space into visual fog.
static func attach(parent: Node3D, biome_id: String, half_w: float, half_d: float) -> void:
	if parent == null or parent.get_node_or_null("BiomeForeground") != null:
		return
	if PixelDioramaSettings.particle_quality <= 0:
		return
	var profile := _profile_for(biome_id)
	var motes := GPUParticles3D.new()
	motes.name = "BiomeForeground"
	motes.amount = maxi(6, int(float(profile["amount"]) * PixelDioramaSettings.particle_amount_scale()))
	motes.lifetime = float(profile["lifetime"])
	motes.randomness = 0.8
	motes.one_shot = false
	motes.emitting = true
	motes.visibility_aabb = AABB(
		Vector3(-half_w, -0.4, -half_d), Vector3(half_w * 2.0, 5.5, half_d * 2.0)
	)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(half_w * 0.92, 0.3, half_d * 0.92)
	process.direction = profile["direction"]
	process.spread = float(profile["spread"])
	process.gravity = profile["gravity"]
	process.initial_velocity_min = float(profile["speed_min"])
	process.initial_velocity_max = float(profile["speed_max"])
	process.scale_min = float(profile["scale_min"])
	process.scale_max = float(profile["scale_max"])
	process.color = profile["color"]
	motes.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(float(profile["quad_size"]), float(profile["quad_size"]))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.disable_receive_shadows = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# The old untextured quads read as soft modern particles.  A tiny nearest-filtered image makes
	# every mote a deliberate pixel glyph: snow, ash, spores and crystal shards stay legible at the
	# diorama scale instead of dissolving into generic glow.
	material.albedo_texture = _pixel_sprite(str(profile["sprite"]))
	quad.material = material
	motes.draw_pass_1 = quad
	parent.add_child(motes)


static func _profile_for(biome_id: String) -> Dictionary:
	match biome_id:
		"crystal_caverns", "prism_depths":
			return _profile(Color(0.44, 0.82, 1.0, 0.34), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.18, 0.0), 14, 4.4, 0.12, 0.34, 0.025, 0.06, 0.1, 0.28, "shard")
		"poison_swamp", "venom_mire":
			return _profile(Color(0.5, 0.92, 0.34, 0.22), Vector3(0.12, 0.35, 0.08), Vector3(0.05, 0.04, 0.02), 18, 5.8, 0.1, 0.28, 0.05, 0.13, 0.1, 0.36, "spore")
		"frozen_fortress", "glacial_hollow":
			return _profile(Color(0.82, 0.94, 1.0, 0.38), Vector3(0.38, -0.12, 0.12), Vector3(0.08, -0.1, 0.04), 20, 4.2, 0.18, 0.48, 0.035, 0.09, 0.2, 0.4, "snow")
		"iron_vault":
			return _profile(Color(1.0, 0.46, 0.16, 0.26), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.26, 0.0), 10, 3.5, 0.22, 0.6, 0.025, 0.06, 0.08, 0.24, "spark")
		"dark_cathedral", "umbral_chapel":
			return _profile(Color(0.7, 0.52, 1.0, 0.22), Vector3(-0.05, 0.68, 0.08), Vector3(-0.02, 0.09, 0.02), 13, 5.0, 0.08, 0.26, 0.045, 0.11, 0.13, 0.32, "mote")
		_:
			return _profile(Color(1.0, 0.52, 0.2, 0.2), Vector3(0.02, 0.9, 0.02), Vector3(0.0, 0.18, 0.0), 12, 4.6, 0.12, 0.36, 0.03, 0.08, 0.1, 0.3, "ash")


static func _profile(color: Color, direction: Vector3, gravity: Vector3, amount: int, lifetime: float, speed_min: float, speed_max: float, scale_min: float, scale_max: float, quad_size: float, spread: float, sprite: String) -> Dictionary:
	return {
		"color": color, "direction": direction, "gravity": gravity, "amount": amount,
		"lifetime": lifetime, "speed_min": speed_min, "speed_max": speed_max,
		"scale_min": scale_min, "scale_max": scale_max, "quad_size": quad_size, "spread": spread, "sprite": sprite,
	}


static func _pixel_sprite(kind: String) -> ImageTexture:
	if _sprite_cache.has(kind):
		return _sprite_cache[kind] as ImageTexture
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for x in range(8):
		for y in range(8):
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.0))
	var pixels: Array[Vector2i] = []
	match kind:
		"shard": pixels = [Vector2i(3, 1), Vector2i(4, 1), Vector2i(2, 3), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 3), Vector2i(3, 4), Vector2i(4, 4), Vector2i(3, 6), Vector2i(4, 6)]
		"spore": pixels = [Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(3, 4), Vector2i(4, 4), Vector2i(3, 5), Vector2i(4, 5)]
		"snow": pixels = [Vector2i(3, 1), Vector2i(4, 1), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(3, 5), Vector2i(4, 5)]
		"spark": pixels = [Vector2i(5, 1), Vector2i(4, 2), Vector2i(3, 3), Vector2i(4, 3), Vector2i(2, 4), Vector2i(3, 4), Vector2i(2, 5)]
		"mote": pixels = [Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(3, 4), Vector2i(4, 4), Vector2i(3, 5), Vector2i(4, 5)]
		_: pixels = [Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(3, 4), Vector2i(4, 4)]
	for pixel in pixels:
		image.set_pixelv(pixel, Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	_sprite_cache[kind] = texture
	return texture
