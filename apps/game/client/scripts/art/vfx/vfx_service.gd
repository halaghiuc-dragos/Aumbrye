extends Node

## Global one-shot combat and locomotion particle bursts (hub, dungeon, arena).

const FOOTSTEP_INTERVAL_WALK := 0.42
const FOOTSTEP_INTERVAL_SPRINT := 0.28
const BURST_POOL_SIZE := 16
const GPU_BURST_POOL_SIZE := 8
const DECAL_POOL_SIZE := 12

const _COMBAT_BURST := {
	"amount": 28,
	"lifetime": 0.34,
	"explosiveness": 0.9,
	"spread": 34.0,
	"velocity_min": 2.4,
	"velocity_max": 4.8,
	"gravity": Vector3(0.0, -5.0, 0.0),
	"scale_min": 0.12,
	"scale_max": 0.22,
}

const TRAIL_ARC_DEGREES := 150.0
const TRAIL_LIFETIME := 0.24

var _root: Node3D
var _foot_alt := false
var _chunk_mesh: BoxMesh
var _burst_pool: Array[CPUParticles3D] = []
var _gpu_burst_pool: Array[GPUParticles3D] = []
var _decal_pool: Array[Decal] = []
var _blood_decal_tex: Texture2D
var _impact_decal_tex: Texture2D


func _ready() -> void:
	_root = Node3D.new()
	_root.name = "VfxRoot"
	add_child(_root)
	_blood_decal_tex = _make_decal_texture(Color(0.55, 0.08, 0.06, 0.85), 0.35)
	_impact_decal_tex = _make_decal_texture(Color(0.35, 0.32, 0.28, 0.7), 0.55)
	for i in BURST_POOL_SIZE:
		var particles := CPUParticles3D.new()
		particles.name = "BurstPool%d" % i
		particles.emitting = false
		particles.one_shot = true
		particles.mesh = _pixel_chunk_mesh()
		particles.top_level = true
		particles.visibility_aabb = AABB(Vector3(-2.0, -1.0, -2.0), Vector3(4.0, 4.0, 4.0))
		_root.add_child(particles)
		_burst_pool.append(particles)
	for i in GPU_BURST_POOL_SIZE:
		var gpu := _make_gpu_burst()
		gpu.name = "GpuBurstPool%d" % i
		_root.add_child(gpu)
		_gpu_burst_pool.append(gpu)
	for i in DECAL_POOL_SIZE:
		var decal := Decal.new()
		decal.name = "DecalPool%d" % i
		decal.top_level = true
		decal.visible = false
		_root.add_child(decal)
		_decal_pool.append(decal)


func resolve_combat_anchor(body: Node3D) -> Array:
	var forward := _resolve_forward(body)
	var pos := body.global_position + Vector3(0.0, 1.0, 0.0)
	var hitbox := body.get_node_or_null("Facing/WeaponPivot/Hitbox") as Node3D
	if hitbox:
		pos = hitbox.global_position
	else:
		var pivot := body.get_node_or_null("Facing/WeaponPivot") as Node3D
		if pivot:
			pos = pivot.global_position
		else:
			pos += -forward * 1.0
	return [pos, forward]


func play_attack_swing(world_pos: Vector3, forward: Vector3 = Vector3.FORWARD) -> void:
	_play_combat_burst("AttackSwing", world_pos, forward, Color(1.0, 0.92, 0.55, 0.98), 2.2)
	AudioDirector.play_sfx("swing", world_pos)


func play_block(world_pos: Vector3, forward: Vector3 = Vector3.FORWARD) -> void:
	_play_combat_burst("BlockSpark", world_pos, forward, Color(0.55, 0.82, 1.0, 0.92), 0.8)
	AudioDirector.play_sfx("block", world_pos)


func play_parry(world_pos: Vector3, forward: Vector3 = Vector3.FORWARD) -> void:
	_play_combat_burst("ParrySpark", world_pos, forward, Color(1.0, 0.88, 0.2, 0.95), 0.85)
	AudioDirector.play_sfx("parry", world_pos)


