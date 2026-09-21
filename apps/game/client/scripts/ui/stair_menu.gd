extends Control


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const DescentPactServiceScript := preload("res://scripts/dungeon/descent_pact_service.gd")
const RunModeConfigScript := preload("res://scripts/app/run_mode_config.gd")
const EndlessDifficultyScript := preload("res://scripts/dungeon/endless_difficulty.gd")
const DifficultyProfileScript := preload("res://scripts/dungeon/difficulty_profile.gd")

## UX-05: descent pacts are the run's biggest fork and used to render as a button whose entire
## pitch was squeezed into one label line. Give them the same card treatment `relic_offer_ui.gd`
## gives relics -- gain in green, cost in red -- and keep the plain navigation choices (ascend,
## descend, retreat) as buttons below the cards.
const CARD_MIN_SIZE := Vector2(320.0, 220.0)
const COLOR_GIVES := "#7fd67f"
const COLOR_TAKES := "#e07a7a"

signal closed

var _lever: Node3D
var _open := false
var _action_buttons: Array[Button] = []


func _ready() -> void:
	add_to_group("stair_menu")
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func is_open() -> bool:
	return _open


func open_for_lever(lever: Node3D, options: Array = []) -> void:
	if _open:
		return
	_lever = lever
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	MenuStack.push(self, true)
	if _lever and _lever.has_method("set_menu_open"):
		_lever.call("set_menu_open", true)
	_rebuild_buttons(options)


func close_menu() -> void:
	if not _open:
		return
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStack.pop(self)
	if _lever and _lever.has_method("set_menu_open"):
		_lever.call("set_menu_open", false)
	_lever = null
	_action_buttons.clear()
	closed.emit()


func _build_ui() -> void:
	var shell: Dictionary = MenuShellScript.build_modal(
		self,
		"Stair Lever",
		GameUISkinScript.MENU_HALF_W + 180.0,
		GameUISkinScript.MENU_HALF_H + 120.0
	)
	MenuShellScript.add_hint(shell["content_vbox"], "Esc to close")


func _rebuild_buttons(options: Array) -> void:
	var vbox := get_node_or_null("Panel/Margin/ContentVBox") as VBoxContainer
	if vbox == null:
		return
	for child in vbox.get_children():
		if child.name != "TitleLabel" and child.name != "HintLabel":
			child.queue_free()
	_action_buttons.clear()
	if _lever != null and is_instance_valid(_lever) and _lever.has_method("pressure_note"):
		var note := str(_lever.call("pressure_note"))
		if note != "":
			var pressure := Label.new()
			pressure.name = "PressureLabel"
			pressure.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			GameUISkinScript.style_body_label(pressure)
			pressure.text = note
			vbox.add_child(pressure)
	if RunFlow.get_run_mode() == RunModeConfigScript.MODE_ENDLESS:
		vbox.add_child(_make_pressure_bar())
	var pact_options: Array[Dictionary] = []
	var plain_options: Array[Dictionary] = []
	for option in options:
		if not option is Dictionary:
			continue
		var row: Dictionary = option
		if str(row.get("id", "")).begins_with(DescentPactServiceScript.PACT_OPTION_PREFIX):
			pact_options.append(row)
		else:
			plain_options.append(row)
	if not pact_options.is_empty():
		var pact_row := HBoxContainer.new()
		pact_row.name = "PactRow"
		pact_row.alignment = BoxContainer.ALIGNMENT_CENTER
		pact_row.add_theme_constant_override("separation", GameUISkinScript.PIXEL_UNIT * 4)
		vbox.add_child(pact_row)
		for row in pact_options:
			pact_row.add_child(_make_pact_card(row))
	for row in plain_options:
		var enabled := bool(row.get("enabled", false))
		var label := str(row.get("label", "Action"))
		if not enabled:
			var reason := str(row.get("reason", ""))
			if reason != "":
				label = "%s (%s)" % [label, reason]
		var option_id := str(row.get("id", ""))
		var btn := MenuShellScript.make_menu_button(
			label,
			func() -> void:
				if enabled:
					_on_option_pressed(option_id)
		)
		btn.disabled = not enabled
		vbox.add_child(btn)
		_action_buttons.append(btn)
	var close_button := MenuShellScript.make_menu_button(tr("UI_CLOSE"), close_menu)
	vbox.add_child(close_button)
	_action_buttons.append(close_button)
	_wire_focus_ring()
	_focus_first_enabled()


