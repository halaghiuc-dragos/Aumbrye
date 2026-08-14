extends Node

## Boots UI scenes one at a time and writes a PNG of each, for reviewing visual consistency
## without playing through the game by hand.
##
## Must run windowed — a headless run has no rendering device and produces blank images.
##
## Usage:
##   godot --path apps/game/client --resolution 1920x1080 \
##     res://scenes/debug/capture_ui_screens.tscn

const OUTPUT_DIR := "user://ui_captures"

## Scenes that stand up on their own, in the order a player meets them.
const SCENES: Array[String] = [
	"res://scenes/ui/title_screen.tscn",
	"res://scenes/ui/main_menu.tscn",
	"res://scenes/ui/character_create.tscn",
	"res://scenes/ui/castle_entry_menu.tscn",
	"res://scenes/ui/umbral_endless_menu.tscn",
	"res://scenes/ui/umbral_waves_menu.tscn",
	"res://scenes/ui/results_screen.tscn",
	"res://scenes/ui/loading_screen.tscn",
	# Hub UIs. These have their own scenes and reach their widgets through @onready unique names —
	# attaching the script to a bare Control instead leaves every one of those lookups null.
	"res://scenes/ui/quest_board_ui.tscn",
	"res://scenes/ui/storage_ui.tscn",
	"res://scenes/ui/merchant_ui.tscn",
	"res://scenes/ui/blacksmith_ui.tscn",
	"res://scenes/ui/loadout_ui.tscn",
]

## Screens with no .tscn of their own — a bare Control built entirely by its script. Attaching the
## script to a fresh Control is how the game itself creates them (see PlayerControls).
const SCRIPT_SCREENS: Dictionary = {
	"settings_ui": "res://scripts/ui/settings_ui.gd",
	"pause_menu": "res://scripts/ui/pause_menu.gd",
	"inventory_ui": "res://scripts/ui/inventory_ui.gd",
	"talents_ui": "res://scripts/ui/talents_ui.gd",
	"bestiary_ui": "res://scripts/ui/bestiary_ui.gd",
	"achievements_ui": "res://scripts/ui/achievements_ui.gd",
}

## Frames to let a scene settle before capturing, so tweens and deferred layout have run.
const SETTLE_FRAMES := 12


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	await _capture_all()
	await _capture_script_screens()
	await _capture_settings_pages()
	get_tree().quit(0)


## Most of these screens are modals that start hidden and are shown by an explicit call, so an
## as-instantiated capture would just record the clear colour.
func _open_if_modal(instance: Node) -> void:
	# Screens whose opener is missing from this list are captured in whatever state _ready() left
	# them, which is not the state a player ever sees — the talents screen came out as an empty box
	# because `open_talents` was not listed and its list is only filled by the open call.
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


## Settings is six pages behind one script, and only the first is visible as instantiated.
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
		var name := "settings_%s" % str(schema.PAGES[i])
		if image.save_png("%s/%s.png" % [OUTPUT_DIR, name]) == OK:
			print("captured %s" % name)
	host.queue_free()
	await get_tree().process_frame


func _capture_script_screens() -> void:
	for name in SCRIPT_SCREENS:
		var script_path: String = SCRIPT_SCREENS[name]
		if not ResourceLoader.exists(script_path):
			push_warning("capture_ui_screens: missing %s" % script_path)
			continue
		var script := load(script_path) as Script
		if script == null:
			push_warning("capture_ui_screens: could not load %s" % script_path)
			continue
		var instance := Control.new()
		instance.set_script(script)
		await _capture_instance(instance, str(name))


## Screens are parented to a full-rect Control and anchored full-rect themselves, matching how
## PlayerControls hosts them in game. Hanging them off a bare Node instead leaves them zero-sized,
## so anything that centres itself lands in the top-left corner.
func _capture_instance(instance: Node, name: String) -> void:
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)
	# Offsets as well as anchors, and before the screen is parented: set_anchors_preset() alone
	# rewrites the offsets to preserve the control's current rect, so a freshly created host stayed
	# zero-sized and every screen that centres itself piled up in the top-left corner. The screen
	# also has to be full-rect before it enters the tree, since these build their panels in _ready.
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if instance is Control:
		(instance as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(instance)
	await get_tree().process_frame
	_open_if_modal(instance)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame

	var image := get_viewport().get_texture().get_image()
	var out_path := "%s/%s.png" % [OUTPUT_DIR, name]
	var error := image.save_png(out_path)
	if error == OK:
		print("captured %s -> %s" % [name, ProjectSettings.globalize_path(out_path)])
	else:
		push_warning("capture_ui_screens: could not save %s (error %d)" % [name, error])

	host.queue_free()
	await get_tree().process_frame