func play_hit_spark(world_pos: Vector3, direction: Vector3 = Vector3.UP) -> void:
	var dir := direction.normalized() if direction.length_squared() > 0.01 else Vector3.UP
	if PixelDioramaSettings.particle_quality > 0:
		_emit_gpu_burst(
			"HitSparkGpu",
			world_pos,
			dir,
			Color(1.0, 0.78, 0.35, 0.95),
			int(24 * PixelDioramaSettings.particle_amount_scale()),
			0.28
		)
	else:
		_make_burst_particles(
			"HitSpark",
			world_pos,
			{
				"amount": 24,
				"lifetime": 0.28,
				"explosiveness": 0.9,
				"spread": 42.0,
				"velocity_min": 2.2,
				"velocity_max": 4.8,
				"gravity": Vector3(0.0, -9.0, 0.0),
				"scale_min": 0.05,
				"scale_max": 0.11,
				"color": Color(1.0, 0.78, 0.35, 0.95),
				"emission": 1.0,
				"direction": dir,
				"orient_yaw": false,
			}
		)


func play_blood_decal(world_pos: Vector3, direction: Vector3 = Vector3.FORWARD) -> void:
	_spawn_decal(world_pos, direction, _blood_decal_tex, 0.42, 3.2)


func play_impact_decal(world_pos: Vector3, direction: Vector3 = Vector3.FORWARD) -> void:
	_spawn_decal(world_pos, direction, _impact_decal_tex, 0.28, 2.4)


func play_death(world_pos: Vector3, tint: Color = Color(0.85, 0.35, 0.28)) -> void:
	if PixelDioramaSettings.particle_quality > 0:
		_emit_gpu_burst(
			"DeathBurstGpu",
			world_pos + Vector3(0.0, 0.9, 0.0),
			Vector3.UP,
			Color(tint.r, tint.g, tint.b, 0.9),
			int(36 * PixelDioramaSettings.particle_amount_scale()),
			0.65
		)
		_emit_gpu_burst(
			"DeathMistGpu",
			world_pos + Vector3(0.0, 0.35, 0.0),
			Vector3.UP,
			Color(tint.r * 0.7, tint.g * 0.7, tint.b * 0.7, 0.35),
			int(14 * PixelDioramaSettings.particle_amount_scale()),
			0.9
		)
	else:
		_make_burst_particles(
			"DeathBurst",
			world_pos + Vector3(0.0, 0.9, 0.0),
			{
				"amount": 36,
				"lifetime": 0.65,
				"explosiveness": 0.95,
				"spread": 58.0,
				"velocity_min": 1.6,
				"velocity_max": 4.2,
				"gravity": Vector3(0.0, -10.0, 0.0),
				"scale_min": 0.08,
				"scale_max": 0.18,
				"color": Color(tint.r, tint.g, tint.b, 0.9),
				"emission": 0.45,
				"direction": Vector3(0.0, 1.0, 0.0),
				"orient_yaw": false,
			}
		)
		_make_burst_particles(
			"DeathMist",
			world_pos + Vector3(0.0, 0.35, 0.0),
			{
				"amount": 14,
				"lifetime": 0.9,
				"explosiveness": 0.6,
				"spread": 72.0,
				"velocity_min": 0.4,
				"velocity_max": 1.4,
				"gravity": Vector3(0.0, -2.5, 0.0),
				"scale_min": 0.14,
				"scale_max": 0.26,
				"color": Color(tint.r * 0.7, tint.g * 0.7, tint.b * 0.7, 0.35),
				"emission": 0.2,
				"direction": Vector3(0.0, 1.0, 0.0),
				"orient_yaw": false,
			}
		)
	play_blood_decal(world_pos, Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)))
	AudioDirector.play_sfx("death", world_pos)


