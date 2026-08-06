extends Node

## Estus-style bound heal: limited charges, vulnerable drink animation.

const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")

const DEFAULT_MAX_CHARGES := 3
const HEAL_AMOUNT := 0.45
const DRINK_DURATION := 1.35
const HEAL_STAMINA_COST := 0.0

signal charges_changed(current: int, max_value: int)
signal heal_started
signal heal_ended

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
	charges_changed.emit(current_charges, max_charges)


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


func locks_movement() -> bool:
	return is_drinking


func _try_drink() -> void:
	if is_drinking or current_charges <= 0:
		return
	if _reactions and _reactions.has_method("can_act") and not _reactions.call("can_act"):
		return
	if _health and _health.is_dead():
		return
	if _stamina and HEAL_STAMINA_COST > 0.0 and not _stamina.has(HEAL_STAMINA_COST):
		return
	if _stamina and HEAL_STAMINA_COST > 0.0:
		_stamina.consume(HEAL_STAMINA_COST)
	is_drinking = true
	_heal_committed = false
	_drink_timer = DRINK_DURATION
	heal_started.emit()
	_bind_anim_signals()
	if AudioDirector:
		AudioDirector.play_combat_sfx("heal_raise", _body.global_position + Vector3(0.0, 1.2, 0.0))
	_anim_director = _body.get_node_or_null("AnimDirector")
	if _anim_director and _anim_director.has_method("play_heal"):
		_anim_director.call("play_heal", DRINK_DURATION)


func _bind_anim_signals() -> void:
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
	VfxService.play_hit_spark(_body.global_position + Vector3(0.0, 1.1, 0.0), Vector3.UP)


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
