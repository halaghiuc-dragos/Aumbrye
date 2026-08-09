extends Node

## Global one-shot combat and locomotion particle bursts (hub, dungeon, arena).

const FOOTSTEP_INTERVAL_WALK := 0.42
const FOOTSTEP_INTERVAL_SPRINT := 0.28
const BURST_POOL_MAX := 32
const GPU_BURST_POOL_MAX := 16
const DECAL_POOL_MAX := 24

const TRAIL_ARC_DEGREES := 150.0
const TRAIL_LIFETIME := 0.24

const EMISSIVE_SHADER_PATH := "res://assets/shared/pixel_diorama_emissive.gdshader"
const EFFECTS_PATH := "content/vfx/effects.json"

const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")

static var _particle_material_cache: Dictionary = {}

var _root: Node3D
var _foot_alt := false
var _effects: Dictionary = {}
var _chunks: Dictionary = {}
var _decals: Dictionary = {}
var _unknown_effect_warnings: Dictionary = {}
var _chunk_meshes: Dictionary = {}
var _decal_textures: Dictionary = {}

var _burst_pool: Array[CPUParticles3D] = []
var _gpu_burst_pool: Array[GPUParticles3D] = []
var _decal_pool: Array[Decal] = []
var _burst_acquire_gen: PackedInt64Array = []
var _gpu_acquire_gen: PackedInt64Array = []
var _decal_acquire_gen: PackedInt64Array = []
var _acquire_counter := 0

var _sweep_entries: Array[Dictionary] = []
var _free_nodes: Array[Node] = []

## BUG-41: VfxService is the single owner of Engine.time_scale. Every requester (hit-stop,
## the death sequence, …) calls push_time_scale(id, scale, duration_ms) / release_time_scale(id)
## instead of writing Engine.time_scale directly, so overlapping or interrupted requests cannot
## corrupt a private restore cache (BUG-39) or strand the engine at a slowed scale (BUG-27).
## duration_ms == 0 means "persists until release_time_scale(id) is called" — used by the death
## sequence, whose length spans several awaits rather than one fixed window.
var _time_scale_requests: Dictionary = {}
var _shake_amount := 0.0
var _shake_decay_rate := 9.0


func _ready() -> void:
	_load_effects()
	_root = Node3D.new()
	_root.name = "VfxRoot"
	add_child(_root)
	_init_pools()
	set_process(true)
	if PixelDioramaViewport:
		PixelDioramaViewport.world_attached.connect(_on_pixel_world_attached)


func _process(delta: float) -> void:
	if (
		_sweep_entries.is_empty()
		and _free_nodes.is_empty()
		and _time_scale_requests.is_empty()
		and is_zero_approx(_shake_amount)
	):
		set_process(false)
		return
	_sweep_pools()
	_update_time_scale()
	_shake_amount = lerpf(_shake_amount, 0.0, delta * _shake_decay_rate)
	for node in _free_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_free_nodes.clear()


static func clear_particle_material_cache() -> void:
	_particle_material_cache.clear()


static func get_particle_material_cache_size() -> int:
	return _particle_material_cache.size()


static func get_particle_material_cache_entries() -> Array:
	return _particle_material_cache.values()


static func get_death_burst_lifetime() -> float:
	var data: Dictionary = ContentLoader.load_json(EFFECTS_PATH)
	var effect: Dictionary = data.get("effects", {}).get("death", {})
	var layers: Array = effect.get("layers", [])
	var max_lifetime := 0.65
	for layer in layers:
		if layer is Dictionary and layer.get("kind", "") == "burst":
			max_lifetime = maxf(max_lifetime, float(layer.get("lifetime", 0.0)))
	return max_lifetime


func _max_burst_lifetime_for_effect(effect_id: String) -> float:
	var effect: Dictionary = _effects.get(effect_id, {})
	var layers: Array = effect.get("layers", [])
	var max_lifetime := 0.0
	for layer in layers:
		if layer is Dictionary and layer.get("kind", "") == "burst":
			max_lifetime = maxf(max_lifetime, float(layer.get("lifetime", 0.0)))
	return max_lifetime


func _load_effects() -> void:
	var data: Dictionary = ContentLoader.load_json(EFFECTS_PATH)
	_effects = data.get("effects", {})
	_chunks = data.get("chunks", {})
	_decals = data.get("decals", {})


