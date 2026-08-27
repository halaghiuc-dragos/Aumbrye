extends Node


const OUTPUT_DIR := "user://ui_captures"

const SCENES: Array[String] = [
	"res://scenes/ui/main_menu.tscn",
	"res://scenes/ui/character_create.tscn",
	"res://scenes/ui/castle_entry_menu.tscn",
	"res://scenes/ui/umbral_endless_menu.tscn",
	"res://scenes/ui/umbral_waves_menu.tscn",
	"res://scenes/ui/results_screen.tscn",
	"res://scenes/ui/loading_screen.tscn",
	"res://scenes/ui/quest_board_ui.tscn",
	"res://scenes/ui/storage_ui.tscn",
	"res://scenes/ui/merchant_ui.tscn",
	"res://scenes/ui/blacksmith_ui.tscn",
	"res://scenes/ui/loadout_ui.tscn",
]

const SCRIPT_SCREENS: Dictionary = {
	"settings_ui": "res://scripts/ui/settings_ui.gd",
	"pause_menu": "res://scripts/ui/pause_menu.gd",
	"inventory_ui": "res://scripts/ui/inventory_ui.gd",
	"talents_ui": "res://scripts/ui/talents_ui.gd",
	"bestiary_ui": "res://scripts/ui/bestiary_ui.gd",
	"achievements_ui": "res://scripts/ui/achievements_ui.gd",
}

const SETTLE_FRAMES := 12


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	await _capture_all()
	await _capture_menu_after_intro()
	await _capture_script_screens()
	await _capture_settings_pages()
	get_tree().quit(0)


func _open_if_modal(instance: Node) -> void:
	for method in [
		"open_menu",
		"open_creation",
		"open_settings",
		"open_talents",
		"show_inventory",
		"open_inventory",
		"open_panel",
		"open",
	]:
		if instance.has_method(method):
			instance.call(method)
			return
	if instance is CanvasItem:
		(instance as CanvasItem).visible = true


func _capture_all() -> void:
	for scene_path in SCENES:
		if not ResourceLoader.exists(scene_path):
			push_warning("capture_ui_screens: missing %s" % scene_path)
			continue
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_warning("capture_ui_screens: could not load %s" % scene_path)
			continue

		await _capture_instance(packed.instantiate(), scene_path.get_file().get_basename())


func _capture_menu_after_intro() -> void:
	var packed := load("res://scenes/ui/main_menu.tscn") as PackedScene
	if packed == null:
		return
	var instance := packed.instantiate() as Control
	add_child(instance)
	for _f in SETTLE_FRAMES:
		await get_tree().process_frame
	if instance.has_method("_finish_intro"):
		instance.call("_finish_intro")
	for _f in SETTLE_FRAMES:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if image.save_png("%s/main_menu_resting.png" % OUTPUT_DIR) == OK:
		print("captured main_menu_resting")
	instance.queue_free()
	await get_tree().process_frame


func _capture_settings_pages() -> void:
	var script := load("res://scripts/ui/settings_ui.gd") as Script
	if script == null:
		return
	var schema := load("res://scripts/ui/settings_schema.gd")
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var instance := Control.new()
	instance.set_script(script)
	host.add_child(instance)
	instance.set_anchors_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	instance.call("open_settings")
	for i in schema.PAGES.size():
		instance.call("_select_page", i)
		for _f in SETTLE_FRAMES:
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		var screen_name := "settings_%s" % str(schema.PAGES[i])
		if image.save_png("%s/%s.png" % [OUTPUT_DIR, screen_name]) == OK:
			print("captured %s" % screen_name)
	host.queue_free()
	await get_tree().process_frame


func _capture_script_screens() -> void:
	for screen_name in SCRIPT_SCREENS:
		var script_path: String = SCRIPT_SCREENS[screen_name]
		if not ResourceLoader.exists(script_path):
			push_warning("capture_ui_screens: missing %s" % script_path)
			continue
		var script := load(script_path) as Script
		if script == null:
			push_warning("capture_ui_screens: could not load %s" % script_path)
			continue
		var instance := Control.new()
		instance.set_script(script)
		await _capture_instance(instance, str(screen_name))


func _capture_instance(instance: Node, screen_name: String) -> void:
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if instance is Control:
		(instance as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(instance)
	await get_tree().process_frame
	_open_if_modal(instance)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame

	var image := get_viewport().get_texture().get_image()
	var out_path := "%s/%s.png" % [OUTPUT_DIR, screen_name]
	var error := image.save_png(out_path)
	if error == OK:
		print("captured %s -> %s" % [screen_name, ProjectSettings.globalize_path(out_path)])
	else:
		push_warning("capture_ui_screens: could not save %s (error %d)" % [screen_name, error])

	host.queue_free()
	await get_tree().process_frame
