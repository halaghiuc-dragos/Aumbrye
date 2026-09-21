extends Node
class_name WeaponController

enum AttackPhase { IDLE, STARTUP, ACTIVE, RECOVERY, DRAWING }

const CombatStatModifiersScript := preload("res://scripts/combat/combat_stat_modifiers.gd")
const ProjectileContainerScript := preload("res://scripts/combat/projectile_container.gd")
const AnimLibrary := preload("res://scripts/art/characters/diorama_anim_library.gd")
const WEAPON_DATA_RELATIVE := "content/weapons/sword_basic.json"
const DEFAULT_HITBOX_SIZE := Vector3(1.2, 0.8, 1.4)
const DEFAULT_HITBOX_OFFSET := Vector3(0.0, -0.12, 0.55)
const COMMIT_SPEED_MULT := 0.2
const RECOVERY_SPEED_MULT := 0.65
const POST_DODGE_ATTACK_BUFFER := 0.1
const ATTACK_ROT_CAP_MULT := 0.15
const SOFT_LOCK_CONE_DEG := 100.0
const SOFT_LOCK_RANGE := 14.0
const SOFT_LOCK_VERTICAL_LIMIT := 2.5
const TWO_HAND_DAMAGE_MULT := 1.25
const TWO_HAND_POISE_MULT := 1.35
const DEFAULT_CANCEL_INTO: Array[String] = ["dodge", "guard"]
const DEFAULT_CANCEL_AFTER := 0.55
const RUNNING_ATTACK_SPRINT_BLEND := 0.6
const EXECUTION_RANGE := 2.3
const EXECUTION_OFFSET := 1.15
const EXECUTION_FACING_DOT := 0.55
const EXECUTION_STARTUP := 0.22
const EXECUTION_ACTIVE := 0.2
const EXECUTION_RECOVERY := 0.5
const LUNGE_FRACTION_OF_STARTUP := 1.0
const LUNGE_FRACTION_OF_ACTIVE := 0.5
const LUNGE_MIN_SPEED := 0.5
const PLUNGE_MIN_FALL_TIME := 0.2
const PLUNGE_RADIUS := 2.4
const PLUNGE_FALL_HEIGHT_REF := 4.0
const PLAYER_ARROW_SCENE := preload("res://scenes/combat/player_arrow.tscn")
const ARROW_BASE_SPEED := 26.0
const WEAPON_ROLE_PROFILES := {
	"sword": {"role": "spacing", "recovery_mult": 0.9}, "axe": {"role": "guard_pressure", "poise_mult": 1.3},
	"spear": {"role": "lane_control", "lunge_mult": 1.35}, "dagger": {"role": "punish", "lunge_mult": 1.45, "damage_mult": 1.1},
	"greatsword": {"role": "crowd_control", "poise_mult": 1.2, "hyperarmor": true}, "bow": {"role": "release_timing"},
	"staff": {"role": "spell_delivery", "damage_mult": 1.12},
}

const FALLBACK_WEAPON_DATA := {
	"archetype": "sword",
	"damage_type": "physical",
	"buffer_window": 0.2,
	"lunge_distance": 0.35,
	"light_attacks":
	[
		{
			"damage": 12.0,
			"poise_damage": 10.0,
			"stamina_cost": 12.0,
			"startup": 0.15,
			"active": 0.12,
			"recovery": 0.25,
		}
	],
	"heavy_attack":
	{
		"damage": 28.0,
		"poise_damage": 35.0,
		"stamina_cost": 32.0,
		"startup": 0.35,
		"active": 0.18,
		"recovery": 0.45,
	},
}

signal attack_started(attack_name: String)
signal attack_ended
signal weapon_changed(archetype: String)

@export var hitbox_path: NodePath

var is_attacking := false
var current_phase := AttackPhase.IDLE
var is_bow_aiming := false

var _body: CharacterBody3D
var _stamina: Stamina
var _mana: Mana
var _hitbox: Area3D
var _hitbox_shape: CollisionShape3D
var _combat_reactions: PlayerCombatReactions
var _guard: Guard
var _dodge: Dodge
var _status: StatusController
var _lock_on: LockOn
var _camera_spring: OrbitCamera
var _arrows: PlayerArrows
var _weapon_data: Dictionary = {}
var _combo_index := 0
var _phase_timer := 0.0
var _current_attack: Dictionary = {}
var _buffered_attack := ""
var _attack_name := ""
var _attack_generation := 0
var _damage_multiplier := 1.0
var _draw_charge := 0.0
var _pending_bow_launch: Dictionary = {}
var _hyperarmor_active := false
## CB-02: armed by pressing light attack while falling, resolved on the `landed` signal rather
## than the fixed STARTUP/ACTIVE/RECOVERY timer every other attack uses -- a fall's duration is
## unknown in advance, so "wait for landing" cannot be a phase timer.
var _airborne_timer := 0.0
var _plunge_armed := false
## CB-01: the base `heavy_attack` dict and its `charge` config, held only while charging a melee
## heavy (`current_phase == DRAWING` for a non-bow archetype) -- distinct from the bow's own
## draw-and-fire handling in `_process_bow_input()`, which never touches these.
var _melee_charge_source: Dictionary = {}
var _melee_charge_config: Dictionary = {}
## CB-06: `empower_next` rules effect -- a one-shot multiplier consumed by the next hitbox that
## actually opens, not folded into `_damage_multiplier` (which is gear/talent state, recomputed
## whenever those change, not a single-use pickup).
var _empower_multiplier := 1.0
var _two_hand := false

var _infusion := ""
var _combo_idle_timer := 0.0
var _base_damage_multiplier := 1.0
var _weapon_scaling_multiplier := 1.0
var _class_stats: Dictionary = {}
var _talent_stats: Dictionary = {}
var _equipment_stats: Dictionary = {}
var _post_dodge_attack_buffer := 0.0
var _attack_buffer_timer := 0.0
var _art_cooldown_timer := 0.0
var _lunge_distance := 0.0
var _lunge_duration := 0.0
var _lunge_elapsed := 0.0
var _hitbox_opened_this_swing := false
var _sync_hitbox_from_anim := false
var _last_light_index := -1
var _execution_kind := ""
var _execution_target: Node3D = null
var _execution_iframes := false
var _body_reports_sprint := false


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_error(
			"WeaponController must be a direct child of a CharacterBody3D (parent=%s)"
			% [get_parent()]
		)
		set_physics_process(false)
		return
	_stamina = _body.get_node_or_null("Stamina") as Stamina
	_mana = _body.get_node_or_null("Mana") as Mana
	_combat_reactions = _body.get_node_or_null("CombatReactions") as PlayerCombatReactions
	_guard = _body.get_node_or_null("Guard") as Guard
	_dodge = _body.get_node_or_null("Dodge") as Dodge
	_status = _body.get_node_or_null("StatusController") as StatusController
	_lock_on = _body.get_node_or_null("LockOn") as LockOn
	_camera_spring = _body.get_node_or_null("CameraPivot/SpringArm3D") as OrbitCamera
	_arrows = _body.get_node_or_null("PlayerArrows") as PlayerArrows
	if _dodge:
		_dodge.dodge_started.connect(_on_dodge_started)
		_dodge.dodge_ended.connect(_on_dodge_ended)
	if _guard:
		_guard.block_state_changed.connect(_on_guard_state_changed)
	if _body.has_signal("landed"):
		_body.landed.connect(_on_body_landed)
	_body_reports_sprint = _body != null and _body.has_method("get_sprint_blend")
	call_deferred("_connect_anim_hitbox_signals")
	if hitbox_path:
		_hitbox = get_node_or_null(hitbox_path) as Area3D
		if _hitbox:
			_hitbox_shape = _hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	_load_weapon_data()


func get_debug_state() -> String:
	if not is_attacking:
		return "idle"
	var phase_name := "startup"
	match current_phase:
		AttackPhase.ACTIVE:
			phase_name = "active"
		AttackPhase.RECOVERY:
			phase_name = "recovery"
		AttackPhase.DRAWING:
			phase_name = "drawing"
	return phase_name