func _init_pools() -> void:
	for i in mini(BURST_POOL_MAX, 16):
		var cpu := _make_cpu_burst_node("BurstPool%d" % i)
		_root.add_child(cpu)
		_burst_pool.append(cpu)
	for i in mini(GPU_BURST_POOL_MAX, 8):
		var gpu := _make_gpu_burst_node("GpuBurstPool%d" % i)
		_root.add_child(gpu)
		_gpu_burst_pool.append(gpu)
	for i in mini(DECAL_POOL_MAX, 12):
		var decal := _make_decal_node("DecalPool%d" % i)
		_root.add_child(decal)
		_decal_pool.append(decal)
	_resize_acquire_gens()


func _on_pixel_world_attached(scene_root: Node) -> void:
	if scene_root == null or not is_instance_valid(scene_root):
		return
	if not is_instance_valid(_root):
		_ready_vfx_root()
	if _root.get_parent() == scene_root:
		return
	if _root.get_parent():
		_root.reparent(scene_root)
	else:
		scene_root.add_child(_root)


func _ready_vfx_root() -> void:
	_root = Node3D.new()
	_root.name = "VfxRoot"
	add_child(_root)
	_burst_pool.clear()
	_gpu_burst_pool.clear()
	_decal_pool.clear()
	_init_pools()


## Plays a data-defined effect. Unknown ids play fallback and warn once per id.
func play(
	effect_id: String,
	world_pos: Vector3,
	direction: Vector3 = Vector3.UP,
	tint_override: Color = Color(0, 0, 0, 0),
	normal: Vector3 = Vector3.UP,
	overrides: Dictionary = {}
) -> void:
	var resolved_id := effect_id
	if not _effects.has(effect_id):
		if not _unknown_effect_warnings.has(effect_id):
			push_warning("VfxService: unknown effect '%s', using fallback" % effect_id)
			_unknown_effect_warnings[effect_id] = true
		resolved_id = "fallback"
	var effect: Dictionary = _effects.get(resolved_id, {})
	var layers: Array = effect.get("layers", [])
	for layer in layers:
		if layer is Dictionary:
			_play_layer(layer, world_pos, direction, tint_override, normal, overrides)


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
	play("attack_swing", world_pos, forward)


func play_block(world_pos: Vector3, forward: Vector3 = Vector3.FORWARD) -> void:
	play("block", world_pos, forward)


func play_parry(world_pos: Vector3, forward: Vector3 = Vector3.FORWARD) -> void:
	play("parry", world_pos, forward)


func play_parry_spark(world_pos: Vector3, forward: Vector3 = Vector3.FORWARD) -> void:
	play_parry(world_pos, forward)


func play_hit_spark(
	world_pos: Vector3, direction: Vector3 = Vector3.UP, normal: Vector3 = Vector3.UP
) -> void:
	play("hit_spark", world_pos, direction, Color(0, 0, 0, 0), normal)


func play_blood_decal(
	world_pos: Vector3, direction: Vector3 = Vector3.FORWARD, normal: Vector3 = Vector3.UP
) -> void:
	play("blood_decal", world_pos, direction, Color(0, 0, 0, 0), normal)


func play_impact_decal(
	world_pos: Vector3, direction: Vector3 = Vector3.FORWARD, normal: Vector3 = Vector3.UP
) -> void:
	play("impact_decal", world_pos, direction, Color(0, 0, 0, 0), normal)


func play_rune_flare(world_pos: Vector3) -> void:
	play("rune_flare", world_pos, Vector3.UP)


func play_portal_activate(world_pos: Vector3) -> void:
	play_portal_enter(world_pos, Color(0.35, 0.82, 0.95, 0.85))


func play_portal_enter(world_pos: Vector3, tint: Color = Color(0.9, 0.96, 1.0, 0.9)) -> void:
	play("portal_enter", world_pos + Vector3(0.0, 0.8, 0.0), Vector3.UP, tint)


func play_death(
	world_pos: Vector3, tint: Color = Color(0.85, 0.35, 0.28), debris_count: int = -1
) -> void:
	var scale := 1.0
	if debris_count > 0:
		scale = float(debris_count) / 36.0
	play(
		"death",
		world_pos + Vector3(0.0, 0.45, 0.0),
		Vector3.UP,
		tint,
		Vector3.UP,
		{"burst_scale": scale, "blood_yaw": randf_range(-1.0, 1.0)}
	)


func play_footstep(
	world_pos: Vector3, forward: Vector3 = Vector3.FORWARD, surface: StringName = &"stone"
) -> void:
	var effect_id := _footstep_effect_id(surface)
	var dir := forward.normalized() if forward.length_squared() > 0.01 else Vector3(0.0, 0.0, -1.0)
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	else:
		side = side.normalized()
	var foot_side := 1.0 if _foot_alt else -1.0
	_foot_alt = not _foot_alt
	var foot_pos := world_pos + side * 0.18 * foot_side
	play(effect_id, foot_pos, Vector3.UP)


