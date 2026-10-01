extends Node3D


const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

enum State { IDLE, TELEGRAPH, ACTIVE, COOLDOWN, SPENT }

## Same class every other arena/dungeon hazard now telegraphs as -- see `arena_hazard.gd`.
const HAZARD_ATTACK_CLASS := "unblockable"

@export var trap_id: String = ""

var _def: Dictionary = {}
var _state := State.IDLE
var _timer := 0.0
var _cooldowns: Dictionary = {}
var _area: Area3D
var _shape: CollisionShape3D
var _telegraph: MeshInstance3D
var _body: Node3D
var _trigger := "proximity"
var _radius := 3.0
var _one_shot := false
var _visual := ""
## A hovering body (the falling block) stays on show and resets to this height.
var _hover_height := 0.0
var _landed := true

const FALL_SPEED := 12.0
const BLOCK_HEIGHT := 3.8


func _ready() -> void:
	if trap_id == "":
		trap_id = str(get_meta("trap_id", ""))
	if trap_id == "":
		trap_id = TrapTactics.trap_id_for(self)
	_def = TrapTactics.definition(trap_id)
	_def["attackClass"] = HAZARD_ATTACK_CLASS
	_trigger = str(_def.get("trigger", "proximity"))
	var size := _size()
	_radius = maxf(float(_def.get("triggerRadius", 0.0)), maxf(size.x, size.z) * 0.5 + 0.5)
	_one_shot = bool(_def.get("oneShot", false))
	_visual = str(_def.get("visual", ""))
	_build_volume(size)
	_build_meshes(size)
	TrapTactics.register_hazard(self, _radius)
	if _trigger == "cycle":
		_timer = _cycle_offset()
		_state = State.COOLDOWN


func _physics_process(delta: float) -> void:
	match _state:
		State.IDLE:
			if _should_arm():
				_enter_telegraph()
		State.TELEGRAPH:
			_timer -= delta
			if _timer <= 0.0:
				_enter_active()
		State.ACTIVE:
			_timer -= delta
			if _hover_height > 0.0:
				_drop_body(delta)
			TrapTactics.strike(_area, self, _def, _cooldowns)
			if _timer <= 0.0:
				_enter_cooldown()
		State.COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				if _trigger == "cycle":
					_enter_telegraph()
				else:
					_state = State.IDLE
		State.SPENT:
			set_physics_process(false)


func hazard_radius() -> float:
	return _radius


func _should_arm() -> bool:
	match _trigger:
		"plate":
			return TrapTactics.trigger_present(self, _radius, true, true)
		"lure":
			return TrapTactics.trigger_present(self, _radius, false, true)
		_:
			return TrapTactics.trigger_present(self, _radius, true, false)


func _drop_body(delta: float) -> void:
	if _landed:
		return
	_body.position.y = maxf(_body.position.y - FALL_SPEED * delta, 0.0)
	if _body.position.y <= 0.0:
		_landed = true
		# A beat of dust where the block lands; it lingers there until the trap resets.
		VfxService.play_hit_spark(global_position + Vector3(0.0, 0.2, 0.0), Vector3.UP)


func _enter_telegraph() -> void:
	_state = State.TELEGRAPH
	_timer = float(_def.get("telegraph", 1.0))
	_telegraph.visible = true
	_body.visible = _hover_height > 0.0
	TrapTactics.set_armed(self, true)
	if _timer <= 0.0:
		_enter_active()


func _enter_active() -> void:
	_state = State.ACTIVE
	_timer = float(_def.get("active", 0.6))
	_telegraph.visible = false
	_body.visible = true
	_area.monitoring = true
	_cooldowns.clear()
	_landed = _hover_height <= 0.0


func _enter_cooldown() -> void:
	_area.monitoring = false
	_body.visible = _hover_height > 0.0
	if _hover_height > 0.0:
		_body.position.y = _hover_height
	TrapTactics.set_armed(self, false)
	if _one_shot:
		_state = State.SPENT
		_telegraph.visible = false
		return
	_state = State.COOLDOWN
	_timer = float(_def.get("cooldown", 2.5))


func _size() -> Vector3:
	var raw: Variant = _def.get("size", [3.0, 1.0, 3.0])
	if raw is Array and (raw as Array).size() == 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3(3.0, 1.0, 3.0)


func _build_volume(size: Vector3) -> void:
	_area = Area3D.new()
	_area.name = "HazardArea"
	_area.collision_layer = 4
	_area.collision_mask = 8
	_area.monitoring = false
	_area.monitorable = false
	var box := BoxShape3D.new()
	box.size = size
	_shape = CollisionShape3D.new()
	_shape.shape = box
	_shape.position = Vector3(0.0, size.y * 0.5, 0.0)
	_area.add_child(_shape)
	add_child(_area)


