extends Node
class_name PlayerCombatReactions

const MaterialDissolveScript := preload("res://scripts/art/characters/material_dissolve.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")
const DioramaViewmodelScript := preload("res://scripts/art/characters/diorama_viewmodel.gd")
const DodgeScript := preload("res://scripts/player/dodge.gd")

const STAGGER_DURATION_MIN := 0.45
const STAGGER_DURATION_MAX := 1.25
const STAGGER_POISE_LOW := 10.0
const STAGGER_POISE_HIGH := 45.0
const STAGGER_WAKEUP_IFRAMES := 0.14
const STAGGER_ROLLOUT_WINDOW := 0.22
const STAGGER_ROLLOUT_COST := 1.5

const DEATH_SLOW_SCALE := 0.35
const DEATH_SLOW_DURATION := 0.60
const DEATH_DESATURATE_TIME := 1.40
const DEATH_HANDOFF_TIME := 2.20
const DEATH_DESATURATE_SATURATION := 0.25

signal stagger_started
signal stagger_ended
signal player_died
signal grab_started
signal grab_ended

var is_staggered := false
var is_dead := false
var is_guard_broken := false
var is_grabbed := false
var stagger_direction := Vector3.ZERO
var stagger_duration := 0.0

var _body: CharacterBody3D
var _health: Health
var _poise: Poise
var _guard: Guard
var _dodge: Dodge
var _stamina: Stamina
var _status: StatusController
var _weapon: WeaponController
var _heal: PlayerHeal
var _orbit_camera: Node
var _stagger_timer := 0.0
var _last_poise_damage := STAGGER_POISE_LOW
var _distress_active := false
var _last_hit_direction := Vector3.ZERO
var _wakeup_iframes_active := false
var _death_sequence_running := false
var _saved_screen_saturation := -1.0
var _grab_timer := 0.0
var _grab_pending_damage := 0.0
var _grab_source: Node = null
var _knockback: Knockback


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_health = _body.get_node_or_null("Health") as Health
	_poise = _body.get_node_or_null("Poise") as Poise
	_knockback = _body.get_node_or_null("Knockback") as Knockback
	_guard = _body.get_node_or_null("Guard") as Guard
	_dodge = _body.get_node_or_null("Dodge") as Dodge
	_stamina = _body.get_node_or_null("Stamina") as Stamina
	_status = _body.get_node_or_null("StatusController") as StatusController
	_weapon = _body.get_node_or_null("WeaponController") as WeaponController
	_heal = _body.get_node_or_null("PlayerHeal") as PlayerHeal
	_orbit_camera = _body.get_node_or_null("CameraPivot/SpringArm3D")
	if _health:
		_health.died.connect(_on_died)
		_health.health_changed.connect(_on_health_changed)
	if _poise:
		_poise.poise_broken.connect(_on_poise_broken)
		_poise.poise_damaged.connect(_on_poise_damaged)
	if _guard and _guard.has_signal("parry_success"):
		_guard.parry_success.connect(_on_parry_success)
	if _guard and _guard.has_signal("guard_broken"):
		_guard.guard_broken.connect(_on_guard_broken)
	var hurtbox := _body.get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox and hurtbox.has_signal("hurt_received"):
		hurtbox.hurt_received.connect(_on_hurt_received)


func _physics_process(delta: float) -> void:
	_sync_guard_broken_mirror()
	if is_grabbed and _grab_timer > 0.0:
		_grab_timer -= delta
		if _grab_timer <= 0.0:
			_end_grab()
	if is_staggered and _stagger_timer > 0.0:
		_stagger_timer -= delta
		_update_stagger_iframes()
		_try_stagger_rollout()
		if _stagger_timer <= 0.0:
			_end_stagger()
	elif _wakeup_iframes_active:
		_clear_wakeup_iframes()


func can_act() -> bool:
	return not is_dead and not is_staggered and not is_grabbed


func is_movement_locked() -> bool:
	if is_dead or is_staggered or is_grabbed:
		return true
	if _dodge and _dodge.locks_movement():
		return true
	if _guard and _guard.locks_movement():
		return true
	if _weapon and _weapon.locks_movement():
		return true
	if _heal and _heal.locks_movement():
		return true
	return false


func stagger_duration_for_poise(poise_damage: float) -> float:
	var t := inverse_lerp(STAGGER_POISE_LOW, STAGGER_POISE_HIGH, poise_damage)
	return lerpf(STAGGER_DURATION_MIN, STAGGER_DURATION_MAX, clampf(t, 0.0, 1.0))


