extends Control

## Boot title screen — lore, tower motif, advances to main menu.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var _ready_to_continue := false
var _hint_label: Label


func _ready() -> void:
	add_to_group("front_end")
	process_mode = Node.PROCESS_MODE_ALWAYS
	AccessibilitySettings.load_from_save()
	PixelDioramaBootstrap.prime()
	AudioDirector.play_menu_music()
	_build_ui()
	call_deferred("_enable_continue")


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.015, 0.02, 0.08, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var vignette := ColorRect.new()
	vignette.color = Color(0.0, 0.0, 0.0, 0.35)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vignette)

	_build_tower_silhouette(backdrop)

	var panel := GameUISkinScript.make_center_panel(self, 260.0, 180.0)
	panel.name = "Panel"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var ornament := Label.new()
	ornament.text = "◆ ◆ ◆"
	ornament.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_hint_label(ornament)
	vbox.add_child(ornament)

	var title := Label.new()
	title.text = "AUMBRYE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_menu_title(title)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Echo of the Fallen Warden"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_body_label(subtitle)
	vbox.add_child(subtitle)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.color = Color(0.55, 0.48, 0.32, 0.65)
	vbox.add_child(rule)

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = (
		"The Umbral Tower remembers every oath sworn at its threshold. "
		+ "You are the echo of a warden who failed — bound to climb whenever the tower resets. "
		+ "Each death returns you to Aumbrye Tower; each escape proves you endured."
	)
	GameUISkinScript.style_body_label(body)
	vbox.add_child(body)

	_hint_label = Label.new()
	_hint_label.text = "Press any key to enter the tower"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_hint_label(_hint_label)
	vbox.add_child(_hint_label)

	var version := Label.new()
	version.text = "Early Access — Pixel Diorama build"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_hint_label(version)
	vbox.add_child(version)


func _build_tower_silhouette(parent: Control) -> void:
	var tower := Control.new()
	tower.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tower.offset_left = -90.0
	tower.offset_right = 90.0
	tower.offset_top = 24.0
	tower.offset_bottom = 244.0
	parent.add_child(tower)
	for i in 6:
		var block := ColorRect.new()
		var width := 120.0 - i * 12.0
		block.custom_minimum_size = Vector2(width, 18.0)
		block.color = Color(0.12, 0.14, 0.22, 0.55)
		block.position = Vector2(90.0 - width * 0.5, float(i) * 20.0)
		tower.add_child(block)


func _enable_continue() -> void:
	_ready_to_continue = true


func _process(_delta: float) -> void:
	if _hint_label == null or not _ready_to_continue:
		return
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.004)
	_hint_label.modulate = Color(1.0, 1.0, 1.0, pulse)


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