func _physics_process(delta: float) -> void:
	if _body and _body.has_method("is_on_floor"):
		if _body.is_on_floor():
			_airborne_timer = 0.0
			# Safety net alongside the `landed` signal: a teleport (pit recovery, respawn) can put
			# the player back on the floor without that signal ever firing, which must not leave
			# the plunge armed forever.
			if _plunge_armed and not is_attacking:
				_plunge_armed = false
		else:
			_airborne_timer += delta
	if _combo_idle_timer > 0.0:
		_combo_idle_timer -= delta
		if _combo_idle_timer <= 0.0:
			_combo_index = 0
			_last_light_index = -1
	if _post_dodge_attack_buffer > 0.0:
		_post_dodge_attack_buffer -= delta
		if _post_dodge_attack_buffer <= 0.0:
			_buffered_attack = ""
	if _attack_buffer_timer > 0.0:
		_attack_buffer_timer -= delta
		if _attack_buffer_timer <= 0.0 and _post_dodge_attack_buffer <= 0.0:
			_buffered_attack = ""
	if _art_cooldown_timer > 0.0:
		_art_cooldown_timer -= delta
	if _dodge and _dodge.is_dodging and not is_attacking and _buffered_attack == "":
		if PlayerInput.just_pressed(&"light_attack"):
			_buffered_attack = "light"
		elif PlayerInput.just_pressed(&"heavy_attack"):
			_buffered_attack = "heavy"
	if _is_action_blocked():
		_buffer_blocked_attack_input()
		if is_attacking:
			_cancel_current_action()
		return
	if PlayerInput.just_pressed(&"two_hand"):
		_toggle_two_hand()
	if PlayerInput.just_pressed(&"weapon_art"):
		_try_weapon_art()
	var archetype: String = _weapon_data.get("archetype", "sword")
	if archetype == "bow":
		_process_bow_input(delta)
		return
	if is_attacking:
		if current_phase == AttackPhase.DRAWING:
			_process_melee_charge(delta)
		else:
			_capture_attack_intent()
			_process_attack_phase(delta)
		return
	if PlayerInput.just_pressed(&"light_attack"):
		if _plunge_armed:
			pass
		elif not _try_arm_plunge():
			_try_attack("light")
	elif PlayerInput.just_pressed(&"heavy_attack"):
		_try_heavy_attack()
	if _buffered_attack != "" and not is_attacking:
		var buffered_kind := _buffered_attack
		_buffered_attack = ""
		_attack_buffer_timer = 0.0
		_try_attack(buffered_kind)


func _buffer_blocked_attack_input() -> void:
	if _buffered_attack != "":
		return
	var kind := ""
	if PlayerInput.just_pressed(&"light_attack"):
		kind = "light"
	elif PlayerInput.just_pressed(&"heavy_attack"):
		kind = "heavy"
	if kind == "":
		return
	_buffered_attack = kind
	_attack_buffer_timer = float(_weapon_data.get("buffer_window", 0.2)) + 0.1


func load_weapon_from_path(relative: String) -> void:
	if is_attacking:
		_cancel_current_action()
	_weapon_data = ContentLoader.load_json(relative)
	if _weapon_data.is_empty():
		push_warning("WeaponController: using fallback weapon data")
		_weapon_data = FALLBACK_WEAPON_DATA.duplicate(true)
	_weapon_scaling_multiplier = CombatStatModifiersScript.weapon_scaling_multiplier(
		_weapon_data.get("scaling", {}), _class_stats
	)
	if _two_hand and not _archetype_can_two_hand():
		_two_hand = false
	_refresh_damage_multiplier()
	_apply_hitbox_profile()
	weapon_changed.emit(get_archetype())


func get_weapon_id() -> String:
	return String(_weapon_data.get("id", ""))


func get_archetype() -> String:
	return String(_weapon_data.get("archetype", "sword"))


func get_weapon_art_cooldown_duration() -> float:
	var art: Dictionary = _weapon_data.get("art", {})
	if art.is_empty():
		return 0.0
	return float(art.get("cooldown", 5.0)) * _cooldown_duration_multiplier()


## HD-06: the HUD reads combat state through getters rather than reaching into private fields.
func get_next_attack_cost() -> float:
	var lights: Array = _weapon_data.get("light_attacks", [])
	if lights.is_empty():
		return 0.0
	var attack: Dictionary = lights[_combo_index % lights.size()]
	# CB-05: a mana-costed attack (the staff) has nothing to show on the stamina ghost.
	if float(attack.get("mana_cost", 0.0)) > 0.0:
		return 0.0
	return _scaled_stamina_cost(float(attack.get("stamina_cost", 10.0)))


func is_two_handed() -> bool:
	return _two_hand


func get_infusion() -> String:
	return _infusion


func get_art_cooldown_remaining() -> float:
	return _art_cooldown_timer


## CB-06: `empower_next` rules effect. Grants stack to the larger multiplier rather than
## compounding -- two "on X, empower your next attack" procs landing the same frame should not
## multiply into an outlier.
func grant_empower(multiplier: float) -> void:
	_empower_multiplier = maxf(_empower_multiplier, multiplier)


## CB-06: `reduce_cooldown` rules effect.
func reduce_art_cooldown(amount: float) -> void:
	_art_cooldown_timer = maxf(0.0, _art_cooldown_timer - amount)


func get_combo_index() -> int:
	return _combo_index if _combo_idle_timer > 0.0 else 0


func get_current_attack_animation_clip() -> StringName:
	if _attack_name.begins_with("light_"):
		var index := clampi(int(_attack_name.trim_prefix("light_")) - 1, 0, 8)
		var clips := AnimLibrary.attack_clips_for("melee", get_archetype())
		if index < clips.size():
			return clips[index]
	if _attack_name.begins_with("heavy"):
		return AnimLibrary.heavy_clip_for(get_archetype())
	match _attack_name:
		"bow_shot", "bow_draw":
			return &"attack_shoot"
		"riposte", "backstab":
			return StringName(_attack_name)
	return &""


func get_attack_generation() -> int:
	return _attack_generation


## `RG-01`: HUD reads for the bow reticle/draw arc through getters rather than reaching into
## private fields, same as every other HUD readout on this class.
func get_draw_charge() -> float:
	return _draw_charge


func get_soft_lock_aim_direction() -> Vector3:
	return _get_soft_lock_aim_direction()


func get_aim_point(origin: Vector3) -> Vector3:
	if _lock_on and _lock_on.is_locked and _lock_on.current_target:
		return LockOn.get_target_aim_point(_lock_on.current_target as Node3D)
	return _camera_aim_point(origin)


func _cooldown_duration_multiplier() -> float:
	var reduction := CombatStatModifiersScript.cooldown_reduction(_equipment_stats, _talent_stats)
	return maxf(0.1, 1.0 - reduction)


func get_current_attack_phases() -> Dictionary:
	return {
		"startup": float(_current_attack.get("startup", 0.2)),
		"active": float(_current_attack.get("active", 0.15)),
		"recovery": float(_current_attack.get("recovery", 0.3)),
	}


func set_damage_multiplier(multiplier: float) -> void:
	_base_damage_multiplier = maxf(0.1, multiplier)
	_refresh_damage_multiplier()


func set_infusion(element: String) -> void:
	_infusion = element if element in DamageInfo.ALL_TYPES else ""


func set_combat_stat_modifiers(
	equipment_stats: Dictionary, talent_stats: Dictionary, class_stats: Dictionary = {}
) -> void:
	_equipment_stats = equipment_stats
	_class_stats = class_stats
	_talent_stats = talent_stats
	_weapon_scaling_multiplier = CombatStatModifiersScript.weapon_scaling_multiplier(
		_weapon_data.get("scaling", {}), _class_stats
	)
	set_damage_multiplier(
		CombatStatModifiersScript.damage_multiplier(equipment_stats, talent_stats)
	)


func has_hyperarmor() -> bool:
	return _hyperarmor_active


func locks_movement() -> bool:
	if not is_attacking:
		return false
	if current_phase == AttackPhase.DRAWING:
		return true
	if current_phase == AttackPhase.RECOVERY and _can_cancel_any():
		return false
	return current_phase in [AttackPhase.STARTUP, AttackPhase.ACTIVE, AttackPhase.RECOVERY]


func allows_cancel_into(action: String) -> bool:
	if not is_attacking:
		return true
	if current_phase != AttackPhase.RECOVERY:
		return false
	var options: Array = _current_attack.get(
		"cancel_into", _weapon_data.get("cancel_into", DEFAULT_CANCEL_INTO)
	)
	if not options.has(action):
		return false
	var recovery := float(_current_attack.get("recovery", 0.3))
	if recovery <= 0.0:
		return true
	var after := clampf(
		float(
			_current_attack.get(
				"cancel_after", _weapon_data.get("cancel_after", DEFAULT_CANCEL_AFTER)
			)
		),
		0.0,
		1.0
	)
	return _phase_timer <= recovery * (1.0 - after)


