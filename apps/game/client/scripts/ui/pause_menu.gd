extends Control


signal closed
signal cancel_requested

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const ConfirmSpecScript := preload("res://scripts/ui/confirm_spec.gd")
const RunModeConfigScript := preload("res://scripts/app/run_mode_config.gd")

var _open := false
var _ui_built := false
var _content_vbox: VBoxContainer
var _actions_vbox: VBoxContainer
var _initial_focus: Button
var _mode_value: Label
var _floor_value: Label
var _time_value: Label
var _seed_value: LineEdit
var _objective_value: Label
var _cloud_status_label: Label


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_shell()
	cancel_requested.connect(_on_cancel_requested)
	if not closed.is_connected(_on_closed):
		closed.connect(_on_closed)
	if MenuStack and not MenuStack.stack_changed.is_connected(_on_stack_changed):
		MenuStack.stack_changed.connect(_on_stack_changed)


func is_open() -> bool:
	return _open


func toggle() -> void:
	if PlayerControls and PlayerControls.has_method("allows_player_ui"):
		if not PlayerControls.call("allows_player_ui"):
			return
	if _open:
		close_menu()
	else:
		open_menu()


func open_menu() -> void:
	move_to_front()
	if _open:
		return
	_rebuild_actions()
	_refresh_run_info()
	# HD-03: `build_modal()` only styles the panel shell -- action buttons are rebuilt fresh each
	# open, so the pixel-filter sweep needs to run here rather than once in `_ready()`.
	GameUISkinScript.apply_pixel_theme(self)
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	MenuStack.push(self, true)
	AudioDirector.set_pause_mix(true)
	if _initial_focus:
		_initial_focus.grab_focus()


func close_menu() -> void:
	if not _open:
		return
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStack.pop(self)
	AudioDirector.set_pause_mix(false)
	closed.emit()


func _on_closed() -> void:
	if MenuStack and MenuStack.depth() > 0 and MenuStack.top() == self:
		MenuStack.pop(self)


func _on_stack_changed(_depth: int) -> void:
	if _open and MenuStack and MenuStack.top() == self and _initial_focus:
		_initial_focus.grab_focus()


func _on_cancel_requested() -> void:
	close_menu()


func _build_shell() -> void:
	if _ui_built:
		return
	_ui_built = true
	var shell: Dictionary = MenuShellScript.build_modal(
		self, tr("PAUSE_TITLE"), GameUISkinScript.MENU_HALF_W + 40.0, GameUISkinScript.MENU_HALF_H + 120.0
	)
	_content_vbox = shell["content_vbox"]
	_cloud_status_label = Label.new()
	_cloud_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(_cloud_status_label)
	_content_vbox.add_child(_cloud_status_label)
	_refresh_cloud_status()
	if not ApiConfig.cloud_state_changed.is_connected(_on_cloud_state_changed):
		ApiConfig.cloud_state_changed.connect(_on_cloud_state_changed)
	var run_info := GameUISkinScript.make_section_frame(tr("PAUSE_INFO_SECTION"))
	run_info.name = "RunInfo"
	_content_vbox.add_child(run_info)
	var info_vbox := GameUISkinScript.section_content(run_info)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	info_vbox.add_child(grid)
	_mode_value = _add_info_row(grid, "ModeKey", tr("PAUSE_INFO_MODE"))
	_floor_value = _add_info_row(grid, "FloorKey", tr("PAUSE_INFO_FLOOR"))
	_time_value = _add_info_row(grid, "TimeKey", tr("PAUSE_INFO_TIME"))
	_add_seed_row(grid)
	_objective_value = _add_info_row(grid, "ObjKey", tr("PAUSE_INFO_OBJECTIVE"))
	_actions_vbox = VBoxContainer.new()
	_actions_vbox.name = "Actions"
	_actions_vbox.add_theme_constant_override("separation", MenuShellScript.DEFAULT_SEPARATION)
	_content_vbox.add_child(_actions_vbox)


func _add_info_row(grid: GridContainer, key_name: String, key_text: String) -> Label:
	var key := Label.new()
	key.name = key_name
	key.text = key_text
	GameUISkinScript.style_body_label(key)
	grid.add_child(key)
	var value := Label.new()
	value.name = "%sValue" % key_name.trim_suffix("Key")
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(value)
	grid.add_child(value)
	return value