func play_footstep(world_pos: Vector3, forward: Vector3 = Vector3.FORWARD) -> void:
	var dir := forward.normalized() if forward.length_squared() > 0.01 else Vector3(0.0, 0.0, -1.0)
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	else:
		side = side.normalized()
	var foot_side := 1.0 if _foot_alt else -1.0
	_foot_alt = not _foot_alt
	var foot_pos := world_pos + side * 0.18 * foot_side
	_make_burst_particles(
		"Footstep",
		foot_pos,
		{
			"amount": 10,
			"lifetime": 0.42,
			"explosiveness": 0.65,
			"spread": 38.0,
			"velocity_min": 0.35,
			"velocity_max": 0.95,
			"gravity": Vector3(0.0, -5.5, 0.0),
			"scale_min": 0.07,
			"scale_max": 0.13,
			"color": Color(0.72, 0.64, 0.48, 0.78),
			"emission": 0.15,
			"direction": Vector3(0.0, 1.0, 0.0),
			"flatness": 0.9,
			"orient_yaw": false,
		}
	)
	AudioDirector.play_sfx("footstep", foot_pos)


func play_weapon_trail(
	world_pos: Vector3,
	forward: Vector3 = Vector3.FORWARD,
	tint: Color = Color(1.0, 0.95, 0.72),
	radius: float = 1.05
) -> void:
	var dir := forward.normalized() if forward.length_squared() > 0.01 else Vector3(0.0, 0.0, -1.0)
	var up := Vector3.UP
	var side := dir.cross(up)
	if side.length_squared() < 0.001:
		return
	side = side.normalized()

	var trail := Node3D.new()
	trail.name = "WeaponTrail"
	trail.top_level = true
	_root.add_child(trail)
	trail.global_position = world_pos

	var mesh_instance := MeshInstance3D.new()
	var ribbon := ImmediateMesh.new()
	mesh_instance.mesh = ribbon
	mesh_instance.material_override = _make_particle_material(
		Color(tint.r, tint.g, tint.b, 0.98), 2.4
	)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.add_child(mesh_instance)

	var half_arc := deg_to_rad(TRAIL_ARC_DEGREES) * 0.5
	var segments := 14
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in segments:
		var t := float(i) / float(maxi(1, segments - 1))
		var angle := lerpf(-half_arc, half_arc, t)
		var offset := (side * sin(angle) + dir * cos(angle)) * radius - dir * radius * 0.35
		offset += up * (0.12 - absf(angle) * 0.18)
		var width := lerpf(0.16, 0.04, t)
		var alpha := lerpf(1.0, 0.25, t)
		var color := Color(tint.r, tint.g, tint.b, alpha)
		ribbon.surface_set_color(color)
		ribbon.surface_add_vertex(offset + side * width)
		ribbon.surface_add_vertex(offset - side * width)
	ribbon.surface_end()

	var fade := create_tween()
	fade.tween_property(mesh_instance, "scale", Vector3(0.35, 0.35, 0.35), TRAIL_LIFETIME)
	_schedule_free(trail, TRAIL_LIFETIME + 0.05)


## Floor glyph: outer ring, inner fill, and center marker. Shape: circle | cone | line.
func play_telegraph(world_pos: Vector3, radius: float = 1.6, duration: float = 0.6,
		tint: Color = Color(0.95, 0.34, 0.28), shape: String = "circle") -> void:
	var glyph := Node3D.new()
	glyph.name = "TelegraphGlyph"
	glyph.top_level = true
	_root.add_child(glyph)
	glyph.global_position = world_pos + Vector3(0.0, 0.03, 0.0)

	var rim_mat := _make_particle_material(Color(tint.r, tint.g, tint.b, 0.9), 1.2)
	var fill_mat := _make_particle_material(Color(tint.r, tint.g, tint.b, 0.45), 0.6)
	match shape:
		"line":
			var line := MeshInstance3D.new()
			var line_mesh := BoxMesh.new()
			line_mesh.size = Vector3(radius * 0.22, 0.02, radius * 2.0)
			line.mesh = line_mesh
			line.material_override = fill_mat
			line.position = Vector3(0.0, 0.0, -radius)
			line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			glyph.add_child(line)
		"cone":
			var wedge_segments := 8
			for i in wedge_segments:
				var angle := lerpf(-PI * 0.35, PI * 0.35, float(i) / float(wedge_segments - 1))
				var block := MeshInstance3D.new()
				var wedge := BoxMesh.new()
				wedge.size = Vector3(0.18, 0.02, radius * 0.9)
				block.mesh = wedge
				block.material_override = rim_mat if i == 0 or i == wedge_segments - 1 else fill_mat
				block.position = Vector3(sin(angle) * radius * 0.45, 0.0, -cos(angle) * radius * 0.45)
				block.rotation.y = angle
				block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				glyph.add_child(block)
		_:
			var tick := BoxMesh.new()
			tick.size = Vector3(0.22, 0.02, 0.22)
			var segments := 16
			for i in segments:
				var angle := TAU * float(i) / float(segments)
				var block := MeshInstance3D.new()
				block.mesh = tick
				block.material_override = rim_mat
				block.position = Vector3(cos(angle), 0.0, sin(angle)) * radius
				block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				glyph.add_child(block)
			var fill := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = radius * 0.55
			disc.bottom_radius = radius * 0.55
			disc.height = 0.02
			fill.mesh = disc
			fill.material_override = fill_mat
			fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			glyph.add_child(fill)

	var center := MeshInstance3D.new()
	var core := BoxMesh.new()
	core.size = Vector3(0.28, 0.04, 0.28)
	center.mesh = core
	center.material_override = rim_mat
	center.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glyph.add_child(center)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(glyph, "scale", Vector3(0.35, 1.0, 0.35), duration)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(center, "scale", Vector3(1.6, 1.0, 1.6), duration * 0.5)
	tween.chain().tween_property(center, "scale", Vector3(0.6, 1.0, 0.6), duration * 0.5)
	_schedule_free(glyph, duration + 0.1)