func play_weapon_trail(
	world_pos: Vector3,
	forward: Vector3 = Vector3.FORWARD,
	tint: Color = Color(1.0, 0.95, 0.72),
	radius: float = 1.05
) -> void:
	play("weapon_trail", world_pos, forward, tint, Vector3.UP, {"radius": radius})


func play_telegraph(
	world_pos: Vector3,
	radius: float = 1.6,
	duration: float = 0.6,
	tint: Color = Color(0.95, 0.34, 0.28),
	shape: String = "circle",
	forward: Vector3 = Vector3.FORWARD
) -> void:
	var effect_id := "telegraph_%s" % shape
	if not _effects.has(effect_id):
		effect_id = "telegraph_circle"
	play(
		effect_id,
		world_pos,
		forward,
		tint,
		Vector3.UP,
		{"radius": radius, "duration": duration, "shape": shape, "forward": forward}
	)


func request_hitstop(duration_ms: int, strength: float = 0.05) -> void:
	if not PixelDioramaSettings.hitstop_enabled:
		return
	if AccessibilitySettings.hitstop_scale() <= 0.0:
		return
	push_time_scale(&"vfx_hitstop", strength, duration_ms)


## Requests Engine.time_scale = scale for at least duration_ms of unscaled wall time (or until
## release_time_scale(id) if duration_ms is 0). Repeated pushes to the same id extend the
## deadline and keep the strongest (lowest) scale rather than resetting it — the same
## "never shorten an in-flight freeze" rule the old per-caller implementations each hand-rolled.
func push_time_scale(id: StringName, scale: float, duration_ms: int = 0) -> void:
	set_process(true)
	var until_ms := 0
	if duration_ms > 0:
		until_ms = Time.get_ticks_msec() + duration_ms
	if _time_scale_requests.has(id):
		var existing: Dictionary = _time_scale_requests[id]
		var existing_until := int(existing.get("until_ms", 0))
		if existing_until == 0 or (until_ms != 0 and until_ms < existing_until):
			until_ms = existing_until
		scale = minf(scale, float(existing.get("scale", 1.0)))
	_time_scale_requests[id] = {"scale": scale, "until_ms": until_ms}
	_apply_time_scale()


func release_time_scale(id: StringName) -> void:
	if _time_scale_requests.erase(id):
		_apply_time_scale()


func _apply_time_scale() -> void:
	if _time_scale_requests.is_empty():
		Engine.time_scale = 1.0
		return
	var strongest := 1.0
	for id in _time_scale_requests:
		strongest = minf(strongest, float(_time_scale_requests[id].get("scale", 1.0)))
	Engine.time_scale = strongest


func _update_time_scale() -> void:
	if _time_scale_requests.is_empty():
		return
	var now_ms := Time.get_ticks_msec()
	var expired: Array = []
	for id in _time_scale_requests:
		var until_ms := int((_time_scale_requests[id] as Dictionary).get("until_ms", 0))
		if until_ms > 0 and now_ms >= until_ms:
			expired.append(id)
	if expired.is_empty():
		return
	for id in expired:
		_time_scale_requests.erase(id)
	_apply_time_scale()


func request_shake(amount: float, duration_ms: int) -> void:
	var scale := PixelDioramaSettings.screen_shake_scale
	if scale <= 0.0 or AccessibilitySettings.camera_shake_scale() <= 0.0:
		return
	set_process(true)
	_shake_amount = maxf(_shake_amount, amount * scale * AccessibilitySettings.camera_shake_scale())


func consume_shake() -> Vector3:
	if _shake_amount < 0.001:
		return Vector3.ZERO
	return Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * _shake_amount * 0.06


func get_burst_pool_size() -> int:
	return _burst_pool.size()


func _footstep_effect_id(surface: StringName) -> String:
	match String(surface):
		"wood":
			return "footstep_wood"
		"water":
			return "footstep_water"
		"snow":
			return "footstep_snow"
		_:
			return "footstep"


