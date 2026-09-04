extends Control


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")

## HD-01: this UI owns only the lobby/reward/cash-out flows -- combat status (wave, enemies
## remaining) is HUD territory, shown via combat_hud.gd's region title / objective text.
var _panel: PanelContainer
var _label: Label
var _reward_box: VBoxContainer
var _confirm_button: Button
var _confirm_hint: Label
var _selected_rewards: Array[String] = []
var _reward_stack_pushed := false
var _cash_out_active := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -360.0
	_panel.offset_right = 360.0
	_panel.offset_top = 16.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	GameUISkinScript.style_panel(_panel)
	var margin := MarginContainer.new()
	_panel.add_child(margin)
	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(_label)
	vbox.add_child(_label)
	_reward_box = VBoxContainer.new()
	_reward_box.visible = false
	vbox.add_child(_reward_box)


func show_lobby() -> void:
	_panel.visible = true
	_reward_box.visible = false
	refresh_lobby()


func refresh_lobby() -> void:
	if _cash_out_active:
		return
	var total := WavesRunService.get_chest_count()
	var opened := 0
	for i in total:
		if WavesRunService.chests_opened.get(str(i), false):
			opened += 1
	var glyph := InputGlyphServiceScript.get_action_glyph("interact")
	var lines: Array[String] = []
	if WavesRunService.is_first_lobby():
		if WavesRunService.has_torch():
			lines.append("You have the torch. Light the cresset at the centre (%s)." % glyph)
		else:
			lines.append("A torch is buried in one of these caches. Find it.")
	else:
		lines.append(
			"Wave %d cleared. Fresh caches have come up." % WavesRunService.current_wave
		)
		lines.append(
			"Call wave %d at the cresset when you are ready (%s)."
			% [WavesRunService.current_wave + 1, glyph]
		)
	if WavesRunService.is_cash_out_wave(WavesRunService.current_wave):
		lines.append("The summoner's portal is open. He will send one thing home with you.")
	lines.append("Caches opened %d/%d — walk up and press %s." % [opened, total, glyph])
	_label.text = "\n".join(lines)


## HD-01: wave/enemy-count status now lives on the HUD (`show_region_title`/`set_objective_text`
## in combat_hud.gd); this panel just gets out of the way during combat.
func show_combat(_wave: int) -> void:
	_panel.visible = false
	_reward_box.visible = false


func show_reward_pick() -> void:
	_panel.visible = true
	_reward_box.visible = true
	if MenuStack and not _reward_stack_pushed:
		_reward_stack_pushed = true
		MenuStack.push(self, true)
	_selected_rewards.clear()
	for child in _reward_box.get_children():
		child.queue_free()
	_label.text = tr("WAVES_VICTORY_PICK")
	var inventory := WavesRunService.waves_inventory
	for slot in inventory.slots:
		var item_id: String = str(slot.get("itemId", ""))
		if item_id == "":
			continue
		var display_name: String = inventory.get_slot_display_name(slot)
		var quantity: int = int(slot.get("quantity", 1))
		if quantity > 1:
			display_name = "%s x%d" % [display_name, quantity]
		var btn := GameUISkinScript.make_button(tr("WAVES_TAKE_REWARD").format({"item": display_name}))
		btn.toggle_mode = true
		btn.pressed.connect(_on_pick_reward.bind(item_id, btn))
		_reward_box.add_child(btn)
	_confirm_hint = Label.new()
	_confirm_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(_confirm_hint)
	_reward_box.add_child(_confirm_hint)
	_confirm_button = MenuShellScript.make_menu_button("Confirm selection", _on_confirm_rewards)
	_reward_box.add_child(_confirm_button)
	_refresh_confirm_state()