func reset_combat_state() -> void:
	is_dead = false
	is_staggered = false
	is_guard_broken = false
	_stagger_timer = 0.0
	_death_sequence_running = false
	_clear_wakeup_iframes()
	_restore_death_presentation()
	if _health and _health.has_method("reset_health"):
		_health.reset_health()
	if _stamina and _stamina.has_method("reset_stamina"):
		_stamina.reset_stamina()
	if _poise and _poise.has_method("reset_poise"):
		_poise.reset_poise()
	var mana := _body.get_node_or_null("Mana") as Mana
	if mana and mana.has_method("reset_mana"):
		mana.reset_mana()
	if _guard and _guard.has_method("reset_after_revive"):
		_guard.reset_after_revive()
	if _status and _status.has_method("clear_all"):
		_status.clear_all()
	if _orbit_camera and _orbit_camera.has_method("exit_death_framing"):
		_orbit_camera.call("exit_death_framing")
	var visual := _get_diorama_visual()
	if visual:
		visual.visible = true
		MaterialDissolveScript.reset_death_visual(visual)
		MaterialFlashScript.restore_all(visual)
	var viewmodel := _get_viewmodel_root()
	if viewmodel:
		MaterialDissolveScript.reset_death_visual(viewmodel)
		MaterialFlashScript.restore_all(viewmodel)
	var director := _body.get_node_or_null("AnimDirector")
	if director and director.has_method("revive"):
		director.call("revive")


## `PH-02`: a stagger used to be a timer and a clip -- the body never moved. The impulse is scaled
## off the poise damage that caused it, so a poise break from a heavy attack visibly rocks the
## victim and a bare-minimum break barely nudges them.
func _apply_stagger(duration: float, direction: Vector3 = Vector3.ZERO) -> void:
	is_staggered = true
	_stagger_timer = duration
	stagger_duration = duration
	stagger_direction = direction
	stagger_started.emit()
	_flash_stagger_feedback()
	if _knockback and direction.length_squared() > 0.0001:
		_knockback.apply(direction, 0.8 * _last_poise_damage / STAGGER_POISE_HIGH)


func _end_stagger() -> void:
	is_staggered = false
	_stagger_timer = 0.0
	_clear_wakeup_iframes()
	stagger_ended.emit()
	_on_stagger_ended()


## `EN-02`: a `grab` attack bypasses poise entirely -- it is answered by not being caught, not by
## blocking or parrying, so nothing about it should read as a poise exchange. A fixed-duration lock
## with no i-frames, damage applied only once the lock ends, so a dodge or heal used *during* the
## grab cannot cheat the hit the way an i-framed stagger could.
func apply_grab(damage: float, source: Node, duration: float) -> void:
	if is_dead:
		return
	is_grabbed = true
	_grab_timer = duration
	_grab_pending_damage = damage
	_grab_source = source
	grab_started.emit()


func _end_grab() -> void:
	is_grabbed = false
	_grab_timer = 0.0
	if _health and _grab_pending_damage > 0.0 and not _health.is_dead():
		_health.take_damage(_grab_pending_damage)
	_grab_pending_damage = 0.0
	_grab_source = null
	grab_ended.emit()


func _cancel_stagger() -> void:
	if not is_staggered:
		return
	_stagger_timer = 0.0
	is_staggered = false
	_clear_wakeup_iframes()
	stagger_ended.emit()
	_on_stagger_ended()


func _on_health_changed(current: float, max_value: float) -> void:
	if not CombatEvents or max_value <= 0.0:
		return
	var ratio := current / max_value
	CombatEvents.notify_health_ratio(ratio, _body)
	_update_distress(ratio)


func _update_distress(ratio: float) -> void:
	if _body == null or not _body.is_in_group("player"):
		return
	if ratio <= CombatEvents.LOW_HEALTH_RATIO:
		_distress_active = true
	elif ratio > CombatEvents.LOW_HEALTH_RATIO + 0.05:
		_distress_active = false
	else:
		return
	if PixelDioramaViewport and PixelDioramaViewport.has_method("set_distress"):
		PixelDioramaViewport.call("set_distress", _distress_active)


func _on_poise_damaged(amount: float, _remaining: float) -> void:
	_last_poise_damage = amount


func _on_poise_broken() -> void:
	var direction := _last_hit_direction
	if direction.length_squared() < 0.01:
		direction = -CombatFacing.aim_forward_of(_body)
	_apply_stagger(stagger_duration_for_poise(_last_poise_damage), direction)


func _on_hurt_received(_amount: float, poise_damage: float, direction: Vector3) -> void:
	_last_poise_damage = poise_damage
	if direction.length_squared() > 0.01:
		_last_hit_direction = direction


func _on_stagger_ended() -> void:
	if _poise:
		_poise.reset_poise()


func _on_guard_broken() -> void:
	is_guard_broken = true
	_flash_guard_break_feedback()


func _on_parry_success(_target: Node) -> void:
	_flash_parry_feedback()


func _on_died() -> void:
	if _death_sequence_running:
		return
	_death_sequence_running = true
	_break_player_lock()
	is_dead = true
	if CombatEvents:
		CombatEvents.dispatch(CombatEvents.ON_DEATH, {"actor": _body})
	_run_death_sequence()