func _can_cancel_any() -> bool:
	return allows_cancel_into("dodge") or allows_cancel_into("guard")


func get_move_speed_multiplier() -> float:
	if not is_attacking:
		return 1.0
	if current_phase in [AttackPhase.STARTUP, AttackPhase.ACTIVE, AttackPhase.DRAWING]:
		return COMMIT_SPEED_MULT
	if current_phase == AttackPhase.RECOVERY:
		return RECOVERY_SPEED_MULT
	return 1.0


func get_rotation_cap_multiplier() -> float:
	if (
		is_attacking
		and current_phase in [AttackPhase.STARTUP, AttackPhase.ACTIVE, AttackPhase.DRAWING]
	):
		return ATTACK_ROT_CAP_MULT
	return 1.0


func get_attack_lunge_velocity() -> Vector3:
	if not is_attacking or _body == null:
		return Vector3.ZERO
	if current_phase != AttackPhase.STARTUP and current_phase != AttackPhase.ACTIVE:
		return Vector3.ZERO
	if _lunge_distance <= 0.0 or _lunge_duration <= 0.0:
		return Vector3.ZERO
	if _lunge_elapsed >= _lunge_duration:
		return Vector3.ZERO
	var speed := maxf(LUNGE_MIN_SPEED, _lunge_distance / _lunge_duration)
	var forward: Vector3 = (
		_body.get_facing_direction()
		if _body.has_method("get_facing_direction")
		else CombatFacing.forward_of(_body)
	)
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		return Vector3.ZERO
	return forward.normalized() * speed


## `RG-01`: `OrbitCamera.set_aim_active` composes with lock-on's own dolly/FOV rather than a second
## camera mode -- driven every bow-input frame so releasing block/light-attack relaxes the camera
## the same frame `is_bow_aiming` goes false.
func _sync_camera_aim_state() -> void:
	if _camera_spring and _camera_spring.has_method("set_aim_active"):
		_camera_spring.call("set_aim_active", is_bow_aiming)


## `AN-04`: growing tremor while a bow draw charges.
func _update_charge_shake(amount: float) -> void:
	var director := _body.get_node_or_null("AnimDirector") if _body else null
	if director and director.has_method("set_charge_shake"):
		director.call("set_charge_shake", amount)


func _connect_anim_hitbox_signals() -> bool:
	var director := _body.get_node_or_null("AnimDirector") if _body else null
	if director == null:
		return false
	var clip := get_current_attack_animation_clip()
	if clip == &"" or not director.has_method("has_hitbox_markers"):
		return false
	if not bool(director.call("has_hitbox_markers", clip)):
		return false
	var connected := false
	if director.has_signal("hitbox_open_frame"):
		if not director.hitbox_open_frame.is_connected(enable_hitbox_from_anim):
			director.hitbox_open_frame.connect(enable_hitbox_from_anim)
		connected = true
	if director.has_signal("hitbox_close_frame"):
		if not director.hitbox_close_frame.is_connected(disable_hitbox_from_anim):
			director.hitbox_close_frame.connect(disable_hitbox_from_anim)
		connected = true
	return connected and director.has_signal("hitbox_open_frame") and director.has_signal("hitbox_close_frame")


func enable_hitbox_from_anim(generation: int = -1) -> void:
	if generation != _attack_generation:
		return
	if not is_attacking:
		return
	if current_phase != AttackPhase.STARTUP and current_phase != AttackPhase.ACTIVE:
		return
	if _hitbox_opened_this_swing:
		return
	_hitbox_opened_this_swing = true
	if current_phase == AttackPhase.STARTUP:
		current_phase = AttackPhase.ACTIVE
		_phase_timer = float(_current_attack.get("active", 0.15))
		_snap_soft_lock_facing()
	_enable_hitbox_for_attack()


func disable_hitbox_from_anim(generation: int = -1) -> void:
	if generation != _attack_generation:
		return
	_disable_hitbox()
	if not _sync_hitbox_from_anim or current_phase != AttackPhase.ACTIVE:
		return
	current_phase = AttackPhase.RECOVERY
	_phase_timer = float(_current_attack.get("recovery", 0.3))
	_hyperarmor_active = false


func _load_weapon_data() -> void:
	var path := WEAPON_DATA_RELATIVE
	if (
		InventoryService
		and is_instance_valid(InventoryService)
		and InventoryService.inventory
		and InventoryService.inventory.has_method("get_equipped_weapon_data_path")
	):
		var equipped := str(InventoryService.inventory.get_equipped_weapon_data_path())
		if equipped != "":
			path = equipped
	load_weapon_from_path(path)


func _try_attack(kind: String) -> void:
	if is_attacking:
		_buffer_attack_intent(kind)
		return
	if _try_start_execution():
		return
	var attack: Dictionary = _situational_attack(kind)
	if attack.is_empty():
		if kind == "heavy":
			attack = _resolve_heavy_attack()
			_attack_name = "heavy"
			_combo_index = 0
			_last_light_index = -1
		else:
			var lights: Array = _weapon_data.get("light_attacks", [])
			if lights.is_empty():
				return
			_combo_index = _combo_index % lights.size()
			attack = lights[_combo_index]
			_attack_name = "light_%d" % (_combo_index + 1)
			_last_light_index = _combo_index
	if attack.is_empty():
		return
	if not _consume_attack_cost(attack):
		return
	_snap_soft_lock_facing()
	_start_attack(attack)


func _capture_attack_intent() -> void:
	var kind := ""
	if PlayerInput.just_pressed(&"light_attack"):
		kind = "light"
	elif PlayerInput.just_pressed(&"heavy_attack"):
		kind = "heavy"
	if kind != "":
		_buffer_attack_intent(kind)


func _buffer_attack_intent(kind: String) -> void:
	var buffer_window := float(_weapon_data.get("buffer_window", 0.2))
	var remaining := _phase_timer
	if current_phase == AttackPhase.STARTUP:
		remaining += float(_current_attack.get("active", 0.15))
		remaining += float(_current_attack.get("recovery", 0.3))
	elif current_phase == AttackPhase.ACTIVE:
		remaining += float(_current_attack.get("recovery", 0.3))
	if remaining > buffer_window:
		return
	# A single slot intentionally uses latest-input replacement; it cannot queue a sequence.
	_buffered_attack = kind
	_attack_buffer_timer = buffer_window + 0.1


## CB-05: the staff's identity trait -- an attack with a `mana_cost` spends `Mana` instead of
## `Stamina`, checked and consumed the same way every other attack already handles affordability.
func _consume_attack_cost(attack: Dictionary) -> bool:
	var mana_cost := float(attack.get("mana_cost", 0.0))
	var stamina_cost: float = _scaled_stamina_cost(float(attack.get("stamina_cost", 10.0)))
	if mana_cost > 0.0 and (_mana == null or not _mana.has(mana_cost)):
		return false
	if stamina_cost > 0.0 and (_stamina == null or not _stamina.has(stamina_cost)):
		return false
	# Both requirements are checked before either component is mutated.
	if mana_cost > 0.0:
		_mana.consume(mana_cost)
	if stamina_cost > 0.0:
		_stamina.consume(stamina_cost)
	return true


func _situational_attack(kind: String) -> Dictionary:
	if kind != "light":
		return {}
	if _post_dodge_attack_buffer > 0.0:
		var rolling: Dictionary = _weapon_data.get("rolling_attack", {})
		if not rolling.is_empty():
			_attack_name = "rolling"
			_combo_index = 0
			_last_light_index = -1
			return rolling
	if _sprint_blend() >= RUNNING_ATTACK_SPRINT_BLEND:
		var running: Dictionary = _weapon_data.get("running_attack", {})
		if not running.is_empty():
			_attack_name = "running"
			_combo_index = 0
			_last_light_index = -1
			return running
	return {}


func _sprint_blend() -> float:
	if not _body_reports_sprint:
		return 0.0
	return float(_body.call("get_sprint_blend"))


func _resolve_heavy_attack() -> Dictionary:
	var lights: Array = _weapon_data.get("light_attacks", [])
	if _last_light_index >= 0 and _combo_idle_timer > 0.0 and _last_light_index < lights.size():
		var entry: Dictionary = lights[_last_light_index]
		if entry.has("heavy_branch"):
			var chain: Array = _weapon_data.get("heavy_attacks", [])
			var branch := int(entry.get("heavy_branch", -1))
			if branch >= 0 and branch < chain.size():
				return chain[branch]
	return _weapon_data.get("heavy_attack", {})