func _play_layer(
	layer: Dictionary,
	world_pos: Vector3,
	direction: Vector3,
	tint_override: Color,
	normal: Vector3,
	overrides: Dictionary
) -> void:
	match String(layer.get("kind", "")):
		"burst":
			_play_burst_layer(layer, world_pos, direction, tint_override, overrides)
		"decal":
			_play_decal_layer(layer, world_pos, direction, normal, overrides)
		"ribbon":
			_play_ribbon_layer(layer, world_pos, direction, tint_override, overrides)
		"glyph":
			_play_glyph_layer(layer, world_pos, direction, tint_override, overrides)
		"impact":
			_play_impact_layer(layer)
		"sfx":
			_play_sfx_layer(layer, world_pos)


func _play_burst_layer(
	layer: Dictionary,
	world_pos: Vector3,
	direction: Vector3,
	tint_override: Color,
	overrides: Dictionary
) -> void:
	var use_gpu := String(layer.get("backend", "cpu")) == "gpu"
	if use_gpu and PixelDioramaSettings.particle_quality <= 0:
		use_gpu = false
	var amount := int(layer.get("amount", 12))
	var burst_scale := float(overrides.get("burst_scale", 1.0))
	amount = int(amount * burst_scale * PixelDioramaSettings.particle_amount_scale())
	var lifetime := float(layer.get("lifetime", 0.3))
	var color := _color_from_layer(layer, tint_override)
	var align := String(layer.get("align_to", "up"))
	var dir := _aligned_direction(direction, align)
	var cfg := {
		"amount": amount,
		"lifetime": lifetime,
		"explosiveness": float(layer.get("explosiveness", 0.8)),
		"spread": float(layer.get("spread", 30.0)),
		"velocity_min": _vec2_min(layer.get("velocity", [1.0, 2.5])),
		"velocity_max": _vec2_max(layer.get("velocity", [1.0, 2.5])),
		"gravity": _vec3(layer.get("gravity", [0.0, -9.8, 0.0])),
		"scale_min": _vec2_min(layer.get("scale", [0.05, 0.1])),
		"scale_max": _vec2_max(layer.get("scale", [0.05, 0.1])),
		"color": color,
		"emission": float(layer.get("emission", 0.0)),
		"direction": dir,
		"flatness": float(layer.get("flatness", 0.2)),
		"randomness": float(layer.get("randomness", 0.35)),
		"chunk": String(layer.get("chunk", "shard_small")),
	}
	if use_gpu:
		_emit_gpu_burst("BurstGpu", world_pos, dir, color, amount, lifetime, cfg)
	else:
		var particles := _make_burst_particles("BurstCpu", world_pos, cfg)
		if align == "forward":
			_orient_particles(particles, direction)


func _play_decal_layer(
	layer: Dictionary,
	world_pos: Vector3,
	direction: Vector3,
	normal: Vector3,
	overrides: Dictionary
) -> void:
	var decal_id := String(layer.get("decal", "impact_small"))
	var texture := _pick_decal_texture(decal_id)
	if texture == null:
		return
	var size := float(layer.get("size", 0.3))
	var lifetime := float(layer.get("lifetime", 2.0))
	var fade := float(layer.get("fade", 0.0))
	var yaw := float(overrides.get("blood_yaw", 0.0))
	var facing := direction
	if absf(yaw) > 0.001:
		facing = Vector3(yaw, 0.0, 1.0).normalized()
	_spawn_decal(world_pos, facing, normal, texture, size, lifetime, fade)


func _play_ribbon_layer(
	layer: Dictionary,
	world_pos: Vector3,
	forward: Vector3,
	tint_override: Color,
	overrides: Dictionary
) -> void:
	var tint := _color_from_layer(layer, tint_override)
	var radius := float(overrides.get("radius", layer.get("radius", 1.05)))
	var lifetime := float(layer.get("lifetime", TRAIL_LIFETIME))
	var arc := float(layer.get("arc_degrees", TRAIL_ARC_DEGREES))
	var emission := float(layer.get("emission", 2.4))
	_build_weapon_trail(world_pos, forward, tint, radius, lifetime, arc, emission)


func _play_glyph_layer(
	layer: Dictionary,
	world_pos: Vector3,
	forward: Vector3,
	tint_override: Color,
	overrides: Dictionary
) -> void:
	var radius := float(overrides.get("radius", layer.get("radius", 1.6)))
	var duration := float(overrides.get("duration", layer.get("duration", 0.6)))
	var shape := String(overrides.get("shape", layer.get("shape", "circle")))
	var tint := _color_from_layer(layer, tint_override)
	var glyph_forward: Vector3 = overrides.get("forward", forward)
	_build_telegraph_glyph(world_pos, radius, duration, tint, shape, glyph_forward)


