extends Node
class_name Dodge

## Dash (Space / gamepad B) and jump (F / gamepad A). Bindings locked per DEC-G07–DEC-G10.

const JUMP_VELOCITY := 4.8
const COYOTE_TIME := 0.12
const JUMP_BUFFER_TIME := 0.15
const DODGE_BURST_FRACTION := 0.35
const DODGE_SPEED := 9.0
const DODGE_BACK_SPEED := 6.0

## A neutral backstep is a spacing tool, not a commitment: shorter travel and a shorter roll so
## it can be threaded between attacks. These scale the weight-class profile rather than
## replacing it, so heavy armour still backsteps worse than light does.
##
## Previously `_dodge_speed` (and therefore DODGE_BACK_SPEED above) was computed and then never
## read by `_process_dash`, which used the weight-class peak/end speeds for everything — so a
## backstep travelled exactly as far as a full committed roll and the option did not exist.
const BACKSTEP_SPEED_MULT := DODGE_BACK_SPEED / DODGE_SPEED
const BACKSTEP_DURATION_MULT := 0.8
const DODGE_STAMINA_COST := 32.0
const JUMP_STAMINA_COST := 18.0

const TUNING_PATH := "content/combat/dodge.json"
const FALLBACK_TUNING := {
	"weight_from_defense": {"light_below": 30.0, "heavy_at_or_above": 75.0},
	"weight_classes":
	{
		"light":
		{
			"duration": 0.48,
			"recovery": 0.16,
			"iframe_start": 0.06,
			"iframe_end": 0.42,
			"peak_speed": 12.5,
			"end_speed": 4.2,
			"recovery_speed_mult": 0.82,
			"stamina_cost_mult": 0.85,
		},
		"medium":
		{
			"duration": 0.55,
			"recovery": 0.22,
			"iframe_start": 0.10,
			"iframe_end": 0.45,
			"peak_speed": 11.0,
			"end_speed": 3.6,
			"recovery_speed_mult": 0.7,
			"stamina_cost_mult": 1.0,
		},
		"heavy":
		{
			"duration": 0.62,
			"recovery": 0.3,
			"iframe_start": 0.14,
			"iframe_end": 0.44,
			"peak_speed": 9.2,
			"end_speed": 3.0,
			"recovery_speed_mult": 0.55,
			"stamina_cost_mult": 1.25,
		},
	},
}

signal dodge_started
signal dodge_ended
signal dash_started
signal dash_ended
signal iframes_changed(active: bool)

var is_dodging := false
var iframes_active := false

var _body: CharacterBody3D
var _stamina: Stamina
var _weapon: WeaponController
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _dodge_timer := 0.0
var _recovery_timer := 0.0
var _dodge_direction := Vector3.ZERO
var _is_backstep := false
var _dodge_speed := DODGE_SPEED
var _talent_stamina_mult := 1.0
var _was_on_floor := false
var _profiles: Dictionary = {}
var _light_below := 30.0
var _heavy_at_or_above := 75.0
var _weight_class := ""
var _weight_override := ""
var _duration := 0.55
var _recovery := 0.22
var _iframe_start := 0.10
var _iframe_end := 0.45
var _peak_speed := 11.0
var _end_speed := 3.6
var _recovery_speed_mult := 0.7
var _weight_stamina_mult := 1.0
## Length of the roll currently in flight. Equals `_duration` for a directional roll and is
## shortened for a backstep, so `get_dash_progress` and the i-frame window stay in sync with the
## motion actually being played.
var _active_duration := 0.55


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_stamina = _body.get_node_or_null("Stamina") as Stamina
	_weapon = _body.get_node_or_null("WeaponController") as WeaponController
	_load_tuning()
	_apply_weight_class("medium")
	dash_started.connect(func(): dodge_started.emit())
	dash_ended.connect(func(): dodge_ended.emit())


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_handle_jump_buffer()
	if _recovery_timer > 0.0:
		_recovery_timer -= delta


func configure(data: Dictionary = {}, weight_class: String = "medium") -> void:
	if not data.is_empty():
		_ingest_tuning(data)
	_weight_override = weight_class
	_apply_weight_class(weight_class)


func set_stamina_cost_multiplier(mult: float) -> void:
	_talent_stamina_mult = maxf(0.1, mult)


func get_weight_class() -> String:
	return _weight_class


func _load_tuning() -> void:
	var data := ContentLoader.load_json(TUNING_PATH)
	if data.is_empty():
		data = FALLBACK_TUNING.duplicate(true)
	_ingest_tuning(data)


func _ingest_tuning(data: Dictionary) -> void:
	var classes: Dictionary = data.get("weight_classes", {})
	if not classes.is_empty():
		_profiles = classes
	var thresholds: Dictionary = data.get("weight_from_defense", {})
	_light_below = float(thresholds.get("light_below", _light_below))
	_heavy_at_or_above = float(thresholds.get("heavy_at_or_above", _heavy_at_or_above))


