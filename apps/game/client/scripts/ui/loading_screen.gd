extends Control

## Brief loading gate before hub spawn — runs LocalSave boot then changes scene.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const HUB_SCENE := "res://scenes/hub/hub.tscn"
const MIN_DISPLAY_SEC := 1.1

var _status_label: Label
var _started := false


func _ready() -> void:
	add_to_group("front_end")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	call_deferred("_run_boot")


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.02, 0.06, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var panel := GameUISkinScript.make_center_panel(self, 320.0, 120.0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = tr("LOADING_ENTERING")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_menu_title(title)
	vbox.add_child(title)
	_status_label = Label.new()
	_status_label.text = tr("LOADING_PREPARING")
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_body_label(_status_label)
	vbox.add_child(_status_label)


func _run_boot() -> void:
	if _started:
		return
	_started = true
	var timer := get_tree().create_timer(MIN_DISPLAY_SEC)
	_status_label.text = tr("LOADING_SYNCING")
	await timer.timeout
	var ok := LocalSave.execute_boot()
	if not ok:
		# The specific reason when there is one — a full roster is not a load failure and the
		# player can act on it, which "Could not load save" gives them no way to know.
		var reason := LocalSave.last_boot_failure
		_status_label.text = tr(reason if reason != "" else "LOADING_SAVE_FAILED")
		await get_tree().create_timer(1.2).timeout
		SceneTransition.goto(get_tree(), "res://scenes/ui/main_menu.tscn")
		return
	_status_label.text = tr("LOADING_OPENING_HUB")
	await get_tree().process_frame
	SceneTransition.goto(get_tree(), HUB_SCENE, tr("LOADING_OPENING_HUB"))