func _play_impact_layer(layer: Dictionary) -> void:
	var hitstop_ms := int(layer.get("hitstop_ms", 0))
	if hitstop_ms > 0:
		request_hitstop(hitstop_ms, 0.05)
	var shake := float(layer.get("shake", 0.0))
	var shake_ms := int(layer.get("shake_ms", 0))
	if shake > 0.0 and shake_ms > 0:
		request_shake(shake, shake_ms)
	var vignette := float(layer.get("vignette", 0.0))
	if (
		vignette > 0.0
		and PixelDioramaViewport
		and PixelDioramaViewport.has_method("pulse_damage_vignette")
	):
		PixelDioramaViewport.call("pulse_damage_vignette", vignette)


func _play_sfx_layer(layer: Dictionary, world_pos: Vector3) -> void:
	if OS.has_feature("no_audio"):
		return
	var key := String(layer.get("key", ""))
	if key.is_empty():
		return
	AudioDirector.play_sfx(key, world_pos)


func _make_burst_particles(
	node_name: String, world_pos: Vector3, cfg: Dictionary
) -> CPUParticles3D:
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
	particles.mesh = _chunk_mesh(String(cfg.get("chunk", "shard_small")))
	particles.material_override = _particle_material(
		particles.color, float(cfg.get("emission", 0.0))
	)
	particles.visibility_aabb = _burst_visibility_aabb(cfg)
	particles.global_position = world_pos
	particles.restart()
	particles.emitting = true
	_schedule_pool_return(particles, particles.lifetime + 0.15)
	return particles


func _emit_gpu_burst(
	node_name: String,
	world_pos: Vector3,
	direction: Vector3,
	color: Color,
	amount: int,
	lifetime: float,
	cfg: Dictionary
) -> void:
	var particles := _acquire_gpu_burst()
	particles.name = node_name
	particles.amount = maxi(4, amount)
	particles.lifetime = lifetime
	particles.draw_pass_1 = _chunk_mesh(String(cfg.get("chunk", "shard_small")))
	var mat := particles.process_material as ParticleProcessMaterial
	if mat == null:
		mat = ParticleProcessMaterial.new()
		particles.process_material = mat
	mat.direction = direction.normalized() if direction.length_squared() > 0.01 else Vector3.UP
	mat.color = color
	mat.spread = float(cfg.get("spread", 35.0))
	mat.gravity = cfg.get("gravity", Vector3(0.0, -8.0, 0.0))
	mat.initial_velocity_min = float(cfg.get("velocity_min", 1.5))
	mat.initial_velocity_max = float(cfg.get("velocity_max", 4.0))
	mat.scale_min = float(cfg.get("scale_min", 0.06))
	mat.scale_max = float(cfg.get("scale_max", 0.14))
	particles.material_override = _particle_material(color, float(cfg.get("emission", 0.85)))
	particles.visibility_aabb = _burst_visibility_aabb(cfg)
	particles.global_position = world_pos
	particles.restart()
	particles.emitting = true
	_schedule_gpu_return(particles, lifetime + 0.15)


func _acquire_burst() -> CPUParticles3D:
	return _acquire_from_pool(_burst_pool, _burst_acquire_gen, BURST_POOL_MAX, _make_cpu_burst_node)


func _acquire_gpu_burst() -> GPUParticles3D:
	return _acquire_from_pool(
		_gpu_burst_pool, _gpu_acquire_gen, GPU_BURST_POOL_MAX, _make_gpu_burst_node
	)


func _acquire_decal() -> Decal:
	return _acquire_from_pool(_decal_pool, _decal_acquire_gen, DECAL_POOL_MAX, _make_decal_node)


func _acquire_from_pool(
	pool: Array, gens: PackedInt64Array, cap: int, factory: Callable
) -> Variant:
	var best_idx := -1
	var best_gen := 9223372036854775807
	for i in pool.size():
		var node = pool[i]
		if not _is_pool_node_busy(node):
			return node
		if gens[i] < best_gen:
			best_gen = gens[i]
			best_idx = i
	if pool.size() < cap:
		var fresh = factory.call("Pool%d" % pool.size())
		pool.append(fresh)
		gens.append(0)
		_root.add_child(fresh)
		return fresh
	if best_idx >= 0:
		_stop_pool_node(pool[best_idx])
		return pool[best_idx]
	return pool[0]


func _is_pool_node_busy(node: Variant) -> bool:
	if node is CPUParticles3D:
		return (node as CPUParticles3D).emitting
	if node is GPUParticles3D:
		return (node as GPUParticles3D).emitting
	if node is Decal:
		return (node as Decal).visible
	return false


