extends Node3D


const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

enum State { IDLE, TELEGRAPH, ACTIVE, COOLDOWN, SPENT }

@export var trap_id: String = ""

var _def: Dictionary = {}
var _state := State.IDLE
var _timer := 0.0
var _cooldowns: Dictionary = {}
var _area: Area3D
var _shape: CollisionShape3D
var _telegraph: MeshInstance3D
var _body: MeshInstance3D
var _trigger := "proximity"
var _radius := 3.0
var _one_shot := false


func _ready() -> void:
	if trap_id == "":
		trap_id = str(get_meta("trap_id", ""))
	if trap_id == "":
		trap_id = TrapTactics.trap_id_for(self)
	_def = TrapTactics.definition(trap_id)
	_trigger = str(_def.get("trigger", "proximity"))
	var size := _size()
	_radius = maxf(float(_def.get("triggerRadius", 0.0)), maxf(size.x, size.z) * 0.5 + 0.5)
	_one_shot = bool(_def.get("oneShot", false))
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


func _enter_telegraph() -> void:
	_state = State.TELEGRAPH
	_timer = float(_def.get("telegraph", 1.0))
	_telegraph.visible = true
	_body.visible = false
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


func _enter_cooldown() -> void:
	_area.monitoring = false
	_body.visible = false
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
	var flat := BoxMesh.new()
	flat.size = Vector3(size.x, 0.06, size.z)
	_telegraph = MeshInstance3D.new()
	_telegraph.name = "Telegraph"
	_telegraph.mesh = flat
	_telegraph.position = Vector3(0.0, 0.05, 0.0)
	_telegraph.material_override = DioramaSkin.make_telegraph_material(
		Color(tint.r, tint.g, tint.b, 0.5)
	)
	_telegraph.visible = false
	add_child(_telegraph)
	var solid := BoxMesh.new()
	solid.size = size
	_body = MeshInstance3D.new()
	_body.name = "HazardBody"
	_body.mesh = solid
	_body.position = Vector3(0.0, size.y * 0.5, 0.0)
	_body.material_override = DioramaSkin.make_telegraph_material(
		Color(tint.r, tint.g, tint.b, 0.75)
	)
	_body.visible = false
	add_child(_body)


func _tint() -> Color:
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
