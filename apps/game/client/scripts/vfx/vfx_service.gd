extends Node

## Global one-shot combat and locomotion particle bursts (hub, dungeon, arena).

const FOOTSTEP_INTERVAL_WALK := 0.42
const FOOTSTEP_INTERVAL_SPRINT := 0.28

const _COMBAT_BURST := {
	"amount": 18,
	"lifetime": 0.22,
	"explosiveness": 0.85,
	"spread": 28.0,
	"velocity_min": 1.8,
	"velocity_max": 3.6,
	"gravity": Vector3(0.0, -6.0, 0.0),
	"scale_min": 0.06,
	"scale_max": 0.12,
}

## A slash reads best as a handful of discrete blocks sweeping an arc rather
## than a smooth ribbon; these are the stops along that arc.
const TRAIL_SEGMENTS := 7
const TRAIL_ARC_DEGREES := 150.0
const TRAIL_LIFETIME := 0.16

var _root: Node3D
var _foot_alt := false
var _chunk_mesh: BoxMesh
var _trail_mesh: BoxMesh


func _ready() -> void:
	_root = Node3D.new()
	_root.name = "VfxRoot"
	add_child(_root)


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
	_play_combat_burst("AttackSwing", world_pos, forward, Color(1.0, 0.92, 0.55, 0.9), 0.8)


func play_block(world_pos: Vector3, forward: Vector3 = Vector3.FORWARD) -> void:
	_play_combat_burst("BlockSpark", world_pos, forward, Color(0.55, 0.82, 1.0, 0.92), 0.8)


func play_parry(world_pos: Vector3, forward: Vector3 = Vector3.FORWARD) -> void:
	_play_combat_burst("ParrySpark", world_pos, forward, Color(1.0, 0.88, 0.2, 0.95), 0.85)


func play_hit_spark(world_pos: Vector3, direction: Vector3 = Vector3.UP) -> void:
	var dir := direction.normalized() if direction.length_squared() > 0.01 else Vector3.UP
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


func play_death(world_pos: Vector3, tint: Color = Color(0.85, 0.35, 0.28)) -> void:
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


## Stepped slash arc swept through the strike. Each block pops on a slightly
## later frame and fades on its own, giving the hand-animated feel of a sprite
## slash without any texture work.
func play_weapon_trail(
	world_pos: Vector3,
	forward: Vector3 = Vector3.FORWARD,
	tint: Color = Color(1.0, 0.95, 0.72),
	radius: float = 0.85
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

	if _trail_mesh == null:
		_trail_mesh = BoxMesh.new()
		_trail_mesh.size = Vector3(0.16, 0.16, 0.16)

	var half_arc := deg_to_rad(TRAIL_ARC_DEGREES) * 0.5
	for i in TRAIL_SEGMENTS:
		var t := float(i) / float(maxi(1, TRAIL_SEGMENTS - 1))
		var angle := lerpf(-half_arc, half_arc, t)
		var offset := (side * sin(angle) + dir * cos(angle)) * radius - dir * radius * 0.35
		offset += up * (0.12 - absf(angle) * 0.18)

		var block := MeshInstance3D.new()
		block.mesh = _trail_mesh
		block.position = offset
		# Fat in the middle of the swing, thin at the tips: reads as motion.
		var thickness := lerpf(0.55, 1.45, sin(t * PI))
		block.scale = Vector3(thickness, thickness * 0.8, thickness)
		var shade := tint.lerp(Color(1.0, 1.0, 1.0), t * 0.35)
		block.material_override = _make_particle_material(
			Color(shade.r, shade.g, shade.b, 0.92), 1.4
		)
		block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		block.visible = false
		trail.add_child(block)

		var delay := t * TRAIL_LIFETIME * 0.55
		var tween := create_tween()
		tween.tween_interval(delay)
		tween.tween_callback(func() -> void:
			if is_instance_valid(block):
				block.visible = true
		)
		tween.tween_property(block, "scale", block.scale * 0.12, TRAIL_LIFETIME)
		tween.tween_callback(block.queue_free)

	_schedule_free(trail, TRAIL_LIFETIME * 2.0)


## Flat ground glyph used to telegraph an incoming enemy attack.
func play_telegraph(world_pos: Vector3, radius: float = 1.6, duration: float = 0.6,
		tint: Color = Color(0.95, 0.34, 0.28)) -> void:
	var glyph := Node3D.new()
	glyph.name = "TelegraphGlyph"
	glyph.top_level = true
	_root.add_child(glyph)
	glyph.global_position = world_pos + Vector3(0.0, 0.03, 0.0)

	var tick := BoxMesh.new()
	tick.size = Vector3(0.22, 0.02, 0.22)
	var mat := _make_particle_material(Color(tint.r, tint.g, tint.b, 0.9), 1.2)
	var segments := 16
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		var block := MeshInstance3D.new()
		block.mesh = tick
		block.material_override = mat
		block.position = Vector3(cos(angle), 0.0, sin(angle)) * radius
		block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glyph.add_child(block)

	# Ring tightens onto the strike point, so the wind-up has a readable clock.
	var tween := create_tween()
	tween.tween_property(glyph, "scale", Vector3(0.35, 1.0, 0.35), duration)
	tween.set_trans(Tween.TRANS_QUAD)
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
	var particles := CPUParticles3D.new()
	particles.name = node_name
	particles.emitting = true
	particles.one_shot = true
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

	particles.mesh = _pixel_chunk_mesh()
	particles.material_override = _make_particle_material(
		particles.color,
		float(cfg.get("emission", 0.0))
	)
	particles.visibility_aabb = AABB(Vector3(-2.0, -1.0, -2.0), Vector3(4.0, 4.0, 4.0))

	particles.top_level = true
	_root.add_child(particles)
	particles.global_position = world_pos
	_schedule_free(particles, particles.lifetime + 0.15)
	return particles


## Square, hard-edged chunks instead of soft spheres: at 480x270 a smooth
## billboard turns into mush, while an axis-aligned cube stays a clean cluster
## of lit pixels.
func _pixel_chunk_mesh() -> BoxMesh:
	if _chunk_mesh == null:
		_chunk_mesh = BoxMesh.new()
		_chunk_mesh.size = Vector3(0.14, 0.14, 0.14)
	return _chunk_mesh


func _make_particle_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var quantized := _quantize(color)
	mat.albedo_color = quantized
	# Scissor rather than blend so particle edges land on whole pixels.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = quantized
		mat.emission_energy_multiplier = emission_energy
	return mat


## Snaps a colour onto the same ramp the surface shader uses so sparks read as
## part of the palette instead of floating on top of it.
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