## The summoner's offer. `WavesRunService.cash_out_bank_count()` escalates with depth (one below
## wave 30, up to three from wave 40), and taking it ends the Vigil -- so each option reads as a
## card (rarity border, tooltip) and the risk of what stays behind is spelled out in words.
func show_cash_out_pick() -> void:
	_cash_out_active = true
	_panel.visible = true
	_reward_box.visible = true
	if MenuStack and not _reward_stack_pushed:
		_reward_stack_pushed = true
		MenuStack.push(self, true)
	_selected_rewards.clear()
	for child in _reward_box.get_children():
		child.queue_free()
	var options := WavesRunService.get_cash_out_options()
	var bank_count := WavesRunService.cash_out_bank_count(WavesRunService.current_wave)
	if options.is_empty():
		_label.text = tr("WAVES_CASH_OUT_EMPTY")
	else:
		var lines: Array[String] = [tr("WAVES_CASH_OUT_INTRO")]
		lines.append(
			tr("WAVES_CASH_OUT_RISK").format(
				{"bank": bank_count, "total": options.size(), "lost": maxi(0, options.size() - bank_count)}
			)
		)
		var best_wave := int(CharacterService.get_flag("waves_best_wave"))
		if best_wave > 0:
			lines.append(tr("WAVES_CASH_OUT_BEST").format({"wave": best_wave}))
		_label.text = "\n".join(lines)
	for option in options:
		var item_id := str(option.get("itemId", ""))
		var rarity := str(option.get("rarity", "common"))
		var display_name := str(option.get("displayName", item_id))
		if bool(option.get("equipped", false)):
			display_name = "%s (equipped)" % display_name
		var btn := GameUISkinScript.make_button(display_name)
		btn.toggle_mode = true
		btn.add_theme_stylebox_override("normal", GameUISkinScript.make_item_cell_style(rarity, false))
		btn.add_theme_stylebox_override("pressed", GameUISkinScript.make_item_cell_style(rarity, true))
		var item_def := ItemCatalog.get_definition(item_id)
		var description := str(item_def.get("description", ""))
		if description != "":
			btn.tooltip_text = description
		btn.pressed.connect(_on_pick_cash_out.bind(item_id, btn, bank_count))
		_reward_box.add_child(btn)
	_confirm_hint = Label.new()
	_confirm_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(_confirm_hint)
	_reward_box.add_child(_confirm_hint)
	_confirm_button = MenuShellScript.make_menu_button(
		tr("WAVES_CASH_OUT_CONFIRM"), _on_confirm_cash_out
	)
	_reward_box.add_child(_confirm_button)
	var back_button := MenuShellScript.make_menu_button(
		tr("WAVES_CASH_OUT_STAY"), _on_cancel_cash_out
	)
	_reward_box.add_child(back_button)
	_refresh_cash_out_state(bank_count)


func _on_pick_cash_out(item_id: String, btn: Button, bank_count: int) -> void:
	if item_id in _selected_rewards:
		_selected_rewards.erase(item_id)
		btn.button_pressed = false
	elif _selected_rewards.size() < bank_count:
		_selected_rewards.append(item_id)
		btn.button_pressed = true
	else:
		btn.button_pressed = false
	_refresh_cash_out_state(bank_count)


func _refresh_cash_out_state(bank_count: int = 1) -> void:
	if _confirm_button == null:
		return
	var chosen := not _selected_rewards.is_empty()
	_confirm_button.disabled = not chosen
	if _confirm_hint:
		if chosen:
			_confirm_hint.text = ""
		elif bank_count > 1:
			_confirm_hint.text = tr("WAVES_CASH_OUT_PICK_HINT_MULTI").format({"count": bank_count})
		else:
			_confirm_hint.text = tr("WAVES_CASH_OUT_PICK_HINT")


func _on_cancel_cash_out() -> void:
	_cash_out_active = false
	_selected_rewards.clear()
	_reward_box.visible = false
	if MenuStack and _reward_stack_pushed:
		_reward_stack_pushed = false
		MenuStack.pop(self)
	refresh_lobby()


func _on_confirm_cash_out() -> void:
	if _confirm_button and _confirm_button.disabled:
		return
	if _selected_rewards.is_empty():
		return
	if MenuStack and _reward_stack_pushed:
		_reward_stack_pushed = false
		MenuStack.pop(self)
	_cash_out_active = false
	var run := get_tree().get_first_node_in_group("waves_run")
	if run and run.has_method("cash_out_with_item"):
		run.call("cash_out_with_item", _selected_rewards.duplicate())


func _on_pick_reward(item_id: String, btn: Button) -> void:
	if item_id in _selected_rewards:
		_selected_rewards.erase(item_id)
		btn.button_pressed = false
	elif _selected_rewards.size() < 3:
		_selected_rewards.append(item_id)
		btn.button_pressed = true
	_refresh_confirm_state()


func _inventory_item_count() -> int:
	var count := 0
	for slot in WavesRunService.waves_inventory.slots:
		if str(slot.get("itemId", "")) != "":
			count += 1
	return count


func _refresh_confirm_state() -> void:
	if _confirm_button == null:
		return
	var item_count := _inventory_item_count()
	var needs_pick := item_count > 0 and _selected_rewards.is_empty()
	_confirm_button.disabled = needs_pick
	if _confirm_hint:
		_confirm_hint.text = tr("WAVES_PICK_AT_LEAST_ONE") if needs_pick else ""


func _on_confirm_rewards() -> void:
	if _confirm_button and _confirm_button.disabled:
		return
	if MenuStack and _reward_stack_pushed:
		_reward_stack_pushed = false
		MenuStack.pop(self)
	var run := get_tree().get_first_node_in_group("waves_run")
	if run and run.has_method("complete_waves_with_rewards"):
		run.call("complete_waves_with_rewards", _selected_rewards.duplicate())