func _play_combat_burst(
	node_name: String,
	world_pos: Vector3,
	forward: Vector3,
	color: Color,
	emission: float
) -> void:
	var dir := forward.normalized() if forward.length_squared() > 0.01 else Vector3(0.0, 0.0, -1.0)
	var cfg := _COMBAT_BURST.duplicate()
	cfg["color"] = color
	cfg["emission"] = emission
	cfg["direction"] = Vector3(0.0, 0.0, -1.0)
	var particles := _make_burst_particles(node_name, world_pos, cfg)
	_orient_particles(particles, dir)


func _resolve_forward(body: Node3D) -> Vector3:
	if body.has_method("get_facing_direction"):
		return body.call("get_facing_direction")
	var facing := body.get_node_or_null("Facing") as Node3D
	if facing:
		return -facing.global_transform.basis.z
	return -body.global_transform.basis.z


func _make_burst_particles(node_name: String, world_pos: Vector3, cfg: Dictionary) -> CPUParticles3D:
	var particles := _acquire_burst()
	particles.name = node_name
	particles.amount = int(cfg.get("amount", 12))
	particles.lifetime = float(cfg.get("lifetime", 0.3))
	particles.explosiveness = float(cfg.get("explosiveness", 0.8))
	particles.randomness = float(cfg.get("randomness", 0.35))
	particles.direction = cfg.get("direction", Vector3.UP)
	particles.spread = float(cfg.get("spread", 30.0))
	particles.flatness = float(cfg.get("flatness", 0.2))
	particles.gravity = cfg.get("gravity", Vector3(0.0, -9.8, 0.0))
	particles.initial_velocity_min = float(cfg.get("velocity_min", 1.0))
	particles.initial_velocity_max = float(cfg.get("velocity_max", 2.5))
	particles.scale_amount_min = float(cfg.get("scale_min", 0.05))
	particles.scale_amount_max = float(cfg.get("scale_max", 0.1))
	particles.color = cfg.get("color", Color.WHITE)
	particles.material_override = _make_particle_material(
		particles.color,
		float(cfg.get("emission", 0.0))
	)
	particles.global_position = world_pos
	particles.restart()
	particles.emitting = true
	_schedule_pool_return(particles, particles.lifetime + 0.15)
	return particles


func _acquire_burst() -> CPUParticles3D:
	for particles in _burst_pool:
		if not particles.emitting:
			return particles
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.mesh = _pixel_chunk_mesh()
	particles.top_level = true
	particles.visibility_aabb = AABB(Vector3(-2.0, -1.0, -2.0), Vector3(4.0, 4.0, 4.0))
	_root.add_child(particles)
	_burst_pool.append(particles)
	return particles