func _apply_weight_class(weight_class: String) -> void:
	var fallback: Dictionary = FALLBACK_TUNING["weight_classes"]
	var profile: Dictionary = _profiles.get(weight_class, {})
	if profile.is_empty():
		profile = _profiles.get("medium", fallback.get(weight_class, fallback["medium"]))
	_weight_class = weight_class
	_duration = maxf(0.05, float(profile.get("duration", _duration)))
	_recovery = maxf(0.0, float(profile.get("recovery", _recovery)))
	_iframe_start = maxf(0.0, float(profile.get("iframe_start", _iframe_start)))
	_iframe_end = maxf(_iframe_start, float(profile.get("iframe_end", _iframe_end)))
	_peak_speed = float(profile.get("peak_speed", _peak_speed))
	_end_speed = float(profile.get("end_speed", _end_speed))
	_recovery_speed_mult = clampf(float(profile.get("recovery_speed_mult", _recovery_speed_mult)), 0.1, 1.0)
	_weight_stamina_mult = maxf(0.1, float(profile.get("stamina_cost_mult", 1.0)))


func _sync_weight_class() -> void:
	if _weight_override != "":
		return
	var defense := 0.0
	if _body:
		defense = float(_body.get_meta("combat_defense", 0.0))
	var resolved := "medium"
	if defense < _light_below:
		resolved = "light"
	elif defense >= _heavy_at_or_above:
		resolved = "heavy"
	if resolved != _weight_class:
		_apply_weight_class(resolved)


func _scaled_dodge_cost() -> float:
	return DODGE_STAMINA_COST * _weight_stamina_mult * _talent_stamina_mult


func process_dash_physics(delta: float) -> void:
	process_dodge_physics(delta)


func process_dodge_physics(delta: float) -> void:
	if is_dodging:
		_process_dash(delta)
		return
	if PlayerInput.just_pressed(&"dodge") and _can_dash():
		_start_dash()


func get_dash_progress() -> float:
	if not is_dodging:
		return 0.0
	return clampf(1.0 - (_dodge_timer / maxf(0.001, _active_duration)), 0.0, 1.0)


func get_dash_direction() -> Vector3:
	return _dodge_direction


func locks_movement() -> bool:
	return false


func get_move_speed_multiplier() -> float:
	if is_dodging or _recovery_timer <= 0.0 or _recovery <= 0.0:
		return 1.0
	var t := clampf(1.0 - (_recovery_timer / _recovery), 0.0, 1.0)
	return lerpf(_recovery_speed_mult, 1.0, t)


func grant_external_iframes(active: bool) -> void:
	if iframes_active == active:
		return
	iframes_active = active
	iframes_changed.emit(iframes_active)


func try_rollout_dash(stamina_cost: float) -> bool:
	if is_dodging or _recovery_timer > 0.0:
		return false
	if _stamina and not _stamina.consume(stamina_cost):
		return false
	_start_dash(true)
	return true


func _update_timers(delta: float) -> void:
	if _body and _body.is_on_floor():
		_coyote_timer = COYOTE_TIME
	elif _was_on_floor:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
	_was_on_floor = _body.is_on_floor() if _body else false

	if PlayerInput.just_pressed(&"jump"):
		_jump_buffer_timer = JUMP_BUFFER_TIME
	elif _jump_buffer_timer > 0.0:
		_jump_buffer_timer -= delta


func _handle_jump_buffer() -> void:
	if _jump_buffer_timer <= 0.0 or not _body:
		return
	if _coyote_timer > 0.0 and not is_dodging:
		# Jump used to ignore the attack commitment window that _can_dash respects twelve lines
		# below, so tapping jump cancelled any swing at any phase for 18 stamina — bypassing
		# cancel_into/cancel_after and the entire reason heavy attacks feel heavy.
		if _weapon and not _weapon.allows_cancel_into("dodge"):
			return
		if _stamina and not _stamina.consume(JUMP_STAMINA_COST):
			return
		_body.velocity.y = JUMP_VELOCITY
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0


func _can_dash() -> bool:
	if is_dodging or _recovery_timer > 0.0:
		return false
	if _weapon and not _weapon.allows_cancel_into("dodge"):
		return false
	if _stamina and not _stamina.has(_scaled_dodge_cost()):
		return false
	return true