## CB-01: only the base `heavy_attack` (not a combo's `heavy_branch`) ever carries a `charge`
## block, so a mid-combo heavy still fires instantly the way it always has.
## CB-02: arms a plunge attack instead of a normal light swing when the fall has gone on long
## enough to be deliberate (0.2 s) -- a short hop should not turn every landing into an attack.
func _try_arm_plunge() -> bool:
	if _body == null or _body.is_on_floor() or _airborne_timer <= PLUNGE_MIN_FALL_TIME:
		return false
	var plunge: Variant = _weapon_data.get("plunge_attack", {})
	if not (plunge is Dictionary) or (plunge as Dictionary).is_empty():
		return false
	_plunge_armed = true
	_attack_name = "plunge_arm"
	attack_started.emit("plunge_arm")
	return true


## Fires on `Locomotion.landed` -- not the STARTUP/ACTIVE/RECOVERY timer every other attack uses,
## since a fall's duration cannot be known in advance the way a swing's can.
func _on_body_landed(fall_height: float) -> void:
	if not _plunge_armed:
		return
	_plunge_armed = false
	var plunge: Dictionary = _weapon_data.get("plunge_attack", {})
	if plunge.is_empty():
		return
	var cost := _scaled_stamina_cost(float(plunge.get("stamina_cost", 0.0)))
	if _stamina and not _stamina.has(cost):
		attack_ended.emit()
		return
	if _stamina:
		_stamina.consume(cost)
	var fall_scale := clampf(fall_height / PLUNGE_FALL_HEIGHT_REF, 1.0, 2.0)
	var scaled := plunge.duplicate(true)
	scaled["damage"] = float(scaled.get("damage", 20.0)) * fall_scale
	scaled["poise_damage"] = float(scaled.get("poise_damage", 20.0)) * fall_scale
	_deal_plunge_damage(scaled)
	attack_ended.emit()


## AOE around the landing point rather than the swing hitbox, which is shaped and bone-anchored
## for a normal attack and has nowhere sensible to be for "everyone near where I landed."
func _deal_plunge_damage(attack: Dictionary) -> void:
	if _body == null:
		return
	var base_damage := float(attack.get("damage", 20.0))
	var dmg := base_damage * _damage_multiplier
	dmg += CombatStatModifiersScript.flat_damage_bonus(
		_equipment_stats, CombatStatModifiersScript.attack_weight(attack, _weapon_data), base_damage
	)
	var poise := (
		float(attack.get("poise_damage", 20.0))
		* _damage_multiplier
		* CombatStatModifiersScript.poise_damage_multiplier(_equipment_stats, _talent_stats)
	)
	var dmg_type: String = attack.get("damage_type", _weapon_data.get("damage_type", "physical"))
	var knockback := float(attack.get("knockback", 0.0))
	var origin := _body.global_position
	var radius_sq := PLUNGE_RADIUS * PLUNGE_RADIUS
	var vertical_tolerance := float(attack.get("vertical_tolerance", 1.75))
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	for node in CombatGroups.hostiles(get_tree()):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and enemy.call("is_dead"):
			continue
		var offset := enemy.global_position - origin
		var vertical_distance := absf(offset.y)
		offset.y = 0.0
		if offset.length_squared() > radius_sq or vertical_distance > vertical_tolerance:
			continue
		var query := PhysicsRayQueryParameters3D.create(origin, enemy.global_position)
		query.collision_mask = CombatLayers.WORLD_OCCLUDERS
		query.exclude = [_body]
		var obstruction: Dictionary = space.intersect_ray(query)
		if not obstruction.is_empty() and obstruction.get("collider") != enemy:
			continue
		var hurtbox := enemy.get_node_or_null("Hurtbox")
		if hurtbox == null or not hurtbox.has_method("receive_hit"):
			continue
		var direction := offset.normalized() if offset.length_squared() > 0.0001 else Vector3.FORWARD
		var info := DamageInfo.create(dmg, poise, _body, dmg_type, direction, "", 1, "unblockable")
		info.knockback = knockback
		hurtbox.call("receive_hit", info)
	if VfxService:
		VfxService.play_attack_swing(origin)


func _try_heavy_attack() -> void:
	if _try_start_execution():
		return
	var heavy := _resolve_heavy_attack()
	var charge_cfg: Variant = heavy.get("charge", {})
	if charge_cfg is Dictionary and not (charge_cfg as Dictionary).is_empty():
		_begin_melee_charge(heavy, charge_cfg as Dictionary)
		return
	_try_attack("heavy")


func _begin_melee_charge(heavy: Dictionary, charge_cfg: Dictionary) -> void:
	if _stamina:
		_stamina.set_regen_state(Stamina.RegenState.SUPPRESSED)
	if _mana:
		_mana.set_regen_state(Mana.RegenState.SUPPRESSED)
	_melee_charge_source = heavy
	_melee_charge_config = charge_cfg
	_draw_charge = 0.0
	is_attacking = true
	current_phase = AttackPhase.DRAWING
	_attack_name = "heavy_charge"
	_combo_index = 0
	_last_light_index = -1
	_snap_soft_lock_facing()
	attack_started.emit("heavy_charge")


## Holding accumulates charge toward `max_time`; releasing (or maxing out) fires the swing scaled
## by however far the charge got. Movement is already locked to `COMMIT_SPEED_MULT` for the whole
## hold -- `get_move_speed_multiplier()`/`locks_movement()` already treat `DRAWING` that way.
func _process_melee_charge(delta: float) -> void:
	var max_time := maxf(0.05, float(_melee_charge_config.get("max_time", 0.9)))
	if PlayerInput.pressed(&"heavy_attack"):
		_draw_charge = minf(1.0, _draw_charge + delta / max_time)
		if _draw_charge >= 1.0:
			_fire_charged_heavy()
		return
	_fire_charged_heavy()


func _fire_charged_heavy() -> void:
	var cfg := _melee_charge_config
	var charge := _draw_charge
	var scaled: Dictionary = _melee_charge_source.duplicate(true)
	scaled.erase("charge")
	var dmg_mult := lerpf(1.0, float(cfg.get("damage_mult", 1.0)), charge)
	var poise_mult := lerpf(1.0, float(cfg.get("poise_mult", 1.0)), charge)
	var stamina_mult := lerpf(1.0, float(cfg.get("stamina_mult", 1.0)), charge)
	scaled["damage"] = float(scaled.get("damage", 20.0)) * dmg_mult
	scaled["poise_damage"] = float(scaled.get("poise_damage", 20.0)) * poise_mult
	scaled["stamina_cost"] = float(scaled.get("stamina_cost", 20.0)) * stamina_mult
	if scaled.has("lunge_distance"):
		scaled["lunge_distance"] = float(scaled["lunge_distance"]) * dmg_mult
	if cfg.has("hyperarmor_at"):
		# The charge threshold owns this move's armor decision; do not inherit the base heavy's
		# unconditional flag below the authored threshold.
		scaled["hyperarmor"] = charge >= float(cfg["hyperarmor_at"])
	var cost := _scaled_stamina_cost(float(scaled.get("stamina_cost", 20.0)))
	if _stamina and not _stamina.has(cost):
		_cancel_melee_charge()
		return
	if _stamina:
		_stamina.consume(cost)
	_melee_charge_source = {}
	_melee_charge_config = {}
	_attack_name = "heavy"
	_start_attack(scaled)


## A charge that cannot be afforded at release fizzles rather than firing anyway -- the same rule
## every other attack already follows (`_try_attack()` never spends stamina it does not have).
func _cancel_melee_charge() -> void:
	var was_charging := is_attacking and current_phase == AttackPhase.DRAWING
	if _stamina:
		_stamina.set_regen_state(Stamina.RegenState.NORMAL)
	if _mana:
		_mana.set_regen_state(Mana.RegenState.NORMAL)
	_melee_charge_source = {}
	_melee_charge_config = {}
	_draw_charge = 0.0
	is_attacking = false
	current_phase = AttackPhase.IDLE
	_attack_name = ""
	_update_charge_shake(0.0)
	if was_charging:
		attack_ended.emit()


func _cancel_current_action() -> void:
	if current_phase != AttackPhase.DRAWING:
		_cancel_attack()
		return
	if get_archetype() == "bow":
		_reset_bow()
	else:
		_cancel_melee_charge()