func _schedule_pool_return(particles: CPUParticles3D, delay: float) -> void:
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.emitting = false
	)


func _pixel_chunk_mesh() -> BoxMesh:
	if _chunk_mesh == null:
		_chunk_mesh = BoxMesh.new()
		_chunk_mesh.size = Vector3(0.2, 0.2, 0.2)
	return _chunk_mesh


func _make_particle_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var quantized := _quantize(color)
	mat.albedo_color = quantized
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = quantized
		mat.emission_energy_multiplier = emission_energy
	return mat


func _quantize(color: Color, levels: float = 6.0) -> Color:
	return Color(
		floorf(color.r * levels + 0.5) / levels,
		floorf(color.g * levels + 0.5) / levels,
		floorf(color.b * levels + 0.5) / levels,
		color.a
	)


func _orient_particles(particles: CPUParticles3D, forward: Vector3) -> void:
	if forward.length_squared() < 0.01:
		return
	particles.rotation.y = atan2(forward.x, forward.z)


func _schedule_free(node: Node, delay: float) -> void:
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(node.queue_free)


func _make_gpu_burst() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 24
	particles.lifetime = 0.3
	particles.explosiveness = 0.9
	particles.visibility_aabb = AABB(Vector3(-2.0, -1.0, -2.0), Vector3(4.0, 4.0, 4.0))
	particles.draw_pass_1 = _pixel_chunk_mesh()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 35.0
	mat.gravity = Vector3(0.0, -8.0, 0.0)
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 4.0
	mat.scale_min = 0.06
	mat.scale_max = 0.14
	particles.process_material = mat
	particles.top_level = true
	return particles


func _emit_gpu_burst(
	node_name: String,
	world_pos: Vector3,
	direction: Vector3,
	color: Color,
	amount: int,
	lifetime: float
) -> void:
	var particles := _acquire_gpu_burst()
	particles.name = node_name
	particles.amount = maxi(4, amount)
	particles.lifetime = lifetime
	var mat := particles.process_material as ParticleProcessMaterial
	if mat:
		mat = mat.duplicate() as ParticleProcessMaterial
		mat.direction = direction.normalized() if direction.length_squared() > 0.01 else Vector3.UP
		mat.color = color
		particles.process_material = mat
	particles.global_position = world_pos
	particles.restart()
	particles.emitting = true
	_schedule_gpu_return(particles, lifetime + 0.15)


func _acquire_gpu_burst() -> GPUParticles3D:
	for particles in _gpu_burst_pool:
		if not particles.emitting:
			return particles
	var particles := _make_gpu_burst()
	particles.top_level = true
	_root.add_child(particles)
	_gpu_burst_pool.append(particles)
	return particles


func _schedule_gpu_return(particles: GPUParticles3D, delay: float) -> void:
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.emitting = false
	)


func _spawn_decal(
	world_pos: Vector3,
	direction: Vector3,
	texture: Texture2D,
	size: float,
	lifetime: float
) -> void:
	var decal := _acquire_decal()
	decal.texture_albedo = texture
	decal.size = Vector3(size, 0.12, size)
	decal.global_position = world_pos + Vector3(0.0, 0.02, 0.0)
	var dir := direction
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = Vector3(0.0, 0.0, 1.0)
	decal.look_at(decal.global_position + dir.normalized(), Vector3.UP)
	decal.rotation.x = -PI * 0.5
	decal.visible = true
	_schedule_decal_return(decal, lifetime)


func _acquire_decal() -> Decal:
	for decal in _decal_pool:
		if not decal.visible:
			return decal
	var decal := Decal.new()
	decal.top_level = true
	_root.add_child(decal)
	_decal_pool.append(decal)
	return decal


func _schedule_decal_return(decal: Decal, delay: float) -> void:
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(decal):
			decal.visible = false
	)


func _make_decal_texture(color: Color, scatter: float) -> Texture2D:
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(size * 0.5, size * 0.5)
	for y in size:
		for x in size:
			var dist := Vector2(x, y).distance_to(center) / float(size)
			if dist < scatter + randf() * 0.08:
				img.set_pixel(x, y, color)
	var tex := ImageTexture.create_from_image(img)
	return tex
