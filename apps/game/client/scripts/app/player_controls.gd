extends CanvasLayer

## Global player UI and loadout sync — inventory, settings, talents, loadout in every mode.

const RM := preload("res://scripts/app/run_mode_config.gd")

var _inventory_ui: Control
var _settings_ui: Control
var _talents_ui: Control
var _loadout_ui: Control
var _pause_menu: Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	AccessibilitySettings.load_from_save()
	DisplaySettings.apply()
	_build_global_uis()
	get_tree().scene_changed.connect(_on_scene_changed)
	call_deferred("_after_scene_changed")


func _build_global_uis() -> void:
	_inventory_ui = _make_scripted_ui("InventoryUI", "res://scripts/ui/inventory_ui.gd")
	_settings_ui = _make_scripted_ui("SettingsUI", "res://scripts/ui/settings_ui.gd")
	_talents_ui = _make_scripted_ui("TalentsUI", "res://scripts/ui/talents_ui.gd")
	_pause_menu = _make_scripted_ui("PauseMenu", "res://scripts/ui/pause_menu.gd")
	var loadout_scene := load("res://scenes/ui/loadout_ui.tscn") as PackedScene
	if loadout_scene:
		_loadout_ui = loadout_scene.instantiate() as Control
		_loadout_ui.name = "LoadoutUI"
		_loadout_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_loadout_ui)


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
	for ui_name in ["InventoryUI", "SettingsUI", "TalentsUI", "LoadoutUI", "PauseMenu"]:
		var node := scene.get_node_or_null(ui_name)
		if node:
			node.queue_free()


func sync_player_loadout() -> void:
	if RM.is_waves(RunFlow.get_run_mode()):
		return
	var player := get_tree().get_first_node_in_group("player")
	if player:
		InventoryService.apply_equipment_to_player_node(player)
		var locomotion := player.get_node_or_null("Locomotion")
		if locomotion and locomotion.has_method("refresh_appearance_visual"):
			locomotion.call("refresh_appearance_visual")


func uses_main_inventory() -> bool:
	return not RM.is_waves(RunFlow.get_run_mode())


func get_inventory_ui() -> Control:
	return _inventory_ui


func get_settings_ui() -> Control:
	return _settings_ui


func get_talents_ui() -> Control:
	return _talents_ui


func get_loadout_ui() -> Control:
	return _loadout_ui


func open_settings() -> void:
	if _settings_ui and _settings_ui.has_method("open_settings"):
		_settings_ui.call("open_settings")


func open_loadout() -> void:
	if _loadout_ui and _loadout_ui.has_method("open"):
		_loadout_ui.call("open")


func is_inventory_open() -> bool:
	return _inventory_ui != null and _inventory_ui.has_method("is_open") and _inventory_ui.call("is_open")


func is_settings_open() -> bool:
	return _settings_ui != null and _settings_ui.has_method("is_open") and _settings_ui.call("is_open")


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
		or is_talents_open()
		or is_loadout_open()
		or is_pause_open()
	)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if is_inventory_open() or is_talents_open() or is_loadout_open():
		return
	if is_settings_open() and _settings_ui.has_method("close_settings"):
		_settings_ui.call("close_settings")
		get_viewport().set_input_as_handled()
		return
	if _pause_menu and _pause_menu.has_method("toggle"):
		_pause_menu.call("toggle")
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_player_meta_ui_open():
		return
	if not uses_main_inventory():
		return
	if Input.is_action_just_pressed("quick_slot_1"):
		InventoryService.activate_quick_slot(0)
	elif Input.is_action_just_pressed("quick_slot_2"):
		InventoryService.activate_quick_slot(1)
	elif Input.is_action_just_pressed("quick_slot_3"):
		InventoryService.activate_quick_slot(2)