func _add_seed_row(grid: GridContainer) -> void:
	var key := Label.new()
	key.name = "SeedKey"
	key.text = tr("PAUSE_INFO_SEED")
	GameUISkinScript.style_body_label(key)
	grid.add_child(key)
	_seed_value = LineEdit.new()
	_seed_value.name = "SeedValue"
	_seed_value.editable = false
	_seed_value.focus_mode = Control.FOCUS_ALL
	_seed_value.select_all_on_focus = true
	_seed_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_seed_value)


func _rebuild_actions() -> void:
	if _actions_vbox == null:
		return
	for child in _actions_vbox.get_children():
		_actions_vbox.remove_child(child)
		child.queue_free()
	var buttons: Array[Button] = []
	var resume := MenuShellScript.make_menu_button(tr("PAUSE_RESUME"), _on_resume)
	resume.name = "Resume"
	buttons.append(resume)
	_initial_focus = resume
	if RunFlow.is_run_active():
		if RunModeConfigScript.is_waves(RunFlow.get_run_mode()):
			var leave := MenuShellScript.make_menu_button(tr("PAUSE_LEAVE_WAVES"), _on_leave_waves)
			leave.name = "LeaveWaves"
			buttons.append(leave)
		elif RunFlow.get_run_mode() == RunModeConfigScript.MODE_CASTLE:
			if RunFlow.can_restart_current_floor():
				var restart := MenuShellScript.make_menu_button(
					tr("PAUSE_RESTART_FLOOR"), _on_restart_floor
				)
				restart.name = "RestartFloor"
				buttons.append(restart)
			var abandon := MenuShellScript.make_menu_button(tr("PAUSE_ABANDON"), _on_abandon)
			abandon.name = "AbandonRun"
			buttons.append(abandon)
	buttons.append(MenuShellScript.make_menu_button(tr("PAUSE_ACHIEVEMENTS"), _on_achievements))
	buttons.append(MenuShellScript.make_menu_button(tr("PAUSE_BESTIARY"), _on_bestiary))
	buttons.append(MenuShellScript.make_menu_button(tr("PAUSE_SETTINGS"), _on_settings))
	buttons.append(MenuShellScript.make_menu_button(tr("PAUSE_QUIT"), _on_quit_to_menu))
	for i in buttons.size():
		_actions_vbox.add_child(buttons[i])
	_wire_vertical_focus_neighbors(buttons)


func _wire_vertical_focus_neighbors(buttons: Array[Button]) -> void:
	for i in buttons.size():
		var btn := buttons[i]
		if i > 0:
			btn.focus_neighbor_top = buttons[i - 1].get_path()
		if i < buttons.size() - 1:
			btn.focus_neighbor_bottom = buttons[i + 1].get_path()


func _refresh_run_info() -> void:
	if _mode_value:
		if not RunFlow.is_run_active():
			_mode_value.text = tr("PAUSE_MODE_HUB")
		else:
			match RunFlow.get_run_mode():
				RunModeConfigScript.MODE_CASTLE:
					_mode_value.text = tr("PAUSE_MODE_CASTLE")
				RunModeConfigScript.MODE_WAVES:
					_mode_value.text = tr("PAUSE_MODE_WAVES")
				RunModeConfigScript.MODE_ENDLESS:
					_mode_value.text = tr("PAUSE_MODE_ENDLESS")
				_:
					_mode_value.text = RunFlow.get_run_mode()
	if _floor_value:
		if RunFlow.is_run_active() and RunModeConfigScript.is_multi_floor(RunFlow.get_run_mode()):
			_floor_value.text = tr("PAUSE_FLOOR_FMT") % [
				RunFlow.get_current_floor(),
				RunFlow.get_max_floors(),
			]
		elif RunFlow.is_run_active() and RunModeConfigScript.is_waves(RunFlow.get_run_mode()):
			_floor_value.text = tr("PAUSE_WAVE_FMT") % WavesRunService.current_wave
		else:
			_floor_value.text = "—"
	if _time_value:
		var played := LocalSave.get_playtime_seconds()
		if RunFlow.is_run_active():
			_time_value.text = "%s  (run %s)" % [
				LocalSave.format_playtime(played),
				LocalSave.format_playtime(RunFlow.get_run_elapsed_seconds()),
			]
		else:
			_time_value.text = LocalSave.format_playtime(played)
	if _seed_value:
		if RunFlow.is_run_active() and RunFlow.current_seed > 0:
			_seed_value.text = str(RunFlow.current_seed)
		else:
			_seed_value.text = "—"
	if _objective_value:
		_objective_value.text = RunFlow.get_current_objective()


