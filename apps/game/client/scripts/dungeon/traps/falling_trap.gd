extends Node3D

## Falling block trap — ceiling telegraph then crush (TRAP-2.1).

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

enum State { IDLE, TELEGRAPH, FALLING, RESET }

@export var trap_id: String = "falling_trap"
@export var damage := 25.0
@export var poise_damage := 20.0
@export var telegraph_time := 1.5
@export var fall_speed := 12.0
@export var trigger_radius := 2.5

@onready var _block: Node3D = $FallingBlock
@onready var _telegraph: MeshInstance3D = $TelegraphShadow
@onready var _hitbox: TrapDamageArea = $FallingBlock/DamageArea

var _state := State.IDLE
var _timer := 0.0
var _rest_y := 0.0
var _def: Dictionary = {}
var _strike_cfg: Dictionary = {}
var _cooldowns: Dictionary = {}
var _arms_on_enemies := false


func _ready() -> void:
	_load_definition()
	var block_mesh := _block.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if block_mesh:
		block_mesh.queue_free()
	DioramaSkin.build_falling_block(_block, DioramaSkin.resolve_biome(self))
	_rest_y = _block.position.y
	_telegraph.material_override = DioramaSkin.make_telegraph_material(Color(0.2, 0.2, 0.2, 0.6))
	_telegraph.visible = false
	_hitbox.damage = damage
	_hitbox.poise_damage = poise_damage
	_hitbox.damage_type = str(_def.get("damageType", _hitbox.damage_type))
	_hitbox.set_damage_active(false)
	_sync_trigger_radius_from_hitbox()
	TrapTactics.register_hazard(self, trigger_radius)


func _physics_process(delta: float) -> void:
	match _state:
		State.IDLE:
			if TrapTactics.trigger_present(self, trigger_radius, true, _arms_on_enemies):
				_state = State.TELEGRAPH
				_timer = telegraph_time
				_telegraph.visible = true
				TrapTactics.set_armed(self, true)
		State.TELEGRAPH:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.FALLING
				_telegraph.visible = false
				_cooldowns.clear()
				_hitbox.set_damage_active(true)
		State.FALLING:
			_block.position.y -= fall_speed * delta
			TrapTactics.strike(_hitbox, self, _strike_cfg, _cooldowns)
			if _block.position.y <= 0.2:
				_block.position.y = 0.2
				_hitbox.set_damage_active(false)
				_block.position.y = _rest_y
				_state = State.RESET
				_timer = 2.0
				TrapTactics.set_armed(self, false)
		State.RESET:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.IDLE


func is_hazard_live() -> bool:
	return _state == State.TELEGRAPH or _state == State.FALLING


func hazard_radius() -> float:
	return trigger_radius


func _load_definition() -> void:
	# C-88: explicit id, defaulted to what the node name used to derive, so renaming the scene
	# node can no longer silently change which content file the trap loads.
	# C-140: the spawner's rolled id, then the scene-path map, then the node name.
	if trap_id == "":
		trap_id = str(get_meta("trap_id", ""))
	if trap_id == "":
		trap_id = TrapTactics.trap_id_for(self)
	_def = TrapTactics.definition(trap_id)
	if _def.is_empty():
		return
	telegraph_time = float(_def.get("telegraph", telegraph_time))
	trigger_radius = float(_def.get("triggerRadius", trigger_radius))
	_arms_on_enemies = str(_def.get("trigger", "proximity")) == "plate"
	# C-128/C-129/C-130: this built a three-key dict and handed it to `TrapTactics.strike()`, which
	# reads `damage`, `poiseDamage`, `damageType` and `enemyDamageMultiplier` — none of which were
	# in it. So `strike()` resolved 0.0 damage and never entered its damage block: it walked every
	# overlap, stamped cooldowns and counted trap catches while dealing nothing, and all real damage
	# came from the parallel `TrapDamageArea`, which has no `enemyDamageMultiplier` support and read
	# its value from the `@export` rather than from content. Every one of the 12 trap definitions
	# authors `enemyDamageMultiplier` (0.7–1.25); these two authored 0.8 and applied 1.0.
	#
	# `hazard_trap` is the reference implementation and passes `_def` whole. These now do the same,
	# with the scene exports as defaults for keys the content does not author, and the
	# `TrapDamageArea` damage path is switched off so damage resolves once, through one route.
	_strike_cfg = _def.duplicate(true)
	if not _strike_cfg.has("damage"):
		_strike_cfg["damage"] = damage
	if not _strike_cfg.has("poiseDamage"):
		_strike_cfg["poiseDamage"] = poise_damage
	if not _strike_cfg.has("damageType"):
		_strike_cfg["damageType"] = _hitbox.damage_type
	# C-130: `hitInterval` used to pace only the inert path; the area that actually ticks never got
	# it. Both agree at 0.5 today, so this was latent — any trap authored with another cadence would
	# have ticked at 0.5 regardless.
	_hitbox.hit_interval = float(_strike_cfg.get("hitInterval", _hitbox.hit_interval))
	_hitbox.deals_damage = false


func _sync_trigger_radius_from_hitbox() -> void:
	var shape_node := _hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		return
	var horizontal := 0.0
	var shape := shape_node.shape
	if shape is BoxShape3D:
		var box := shape as BoxShape3D
		horizontal = maxf(box.size.x, box.size.z) * 0.5
	elif shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		horizontal = cap.radius
	elif shape is CylinderShape3D:
		var cyl := shape as CylinderShape3D
		horizontal = cyl.radius
	trigger_radius = maxf(trigger_radius, horizontal + 0.5)