## AD-08: the pressure curve as a bar instead of a line of text -- fill is this floor's damage
## multiplier against the soft cap, with the personal-best depth marked on the same scale so the
## decision to bank the run has a visible "how far past my record am I" reference.
func _make_pressure_bar() -> Control:
	var box := VBoxContainer.new()
	box.name = "PressureBar"
	box.add_theme_constant_override("separation", 2)

	var next_floor := RunFlow.get_current_floor() + 1
	var profile := DifficultyProfileScript.for_run(RunModeConfigScript.MODE_ENDLESS)
	var current_floor := RunFlow.get_current_floor()
	var current_damage := profile.damage_multiplier(current_floor)
	var next_damage := profile.damage_multiplier(next_floor)
	var current_health := profile.hp_multiplier(current_floor)
	var next_health := profile.hp_multiplier(next_floor)
	var best_floor := ProgressionService.get_endless_best_floor()
	var best_damage := profile.damage_multiplier(best_floor) if best_floor > 0 else 1.0
	var scale_max := maxf(maxf(next_damage, best_damage), EndlessDifficultyScript.DAMAGE_SOFT_CAP)
	var ratio := log(maxf(1.0, next_damage)) / maxf(0.001, log(scale_max))
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = ratio * 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(300.0, 10.0)
	box.add_child(bar)
	var risk := Label.new()
	risk.text = "Current %.1fx HP / %.1fx damage · Next %.1fx HP / %.1fx damage" % [
		current_health, current_damage, next_health, next_damage
	]
	GameUISkinScript.style_hint_label(risk)
	box.add_child(risk)

	if best_floor > 0:
		var marker := Label.new()
		marker.text = "%s · %.1fx damage" % [
			tr("STAIR_PRESSURE_BEST").format({"floor": best_floor}), best_damage
		]
		GameUISkinScript.style_hint_label(marker)
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(marker)

	var next_milestone := _next_endless_milestone(next_floor)
	if not next_milestone.is_empty():
		var milestone_label := Label.new()
		milestone_label.text = tr("STAIR_PRESSURE_MILESTONE").format(
			{
				"floors": int(next_milestone.get("floor", 0)) - next_floor + 1,
				"label": str(next_milestone.get("label", "")),
			}
		)
		GameUISkinScript.style_hint_label(milestone_label)
		box.add_child(milestone_label)
	return box


func _next_endless_milestone(from_floor: int) -> Dictionary:
	var data := ProgressionService.get_endless_depth_data()
	var milestones: Array = data.get("milestones", [])
	for milestone in milestones:
		if not milestone is Dictionary:
			continue
		if int((milestone as Dictionary).get("floor", 0)) >= from_floor:
			return milestone
	return {}


func _make_pact_card(row: Dictionary) -> Control:
	var option_id := str(row.get("id", ""))
	var pact_id := DescentPactServiceScript.pact_id_from_option(option_id)
	var pact := DescentPactServiceScript.get_pact(pact_id)
	var card := VBoxContainer.new()
	card.name = "PactCard_%s" % pact_id
	card.custom_minimum_size = CARD_MIN_SIZE
	card.add_theme_constant_override("separation", GameUISkinScript.PIXEL_UNIT)

	var name_label := Label.new()
	name_label.text = str(pact.get("label", "Pact"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(name_label)

	var flavor := str(pact.get("description", ""))
	if flavor != "":
		var flavor_label := Label.new()
		flavor_label.text = flavor
		flavor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		GameUISkinScript.style_hint_label(flavor_label)
		card.add_child(flavor_label)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var gain := str(pact.get("gain", ""))
	var cost := str(pact.get("cost", ""))
	var lines: PackedStringArray = []
	if gain != "":
		lines.append("[color=%s]%s[/color]" % [COLOR_GIVES, gain])
	if cost != "":
		lines.append("[color=%s]%s[/color]" % [COLOR_TAKES, cost])
	body.text = "\n".join(lines)
	card.add_child(body)

	var enabled := bool(row.get("enabled", false))
	var take := MenuShellScript.make_menu_button(
		tr("RELIC_OFFER_TAKE"),
		func() -> void:
			if enabled:
				_on_option_pressed(option_id)
	)
	take.disabled = not enabled
	card.add_child(take)
	_action_buttons.append(take)
	return card


func _wire_focus_ring() -> void:
	var focusable: Array[Button] = []
	for btn in _action_buttons:
		if not btn.disabled:
			focusable.append(btn)
	if focusable.is_empty():
		return
	for i in focusable.size():
		var btn := focusable[i]
		var prev := focusable[(i - 1 + focusable.size()) % focusable.size()]
		var next := focusable[(i + 1) % focusable.size()]
		btn.focus_neighbor_top = prev.get_path()
		btn.focus_neighbor_bottom = next.get_path()


func _focus_first_enabled() -> void:
	for btn in _action_buttons:
		if not btn.disabled:
			btn.grab_focus()
			return
	for btn in _action_buttons:
		if btn.text == tr("UI_CLOSE"):
			btn.grab_focus()
			return


func _on_option_pressed(option_id: String) -> void:
	if _lever == null:
		close_menu()
		return
	if _lever.has_method("use"):
		if bool(_lever.call("use", option_id)):
			close_menu()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_menu()
