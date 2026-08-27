extends Node3D


const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

enum State { IDLE, TELEGRAPH, ACTIVE, COOLDOWN }

@export var trap_id: String = "spike_trap"
@export var damage := 18.0
@export var poise_damage := 10.0
@export var telegraph_time := 1.2
@export var active_time := 0.6
@export var cooldown_time := 2.5
@export var trigger_radius := 3.0

@onready var _telegraph_mesh: MeshInstance3D = $TelegraphMesh
var _spikes_mesh: Node3D
@onready var _hitbox: TrapDamageArea = $DamageArea

var _state := State.IDLE
var _timer := 0.0
var _def: Dictionary = {}
var _strike_cfg: Dictionary = {}
var _cooldowns: Dictionary = {}
var _arms_on_enemies := false


func _ready() -> void:
	_load_definition()
	var biome := DioramaSkin.resolve_biome(self)
	_spikes_mesh = DioramaSkin.build_spikes(self, biome)
	_spikes_mesh.visible = false
	_telegraph_mesh.material_override = DioramaSkin.make_telegraph_material(Color(1, 0.2, 0.2, 0.5))
	_telegraph_mesh.visible = false
	_hitbox.damage = damage
	_hitbox.poise_damage = poise_damage
	_hitbox.damage_type = str(_def.get("damageType", _hitbox.damage_type))
	_hitbox.set_damage_active(false)
	trigger_radius = TrapTactics.trigger_radius_for_hitbox(_hitbox, trigger_radius)
	TrapTactics.register_hazard(self, trigger_radius)


func _physics_process(delta: float) -> void:
	match _state:
		State.IDLE:
			if TrapTactics.trigger_present(self, trigger_radius, true, _arms_on_enemies):
				_state = State.TELEGRAPH
				_timer = telegraph_time
				_telegraph_mesh.visible = true
				TrapTactics.set_armed(self, true)
		State.TELEGRAPH:
			_timer -= delta
			if _timer <= 0.0:
				_activate_spikes()
		State.ACTIVE:
			_timer -= delta
			TrapTactics.strike(_hitbox, self, _strike_cfg, _cooldowns)
			if _timer <= 0.0:
				_deactivate_spikes()
		State.COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.IDLE


func hazard_radius() -> float:
	return trigger_radius


func _load_definition() -> void:
	if trap_id == "":
		trap_id = str(get_meta("trap_id", ""))
	if trap_id == "":
		trap_id = TrapTactics.trap_id_for(self)
	_def = TrapTactics.definition(trap_id)
	if _def.is_empty():
		return
	telegraph_time = float(_def.get("telegraph", telegraph_time))
	active_time = float(_def.get("active", active_time))
	cooldown_time = float(_def.get("cooldown", cooldown_time))
	trigger_radius = float(_def.get("triggerRadius", trigger_radius))
	_arms_on_enemies = str(_def.get("trigger", "proximity")) == "plate"
	_strike_cfg = _def.duplicate(true)
	if not _strike_cfg.has("damage"):
		_strike_cfg["damage"] = damage
	if not _strike_cfg.has("poiseDamage"):
		_strike_cfg["poiseDamage"] = poise_damage
	if not _strike_cfg.has("damageType"):
		_strike_cfg["damageType"] = _hitbox.damage_type
	_hitbox.hit_interval = float(_strike_cfg.get("hitInterval", _hitbox.hit_interval))
	_hitbox.deals_damage = false


func _activate_spikes() -> void:
	_state = State.ACTIVE
	_timer = active_time
	_cooldowns.clear()
	_telegraph_mesh.visible = false
	_spikes_mesh.visible = true
	_hitbox.set_damage_active(true)


func _deactivate_spikes() -> void:
	_state = State.COOLDOWN
	_timer = cooldown_time
	_spikes_mesh.visible = false
	_hitbox.set_damage_active(false)
	TrapTactics.set_armed(self, false)

