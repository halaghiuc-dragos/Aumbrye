extends Control

## In-run UI for Umbral Waves lobby, combat, prep, and reward pick.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")

var _label: Label
var _ready_button: Button
var _reward_box: VBoxContainer
var _confirm_button: Button
var _confirm_hint: Label
var _selected_rewards: Array[String] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 120.0
	add_child(panel)
	GameUISkinScript.style_panel(panel)
	var margin := MarginContainer.new()
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(_label)
	vbox.add_child(_label)
	_ready_button = MenuShellScript.make_menu_button("Ready — start waves", _on_ready_pressed)
	_ready_button.visible = false
	vbox.add_child(_ready_button)
	_reward_box = VBoxContainer.new()
	_reward_box.visible = false
	vbox.add_child(_reward_box)


func show_lobby() -> void:
	_reward_box.visible = false
	_ready_button.visible = true
	refresh_lobby()


func refresh_lobby() -> void:
	var total := WavesRunService.get_chest_count()
	var opened := 0
	for i in total:
		if WavesRunService.chests_opened.get(str(i), false):
			opened += 1
	_label.text = (
		"Open all %d chests (%d/%d). Walk to chest + E. Waves loadout only."
		% [total, opened, total]
	)
	_ready_button.disabled = not WavesRunService.all_chests_opened()
	if WavesRunService.all_chests_opened() and not WavesRunService.lobby_ready:
		_label.text += "\nAll chests open — press Ready."


func show_combat(wave: int) -> void:
	_ready_button.visible = false
	_reward_box.visible = false
	_label.text = tr("WAVES_WAVE_ACTIVE").format({"wave": wave})


func show_prep(wave: int, countdown: float) -> void:
	_ready_button.visible = false
	_label.text = tr("WAVES_MILESTONE_CLEARED").format({"wave": wave, "seconds": "%.0f" % countdown})


func show_reward_pick() -> void:
	_ready_button.visible = false
	_reward_box.visible = true
	_selected_rewards.clear()
	for child in _reward_box.get_children():
		child.queue_free()
	_label.text = tr("WAVES_VICTORY_PICK")
	var inventory := WavesRunService.waves_inventory
	for slot in inventory.slots:
		var item_id: String = str(slot.get("itemId", ""))
		if item_id == "":
			continue
		# C-247: this read `"Take %s" % item_id`, so the final screen of the mode offered
		# "Take unique_widow_of_the_stair". `get_slot_display_name` resolves the catalog name and
		# prefixes the rarity, exactly as the inventory and loadout lists already do.
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


func _on_ready_pressed() -> void:
	var run := get_tree().get_first_node_in_group("waves_run")
	if run and run.has_method("try_ready"):
		run.call("try_ready")
	if run and run.has_method("start_waves_from_lobby") and WavesRunService.lobby_ready:
		run.call("start_waves_from_lobby")


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
	var run := get_tree().get_first_node_in_group("waves_run")
	if run and run.has_method("complete_waves_with_rewards"):
		run.call("complete_waves_with_rewards", _selected_rewards.duplicate())
