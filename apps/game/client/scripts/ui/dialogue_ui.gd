extends Control


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

signal closed

const BLOCKED_GROUPS := [PlayerInput.Group.COMBAT, PlayerInput.Group.INTERACT]

@onready var _speaker_label: Label = $Panel/Margin/VBox/SpeakerLabel
@onready var _text_label: Label = $Panel/Margin/VBox/TextLabel
@onready var _choices_box: VBoxContainer = $Panel/Margin/VBox/ChoicesBox
@onready var _hint_label: Label = $Panel/Margin/VBox/HintLabel

var _runner: DialogueRunner
var _choice_buttons: Array[Button] = []
var _selected_index := 0


func _ready() -> void:
	add_to_group("dialogue_ui")
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkinScript.apply_modal_menu(self, "Panel")
	_runner = DialogueRunner.new()
	_runner.line_changed.connect(_on_line_changed)
	_runner.dialogue_ended.connect(_on_dialogue_ended)
	_runner.action_triggered.connect(_on_action_triggered)
	var panel := get_node_or_null("Panel") as Control
	if panel:
		panel.gui_input.connect(_on_panel_gui_input)


func is_open() -> bool:
	return visible


func start_dialogue(dialogue_id: String) -> bool:
	if not _runner.start(dialogue_id):
		return false
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	PlayerInput.block_groups(BLOCKED_GROUPS)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true


func close() -> void:
	if _runner.is_active():
		_runner.end_dialogue()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	PlayerInput.unblock_groups(BLOCKED_GROUPS)
	PlayerControls.capture_mouse_if_allowed()
	closed.emit()


func _exit_tree() -> void:
	PlayerInput.unblock_groups(BLOCKED_GROUPS)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		return
	if _choice_buttons.is_empty():
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
			get_viewport().set_input_as_handled()
			_runner.advance()
		return
	if event.is_action_pressed("ui_up"):
		_move_selection(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_move_selection(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_runner.select_choice(_selected_index)


func _on_panel_gui_input(event: InputEvent) -> void:
	if not visible or not _choice_buttons.is_empty():
		return
	if not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	accept_event()
	_runner.advance()


func _on_line_changed(speaker: String, text: String, choices: Array) -> void:
	_speaker_label.text = speaker
	_text_label.text = text
	_apply_subtitle_scale()
	_rebuild_choices(choices)
	if choices.is_empty():
		_hint_label.text = tr("DIALOGUE_HINT_CONTINUE")
	else:
		_hint_label.text = tr("DIALOGUE_HINT_CHOOSE")


func refresh_accessibility() -> void:
	if not visible:
		return
	_apply_subtitle_scale()


func _apply_subtitle_scale() -> void:
	var subtitle_scale := AccessibilitySettings.subtitle_scale
	_speaker_label.add_theme_font_size_override(
		"font_size", int(GameUISkinScript.FONT_SIZE_BODY * subtitle_scale)
	)
	_text_label.add_theme_font_size_override(
		"font_size", int(GameUISkinScript.FONT_SIZE_HEADER * subtitle_scale)
	)


func _rebuild_choices(choices: Array) -> void:
	for btn in _choice_buttons:
		btn.queue_free()
	_choice_buttons.clear()
	_selected_index = 0
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var btn := GameUISkinScript.make_button(str(choice.get("text", "???")))
		btn.focus_mode = Control.FOCUS_NONE
		var idx := i
		btn.pressed.connect(func() -> void: _runner.select_choice(idx))
		btn.mouse_entered.connect(
			func() -> void:
				_selected_index = idx
				_update_selection_visual()
		)
		_choices_box.add_child(btn)
		_choice_buttons.append(btn)
	_update_selection_visual()


func _move_selection(delta: int) -> void:
	if _choice_buttons.is_empty():
		return
	_selected_index = wrapi(_selected_index + delta, 0, _choice_buttons.size())
	_update_selection_visual()


func _update_selection_visual() -> void:
	for i in _choice_buttons.size():
		var btn: Button = _choice_buttons[i]
		if i == _selected_index:
			btn.modulate = Color(1.2, 1.2, 0.9)
		else:
			btn.modulate = Color.WHITE


func _on_dialogue_ended() -> void:
	close()


func _on_action_triggered(action: Dictionary) -> void:
	var action_type: String = str(action.get("type", ""))
	match action_type:
		"open_blacksmith":
			get_parent().call("open_blacksmith")
		"open_merchant":
			get_parent().call("open_merchant")
		"open_quest_board":
			get_parent().call("open_quest_board")
		"open_storage":
			get_parent().call("open_storage")