func _stop_pool_node(node: Variant) -> void:
	if node is CPUParticles3D:
		(node as CPUParticles3D).emitting = false
	elif node is GPUParticles3D:
		(node as GPUParticles3D).emitting = false
	elif node is Decal:
		(node as Decal).visible = false


func _mark_acquired(pool: Array, gens: PackedInt64Array, node: Variant) -> void:
	_acquire_counter += 1
	var idx := pool.find(node)
	if idx >= 0 and idx < gens.size():
		gens[idx] = _acquire_counter


func _resize_acquire_gens() -> void:
	_burst_acquire_gen.resize(_burst_pool.size())
	_gpu_acquire_gen.resize(_gpu_burst_pool.size())
	_decal_acquire_gen.resize(_decal_pool.size())


func _make_cpu_burst_node(node_name: String) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = node_name
	particles.emitting = false
	particles.one_shot = true
	particles.top_level = true
	particles.mesh = _chunk_mesh("shard_small")
	return particles


func _make_gpu_burst_node(node_name: String) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.emitting = false
	particles.one_shot = true
	particles.top_level = true
	particles.amount = 24
	particles.lifetime = 0.3
	particles.explosiveness = 0.9
	particles.draw_pass_1 = _chunk_mesh("shard_small")
	particles.material_override = _particle_material(Color.WHITE, 0.0)
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 35.0
	mat.gravity = Vector3(0.0, -8.0, 0.0)
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 4.0
	mat.scale_min = 0.06
	mat.scale_max = 0.14
	particles.process_material = mat
	return particles


func _make_decal_node(node_name: String) -> Decal:
	var decal := Decal.new()
	decal.name = node_name
	decal.top_level = true
	decal.visible = false
	return decal


func _schedule_pool_return(particles: CPUParticles3D, delay: float) -> void:
	set_process(true)
	_mark_acquired(_burst_pool, _burst_acquire_gen, particles)
	_sweep_entries.append(
		{
			"node": particles,
			"expires_at": Time.get_ticks_msec() + int(delay * 1000.0),
			"kind": "cpu"
		}
	)


func _schedule_gpu_return(particles: GPUParticles3D, delay: float) -> void:
	set_process(true)
	_mark_acquired(_gpu_burst_pool, _gpu_acquire_gen, particles)
	_sweep_entries.append(
		{
			"node": particles,
			"expires_at": Time.get_ticks_msec() + int(delay * 1000.0),
			"kind": "gpu"
		}
	)


func _schedule_decal_return(decal: Decal, delay: float) -> void:
	set_process(true)
	_mark_acquired(_decal_pool, _decal_acquire_gen, decal)
	_sweep_entries.append(
		{"node": decal, "expires_at": Time.get_ticks_msec() + int(delay * 1000.0), "kind": "decal"}
	)


func _schedule_free(node: Node, delay: float) -> void:
	set_process(true)
	_sweep_entries.append(
		{"node": node, "expires_at": Time.get_ticks_msec() + int(delay * 1000.0), "kind": "free"}
	)


func _sweep_pools() -> void:
	if _sweep_entries.is_empty():
		return
	var now := Time.get_ticks_msec()
	for i in range(_sweep_entries.size() - 1, -1, -1):
		var entry := _sweep_entries[i]
		if now < int(entry.get("expires_at", 0)):
			continue
		_sweep_entries.remove_at(i)
		var node: Variant = entry.get("node")
		if not is_instance_valid(node):
			continue
		match String(entry.get("kind", "")):
			"cpu", "gpu":
				_stop_pool_node(node)
			"decal":
				(node as Decal).visible = false
			"free":
				_free_nodes.append(node)


func _particle_material(color: Color, emission_energy: float) -> ShaderMaterial:
	var key := "%s_%.2f" % [color.to_html(false), emission_energy]
	if _particle_material_cache.has(key):
		return _particle_material_cache[key] as ShaderMaterial
	var mat := ShaderMaterial.new()
	mat.shader = load(EMISSIVE_SHADER_PATH) as Shader
	mat.set_shader_parameter("color_core", color)
	mat.set_shader_parameter("color_edge", color.darkened(0.25))
	mat.set_shader_parameter("emission_energy", emission_energy)
	mat.set_shader_parameter("grain_strength", 0.0)
	mat.set_shader_parameter("pulse_speed", 0.0)
	PixelDioramaSettings.apply_to_shader_material(mat)
	_particle_material_cache[key] = mat
	PixelDioramaSettings.track(mat)
	return mat