func _try_weapon_art() -> void:
	if is_attacking or _art_cooldown_timer > 0.0:
		return
	var art: Dictionary = _weapon_data.get("art", {})
	if art.is_empty():
		return
	var cost: float = _scaled_stamina_cost(float(art.get("stamina_cost", 24.0)))
	if _stamina and not _stamina.has(cost):
		return
	var behavior := str(art.get("behavior", art.get("id", "attack")))
	if behavior == "arcane_nova":
		if not _consume_art_cost(cost):
			return
		_art_cooldown_timer = get_weapon_art_cooldown_duration()
		_cast_arcane_nova(art)
		return
	if behavior == "piercing_shot":
		if not _consume_art_cost(cost):
			return
		var shot := _prepare_arrow_launch(art, 1.0)
		var arrow := shot.get("arrow") as Node3D
		if shot.is_empty() or arrow == null:
			if _stamina:
				_stamina.restore(cost)
			return
		arrow.set("pierce", maxi(1, int(art.get("pierce", 2))))
		if not _commit_arrow_launch(shot):
			if _stamina:
				_stamina.restore(cost)
			_discard_arrow_request(shot)
			return
		_art_cooldown_timer = get_weapon_art_cooldown_duration()
		return
	if _stamina:
		_stamina.consume(cost)
	var attack := {
		"damage": float(art.get("damage", 20.0)),
		"poise_damage": float(art.get("poise_damage", 18.0)),
		"startup": float(art.get("startup", 0.25)),
		"active": float(art.get("active", 0.18)),
		"recovery": float(art.get("recovery", 0.4)),
		"lunge_distance": float(art.get("lunge_distance", _weapon_data.get("lunge_distance", 0.0))),
		"hyperarmor": bool(art.get("hyperarmor", true)),
		"knockback": float(art.get("knockback", 0.0)),
	}
	if behavior == "guard_break":
		attack["poise_damage"] = float(attack["poise_damage"]) * float(art.get("guard_break_mult", 2.0))
	_attack_name = "weapon_art"
	_art_cooldown_timer = get_weapon_art_cooldown_duration()
	_snap_soft_lock_facing()
	_start_attack(attack)


func _consume_art_cost(cost: float) -> bool:
	return _stamina == null or _stamina.consume(cost)


func _cast_arcane_nova(art: Dictionary) -> void:
	if _body == null or _body.get_tree() == null:
		return
	var radius := maxf(0.5, float(art.get("radius", 4.0)))
	var damage := float(art.get("damage", 20.0)) * _damage_multiplier
	var poise := float(art.get("poise_damage", 18.0))
	var damage_type := str(art.get("damage_type", DamageInfo.TYPE_ARCANE))
	for node in _body.get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Node3D
		if enemy == null or enemy.global_position.distance_to(_body.global_position) > radius:
			continue
		var hurtbox := enemy.get_node_or_null("Hurtbox")
		if hurtbox and hurtbox.has_method("receive_hit"):
			var direction := (enemy.global_position - _body.global_position).normalized()
			hurtbox.call("receive_hit", DamageInfo.create(damage, poise, _body, damage_type, direction))
	if VfxService:
		VfxService.play_rune_flare(_body.global_position)


func _try_start_execution() -> bool:
	if _body == null or get_archetype() == "bow":
		return false
	var kind := "riposte"
	var victim := _resolve_riposte_target()
	# CB-04: a poise-broken enemy plays the same riposte execution -- breaking poise costs the
	# player real effort (poise_damage is a stat gear rolls for) and used to pay out nothing but a
	# stagger animation.
	if victim == null:
		victim = _resolve_poise_break_target()
	if victim == null:
		victim = _resolve_backstab_target()
		kind = "backstab"
	if victim == null:
		return false
	var execution_pose := _execution_target_position(victim, kind)
	if execution_pose == Vector3.INF or not _execution_path_clear(victim, execution_pose):
		return false
	var attack := _execution_attack(kind)
	var cost := _scaled_stamina_cost(float(attack.get("stamina_cost", 20.0)))
	if _stamina and not _stamina.has(cost):
		return false
	var victim_poise := victim.get_node_or_null("Poise") as Poise
	_execution_kind = kind
	_execution_target = victim
	if not _snap_to_execution_position(victim, execution_pose):
		# Alignment was reserved but could not be achieved; retain every execution opportunity.
		_execution_kind = ""
		_execution_target = null
		return false
	if _stamina and not _stamina.consume(cost):
		_execution_kind = ""
		_execution_target = null
		return false
	if kind == "riposte" and _guard:
		_guard.consume_riposte()
	if victim_poise:
		victim_poise.execution_available = false
	if _dodge and not _execution_iframes:
		_execution_iframes = true
		_dodge.grant_external_iframes(true, &"execution")
	# VS-09: the camera moment an execution deserves -- runs entirely inside the i-frame window
	# just granted above, so it never costs the player control.
	if _camera_spring and _camera_spring.has_method("play_execution_framing"):
		_camera_spring.call("play_execution_framing", victim)
	_attack_name = kind
	_combo_index = 0
	_last_light_index = -1
	if CombatEvents:
		CombatEvents.dispatch(CombatEvents.ON_EXECUTE, {"actor": _body, "target": victim})
	_start_attack(attack)
	return true


func _execution_attack(kind: String) -> Dictionary:
	var base: Dictionary = _weapon_data.get("heavy_attack", {})
	if base.is_empty():
		base = FALLBACK_WEAPON_DATA["heavy_attack"]
	var attack: Dictionary = base.duplicate(true)
	attack["startup"] = EXECUTION_STARTUP
	attack["active"] = EXECUTION_ACTIVE
	attack["recovery"] = EXECUTION_RECOVERY
	attack["lunge_distance"] = 0.0
	attack["hyperarmor"] = true
	attack["cancel_into"] = [] as Array[String]
	if kind == "riposte":
		attack["damage"] = float(attack.get("damage", 28.0)) * Guard.RIPOSTE_DAMAGE_MULT
		attack["poise_damage"] = float(attack.get("poise_damage", 35.0)) * Guard.RIPOSTE_DAMAGE_MULT
	return attack


func _resolve_riposte_target() -> Node3D:
	if _guard == null or not _guard.riposte_active:
		return null
	var victim := _guard.parried_target as Node3D
	if victim == null or not is_instance_valid(victim):
		return null
	if victim.has_method("is_dead") and victim.call("is_dead"):
		return null
	if not _is_in_execution_range(victim):
		return null
	return victim


## CB-04: `Poise.execution_available` gates this to once per break -- without it a fast weapon
## could execute the same stagger repeatedly before it ends.
func _resolve_poise_break_target() -> Node3D:
	var facing := _facing_forward()
	if facing.length_squared() < 0.01:
		return null
	var origin := _body.global_position
	for node in CombatGroups.hostiles(get_tree()):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and enemy.call("is_dead"):
			continue
		var poise := enemy.get_node_or_null("Poise") as Poise
		if poise == null or not poise.is_broken() or not poise.execution_available:
			continue
		if not _is_in_execution_range(enemy):
			continue
		var offset := enemy.global_position - origin
		offset.y = 0.0
		if offset.length_squared() < 0.0001:
			continue
		if facing.dot(offset.normalized()) < EXECUTION_FACING_DOT:
			continue
		return enemy
	return null


func _resolve_backstab_target() -> Node3D:
	var facing := _facing_forward()
	if facing.length_squared() < 0.01:
		return null
	var origin := _body.global_position
	var best: Node3D = null
	var best_dist := EXECUTION_RANGE * EXECUTION_RANGE
	for node in CombatGroups.hostiles(get_tree()):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and enemy.call("is_dead"):
			continue
		var offset := enemy.global_position - origin
		offset.y = 0.0
		var dist_sq := offset.length_squared()
		if dist_sq >= best_dist or dist_sq < 0.0004:
			continue
		if facing.dot(offset.normalized()) < EXECUTION_FACING_DOT:
			continue
		if DamageInfo.classify_arc(enemy, origin) != DamageInfo.HitArc.BACK:
			continue
		best_dist = dist_sq
		best = enemy
	return best


func _is_in_execution_range(victim: Node3D) -> bool:
	var offset := victim.global_position - _body.global_position
	offset.y = 0.0
	return offset.length_squared() <= EXECUTION_RANGE * EXECUTION_RANGE


func _facing_forward() -> Vector3:
	var forward: Vector3 = (
		_body.get_facing_direction()
		if _body.has_method("get_facing_direction")
		else CombatFacing.forward_of(_body)
	)
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		return Vector3.ZERO
	return forward.normalized()


