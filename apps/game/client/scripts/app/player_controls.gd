extends CanvasLayer


signal quick_slot_used(index: int, item_id: String)
signal quick_slot_selection_changed(index: int)

const RM := preload("res://scripts/app/run_mode_config.gd")
const QUICK_SLOT_COUNT := 4

var _inventory_ui: Control
var _settings_ui: Control
var _achievements_ui: Control
var _bestiary_ui: Control
var _talents_ui: Control
var _loadout_ui: Control
var _pause_menu: Control
var _quick_slot_selected := 0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	AccessibilitySettings.load_from_save()
	InputBindings.snapshot_defaults()
	InputBindings.load_from_save()
	InputBindings.apply()
	_build_global_uis()
	get_tree().scene_changed.connect(_on_scene_changed)
	call_deferred("_after_scene_changed")


static func resolve_locomotion(player: Node) -> Node:
	if player == null:
		return null
	if player.has_method("set_speed_multiplier"):
		return player
	return player.get_node_or_null("Locomotion")


func allows_player_ui() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	return not scene.is_in_group("front_end")


func gameplay_input_blocked() -> bool:
	return (
		is_player_meta_ui_open()
		or scene_ui_open()
		or modal_stack_open()
		or get_tree().paused
	)


func modal_stack_open() -> bool:
	var stack := get_tree().root.get_node_or_null("/root/MenuStack")
	return stack != null and int(stack.call("depth")) > 0


func scene_ui_open() -> bool:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("has_open_ui"):
		return false
	return bool(scene.call("has_open_ui"))


func capture_mouse_if_allowed() -> void:
	if gameplay_input_blocked():
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(_delta: float) -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if not gameplay_input_blocked():
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _build_global_uis() -> void:
	_inventory_ui = _make_scripted_ui("InventoryUI", "res://scripts/ui/inventory_ui.gd")
	_settings_ui = _make_scripted_ui("SettingsUI", "res://scripts/ui/settings_ui.gd")
	_achievements_ui = _make_scripted_ui("AchievementsUI", "res://scripts/ui/achievements_ui.gd")
	_bestiary_ui = _make_scripted_ui("BestiaryUI", "res://scripts/ui/bestiary_ui.gd")
	_talents_ui = _make_scripted_ui("TalentsUI", "res://scripts/ui/talents_ui.gd")
	_pause_menu = _make_scripted_ui("PauseMenu", "res://scripts/ui/pause_menu.gd")
	var loadout_scene := load("res://scenes/ui/loadout_ui.tscn") as PackedScene
	if loadout_scene:
		_loadout_ui = loadout_scene.instantiate() as Control
		_loadout_ui.name = "LoadoutUI"
		_loadout_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_loadout_ui)


func _raise(ui: Control) -> void:
	if ui != null and is_instance_valid(ui):
		ui.move_to_front()


func _make_scripted_ui(node_name: String, script_path: String) -> Control:
	var ui := Control.new()
	ui.name = node_name
	ui.set_script(load(script_path))
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	return ui


func _on_scene_changed() -> void:
	call_deferred("_after_scene_changed")


func _after_scene_changed() -> void:
	_remove_duplicate_scene_uis()
	await get_tree().process_frame
	if _inventory_ui and _inventory_ui.has_method("_bind_inventory_context"):
		_inventory_ui.call("_bind_inventory_context")
	sync_player_loadout()


func _remove_duplicate_scene_uis() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for ui_name in ["InventoryUI", "SettingsUI", "AchievementsUI", "TalentsUI", "LoadoutUI", "PauseMenu"]:
		var node := scene.get_node_or_null(ui_name)
		if node:
			node.queue_free()


func sync_player_loadout() -> void:
	if RM.is_waves(RunFlow.get_run_mode()):
		return
	var player := get_tree().get_first_node_in_group("player")
	if player:
		InventoryService.apply_equipment_to_player_node(player)
		var locomotion := resolve_locomotion(player)
		if locomotion and locomotion.has_method("refresh_appearance_visual"):
			locomotion.call("refresh_appearance_visual")


func uses_main_inventory() -> bool:
	return not RM.is_waves(RunFlow.get_run_mode())


func get_settings_ui() -> Control:
	return _settings_ui


func open_settings() -> void:
	_raise(_settings_ui)
	if _settings_ui and _settings_ui.has_method("open_settings"):
		_settings_ui.call("open_settings")


func open_achievements() -> void:
	_raise(_achievements_ui)
	if _achievements_ui and _achievements_ui.has_method("open"):
		_achievements_ui.call("open")


func open_bestiary() -> void:
	_raise(_bestiary_ui)
	if _bestiary_ui and _bestiary_ui.has_method("open"):
		_bestiary_ui.call("open")


func open_loadout() -> void:
	_raise(_loadout_ui)
	if _loadout_ui and _loadout_ui.has_method("open"):
		_loadout_ui.call("open")


func is_inventory_open() -> bool:
	return (
		_inventory_ui != null
		and _inventory_ui.has_method("is_open")
		and _inventory_ui.call("is_open")
	)


func is_settings_open() -> bool:
	return (
		_settings_ui != null and _settings_ui.has_method("is_open") and _settings_ui.call("is_open")
	)


func is_achievements_open() -> bool:
	return (
		_achievements_ui != null
		and _achievements_ui.has_method("is_open")
		and _achievements_ui.call("is_open")
	)


func is_bestiary_open() -> bool:
	return (
		_bestiary_ui != null
		and _bestiary_ui.has_method("is_open")
		and _bestiary_ui.call("is_open")
	)


func is_talents_open() -> bool:
	return _talents_ui != null and _talents_ui.has_method("is_open") and _talents_ui.call("is_open")


func is_loadout_open() -> bool:
	return _loadout_ui != null and _loadout_ui.has_method("is_open") and _loadout_ui.call("is_open")


func is_pause_open() -> bool:
	return _pause_menu != null and _pause_menu.has_method("is_open") and _pause_menu.call("is_open")


func is_player_meta_ui_open() -> bool:
	return (
		is_inventory_open()
		or is_settings_open()
		or is_achievements_open()
		or is_bestiary_open()
		or is_talents_open()
		or is_loadout_open()
		or is_pause_open()
	)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if (
			is_inventory_open()
			or is_talents_open()
			or is_loadout_open()
			or is_achievements_open()
			or is_bestiary_open()
		):
			return
		if is_settings_open() and _settings_ui.has_method("close_settings"):
			_settings_ui.call("close_settings")
			get_viewport().set_input_as_handled()
			return
		if _pause_menu and _pause_menu.has_method("toggle"):
			_pause_menu.call("toggle")
		get_viewport().set_input_as_handled()
		return
	if is_player_meta_ui_open() or not uses_main_inventory():
		return
	if event.is_action_pressed("quick_slot_cycle"):
		_quick_slot_selected = (_quick_slot_selected + 1) % QUICK_SLOT_COUNT
		quick_slot_selection_changed.emit(_quick_slot_selected)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("quick_slot_use"):
		_activate_quick_slot(_quick_slot_selected)
		get_viewport().set_input_as_handled()
		return
	for i in QUICK_SLOT_COUNT:
		var action := StringName("quick_slot_%d" % (i + 1))
		if event.is_action_pressed(action):
			_activate_quick_slot(i)
			get_viewport().set_input_as_handled()
			return


func get_quick_slot_selected() -> int:
	return _quick_slot_selected


func _activate_quick_slot(index: int) -> void:
	var item_id := InventoryService.activate_quick_slot(index)
	if item_id != "":
		quick_slot_used.emit(index, item_id)