func _build_meshes(size: Vector3) -> void:
	var tint := _tint()
	var biome_id := DioramaSkin.resolve_biome(self)
	var stone := BiomeRegistry.get_floor_material(biome_id)
	var metal := PixelDioramaStyle.make_metal_material(Color(0.26, 0.29, 0.32), 0.35)
	var danger := PixelDioramaStyle.make_glow_material(tint, tint * 0.45, 0.85)
	if _visual == "":
		var housing := Node3D.new()
		housing.name = "TrapHousing"
		add_child(housing)
		for side in [-1.0, 1.0]:
			_visual_box(housing, Vector3(size.x, 0.12, 0.15), Vector3(0.0, 0.06, side * size.z * 0.5), stone)
			_visual_box(housing, Vector3(0.15, 0.12, size.z), Vector3(side * size.x * 0.5, 0.06, 0.0), stone)
	var flat := BoxMesh.new()
	flat.size = Vector3(size.x * 0.88, 0.025, size.z * 0.88)
	_telegraph = MeshInstance3D.new()
	_telegraph.name = "Telegraph"
	_telegraph.mesh = flat
	_telegraph.position = Vector3(0.0, 0.025, 0.0)
	_telegraph.material_override = DioramaSkin.make_telegraph_material(
		AccessibilitySettings.emphasise_telegraph_tint(Color(tint.r, tint.g, tint.b, 0.5))
	)
	_telegraph.visible = false
	add_child(_telegraph)
	if _visual == "spikes":
		_body = DioramaSkin.build_spikes(self, biome_id, tint)
		_body.visible = false
		return
	if _visual == "falling":
		_body = DioramaSkin.build_falling_block(self, biome_id)
		_hover_height = BLOCK_HEIGHT
		_body.position.y = _hover_height
		return
	_body = Node3D.new()
	_body.name = "HazardBody"
	match trap_id:
		"poison_pool", "gas_vent", "rot_censer":
			_visual_disc(_body, minf(size.x, size.z) * 0.42, 0.12, Vector3(0.0, 0.08, 0.0), danger)
			for i in 5:
				var angle := TAU * float(i) / 5.0
				_visual_disc(_body, 0.16, 0.05, Vector3(cos(angle) * size.x * 0.23, 0.18, sin(angle) * size.z * 0.23), danger)
		"frost_trap", "ember_grate":
			for i in 4:
				var row_z := (float(i) - 1.5) * size.z * 0.2
				_visual_box(_body, Vector3(size.x * 0.78, 0.08, 0.11), Vector3(0.0, 0.08, row_z), metal)
				_visual_cone(_body, 0.18, minf(0.7, size.y), Vector3(0.0, minf(0.7, size.y) * 0.5, row_z), danger)
		"arrow_line", "bone_snare", "swinging_blade":
			for i in 5:
				var blade_x := (float(i) - 2.0) * size.x * 0.16
				_visual_cone(_body, 0.12, minf(0.85, size.y), Vector3(blade_x, minf(0.85, size.y) * 0.5, 0.0), metal)
			_visual_box(_body, Vector3(size.x * 0.84, 0.08, 0.16), Vector3(0.0, 0.06, 0.0), danger)
		_:
			for x in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					_visual_box(_body, Vector3(size.x * 0.4, 0.1, size.z * 0.4), Vector3(x * size.x * 0.22, 0.07, z * size.z * 0.22), stone)
			_visual_disc(_body, minf(size.x, size.z) * 0.18, 0.08, Vector3(0.0, 0.13, 0.0), danger)
	_body.visible = false
	add_child(_body)


func _visual_box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	_visual_part(parent, "fx/slab", size, at, material)


func _visual_disc(parent: Node3D, radius: float, height: float, at: Vector3, material: Material) -> void:
	_visual_part(parent, "fx/disc", Vector3(radius, height, radius), at, material)


func _visual_cone(parent: Node3D, radius: float, height: float, at: Vector3, material: Material) -> void:
	_visual_part(parent, "fx/spike", Vector3(radius, height, radius), at, material)


## One Blender shape (a unit slab, disc or spike) scaled to size, wearing the trap's own material.
func _visual_part(parent: Node3D, mesh_id: String, part_scale: Vector3, at: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = PropLibrary.bare_mesh(mesh_id)
	mesh.material_override = material
	mesh.position = at
	mesh.scale = part_scale
	parent.add_child(mesh)


func _tint() -> Color:
	if AccessibilitySettings.colorblind_mode != "default":
		return AccessibilitySettings.get_telegraph_class_color(HAZARD_ATTACK_CLASS)
	var raw := str(_def.get("color", ""))
	if raw != "" and Color.html_is_valid(raw):
		return Color.html(raw)
	return Color(0.85, 0.3, 0.25)


func _cycle_offset() -> float:
	var period := maxf(
		0.2,
		(
			float(_def.get("telegraph", 1.0))
			+ float(_def.get("active", 0.6))
			+ float(_def.get("cooldown", 2.5))
		)
	)
	var rng := RandomNumberGenerator.new()
	var key := "%s:%d:%d" % [trap_id, int(round(position.x * 4.0)), int(round(position.z * 4.0))]
	var run_seed: int = RunFlow.current_seed if RunFlow else 0
	rng.seed = FloorSeedMix.mix(run_seed, hash(key))
	return rng.randf() * period