func _chunk_mesh(chunk_id: String) -> Mesh:
	if _chunk_meshes.has(chunk_id):
		return _chunk_meshes[chunk_id]
	var spec: Dictionary = _chunks.get(chunk_id, {"mesh": "box", "size": [0.2, 0.2, 0.2]})
	var mesh_kind := String(spec.get("mesh", "box"))
	var sizes: Array = spec.get("size", [0.2, 0.2, 0.2])
	var built: Mesh
	if mesh_kind == "quad":
		var quad := QuadMesh.new()
		quad.size = PixelStyle.snap_size2_to_pixel_grid(
			Vector2(float(sizes[0]), float(sizes[1]))
		)
		if bool(spec.get("billboard", false)):
			quad.orientation = PlaneMesh.FACE_Z
		built = quad
	else:
		var box := BoxMesh.new()
		if sizes.size() >= 3:
			box.size = PixelStyle.snap_size_to_pixel_grid(
				Vector3(float(sizes[0]), float(sizes[1]), float(sizes[2]))
			)
		else:
			box.size = PixelStyle.snap_size_to_pixel_grid(
				Vector3(float(sizes[0]), float(sizes[0]), float(sizes[0]))
			)
		built = box
	_chunk_meshes[chunk_id] = built
	return built


func _pick_decal_texture(decal_id: String) -> Texture2D:
	if _decal_textures.has(decal_id):
		var cached: Variant = _decal_textures[decal_id]
		if cached is Array:
			return (cached as Array)[randi() % cached.size()] as Texture2D
		return cached as Texture2D
	var entry: Variant = _decals.get(decal_id, "")
	var paths: Array[String] = []
	if entry is Array:
		for p in entry:
			paths.append(String(p))
	elif entry is String and not String(entry).is_empty():
		paths.append(String(entry))
	var loaded: Array[Texture2D] = []
	for path in paths:
		var tex: Texture2D = null
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
		if tex == null:
			if FileAccess.file_exists(path):
				var img := Image.load_from_file(path)
				if img:
					tex = ImageTexture.create_from_image(img)
		if tex != null:
			loaded.append(tex)
	if loaded.is_empty():
		var fallback := _procedural_decal_texture(decal_id)
		_decal_textures[decal_id] = fallback
		return fallback
	if loaded.size() == 1:
		_decal_textures[decal_id] = loaded[0]
		return loaded[0]
	_decal_textures[decal_id] = loaded
	return loaded[randi() % loaded.size()]


func _procedural_decal_texture(decal_id: String) -> Texture2D:
	var color := Color(0.35, 0.32, 0.28, 0.7)
	var scatter := 0.55
	if "blood" in decal_id:
		color = Color(0.55, 0.08, 0.06, 0.85)
		scatter = 0.35
	return _make_decal_texture(color, scatter)


func _spawn_decal(
	world_pos: Vector3,
	direction: Vector3,
	normal: Vector3,
	texture: Texture2D,
	size: float,
	lifetime: float,
	fade: float
) -> void:
	var decal := _acquire_decal()
	decal.texture_albedo = texture
	decal.size = PixelStyle.snap_size_to_pixel_grid(
		Vector3(size, maxf(0.08, size * 0.3), size)
	)
	var n := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	decal.global_position = world_pos + n * 0.02
	var tangent := direction
	tangent.y = 0.0
	if tangent.length_squared() < 0.01:
		tangent = Vector3.FORWARD
	tangent = tangent.normalized()
	var bitangent := n.cross(tangent).normalized()
	if bitangent.length_squared() < 0.01:
		bitangent = Vector3.RIGHT
	decal.global_basis = Basis(bitangent, n, -tangent)
	decal.modulate = Color(1, 1, 1, 1)
	decal.visible = true
	if fade > 0.0:
		var tween := create_tween()
		tween.tween_property(decal, "modulate:a", 0.0, fade).set_delay(maxf(0.0, lifetime - fade))
	_schedule_decal_return(decal, lifetime)


func _make_decal_texture(color: Color, scatter: float) -> Texture2D:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(size * 0.5, size * 0.5)
	for y in size:
		for x in size:
			var dist := Vector2(x, y).distance_to(center) / float(size)
			if dist < scatter + randf() * 0.08:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


