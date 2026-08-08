extends Node3D

## Falling block trap — ceiling telegraph then crush (TRAP-2.1).

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

enum State { IDLE, TELEGRAPH, FALLING, RESET }

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
var _status_cfg: Dictionary = {}
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
			TrapTactics.strike(_hitbox, self, _status_cfg, _cooldowns)
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
	_def = TrapTactics.definition(TrapTactics.trap_id_for(self))
	if _def.is_empty():
		return
	telegraph_time = float(_def.get("telegraph", telegraph_time))
	trigger_radius = float(_def.get("triggerRadius", trigger_radius))
	_arms_on_enemies = str(_def.get("trigger", "proximity")) == "plate"
	_status_cfg = {
		"statusId": str(_def.get("statusId", "")),
		"statusBuildUp": float(_def.get("statusBuildUp", 0.0)),
		"hitInterval": float(_def.get("hitInterval", 0.5)),
	}


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
