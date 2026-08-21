extends Node

## Drives main menu -> character creation -> Begin, and reports which scene the game lands on.
##
## `LoadingScreen` returns the player to the main menu whenever `LocalSave.execute_boot()` is
## false, and it does so silently in a release run, so from the outside a failed boot and a
## deliberate cancel look identical. This walks the real UI and prints every branch it takes.
##
## Usage:
##   godot --path apps/game/client --resolution 1280x720 res://scenes/debug/probe_creation_flow.tscn

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"


func _ready() -> void:
	print("roster: %d of %d used, can_create=%s" % [
		LocalSave.used_character_slots(), LocalSave.MAX_CHARACTER_SLOTS,
		str(LocalSave.can_create_character()),
	])
	await get_tree().process_frame
	var menu := (load(MAIN_MENU) as PackedScene).instantiate()
	add_child(menu)
	for i in 8:
		await get_tree().process_frame

	var create := menu.get_node_or_null("CharacterCreate")
	if create == null:
		for child in menu.get_children():
			if child.has_method("open_creation"):
				create = child
				break
	if create == null:
		print("FAIL: no character-create child on the main menu")
		get_tree().quit(1)
		return

	create.completed.connect(
		func(class_id: String, character_name: String, _appearance: Dictionary) -> void:
			print("completed emitted: class=%s name=%s" % [class_id, character_name])
	)
	create.cancelled.connect(func() -> void: print("cancelled emitted"))

	create.call("open_creation")
	for i in 8:
		await get_tree().process_frame

	var name_input := _find_line_edit(create)
	if name_input == null:
		print("FAIL: no name field")
		get_tree().quit(1)
		return
	name_input.text = "ProbeFlow%d" % (Time.get_ticks_msec() % 10000)
	create.call("_on_name_changed", name_input.text)
	create.call("_select_class_index", 0)
	for i in 4:
		await get_tree().process_frame

	var begin_button := _find_button(create, [tr("CREATE_BEGIN")])
	print("begin button: %s disabled=%s" % [
		"found" if begin_button else "MISSING",
		str(begin_button.disabled) if begin_button else "?",
	])
	print("name field  : '%s'" % name_input.text)
	print("classes     : %d, selected index %s" % [
		int(create.get("_classes").size()), str(create.get("_selected_class_index")),
	])

	print("pressing Begin")
	create.call("_on_confirm_pressed")
	for i in 6:
		await get_tree().process_frame

	var overlay := create.get_node_or_null("ConfirmOverlay")
	print("confirmation overlay: %s" % ("shown" if overlay else "NOT SHOWN — _on_confirm_pressed returned early"))
	if overlay == null:
		get_tree().quit(1)
		return
	var confirm := _find_button(overlay, [tr("CREATE_BEGIN")])
	if confirm == null:
		print("FAIL: confirmation dialog has no Begin button")
		get_tree().quit(1)
		return
	confirm.emit_signal("pressed")
	for i in 6:
		await get_tree().process_frame

	print("boot mode queued; letting the real LoadingScreen run")
	# The watcher lives on the tree root, not under this scene: `SceneTransition.goto` frees the
	# current scene, and a coroutine awaiting inside it never resumes.
	var watcher := Node.new()
	watcher.name = "SceneWatcher"
	watcher.process_mode = Node.PROCESS_MODE_ALWAYS
	watcher.set_script(load("res://scripts/tools/probe_scene_watcher.gd"))
	get_tree().root.add_child(watcher)
	SceneTransition.goto(get_tree(), "res://scenes/ui/loading_screen.tscn")



func _find_line_edit(root: Node) -> LineEdit:
	if root is LineEdit:
		return root as LineEdit
	for child in root.get_children():
		var found := _find_line_edit(child)
		if found:
			return found
	return null


func _find_button(root: Node, labels: Array) -> Button:
	if root is Button:
		for label in labels:
			if str((root as Button).text).to_upper().contains(str(label).to_upper()):
				return root as Button
	for child in root.get_children():
		var found := _find_button(child, labels)
		if found:
			return found
	return null