func _execution_target_position(victim: Node3D, kind: String) -> Vector3:
	var facing_node := victim.get_node_or_null("Facing") as Node3D
	var forward := CombatFacing.forward_of(facing_node if facing_node else victim)
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		return Vector3.INF
	forward = forward.normalized()
	var target_pos := victim.global_position + forward * EXECUTION_OFFSET
	if kind == "backstab":
		target_pos = victim.global_position - forward * EXECUTION_OFFSET
	target_pos.y = _body.global_position.y
	return target_pos


func _execution_path_clear(victim: Node3D, target_pos: Vector3) -> bool:
	if absf(victim.global_position.y - _body.global_position.y) > 1.25:
		return false
	var space := _body.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		_body.global_position + Vector3.UP, victim.global_position + Vector3.UP
	)
	query.exclude = [_body.get_rid(), victim.get_rid()]
	if not space.intersect_ray(query).is_empty():
		return false
	if _body is CharacterBody3D:
		return not (_body as CharacterBody3D).test_move(_body.global_transform, target_pos - _body.global_position)
	return true


func _snap_to_execution_position(victim: Node3D, target_pos: Vector3) -> bool:
	if _body is CharacterBody3D:
		var motion := target_pos - _body.global_position
		if motion.length_squared() > 0.000001:
			(_body as CharacterBody3D).move_and_collide(motion)
	else:
		_body.global_position = target_pos
	if _body.global_position.distance_to(target_pos) > 0.18:
		return false
	_body.velocity = Vector3.ZERO
	_body.reset_physics_interpolation()
	_face_target(victim)
	return true


func _clear_execution_state() -> void:
	if _execution_iframes:
		_execution_iframes = false
		if _dodge:
			_dodge.grant_external_iframes(false, &"execution")
	_execution_kind = ""
	_execution_target = null


## Attack speed is applied once, here, by scaling the timings into the copy of the attack this
## swing will use. Every consumer downstream -- the phase machine, the animation director, the
## cancel window, the lunge -- reads its timings off `_current_attack`, so scaling at the source
## is the only way they are guaranteed to agree. Scaling at each call site instead would let the
## hitbox open on a frame the animation had not reached yet the first time one was missed.
##
## The copy matters: the attack dictionaries come straight out of the weapon data, and writing
## scaled numbers back into those would compound the multiplier on every swing.
func _scaled_attack(attack: Dictionary) -> Dictionary:
	var scale := CombatStatModifiersScript.attack_phase_scale(_equipment_stats, _talent_stats)
	if is_equal_approx(scale, 1.0):
		return attack
	var scaled := attack.duplicate(true)
	# `cancel_after` is a dimensionless fraction of recovery and must not be timing-scaled.
	for key in ["startup", "active", "recovery"]:
		if scaled.has(key):
			scaled[key] = float(scaled[key]) * scale
	return scaled


func _start_attack(attack_source: Dictionary) -> void:
	_attack_generation += 1
	if _stamina:
		_stamina.set_regen_state(Stamina.RegenState.SUPPRESSED)
	if _mana:
		_mana.set_regen_state(Mana.RegenState.SUPPRESSED)
	var attack := _apply_weapon_role(_scaled_attack(attack_source))
	_current_attack = attack
	is_attacking = true
	current_phase = AttackPhase.STARTUP
	_phase_timer = attack.get("startup", 0.2)
	_hyperarmor_active = bool(attack.get("hyperarmor", false))
	if not _hyperarmor_active:
		_hyperarmor_active = float(attack.get("poise_threshold", 0.0)) > 0.0
	_hitbox_opened_this_swing = false
	var startup := float(attack.get("startup", 0.2))
	var active := float(attack.get("active", 0.15))
	_lunge_distance = float(attack.get("lunge_distance", _weapon_data.get("lunge_distance", 0.0)))
	_lunge_duration = startup * LUNGE_FRACTION_OF_STARTUP + active * LUNGE_FRACTION_OF_ACTIVE
	_lunge_elapsed = 0.0
	if _hitbox and _hitbox.has_method("reset_swing"):
		_hitbox.call("reset_swing")
	var director := _body.get_node_or_null("AnimDirector") if _body else null
	var director_bound := (
		director != null and director.has_method("is_bound") and bool(director.call("is_bound"))
	)
	_sync_hitbox_from_anim = director_bound and _connect_anim_hitbox_signals()
	attack_started.emit(_attack_name)


func _apply_weapon_role(attack: Dictionary) -> Dictionary:
	var profile: Dictionary = WEAPON_ROLE_PROFILES.get(get_archetype(), {})
	attack["weaponRole"] = str(profile.get("role", ""))
	attack["damage"] = float(attack.get("damage", 0.0)) * float(profile.get("damage_mult", 1.0))
	attack["poise_damage"] = float(attack.get("poise_damage", 0.0)) * float(profile.get("poise_mult", 1.0))
	attack["lunge_distance"] = float(attack.get("lunge_distance", _weapon_data.get("lunge_distance", 0.0))) * float(profile.get("lunge_mult", 1.0))
	attack["recovery"] = float(attack.get("recovery", 0.0)) * float(profile.get("recovery_mult", 1.0))
	if bool(profile.get("hyperarmor", false)):
		attack["hyperarmor"] = true
	return attack


func _play_swing_feedback() -> void:
	if _body == null:
		return
	var anchor: Array = VfxService.resolve_combat_anchor(_body)
	VfxService.play_attack_swing(anchor[0], anchor[1])


func _process_attack_phase(delta: float) -> void:
	if current_phase in [AttackPhase.STARTUP, AttackPhase.ACTIVE]:
		_lunge_elapsed += delta
	_phase_timer -= delta
	var transitions := 0
	while is_attacking and _phase_timer <= 0.0 and transitions < 4:
		transitions += 1
		var overshoot := _phase_timer
		match current_phase:
			AttackPhase.STARTUP:
				if _attack_name == "bow_shot" and not _commit_pending_bow_launch():
					_cancel_attack()
					return
				_play_swing_feedback()
				current_phase = AttackPhase.ACTIVE
				_phase_timer = float(_current_attack.get("active", 0.15)) + overshoot
				_snap_soft_lock_facing()
				if not _sync_hitbox_from_anim and not _hitbox_opened_this_swing:
					_enable_hitbox_for_attack()
					_hitbox_opened_this_swing = true
			AttackPhase.ACTIVE:
				# Opening then closing here explicitly samples an active interval crossed by a hitch.
				if not _sync_hitbox_from_anim and not _hitbox_opened_this_swing:
					_enable_hitbox_for_attack()
					_hitbox_opened_this_swing = true
				current_phase = AttackPhase.RECOVERY
				_phase_timer = float(_current_attack.get("recovery", 0.3)) + overshoot
				_disable_hitbox()
				_hyperarmor_active = false
			AttackPhase.RECOVERY:
				_end_attack()
			AttackPhase.DRAWING:
				break


func _enable_hitbox_for_attack() -> void:
	if _hitbox == null or not _hitbox.has_method("enable"):
		return
	var base_damage: float = float(_current_attack.get("damage", 10.0))
	var dmg: float = base_damage * _damage_multiplier * _empower_multiplier
	_empower_multiplier = 1.0
	dmg += CombatStatModifiersScript.flat_damage_bonus(
		_equipment_stats,
		CombatStatModifiersScript.attack_weight(_current_attack, _weapon_data),
		base_damage
	)
	if _body:
		dmg *= ClassPerks.bloodrage_damage_multiplier(
			_body, _body.get_node_or_null("Health") as Health
		)
	var poise: float = (
		float(_current_attack.get("poise_damage", 10.0))
		* _damage_multiplier
		* CombatStatModifiersScript.poise_damage_multiplier(_equipment_stats, _talent_stats)
	)
	if _two_hand:
		poise *= TWO_HAND_POISE_MULT
	var dmg_type: String = _current_attack.get(
		"damage_type", _weapon_data.get("damage_type", "physical")
	)
	if _infusion != "":
		dmg_type = _infusion
	var status_id: String = _current_attack.get("status", _weapon_data.get("status_on_hit", ""))
	var status_stacks: int = int(_current_attack.get("status_stacks", 1))
	var crit := CombatStatModifiersScript.crit_chance(_equipment_stats, _talent_stats)
	var crit_mult := CombatStatModifiersScript.crit_multiplier(_equipment_stats, _talent_stats)
	var knockback: float = float(
		_current_attack.get("knockback", _weapon_data.get("knockback", 0.0))
	)
	var backstab_multiplier := float(_weapon_data.get("backstab_multiplier", 0.0))
	_hitbox.call(
		"set_attack_values",
		dmg,
		poise,
		dmg_type,
		status_id,
		status_stacks,
		crit,
		crit_mult,
		"blockable",
		knockback,
		backstab_multiplier
	)
	if _hitbox.has_method("set_execution"):
		_hitbox.call("set_execution", _execution_target, _execution_kind)
	_hitbox.call("enable")


