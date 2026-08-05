extends Control

## Boot title screen with premise card — advances to the main menu.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var _ready_to_continue := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AccessibilitySettings.load_from_save()
	DisplaySettings.apply()
	_build_ui()
	call_deferred("_enable_continue")


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.02, 0.06, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var panel := GameUISkinScript.make_center_panel(self, 440.0, 300.0)
	panel.name = "Panel"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = "Aumbrye"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_menu_title(title)
	vbox.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Echo of the Fallen Warden"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_body_label(subtitle)
	vbox.add_child(subtitle)
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = (
		"The Umbral Tower remembers every oath sworn at its threshold. "
		+ "You are the echo of a warden who failed — bound to climb again whenever the tower resets. "
		+ "Each death returns you to Aumbrye Tower; each escape carries proof you endured."
	)
	GameUISkinScript.style_body_label(body)
	vbox.add_child(body)
	var hint := Label.new()
	hint.text = "Click or press any key to continue"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_hint_label(hint)
	vbox.add_child(hint)


func _enable_continue() -> void:
	_ready_to_continue = true


func _go_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _input(event: InputEvent) -> void:
	if not _ready_to_continue:
		return
	var advance := false
	if event is InputEventKey and event.pressed and not event.echo:
		advance = true
	elif event is InputEventMouseButton and event.pressed:
		advance = true
	elif event is InputEventJoypadButton and event.pressed:
		advance = true
	if advance:
		get_viewport().set_input_as_handled()
		_go_to_main_menu()
