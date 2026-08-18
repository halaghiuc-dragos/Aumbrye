class_name HealChargeMeter
extends RefCounted

## The flask counter: one pip per heal charge, filled while the charge is available.
##
## `PlayerHeal` has tracked charges and emitted `charges_changed` since it was written, and the
## HUD never showed them — the player had no way to know how many heals were left. In a
## soulslike the flask count is one of the three things permanently on screen, and it matters
## more now that a broken drink still spends the charge: without a visible count, the cost of a
## failed heal is invisible.
##
## Lives outside `combat_hud.gd` so the HUD stays under the project's file-length limit.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

const PIP_SIZE := Vector2(18.0, 10.0)
const PIP_FULL := Color(0.86, 0.74, 0.36, 1.0)
const PIP_EMPTY := Color(0.20, 0.18, 0.13, 0.85)
const INTERRUPT_FLASH := Color(1.8, 0.7, 0.6, 1.0)
const INTERRUPT_FLASH_IN := 0.06
const INTERRUPT_FLASH_OUT := 0.22


## Creates the pip row and inserts it directly above `sibling`, which is expected to be the
## status-icon row: the flask count is a resource, and belongs with the resource bars rather
## than among the transient effect icons.
static func build(sibling: Control) -> HBoxContainer:
	var parent := sibling.get_parent() as Control
	if parent == null:
		return null
	var row := HBoxContainer.new()
	row.name = "HealCharges"
	row.add_theme_constant_override("separation", GameUISkinScript.PIXEL_UNIT)
	parent.add_child(row)
	parent.move_child(row, sibling.get_index())
	return row


## Creates the row (if needed) and subscribes it to the player's flask.
##
## `on_changed` receives (current, max) and `on_interrupted` takes no arguments; the caller
## keeps ownership of the row so it can refresh from elsewhere. Returns the row, or null when
## the player carries no `PlayerHeal`.
static func bind(
	player: Node, sibling: Control, on_changed: Callable, on_interrupted: Callable
) -> HBoxContainer:
	if player == null or sibling == null:
		return null
	var heal := player.get_node_or_null("PlayerHeal")
	if heal == null:
		return null
	var row := build(sibling)
	if heal.has_signal("charges_changed") and not heal.charges_changed.is_connected(on_changed):
		heal.charges_changed.connect(on_changed)
	if (
		heal.has_signal("heal_interrupted")
		and not heal.heal_interrupted.is_connected(on_interrupted)
	):
		heal.heal_interrupted.connect(on_interrupted)
	refresh(row, int(heal.get("current_charges")), int(heal.get("max_charges")))
	return row


static func refresh(row: HBoxContainer, current: int, max_value: int) -> void:
	if row == null or not is_instance_valid(row):
		return
	for i in range(row.get_child_count(), max_value):
		var pip := ColorRect.new()
		pip.name = "HealPip%d" % i
		pip.custom_minimum_size = PIP_SIZE
		row.add_child(pip)
	for i in row.get_child_count():
		var pip := row.get_child(i) as ColorRect
		if pip == null:
			continue
		pip.visible = i < max_value
		pip.color = PIP_FULL if i < current else PIP_EMPTY


## Flashes the counter when a drink is broken, so the spent charge is attributable to the hit
## that took it rather than reading as a miscount.
static func flash_interrupt(row: HBoxContainer) -> void:
	if row == null or not is_instance_valid(row) or not row.is_inside_tree():
		return
	var tween := row.create_tween()
	tween.tween_property(row, "modulate", INTERRUPT_FLASH, INTERRUPT_FLASH_IN)
	tween.tween_property(row, "modulate", Color.WHITE, INTERRUPT_FLASH_OUT)
