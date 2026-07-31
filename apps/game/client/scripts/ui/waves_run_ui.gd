extends Control

## In-run UI for Umbral Waves lobby, combat, prep, and reward pick.

var _label: Label
var _ready_button: Button
var _reward_box: VBoxContainer
var _selected_rewards: Array[String] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 120.0
	add_child(panel)
	var margin := MarginContainer.new()
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_label)
	_ready_button = Button.new()
	_ready_button.text = "Ready — start waves"
	_ready_button.visible = false
	_ready_button.pressed.connect(_on_ready_pressed)
	vbox.add_child(_ready_button)
	_reward_box = VBoxContainer.new()
	_reward_box.visible = false
	vbox.add_child(_reward_box)


func show_lobby() -> void:
	_reward_box.visible = false
	_ready_button.visible = true
	refresh_lobby()


func refresh_lobby() -> void:
	var opened := 0
	for i in WavesRunService.CHEST_RARITIES.size():
		if WavesRunService.chests_opened.get(str(i), false):
			opened += 1
	_label.text = "Open all 10 chests (%d/10). Walk to chest + E. Umbral loadout only." % opened
	_ready_button.disabled = not WavesRunService.all_chests_opened()
	if WavesRunService.all_chests_opened() and not WavesRunService.lobby_ready:
		_label.text += "\nAll chests open — press Ready."


func show_combat(wave: int) -> void:
	_ready_button.visible = false
	_reward_box.visible = false
	_label.text = "Wave %d — clear all enemies." % wave


func show_prep(wave: int, countdown: float) -> void:
	_ready_button.visible = false
	_label.text = "Milestone wave %d cleared! Walls rebuild — prep %.0fs." % [wave, countdown]


func show_reward_pick() -> void:
	_ready_button.visible = false
	_reward_box.visible = true
	_selected_rewards.clear()
	for child in _reward_box.get_children():
		child.queue_free()
	_label.text = "Victory! Choose up to 3 items to keep:"
	for slot in WavesRunService.waves_inventory.slots:
		var item_id: String = str(slot.get("itemId", ""))
		if item_id == "":
			continue
		var btn := Button.new()
		btn.text = "Take %s" % item_id
		btn.pressed.connect(_on_pick_reward.bind(item_id, btn))
		_reward_box.add_child(btn)
	var confirm := Button.new()
	confirm.text = "Confirm selection"
	confirm.pressed.connect(_on_confirm_rewards)
	_reward_box.add_child(confirm)


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


func _on_confirm_rewards() -> void:
	var run := get_tree().get_first_node_in_group("waves_run")
	if run and run.has_method("complete_waves_with_rewards"):
		run.call("complete_waves_with_rewards", _selected_rewards.duplicate())