func _build_weapon_trail(
	world_pos: Vector3,
	forward: Vector3,
	tint: Color,
	radius: float,
	lifetime: float,
	arc_degrees: float,
	emission: float
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
	mesh_instance.material_override = _particle_material(
		Color(tint.r, tint.g, tint.b, 0.98), emission
	)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.add_child(mesh_instance)
	var half_arc := deg_to_rad(arc_degrees) * 0.5
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
	fade.tween_property(mesh_instance, "scale", Vector3(0.35, 0.35, 0.35), lifetime)
	_schedule_free(trail, lifetime + 0.05)


func _build_telegraph_glyph(
	world_pos: Vector3, radius: float, duration: float, tint: Color, shape: String, forward: Vector3
) -> void:
	var glyph := Node3D.new()
	glyph.name = "TelegraphGlyph"
	glyph.top_level = true
	_root.add_child(glyph)
	glyph.global_position = world_pos + Vector3(0.0, 0.03, 0.0)
	if forward.length_squared() > 0.01:
		glyph.look_at(glyph.global_position + Vector3(forward.x, 0.0, forward.z), Vector3.UP)
	var rim_mat := PixelStyle.make_glow_material(
		Color(tint.r, tint.g, tint.b, 0.95),
		Color(tint.r, tint.g, tint.b, 0.55).darkened(0.15),
		1.35
	)
	var fill_mat := PixelStyle.make_glow_material(
		Color(tint.r, tint.g, tint.b, 0.42), Color(tint.r, tint.g, tint.b, 0.22).darkened(0.2), 0.55
	)
	match shape:
		"line":
			var line := MeshInstance3D.new()
			var line_mesh := BoxMesh.new()
			line_mesh.size = PixelStyle.snap_size_to_pixel_grid(
				Vector3(radius * 0.22, 0.02, radius * 2.0)
			)
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
				wedge.size = PixelStyle.snap_size_to_pixel_grid(
					Vector3(0.18, 0.02, radius * 0.9)
				)
				block.mesh = wedge
				block.material_override = rim_mat if i == 0 or i == wedge_segments - 1 else fill_mat
				block.position = Vector3(
					sin(angle) * radius * 0.45, 0.0, -cos(angle) * radius * 0.45
				)
				block.rotation.y = angle
				block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				glyph.add_child(block)
		_:
			var tick := BoxMesh.new()
			tick.size = PixelStyle.snap_size_to_pixel_grid(Vector3(0.22, 0.02, 0.22))
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
			disc.height = PixelStyle.WORLD_PIXEL
			fill.mesh = disc
			fill.material_override = fill_mat
			fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			glyph.add_child(fill)
	var center := MeshInstance3D.new()
	var core := BoxMesh.new()
	core.size = PixelStyle.snap_size_to_pixel_grid(Vector3(0.28, 0.04, 0.28))
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


func _burst_visibility_aabb(cfg: Dictionary) -> AABB:
	var velocity_max := float(cfg.get("velocity_max", 2.5))
	var lifetime := float(cfg.get("lifetime", 0.3))
	var scale_max := float(cfg.get("scale_max", 0.1))
	var extent := (velocity_max * lifetime + scale_max) * 1.25
	return AABB(
		Vector3(-extent, -extent * 0.5, -extent), Vector3(extent * 2.0, extent * 2.0, extent * 2.0)
	)


func _resolve_forward(body: Node3D) -> Vector3:
	if body.has_method("get_facing_direction"):
		return body.call("get_facing_direction")
	var facing := body.get_node_or_null("Facing") as Node3D
	if facing:
		return -facing.global_transform.basis.z
	return -body.global_transform.basis.z


func _orient_particles(particles: CPUParticles3D, forward: Vector3) -> void:
	if forward.length_squared() < 0.01:
		return
	particles.rotation.y = atan2(forward.x, forward.z)


func _aligned_direction(direction: Vector3, align: String) -> Vector3:
	match align:
		"forward":
			return Vector3(0.0, 0.0, -1.0)
		"direction":
			return direction.normalized() if direction.length_squared() > 0.01 else Vector3.UP
		"up", _:
			return Vector3.UP


func _color_from_layer(layer: Dictionary, tint_override: Color) -> Color:
	if tint_override.a > 0.0:
		return tint_override
	var hex := String(layer.get("color", layer.get("tint", "#ffffff")))
	if hex.begins_with("#") and hex.length() >= 7:
		return Color.html(hex)
	return Color.WHITE


func _vec2_min(value: Variant) -> float:
	if value is Array and value.size() >= 1:
		return float(value[0])
	return 1.0


func _vec2_max(value: Variant) -> float:
	if value is Array and value.size() >= 2:
		return float(value[1])
	return 2.5


func _vec3(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
