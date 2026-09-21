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
var _input_lock_handle := 0
var _closing := false
var _starting := false
var _ended_while_starting := false

## UX-04: a typewriter reveal that a press completes -- reduced_motion (and a text length under
## the minimum worth animating) skips straight to the full line, matching how every other motion
## setting in this project degrades.
const TYPEWRITER_CHARS_PER_SEC := 42.0
const TYPEWRITER_MIN_CHARS := 24
var _reveal_tween: Tween
var _is_revealing := false


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
	_runner.action_failed.connect(_on_action_failed)
	var panel := get_node_or_null("Panel") as Control
	if panel:
		panel.gui_input.connect(_on_panel_gui_input)


func is_open() -> bool:
	return visible


func start_dialogue(dialogue_id: String) -> bool:
	_starting = true
	_ended_while_starting = false
	var result := _runner.start(dialogue_id)
	_starting = false
	if result == DialogueRunner.StartResult.FAILED:
		return false
	if result == DialogueRunner.StartResult.COMPLETED:
		_cleanup_dialogue(true)
		return true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _input_lock_handle == 0:
		_input_lock_handle = PlayerInput.block_groups(BLOCKED_GROUPS)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true


func close() -> void:
	if _closing:
		return
	_closing = true
	if _runner.is_active():
		_runner.end_dialogue()
	_cleanup_dialogue(true)
	_closing = false


func _cleanup_dialogue(notify_closed: bool) -> void:
	if _reveal_tween and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_reveal_tween = null
	_is_revealing = false
	var was_open := visible or _input_lock_handle != 0
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	PlayerInput.release_group_block(_input_lock_handle)
	_input_lock_handle = 0
	PlayerControls.capture_mouse_if_allowed()
	if notify_closed and was_open:
		closed.emit()


func _exit_tree() -> void:
	PlayerInput.release_group_block(_input_lock_handle)
	_input_lock_handle = 0


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
			_complete_reveal_or(_runner.advance)
		return
	if _is_revealing:
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
			get_viewport().set_input_as_handled()
			_skip_reveal()
		return
	if event.is_action_pressed("ui_up"):
		_move_selection(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_move_selection(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_activate_choice(_selected_index)


func _on_panel_gui_input(event: InputEvent) -> void:
	if not visible or not _choice_buttons.is_empty():
		return
	if not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	accept_event()
	_complete_reveal_or(_runner.advance)


func _on_line_changed(speaker: String, text: String, choices: Array) -> void:
	_speaker_label.text = speaker
	_text_label.text = text
	_apply_subtitle_scale()
	_start_reveal(text)
	_rebuild_choices(choices)
	if choices.is_empty():
		_hint_label.text = tr("DIALOGUE_HINT_CONTINUE")
	else:
		_hint_label.text = tr("DIALOGUE_HINT_CHOOSE")


func _start_reveal(text: String) -> void:
	if _reveal_tween and _reveal_tween.is_valid():
		_reveal_tween.kill()
	var char_count := text.length()
	if AccessibilitySettings.reduced_motion or char_count < TYPEWRITER_MIN_CHARS:
		_text_label.visible_characters = -1
		_is_revealing = false
		return
	_text_label.visible_characters = 0
	_is_revealing = true
	var duration := float(char_count) / TYPEWRITER_CHARS_PER_SEC
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(_text_label, "visible_characters", char_count, duration)
	_reveal_tween.tween_callback(func() -> void: _is_revealing = false)


## The press that would otherwise advance/select completes the reveal instead, the same way a
## skippable cutscene works elsewhere in this project -- the press is never lost, it just does the
## more useful thing first.
func _complete_reveal_or(action: Callable) -> void:
	if _is_revealing:
		_skip_reveal()
		return
	action.call()


func _skip_reveal() -> void:
	if _reveal_tween and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_text_label.visible_characters = -1
	_is_revealing = false


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
		btn.focus_mode = Control.FOCUS_ALL
		var idx := i
		var choice_id := str(choice.get("_choiceId", ""))
		btn.set_meta("choice_id", choice_id)
		btn.pressed.connect(func() -> void: _activate_choice(idx))
		btn.mouse_entered.connect(
			func() -> void:
				_selected_index = idx
				_update_selection_visual()
		)
		_choices_box.add_child(btn)
		_choice_buttons.append(btn)
	_update_selection_visual()
	if not _choice_buttons.is_empty():
		_choice_buttons[0].grab_focus()


func _activate_choice(index: int) -> void:
	if _is_revealing:
		_skip_reveal()
		return
	if index < 0 or index >= _choice_buttons.size():
		return
	_runner.select_choice_id(str(_choice_buttons[index].get_meta("choice_id", "")))


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
	if _starting:
		_ended_while_starting = true
		return
	if _closing:
		return
	_closing = true
	_cleanup_dialogue(true)
	_closing = false


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


func _on_action_failed(message: String) -> void:
	_hint_label.text = message
	_hint_label.modulate = Color(1.0, 0.55, 0.45)
