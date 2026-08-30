extends Node
class_name PlayerHeal


const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")

const DEFAULT_MAX_CHARGES := 3
const HEAL_AMOUNT := 0.45
const DRINK_DURATION := 1.35

const INTERRUPT_DAMAGE_THRESHOLD := 4.0

const HEAL_COMMIT_FRACTION := 0.62

## Passive regeneration from gear.
##
## Thirteen items have carried `healthRegen` since the first loot pass with nothing reading it.
## It lives here rather than on Health because it is the same decision the flask is: how much
## pressure the player is under between fights. Regen holds off for a moment after a hit, so it
## tops the player up between encounters without quietly winning one for them.
const REGEN_SUPPRESSION_AFTER_HIT := 4.0

signal charges_changed(current: int, max_value: int)
signal heal_started
signal heal_ended
signal heal_interrupted

var max_charges := DEFAULT_MAX_CHARGES
var current_charges := DEFAULT_MAX_CHARGES
var is_drinking := false

var _body: CharacterBody3D
var _health: Health
var _stamina: Stamina
var _reactions: Node
var _anim_director: Node
var _drink_timer := 0.0
var _heal_committed := false
var _regen_suppressed := 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_health = _body.get_node_or_null("Health") as Health
	_stamina = _body.get_node_or_null("Stamina") as Stamina
	_reactions = _body.get_node_or_null("CombatReactions")
	_connect_heal_anim_signals()
	_connect_interrupt_sources()
	charges_changed.emit(current_charges, max_charges)


func _connect_interrupt_sources() -> void:
	call_deferred("_bind_interrupt_signals")


func _bind_interrupt_signals() -> void:
	if _body == null or not is_instance_valid(_body):
		return
	var hurtbox := _body.get_node_or_null("Hurtbox")
	if hurtbox and hurtbox.has_signal("hurt_received"):
		if not hurtbox.hurt_received.is_connected(_on_hurt_received):
			hurtbox.hurt_received.connect(_on_hurt_received)
	if _reactions == null:
		_reactions = _body.get_node_or_null("CombatReactions")
	if _reactions and _reactions.has_signal("stagger_started"):
		if not _reactions.stagger_started.is_connected(_on_stagger_started):
			_reactions.stagger_started.connect(_on_stagger_started)
	if _health and not _health.died.is_connected(_on_owner_died):
		_health.died.connect(_on_owner_died)


func _on_hurt_received(amount: float, _poise_damage: float, _direction: Vector3) -> void:
	if amount > 0.0:
		suppress_regen()
	if not is_drinking:
		return
	if amount < INTERRUPT_DAMAGE_THRESHOLD:
		return
	_interrupt_drink()


func _on_stagger_started() -> void:
	if is_drinking:
		_interrupt_drink()


func _on_owner_died() -> void:
	if is_drinking:
		_interrupt_drink()


func _interrupt_drink() -> void:
	if not is_drinking:
		return
	is_drinking = false
	var elapsed := DRINK_DURATION - _drink_timer
	if not _heal_committed and elapsed >= DRINK_DURATION * HEAL_COMMIT_FRACTION:
		_heal_committed = true
		_apply_heal_amount()
	_drink_timer = 0.0
	current_charges = maxi(0, current_charges - 1)
	charges_changed.emit(current_charges, max_charges)
	var director := _body.get_node_or_null("AnimDirector") if _body else null
	if director and director.has_method("cancel_heal"):
		director.call("cancel_heal")
	heal_interrupted.emit()
	heal_ended.emit()


func _connect_heal_anim_signals() -> void:
	var director := _body.get_node_or_null("AnimDirector")
	if director == null:
		return
	if (
		director.has_signal("heal_gulp_frame")
		and not director.heal_gulp_frame.is_connected(_on_heal_gulp)
	):
		director.heal_gulp_frame.connect(_on_heal_gulp)
	if (
		director.has_signal("heal_commit_frame")
		and not director.heal_commit_frame.is_connected(_on_heal_commit)
	):
		director.heal_commit_frame.connect(_on_heal_commit)


func _physics_process(delta: float) -> void:
	_process_regen(delta)
	if not is_drinking:
		if PlayerInput.just_pressed(&"heal"):
			_try_drink()
		return
	_drink_timer -= delta
	if _drink_timer <= 0.0:
		_finish_drink()


func _process_regen(delta: float) -> void:
	if _regen_suppressed > 0.0:
		_regen_suppressed -= delta
		return
	if _health == null or _health.is_dead() or _health.current >= _health.max_health:
		return
	var per_second := 0.0
	if _body:
		per_second = float(_body.get_meta("combat_health_regen", 0.0))
	if per_second <= 0.0:
		return
	_health.heal(per_second * delta)


## Called when the player is hit, so regeneration cannot tick through a fight.
func suppress_regen() -> void:
	_regen_suppressed = REGEN_SUPPRESSION_AFTER_HIT


func refill_charges() -> void:
	current_charges = max_charges
	charges_changed.emit(current_charges, max_charges)


func grant_charge(count: int = 1) -> void:
	if count <= 0:
		return
	var granted := mini(max_charges, current_charges + count)
	if granted == current_charges:
		return
	current_charges = granted
	charges_changed.emit(current_charges, max_charges)


func locks_movement() -> bool:
	return is_drinking


func _try_drink() -> void:
	if is_drinking or current_charges <= 0:
		return
	if _reactions and _reactions.has_method("can_act") and not _reactions.call("can_act"):
		return
	if _health and _health.is_dead():
		return
	is_drinking = true
	_heal_committed = false
	_drink_timer = DRINK_DURATION
	heal_started.emit()
	_connect_heal_anim_signals()
	if AudioDirector:
		AudioDirector.play_combat_sfx("heal_raise", _body.global_position + Vector3(0.0, 1.2, 0.0))
	_anim_director = _body.get_node_or_null("AnimDirector")
	if _anim_director and _anim_director.has_method("play_heal"):
		_anim_director.call("play_heal", DRINK_DURATION)


func _on_heal_gulp() -> void:
	if not is_drinking:
		return
	if AudioDirector:
		AudioDirector.play_combat_sfx("heal_gulp", _body.global_position + Vector3(0.0, 1.1, 0.0))


func _on_heal_commit() -> void:
	if not is_drinking or _heal_committed:
		return
	_heal_committed = true
	if AudioDirector:
		AudioDirector.play_combat_sfx("heal_commit", _body.global_position + Vector3(0.0, 1.2, 0.0))
	_apply_heal_amount()
	var visual := _body.get_node_or_null("Facing/DioramaVisual") as Node3D
	if visual:
		MaterialFlashScript.flash(visual, 0.85)
	VfxService.play_heal(_body.global_position + Vector3(0.0, 1.1, 0.0))


func _apply_heal_amount() -> void:
	if _health:
		_health.heal(_health.max_health * HEAL_AMOUNT)


func _finish_drink() -> void:
	is_drinking = false
	current_charges = maxi(0, current_charges - 1)
	charges_changed.emit(current_charges, max_charges)
	if not _heal_committed:
		_apply_heal_amount()
	heal_ended.emit()
