extends Control


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

var _body_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func show_epilogue(text: String) -> Signal:
	_body_label.text = text
	visible = true
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.5)
	return tween.finished


func _build_ui() -> void:
	GameUISkinScript.make_backdrop(self)
	var panel := GameUISkinScript.make_center_panel(self, 520.0, 300.0)
	panel.name = "Panel"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	var title := Label.new()
	title.text = tr("EPILOGUE_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_menu_title(title)
	vbox.add_child(title)
	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_body_label)
	var hint := Label.new()
	hint.text = tr("EPILOGUE_HINT")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_hint_label(hint)
	vbox.add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		visible = false