func _disable_hitbox() -> void:
	if _hitbox and _hitbox.has_method("disable"):
		_hitbox.call("disable")


func _cancel_attack() -> void:
	_discard_pending_bow_launch()
	_disable_hitbox()
	_end_attack()
	_combo_index = 0
	_last_light_index = -1


func _end_attack() -> void:
	if _stamina:
		_stamina.set_regen_state(Stamina.RegenState.NORMAL)
	if _mana:
		_mana.set_regen_state(Mana.RegenState.NORMAL)
	_clear_execution_state()
	is_attacking = false
	current_phase = AttackPhase.IDLE
	_hyperarmor_active = false
	_lunge_distance = 0.0
	_lunge_duration = 0.0
	_lunge_elapsed = 0.0
	_hitbox_opened_this_swing = false
	var buffer_window: float = _weapon_data.get("buffer_window", 0.2)
	var recovery: float = float(_current_attack.get("recovery", 0.3))
	_combo_idle_timer = buffer_window + recovery
	if _attack_name.begins_with("light"):
		_combo_index += 1
	attack_ended.emit()


func _process_bow_input(delta: float) -> void:
	is_bow_aiming = PlayerInput.pressed(&"block") or (is_attacking and current_phase == AttackPhase.DRAWING)
	_sync_camera_aim_state()
	if is_attacking and current_phase == AttackPhase.DRAWING:
		if PlayerInput.pressed(&"heavy_attack"):
			_draw_charge = minf(
				1.0, _draw_charge + delta / float(_weapon_data.get("draw_time", 0.8))
			)
			_update_charge_shake(_draw_charge)
		elif _draw_charge > 0.05:
			_fire_bow_shot()
		else:
			_reset_bow()
		return
	if is_attacking:
		_process_attack_phase(delta)
		return
	if PlayerInput.pressed(&"heavy_attack") and _has_arrow_available():
		current_phase = AttackPhase.DRAWING
		is_attacking = true
		_attack_name = "bow_draw"
		_draw_charge = minf(1.0, _draw_charge + delta / float(_weapon_data.get("draw_time", 0.8)))
		attack_started.emit("bow_draw")
		if _stamina:
			_stamina.set_regen_state(Stamina.RegenState.SUPPRESSED)
		if _mana:
			_mana.set_regen_state(Mana.RegenState.SUPPRESSED)
		return
	if PlayerInput.just_pressed(&"light_attack"):
		_try_attack("light")


## `RG-02`: an unaffordable shot fizzles rather than firing, the same rule `_try_attack()` already
## follows for stamina -- checked here (not at draw start) so a draw that goes on long enough to
## outlast the last arrow release still fizzles cleanly instead of firing on credit.
func _has_arrow_available() -> bool:
	return _arrows == null or _arrows.has_arrow()


func _fire_bow_shot() -> void:
	if not _has_arrow_available():
		_reset_bow()
		return
	var heavy: Dictionary = _weapon_data.get("heavy_attack", {})
	var cost: float = _scaled_stamina_cost(float(heavy.get("stamina_cost", 18.0)))
	if _stamina and not _stamina.has(cost):
		_reset_bow()
		return
	var scaled := heavy.duplicate()
	scaled["damage"] = float(heavy.get("damage", 20.0)) * lerpf(0.5, 1.5, _draw_charge)
	var charge := _draw_charge
	var launch_request := _prepare_arrow_launch(scaled, charge)
	if launch_request.is_empty():
		_reset_bow()
		return
	_draw_charge = 0.0
	_update_charge_shake(0.0)
	attack_ended.emit()
	_current_attack = scaled
	is_attacking = true
	current_phase = AttackPhase.STARTUP
	_phase_timer = float(heavy.get("startup", 0.08))
	_attack_name = "bow_shot"
	_hitbox_opened_this_swing = true
	launch_request["stamina_cost"] = cost
	_pending_bow_launch = launch_request
	_snap_soft_lock_facing()
	attack_started.emit(_attack_name)


func _prepare_arrow_launch(attack: Dictionary, charge: float) -> Dictionary:
	if _body == null or not is_instance_valid(_body):
		return {}
	var tree := _body.get_tree()
	if tree == null or tree.current_scene == null:
		return {}
	var arrow: Node3D = PLAYER_ARROW_SCENE.instantiate() as Node3D
	if arrow == null or not arrow.has_method("launch"):
		if arrow != null:
			arrow.queue_free()
		return {}
	var container := ProjectileContainerScript.get_or_create(_body)
	if container == null or not is_instance_valid(container):
		arrow.queue_free()
		return {}
	var origin := _projectile_origin()
	var target_pos := get_aim_point(origin)
	var direction := (target_pos - origin).normalized()
	if _lock_on and _lock_on.is_locked and _lock_on.current_target:
		var target_body := _lock_on.current_target as Node3D
		target_pos = LockOn.get_target_aim_point(target_body)
		var to_target: Vector3 = target_pos - origin
		if to_target.length_squared() > 0.01:
			direction = to_target.normalized()
	var shot_damage: float = float(attack.get("damage", 20.0))
	var dmg: float = shot_damage * _damage_multiplier
	dmg += CombatStatModifiersScript.flat_damage_bonus(
		_equipment_stats,
		CombatStatModifiersScript.attack_weight(attack, _weapon_data),
		shot_damage
	)
	var poise: float = (
		float(attack.get("poise_damage", 15.0))
		* _damage_multiplier
		* CombatStatModifiersScript.poise_damage_multiplier(_equipment_stats, _talent_stats)
	)
	var dmg_type: String = attack.get("damage_type", _weapon_data.get("damage_type", "physical"))
	var status_id: String = attack.get("status", _weapon_data.get("status_on_hit", ""))
	var status_stacks: int = int(attack.get("status_stacks", 1))
	var crit := CombatStatModifiersScript.crit_chance(_equipment_stats, _talent_stats)
	var crit_mult := CombatStatModifiersScript.crit_multiplier(_equipment_stats, _talent_stats)
	var speed := (
		ARROW_BASE_SPEED
		* float(_weapon_data.get("projectile_speed_multiplier", 1.0))
		* lerpf(0.75, 1.25, charge)
	)
	var knockback: float = float(attack.get("knockback", _weapon_data.get("knockback", 0.0)))
	return {
		"arrow": arrow,
		"container": container,
		"origin": origin,
		"launch_args": [
			"launch",
			direction,
			speed,
			dmg,
			poise,
			_body,
			dmg_type,
			status_id,
			status_stacks,
			crit,
			crit_mult,
			"blockable",
			knockback,
			target_pos
		],
	}


func _commit_arrow_launch(request: Dictionary) -> bool:
	var arrow := request.get("arrow") as Node3D
	var container := request.get("container") as Node
	var args: Array = request.get("launch_args", [])
	if arrow == null or container == null or not is_instance_valid(container) or args.size() < 2:
		return false
	container.add_child(arrow)
	arrow.global_position = request.get("origin", _body.global_position)
	var method := StringName(str(args.pop_front()))
	arrow.callv(method, args)
	return true


func _commit_pending_bow_launch() -> bool:
	if _pending_bow_launch.is_empty():
		return false
	var request := _pending_bow_launch
	_pending_bow_launch = {}
	var cost := float(request.get("stamina_cost", 0.0))
	if _stamina and (not _stamina.has(cost) or not _stamina.consume(cost)):
		_discard_arrow_request(request)
		return false
	if _arrows and not _arrows.consume_arrow():
		if _stamina:
			_stamina.restore(cost)
		_discard_arrow_request(request)
		return false
	if _commit_arrow_launch(request):
		return true
	if _stamina:
		_stamina.restore(cost)
	if _arrows:
		_arrows.grant_arrow(1)
	_discard_arrow_request(request)
	return false


func _discard_arrow_request(request: Dictionary) -> void:
	var arrow := request.get("arrow") as Node3D
	if arrow != null and is_instance_valid(arrow) and arrow.get_parent() == null:
		arrow.queue_free()


func _discard_pending_bow_launch() -> void:
	if _pending_bow_launch.is_empty():
		return
	_discard_arrow_request(_pending_bow_launch)
	_pending_bow_launch = {}


