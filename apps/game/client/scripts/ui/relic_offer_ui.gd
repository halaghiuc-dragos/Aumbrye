extends Control

## Choice-of-three relic offer, presented after a boss falls.
##
## `RunBuffs.roll_offer()` and `take_offer()` — the seeded, synergy-weighted pick that is the
## core roguelite decision — were fully implemented and invoked from nowhere. The only way a
## relic could enter a run was picking up one of the eleven items that carry a `runRelicId`,
## which left 24 of the 35 authored relics (all the rule-bearing, build-defining ones)
## unreachable in normal play.
##
## The offer is keyed to the floor and dungeon, so a given run seed always presents the same
## three choices at the same boss — rerolling by dying and returning is not a strategy.

signal offer_closed(relic_id: String)

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const OFFER_COUNT := 3
const CARD_MIN_SIZE := Vector2(210.0, 150.0)

var _open := false
var _offer_ids: Array[String] = []
var _buttons: Array[Button] = []


func _ready() -> void:
	add_to_group("relic_offer_ui")
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_open() -> bool:
	return _open


## Rolls and shows an offer. Returns false when there is nothing to present — no relics left
## that this run can still take — so callers can carry on without a dead modal.
func open_offer(offer_key: String) -> bool:
	if _open or RunBuffs == null:
		return false
	var rolled: Array[String] = RunBuffs.roll_offer(offer_key, OFFER_COUNT)
	if rolled.is_empty():
		return false
	_offer_ids = rolled
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	MenuStack.push(self, true)
	_build_ui()
	return true


func get_offer_ids() -> Array[String]:
	return _offer_ids.duplicate()


func _build_ui() -> void:
	var shell: Dictionary = MenuShellScript.build_modal(
		self,
		tr("RELIC_OFFER_TITLE"),
		GameUISkinScript.MENU_HALF_W + 180.0,
		GameUISkinScript.MENU_HALF_H + 40.0
	)
	var vbox: VBoxContainer = shell["content_vbox"]
	MenuShellScript.add_subtitle(vbox, tr("RELIC_OFFER_SUBTITLE"))
	var row := HBoxContainer.new()
	row.name = "OfferRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", GameUISkinScript.PIXEL_UNIT * 4)
	vbox.add_child(row)
	_buttons.clear()
	for relic_id in _offer_ids:
		row.add_child(_make_card(relic_id))
	MenuShellScript.add_hint(vbox, tr("RELIC_OFFER_HINT"))
	_wire_focus_ring()
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _make_card(relic_id: String) -> Control:
	var def := RelicCatalog.get_definition(relic_id)
	var card := VBoxContainer.new()
	card.name = "Card_%s" % relic_id
	card.custom_minimum_size = CARD_MIN_SIZE
	card.add_theme_constant_override("separation", GameUISkinScript.PIXEL_UNIT)

	var name_label := Label.new()
	name_label.text = str(def.get("name", relic_id))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(name_label)

	var body := Label.new()
	body.text = _describe(def)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(body)

	var take := MenuShellScript.make_menu_button(
		tr("RELIC_OFFER_TAKE"), func() -> void: _take(relic_id)
	)
	card.add_child(take)
	_buttons.append(take)
	return card


## Prefers the authored description, and falls back to the stat block so a relic without prose
## still tells the player what it does rather than showing an empty card.
func _describe(def: Dictionary) -> String:
	var text := str(def.get("description", ""))
	if text != "":
		return text
	var lines: PackedStringArray = PackedStringArray()
	var stats: Dictionary = def.get("stats", {})
	for stat in stats:
		lines.append(
			"%s %s"
			% [
				Equipment.stat_display_name(str(stat)),
				Equipment.format_stat_value(str(stat), float(stats[stat]), true)
			]
		)
	return "\n".join(lines)


func _take(relic_id: String) -> void:
	if not _open:
		return
	if RunBuffs:
		RunBuffs.take_offer(relic_id)
	_close(relic_id)


func _close(relic_id: String) -> void:
	if not _open:
		return
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStack.pop(self)
	_buttons.clear()
	_offer_ids.clear()
	offer_closed.emit(relic_id)


func _wire_focus_ring() -> void:
	if _buttons.is_empty():
		return
	for i in _buttons.size():
		var btn := _buttons[i]
		var prev := _buttons[(i - 1 + _buttons.size()) % _buttons.size()]
		var next := _buttons[(i + 1) % _buttons.size()]
		btn.focus_neighbor_left = prev.get_path()
		btn.focus_neighbor_right = next.get_path()


## Deliberately no cancel path: the offer is a decision, and letting the player dismiss it
## turns "which relic" into "do I want to be bothered". `ui_cancel` is swallowed so the pause
## menu cannot open behind it either.
func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
