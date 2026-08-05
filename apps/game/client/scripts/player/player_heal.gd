extends Node

## Estus-style bound heal: limited charges, vulnerable drink animation.

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
var _drink_timer := 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_health = _body.get_node_or_null("Health") as Health
	_stamina = _body.get_node_or_null("Stamina") as Stamina
	_reactions = _body.get_node_or_null("CombatReactions")
	charges_changed.emit(current_charges, max_charges)


func _physics_process(delta: float) -> void:
	if not is_drinking:
		if Input.is_action_just_pressed("heal"):
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
	_drink_timer = DRINK_DURATION
	heal_started.emit()
	var director := _body.get_node_or_null("AnimDirector")
	if director and director.has_method("play_heal"):
		director.call("play_heal", DRINK_DURATION)


func _finish_drink() -> void:
	is_drinking = false
	current_charges = maxi(0, current_charges - 1)
	charges_changed.emit(current_charges, max_charges)
	if _health:
		_health.heal(_health.max_health * HEAL_AMOUNT)
	heal_ended.emit()
