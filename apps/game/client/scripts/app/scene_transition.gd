extends CanvasLayer
class_name SceneTransition


const GROUP := &"scene_transition"
const OVERLAY_LAYER := 200
const FADE_SEC := 0.18
const UNCLAIMED_GRACE_FRAMES := 4
const BUILD_WATCHDOG_SEC := 45.0
const LOAD_SHARE := 0.5

enum Phase { LOADING, BUILDING, DONE }

var _path := ""
var _pending_status := ""
var _phase := Phase.LOADING
var _claimed := false
var _grace_frames := UNCLAIMED_GRACE_FRAMES
var _elapsed := 0.0
var _progress_args: Array = []
var _root: Control
var _bar: ProgressBar
var _status: Label


static func goto(tree: SceneTree, path: String, status_text: String = "") -> void:
	if tree == null or path.is_empty():
		return
	if not _can_thread_load(path):
		tree.call_deferred("change_scene_to_file", path)
		return
	var existing := active(tree)
	if existing != null:
		existing.queue_free()
	var transition := SceneTransition.new()
	transition._path = path
	tree.root.add_child.call_deferred(transition)
	if status_text != "":
		transition.set_status(status_text)


static func active(tree: SceneTree) -> SceneTransition:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as SceneTransition


static func claim(tree: SceneTree, status_text: String = "") -> SceneTransition:
	var transition := active(tree)
	if transition == null:
		return null
	transition._claimed = true
	if status_text != "":
		transition.set_status(status_text)
	return transition


static func report_progress(tree: SceneTree, ratio: float) -> void:
	var transition := active(tree)
	if transition == null:
		return
	transition._claimed = true
	transition.set_progress(LOAD_SHARE + clampf(ratio, 0.0, 1.0) * (1.0 - LOAD_SHARE))


static func finish(tree: SceneTree) -> void:
	var transition := active(tree)
	if transition != null:
		transition.dismiss()


static func _can_thread_load(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	return DisplayServer.get_name() != "headless"


func _ready() -> void:
	add_to_group(GROUP)
	layer = OVERLAY_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()
	if _pending_status != "":
		set_status(_pending_status)
		_pending_status = ""
	var err := ResourceLoader.load_threaded_request(_path, "PackedScene")
	if err != OK:
		get_tree().change_scene_to_file(_path)
		_phase = Phase.BUILDING
		return
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	if _phase == Phase.LOADING:
		_poll_load()
		return
	if _phase == Phase.DONE:
		set_process(false)
		return
	if not _claimed:
		_grace_frames -= 1
		if _grace_frames <= 0:
			dismiss()
	elif _elapsed >= BUILD_WATCHDOG_SEC:
		dismiss()


func _poll_load() -> void:
	_progress_args.clear()
	var status := ResourceLoader.load_threaded_get_status(_path, _progress_args)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_swap_to_loaded()
		return
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if not _progress_args.is_empty():
			set_progress(float(_progress_args[0]) * LOAD_SHARE)
		return
	_phase = Phase.BUILDING
	get_tree().change_scene_to_file(_path)


func _swap_to_loaded() -> void:
	var packed := ResourceLoader.load_threaded_get(_path) as PackedScene
	_phase = Phase.BUILDING
	set_progress(LOAD_SHARE)
	set_status("Building the floor...")
	if packed == null:
		get_tree().change_scene_to_file(_path)
		return
	get_tree().change_scene_to_packed(packed)


func set_status(text: String) -> void:
	if _status:
		_status.text = text
	else:
		_pending_status = text


func set_progress(ratio: float) -> void:
	if _bar:
		_bar.value = clampf(ratio, 0.0, 1.0) * 100.0


func dismiss() -> void:
	if _phase == Phase.DONE:
		return
	_phase = Phase.DONE
	set_process(false)
	remove_from_group(GROUP)
	set_progress(1.0)
	if _root == null:
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE_SEC)
	tween.tween_callback(queue_free)


func _build_overlay() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.02, 0.06, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(420.0, 0.0)
	box.add_theme_constant_override("separation", 10)
	_root.add_child(box)
	_status = Label.new()
	_status.text = "Loading..."
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(420.0, 14.0)
	box.add_child(_bar)