func _reset_bow() -> void:
	_discard_pending_bow_launch()
	var was_drawing := is_attacking
	_draw_charge = 0.0
	is_attacking = false
	current_phase = AttackPhase.IDLE
	is_bow_aiming = false
	_sync_camera_aim_state()
	_update_charge_shake(0.0)
	if was_drawing:
		if _stamina:
			_stamina.set_regen_state(Stamina.RegenState.NORMAL)
		if _mana:
			_mana.set_regen_state(Mana.RegenState.NORMAL)
		attack_ended.emit()


func _archetype_can_two_hand() -> bool:
	return get_archetype() not in ["bow", "dagger"]


func _toggle_two_hand() -> void:
	if is_attacking or not _archetype_can_two_hand():
		return
	_two_hand = not _two_hand
	_refresh_damage_multiplier()
	_apply_hitbox_profile()


func _refresh_damage_multiplier() -> void:
	var stance_mult := TWO_HAND_DAMAGE_MULT if _two_hand else 1.0
	_damage_multiplier = _base_damage_multiplier * _weapon_scaling_multiplier * stance_mult


func _on_dodge_started() -> void:
	if is_attacking:
		_cancel_attack()


func _on_guard_state_changed(blocking: bool) -> void:
	if blocking and is_attacking:
		_cancel_attack()


func _on_dodge_ended() -> void:
	_post_dodge_attack_buffer = POST_DODGE_ATTACK_BUFFER


func _scaled_stamina_cost(base_cost: float) -> float:
	return base_cost * CombatStatModifiersScript.stamina_cost_multiplier(_equipment_stats, _talent_stats)


func _snap_soft_lock_facing() -> void:
	if _lock_on and _lock_on.is_locked and _lock_on.current_target:
		_face_target(_lock_on.current_target)
		return
	var target := _find_soft_lock_target()
	if target:
		_face_target(target)


func _get_soft_lock_aim_direction() -> Vector3:
	if _body == null:
		return Vector3.FORWARD
	var camera_pivot := _body.get_node_or_null("CameraPivot") as Node3D
	if camera_pivot:
		var dir := -camera_pivot.global_transform.basis.z
		if dir.length_squared() > 0.01:
			return dir.normalized()
	if _body.has_method("get_facing_direction"):
		var facing: Vector3 = _body.call("get_facing_direction")
		if facing.length_squared() > 0.01:
			return facing.normalized()
	return Vector3.FORWARD


func _camera_aim_point(origin: Vector3) -> Vector3:
	var direction := _get_soft_lock_aim_direction()
	var camera_pivot := _body.get_node_or_null("CameraPivot") as Node3D
	var ray_origin := camera_pivot.global_position if camera_pivot else origin
	var ray_end := ray_origin + direction * 40.0
	var space := _body.get_world_3d().direct_space_state
	if space == null:
		return ray_end
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = CombatLayers.WORLD_OCCLUDERS
	query.exclude = [_body.get_rid()]
	var hit := space.intersect_ray(query)
	var impact: Variant = hit.get("position", ray_end)
	return impact if impact is Vector3 else ray_end


func _projectile_origin() -> Vector3:
	if _body == null:
		return Vector3.ZERO
	for anchor_name in ["ProjectileMuzzle", "Muzzle", "AimAnchor"]:
		var anchor := _body.find_child(anchor_name, true, false) as Node3D
		if anchor:
			return anchor.global_position
	return _body.global_position + Vector3(0.0, 1.2, 0.0)


func _face_target(target: Node3D) -> void:
	if _body == null or target == null:
		return
	var facing := _body.get_node_or_null("Facing") as Node3D
	if facing == null:
		return
	var to_target := target.global_position - _body.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return
	facing.rotation.y = LockOnMovement.world_direction_to_local_facing_y(_body, to_target)


func _find_soft_lock_target() -> Node3D:
	if _lock_on and _lock_on.is_locked:
		return null
	if _body == null:
		return null
	var best: Node3D
	var best_score := -INF
	var facing := _get_soft_lock_aim_direction()
	var cone_deg := SOFT_LOCK_CONE_DEG
	if _body.velocity.length_squared() > 1.0:
		cone_deg = maxf(70.0, SOFT_LOCK_CONE_DEG - 12.0)
	for node in CombatGroups.lockables(get_tree()):
		if not node is Node3D or not is_instance_valid(node):
			continue
		if node.has_method("is_dead") and node.call("is_dead"):
			continue
		var offset_3d := (node as Node3D).global_position - _body.global_position
		if absf(offset_3d.y) > SOFT_LOCK_VERTICAL_LIMIT:
			continue
		var offset := Vector3(offset_3d.x, 0.0, offset_3d.z)
		var dist := offset.length()
		var assist_range := minf(SOFT_LOCK_RANGE, _soft_lock_reach())
		if dist > assist_range or dist < 0.01:
			continue
		if not _soft_lock_visible(node as Node3D):
			continue
		var dir := offset / dist
		var angle := rad_to_deg(facing.angle_to(dir))
		if angle > cone_deg:
			continue
		var score := (cone_deg - angle) / dist
		if score > best_score:
			best_score = score
			best = node as Node3D
	return best


func _soft_lock_reach() -> float:
	var profile: Dictionary = _weapon_data.get("hitbox", {})
	var authored_reach := float(profile.get("radius", profile.get("depth", 2.0)))
	return maxf(2.5, authored_reach + float(_weapon_data.get("lunge_distance", 0.0)) + 2.0)


func _soft_lock_visible(target: Node3D) -> bool:
	var space := _body.get_world_3d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(
		_body.global_position + Vector3.UP, target.global_position + Vector3.UP
	)
	query.collision_mask = CombatLayers.WORLD_OCCLUDERS
	query.exclude = [_body.get_rid()]
	return space.intersect_ray(query).is_empty()


func _apply_hitbox_profile() -> void:
	if _hitbox_shape == null:
		return
	var profile: Dictionary = _weapon_data.get("hitbox", {})
	var scale := 1.0
	if _two_hand and get_archetype() != "bow":
		scale = 1.1
	var offset := _vector_from(profile.get("offset"), DEFAULT_HITBOX_OFFSET)
	if scale > 1.0:
		offset.z *= 1.08
	match String(profile.get("shape", "box")):
		"capsule":
			var capsule := _hitbox_shape.shape as CapsuleShape3D
			if capsule == null:
				capsule = CapsuleShape3D.new()
				_hitbox_shape.shape = capsule
			capsule.radius = maxf(0.05, float(profile.get("radius", 0.35)) * scale)
			capsule.height = maxf(capsule.radius * 2.0, float(profile.get("height", 2.0)) * scale)
		"arc":
			var cylinder := _hitbox_shape.shape as CylinderShape3D
			if cylinder == null:
				cylinder = CylinderShape3D.new()
				_hitbox_shape.shape = cylinder
			cylinder.radius = maxf(0.05, float(profile.get("radius", 1.1)) * scale)
			cylinder.height = maxf(0.05, float(profile.get("height", 0.9)) * scale)
		"sphere":
			var sphere := _hitbox_shape.shape as SphereShape3D
			if sphere == null:
				sphere = SphereShape3D.new()
				_hitbox_shape.shape = sphere
			sphere.radius = maxf(0.05, float(profile.get("radius", 0.9)) * scale)
		_:
			var box := _hitbox_shape.shape as BoxShape3D
			if box == null:
				box = BoxShape3D.new()
				_hitbox_shape.shape = box
			box.size = _vector_from(profile.get("size"), DEFAULT_HITBOX_SIZE) * scale
	_hitbox_shape.position = offset
	_hitbox_shape.rotation = Vector3(deg_to_rad(float(profile.get("pitch_deg", 0.0))), 0.0, 0.0)
	if _hitbox and _hitbox.has_method("configure_arc"):
		var arc_degrees := float(profile.get("arc_degrees", 150.0)) if String(profile.get("shape", "box")) == "arc" else 360.0
		_hitbox.call("configure_arc", arc_degrees)


func _vector_from(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		var values: Array = value
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return fallback


func _is_action_blocked() -> bool:
	var heal := _body.get_node_or_null("PlayerHeal") as PlayerHeal
	if heal and heal.is_drinking:
		return true
	if _dodge and _dodge.is_dodging:
		return true
	# CB-05: the spear's identity trait -- a thrust from behind a raised guard, not a reason to
	# drop the shield first.
	if _guard and _guard.is_guard_active and not bool(_weapon_data.get("attack_while_guarding", false)):
		return true
	if _combat_reactions and not _combat_reactions.can_act() and not _hyperarmor_active:
		return true
	if _status and _status.is_stunned():
		return true
	return false