func _run_death_sequence() -> void:
	var director := _body.get_node_or_null("AnimDirector")
	if director and director.has_method("play_death"):
		director.call("play_death")
	VfxService.push_time_scale(&"death", DEATH_SLOW_SCALE)
	AudioDirector.play_sfx("death", _body.global_position)
	var opts := MaterialDissolveScript.death_opts_for_profile("player")
	opts["vfx_position"] = _body.global_position
	opts["vfx_tint"] = Color(0.72, 0.28, 0.22)
	opts["has_animator"] = true
	if _last_hit_direction.length_squared() > 0.01:
		opts["sweep_dir"] = _last_hit_direction
	var visual := _get_diorama_visual()
	if visual:
		MaterialDissolveScript.play_death_visual(visual, opts)
	var viewmodel := _get_viewmodel_root()
	if viewmodel:
		var vm_opts := opts.duplicate()
		vm_opts.erase("vfx_position")
		MaterialDissolveScript.play_death_visual(viewmodel, vm_opts)
	await get_tree().create_timer(DEATH_SLOW_DURATION, true, false, true).timeout
	VfxService.release_time_scale(&"death")
	if _orbit_camera and _orbit_camera.has_method("enter_death_framing"):
		_orbit_camera.call("enter_death_framing")
	await (
		get_tree()
		. create_timer(DEATH_DESATURATE_TIME - DEATH_SLOW_DURATION, true, false, true)
		. timeout
	)
	_saved_screen_saturation = PixelDioramaSettings.screen_saturation
	PixelDioramaSettings.screen_saturation = DEATH_DESATURATE_SATURATION
	await (
		get_tree()
		. create_timer(DEATH_HANDOFF_TIME - DEATH_DESATURATE_TIME, true, false, true)
		. timeout
	)
	player_died.emit()


func _restore_death_presentation() -> void:
	if VfxService:
		VfxService.release_time_scale(&"death")
	if _saved_screen_saturation >= 0.0:
		PixelDioramaSettings.screen_saturation = _saved_screen_saturation
		_saved_screen_saturation = -1.0


func _exit_tree() -> void:
	_restore_death_presentation()


func _flash_parry_feedback() -> void:
	var visual := _get_diorama_visual()
	if visual:
		MaterialFlashScript.flash(visual, {"strength": 1.0, "duration": 0.10})
	AudioDirector.play_sfx("parry", _body.global_position)
	var anchor: Array = VfxService.resolve_combat_anchor(_body)
	VfxService.play_parry_spark(anchor[0], anchor[1])


func _flash_guard_break_feedback() -> void:
	var visual := _get_diorama_visual()
	if visual:
		MaterialFlashScript.flash(visual, {"strength": 0.9, "duration": 0.16})
	if _orbit_camera and _orbit_camera.has_method("apply_landing_dip"):
		_orbit_camera.call("apply_landing_dip", 0.35)
	if _orbit_camera and _orbit_camera.has_method("apply_shake"):
		_orbit_camera.call("apply_shake", 0.35, 0.35)
	if AudioDirector:
		AudioDirector.play_combat_sfx(
			"guard_break", _body.global_position + Vector3(0.0, 1.2, 0.0)
		)


func _flash_stagger_feedback() -> void:
	var visual := _get_diorama_visual()
	if visual:
		MaterialFlashScript.flash(visual, {"strength": 0.85, "duration": 0.12})


func _update_stagger_iframes() -> void:
	if _stagger_timer <= STAGGER_WAKEUP_IFRAMES and _stagger_timer > 0.0:
		_grant_wakeup_iframes()
	else:
		_clear_wakeup_iframes()


func _grant_wakeup_iframes() -> void:
	if _wakeup_iframes_active:
		return
	_wakeup_iframes_active = true
	if _dodge:
		_dodge.grant_external_iframes(true)


func _clear_wakeup_iframes() -> void:
	if not _wakeup_iframes_active:
		return
	_wakeup_iframes_active = false
	if _dodge:
		_dodge.grant_external_iframes(false)


func _try_stagger_rollout() -> void:
	if not is_staggered or _stagger_timer <= 0.0 or _stagger_timer > STAGGER_ROLLOUT_WINDOW:
		return
	if not PlayerInput.just_pressed(&"dodge"):
		return
	var cost := DodgeScript.DODGE_STAMINA_COST * STAGGER_ROLLOUT_COST
	if _dodge and _dodge.try_rollout_dash(cost):
		_cancel_stagger()


func _sync_guard_broken_mirror() -> void:
	if _guard == null:
		is_guard_broken = false
		return
	is_guard_broken = _guard.guard_broken_state


func _get_diorama_visual() -> Node3D:
	return _body.get_node_or_null("Facing/DioramaVisual") as Node3D


func _get_viewmodel_root() -> Node3D:
	var camera := _body.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if camera == null:
		return null
	return DioramaViewmodelScript.get_root(camera)

func _break_player_lock() -> void:
	var lock_on := _body.get_node_or_null("LockOn")
	if lock_on and lock_on.has_method("break_lock"):
		lock_on.call("break_lock")
