extends Node
class_name PlayerHeal

## Estus-style bound heal: limited charges, vulnerable drink animation.

const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")

const DEFAULT_MAX_CHARGES := 3
const HEAL_AMOUNT := 0.45
const DRINK_DURATION := 1.35

## A hit at or above this lands hard enough to break the drink. Anything smaller — a poison
## tick, a glancing blow, chip through a block — is ridden out, so hostile-environment damage
## does not make the flask unusable.
const INTERRUPT_DAMAGE_THRESHOLD := 4.0

## Fraction of the drink after which the heal is banked even if the drink is then broken.
## Used only when the rig's animation carries no `heal_commit_frame` method track.
const HEAL_COMMIT_FRACTION := 0.62

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


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_health = _body.get_node_or_null("Health") as Health
	_stamina = _body.get_node_or_null("Stamina") as Stamina
	_reactions = _body.get_node_or_null("CombatReactions")
	_connect_heal_anim_signals()
	_connect_interrupt_sources()
	charges_changed.emit(current_charges, max_charges)


## The drink is supposed to be the gamble that defines the genre: 1.35 s of helplessness
## against a heal you might not get. Nothing was wired to interrupt it, so it was 45% max HP
## for free and the whole risk/reward of the estus loop was inert.
##
## Deferred because the Hurtbox and CombatReactions siblings are added by the player scene and
## may not have run their own _ready when this one does.
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


## Chip damage through a heal is survivable; a real hit is not. Below the threshold the drink
## rides it out, which keeps damage-over-time ticks and glancing blows from making the flask
## unusable in a poison room.
func _on_hurt_received(amount: float, _poise_damage: float, _direction: Vector3) -> void:
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


## Ends the drink where it stands. The charge is spent either way — that is the cost of the
## gamble, and refunding it would remove the decision again — but the heal still lands if the
## commit point had already passed, so a hit landing on the last few frames is not a total loss.
##
## The commit point comes from the rig's `heal_commit_frame` when the clip authors one, and
## falls back to HEAL_COMMIT_FRACTION of the drink otherwise. Without that fallback the whole
## risk model would depend on whether a given character rig happened to carry a method track,
## and a rig missing one would make every interrupted heal a total loss.
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


## C-21: `_bind_anim_signals()` was a byte-identical copy of this function, one called from
## `_ready()` and one from `_try_drink()`. Both call sites now share this one.
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
	if not is_drinking:
		if PlayerInput.just_pressed(&"heal"):
			_try_drink()
		return
	_drink_timer -= delta
	if _drink_timer <= 0.0:
		_finish_drink()


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
	# C-21: `HEAL_STAMINA_COST` is 0.0, so the four stamina branches that used to stand here were
	# unreachable. Drinking is deliberately free of stamina cost — it is gated by charges and by
	# the drink animation's commitment window, not by the bar.
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
	# C-20: this played `play_hit_spark`, so the tensest voluntary act in the game looked exactly
	# like being hit. `heal` is its own effect in `content/vfx/effects.json` — rising motes, no
	# shard debris, no shake and no hitstop, since drinking must not cost a frame of control.
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