func _on_resume() -> void:
	close_menu()


func _on_settings() -> void:
	if PlayerControls:
		PlayerControls.open_settings()


func _on_achievements() -> void:
	if PlayerControls:
		PlayerControls.open_achievements()


func _on_bestiary() -> void:
	if PlayerControls:
		PlayerControls.open_bestiary()


func _on_leave_waves() -> void:
	var spec := ConfirmSpecScript.new()
	spec.title_key = &"PAUSE_CONFIRM_LEAVE_TITLE"
	spec.message_key = &"PAUSE_CONFIRM_LEAVE_BODY"
	spec.confirm_key = &"PAUSE_CONFIRM_LEAVE_OK"
	spec.cancel_key = &"PAUSE_CONFIRM_LEAVE_CANCEL"
	spec.destructive = true
	spec.on_confirm = func() -> void:
		close_menu()
		RunFlow.quit_waves_run()
	if MenuStack:
		MenuStack.confirm(spec)


func _on_restart_floor() -> void:
	close_menu()
	RunFlow.restart_current_floor()


func _on_abandon() -> void:
	var stakes := RunFlow.get_abandon_stakes()
	var spec := ConfirmSpecScript.new()
	spec.title_key = &"PAUSE_CONFIRM_ABANDON_TITLE"
	spec.message_key = &"PAUSE_CONFIRM_ABANDON_BODY"
	spec.message_args = [stakes.get("floor", 1), stakes.get("items", 0), stakes.get("gold", 0)]
	spec.confirm_key = &"PAUSE_CONFIRM_ABANDON_OK"
	spec.cancel_key = &"PAUSE_CONFIRM_ABANDON_CANCEL"
	spec.destructive = true
	spec.on_confirm = func() -> void:
		close_menu()
		RunFlow.abandon_active_run()
	if MenuStack:
		MenuStack.confirm(spec)


## Quitting is not a save point. `return_to_main_menu()` flushes the run to disk before leaving --
## right for closing the app mid-hub, wrong here, where the same button sat next to "Abandon" in
## castle mode and quietly did the opposite of it: abandon discarded the run, this saved it, so
## which one lost your progress depended on which button you happened to press. Every mode now
## leaves the same way abandoning already did -- through whichever discard path that mode owns --
## so quitting never leaves a run to continue and never leaves this run's loot in the bag.
func _on_quit_to_menu() -> void:
	var spec := ConfirmSpecScript.new()
	spec.title_key = &"PAUSE_CONFIRM_QUIT_TITLE"
	spec.message_key = &"PAUSE_CONFIRM_QUIT_BODY"
	spec.confirm_key = &"PAUSE_CONFIRM_QUIT_OK"
	spec.cancel_key = &"PAUSE_CONFIRM_QUIT_CANCEL"
	spec.destructive = true
	spec.on_confirm = func() -> void:
		close_menu()
		if not RunFlow.is_run_active():
			RunFlow.return_to_main_menu()
		elif RunModeConfigScript.is_waves(RunFlow.get_run_mode()):
			RunFlow.quit_waves_run()
		else:
			RunFlow.abandon_active_run()
	if MenuStack:
		MenuStack.confirm(spec)


func _on_cloud_state_changed(_state: int, _detail: String) -> void:
	_refresh_cloud_status()


func _refresh_cloud_status() -> void:
	if _cloud_status_label == null:
		return
	match ApiConfig.cloud_state:
		ApiConfig.CloudState.DISABLED, ApiConfig.CloudState.SIGNED_OUT, ApiConfig.CloudState.SYNCED:
			_cloud_status_label.visible = false
		ApiConfig.CloudState.SYNCING:
			_cloud_status_label.visible = true
			_cloud_status_label.text = tr("PAUSE_CLOUD_SYNCING")
		ApiConfig.CloudState.ERROR:
			_cloud_status_label.visible = true
			_cloud_status_label.text = tr("PAUSE_CLOUD_ERROR")
		ApiConfig.CloudState.VERSION_MISMATCH:
			_cloud_status_label.visible = true
			_cloud_status_label.text = tr("PAUSE_CLOUD_UPDATE")
		_:
			_cloud_status_label.visible = false
