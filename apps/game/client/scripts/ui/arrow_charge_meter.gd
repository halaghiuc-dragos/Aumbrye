class_name ArrowChargeMeter
extends RefCounted

## `RG-02`: the quiver's HUD pips, right next to `HealChargeMeter` which this mirrors exactly --
## same build/bind/refresh shape, a smaller pip for a resource that refills 12-wide instead of 3.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

const PIP_SIZE := Vector2(8.0, 10.0)
const PIP_FULL := Color(0.62, 0.74, 0.46, 1.0)
const PIP_EMPTY := Color(0.16, 0.19, 0.14, 0.85)


static func build(sibling: Control) -> HBoxContainer:
	var parent := sibling.get_parent() as Control
	if parent == null:
		return null
	var row := HBoxContainer.new()
	row.name = "ArrowCharges"
	row.add_theme_constant_override("separation", maxi(1, int(GameUISkinScript.PIXEL_UNIT / 2.0)))
	parent.add_child(row)
	parent.move_child(row, sibling.get_index() + 1)
	return row


static func bind(player: Node, sibling: Control, on_changed: Callable) -> HBoxContainer:
	if player == null or sibling == null:
		return null
	var arrows := player.get_node_or_null("PlayerArrows")
	if arrows == null:
		return null
	var row := build(sibling)
	if arrows.has_signal("arrows_changed") and not arrows.arrows_changed.is_connected(on_changed):
		arrows.arrows_changed.connect(on_changed)
	refresh(row, int(arrows.get("current_arrows")), int(arrows.get("max_arrows")))
	return row


static func refresh(row: HBoxContainer, current: int, max_value: int) -> void:
	if row == null or not is_instance_valid(row):
		return
	for i in range(row.get_child_count(), max_value):
		var pip := ColorRect.new()
		pip.name = "ArrowPip%d" % i
		pip.custom_minimum_size = PIP_SIZE
		row.add_child(pip)
	for i in row.get_child_count():
		var pip := row.get_child(i) as ColorRect
		if pip == null:
			continue
		pip.visible = i < max_value
		pip.color = PIP_FULL if i < current else PIP_EMPTY