func _start_dash(skip_cost: bool = false) -> void:
	_sync_weight_class()
	if not skip_cost and _stamina and not _stamina.consume(_scaled_dodge_cost()):
		return
	if _stamina:
		_stamina.set_regen_state(Stamina.RegenState.SUPPRESSED)
	var input_dir := PlayerInput.move_vector()
	var lock_on := _body.get_node_or_null("LockOn")
	if LockOnMovement.is_active(lock_on):
		_dodge_direction = LockOnMovement.get_locked_dodge_direction(_body, lock_on, input_dir)
		if input_dir.length_squared() > 0.01 and absf(input_dir.x) >= 0.01:
			_dodge_speed = DODGE_SPEED
		else:
			_dodge_speed = DODGE_BACK_SPEED
	elif input_dir.length_squared() > 0.01:
		_dodge_speed = DODGE_SPEED
		_dodge_direction = _get_camera_relative_direction(input_dir)
	else:
		_dodge_speed = DODGE_BACK_SPEED
		_dodge_direction = _get_attack_backstep_direction()
	if _dodge_direction.length_squared() < 0.01:
		_dodge_direction = _get_attack_backstep_direction()
	_is_backstep = is_equal_approx(_dodge_speed, DODGE_BACK_SPEED)
	is_dodging = true
	_active_duration = _duration * (BACKSTEP_DURATION_MULT if _is_backstep else 1.0)
	_dodge_timer = _active_duration
	dash_started.emit()
	# Dodge was the one core action with no VFX entry at all — it moved the character and nothing
	# else acknowledged it. The dust is spawned at the feet, not the chest, so it reads as ground
	# contact; the roll leaves from where it pushed off.
	if _body and VfxService:
		VfxService.play_dodge(
			_body.global_position + Vector3(0.0, 0.05, 0.0), _dodge_direction
		)
	if _body and _body.is_in_group("player") and CombatEvents:
		CombatEvents.dispatch(CombatEvents.ON_DODGE, {"actor": _body})


func _get_attack_backstep_direction() -> Vector3:
	var facing := _body.get_node_or_null("Facing") as Node3D
	if facing:
		var back := -CombatFacing.forward_of(facing)
		back.y = 0.0
		if back.length_squared() > 0.01:
			return back.normalized()
	var fallback := -_get_facing_forward()
	fallback.y = 0.0
	if fallback.length_squared() > 0.01:
		return fallback.normalized()
	return Vector3.BACK


func _get_camera_relative_direction(input_dir: Vector2) -> Vector3:
	if _body.has_method("get_camera_relative_direction"):
		return _body.call("get_camera_relative_direction", input_dir)
	return Vector3.ZERO


func _get_facing_forward() -> Vector3:
	if _body.has_method("get_facing_direction"):
		return _body.call("get_facing_direction")
	return CombatFacing.forward_of(_body)


func _process_dash(delta: float) -> void:
	_dodge_timer -= delta
	var duration := maxf(0.001, _active_duration)
	var elapsed := duration - _dodge_timer
	var t := clampf(elapsed / duration, 0.0, 1.0)
	var travel_mult := BACKSTEP_SPEED_MULT if _is_backstep else 1.0
	var speed := _peak_speed * travel_mult
	if t >= DODGE_BURST_FRACTION:
		var blend := (t - DODGE_BURST_FRACTION) / maxf(0.001, 1.0 - DODGE_BURST_FRACTION)
		speed = lerpf(_peak_speed, _end_speed, blend) * travel_mult
	_body.velocity.x = _dodge_direction.x * speed
	_body.velocity.z = _dodge_direction.z * speed
	if not _body.is_on_floor():
		_body.velocity += _body.get_gravity() * delta
	elif _body.velocity.y > 0.0:
		_body.velocity.y = 0.0
	var iframe_end := _iframe_end + ClassPerks.shadowstep_iframe_bonus(_body, _is_backstep)
	iframe_end = _apply_dodge_window_assist(iframe_end)
	var iframes := elapsed >= _iframe_start and elapsed <= iframe_end
	if iframes != iframes_active:
		iframes_active = iframes
		iframes_changed.emit(iframes_active)
	_body.move_and_slide()
	if _dodge_timer <= 0.0:
		_end_dash()


## Stretches the invulnerable part of the roll by the accessibility "Dodge Window" multiplier.
##
## The setting existed, saved and loaded, and was shown in the Accessibility page, but nothing in
## the game ever read it — moving the slider changed nothing. Scaling the window's length from its
## start keeps the wind-up honest: the roll still has to be timed, it just forgives a later press.
func _apply_dodge_window_assist(iframe_end: float) -> float:
	var generosity := AccessibilitySettings.assist_iframe_generosity
	if is_equal_approx(generosity, 1.0):
		return iframe_end
	return _iframe_start + (iframe_end - _iframe_start) * generosity


func _end_dash() -> void:
	is_dodging = false
	iframes_active = false
	iframes_changed.emit(false)
	_recovery_timer = _recovery
	_dodge_speed = DODGE_SPEED
	if _stamina:
		_stamina.set_regen_state(Stamina.RegenState.NORMAL)
	dash_ended.emit()
