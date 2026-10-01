extends Control


signal closed

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")

var _open := false
var _sections: VBoxContainer
var _first_focus: Control


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_open() -> bool:
	return _open


func open() -> void:
	_build_ui_if_needed()
	_refresh()
	_open = true
	MenuStack.show_modal(self)
	if _first_focus and is_instance_valid(_first_focus):
		_first_focus.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	MenuStack.hide_modal(self)
	closed.emit()


func _build_ui_if_needed() -> void:
	if _sections != null and is_instance_valid(_sections):
		return
	for child in get_children():
		child.queue_free()
	GameUISkinScript.ensure_full_rect(self)
	var shell: Dictionary = MenuShellScript.build_modal(
		self, "The Board", GameUISkinScript.PANEL_HALF_W, GameUISkinScript.PANEL_HALF_H
	)
	var content_vbox: VBoxContainer = shell["content_vbox"]
	var scroll := ScrollContainer.new()
	scroll.name = "BoardScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_vbox.add_child(scroll)
	_sections = VBoxContainer.new()
	_sections.name = "BoardSections"
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_theme_constant_override("separation", GameUISkinScript.SECTION_SEPARATION)
	scroll.add_child(_sections)
	var close_btn := MenuShellScript.make_menu_button(tr("UI_CLOSE"), close)
	content_vbox.add_child(close_btn)
	MenuShellScript.add_hint(content_vbox, tr("UI_HINT_CLOSE"))


func _refresh() -> void:
	if _sections == null:
		return
	for child in _sections.get_children():
		_sections.remove_child(child)
		child.queue_free()
	_first_focus = null
	_build_challenge_section()
	_build_modes_section()
	_build_standing_section()


func _can_start_run() -> bool:
	return not RunFlow.is_run_active()


func _add_body(parent: VBoxContainer, text: String) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	GameUISkinScript.style_body_label(label)
	parent.add_child(label)
	return label


func _add_hint(parent: VBoxContainer, text: String) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	GameUISkinScript.style_hint_label(label)
	parent.add_child(label)
	return label


func _build_challenge_section() -> void:
	var challenge := ChallengeService.get_active_challenge()
	var frame := GameUISkinScript.make_pixel_frame("This Week")
	frame.name = "ChallengeFrame"
	_sections.add_child(frame)
	var body: VBoxContainer = GameUISkinScript.pixel_frame_content(frame)
	if challenge.is_empty():
		_add_hint(body, tr("BOARD_NOTHING_POSTED"))
		return
	_add_body(body, str(challenge.get("name", "")))
	_add_hint(body, ContentText.description(challenge))
	var rules := ChallengeService.describe_rules(challenge)
	if rules != "":
		_add_body(body, rules)
	_add_hint(
		body,
		(
			"Seed %d — %s"
			% [
				int(challenge.get("seed", 0)),
				ChallengeService.format_remaining(int(challenge.get("endsInSeconds", 0))),
			]
		)
	)
	var best := ChallengeService.get_local_best(int(challenge.get("weekIndex", 0)))
	if best.is_empty():
		_add_hint(body, tr("BOARD_NO_MARK"))
	else:
		_add_hint(
			body,
			(
				tr("BOARD_YOUR_BEST")
				% ChallengeService.format_score(challenge, int(best.get("score", 0)))
			)
		)
	var button := GameUISkinScript.make_button(tr("BOARD_TAKE_CHALLENGE"))
	button.disabled = not _can_start_run()
	button.pressed.connect(_on_challenge_pressed)
	body.add_child(button)
	if _first_focus == null:
		_first_focus = button


func _build_modes_section() -> void:
	var frame := GameUISkinScript.make_pixel_frame("Rule Sets")
	frame.name = "ModesFrame"
	_sections.add_child(frame)
	var body: VBoxContainer = GameUISkinScript.pixel_frame_content(frame)
	var modes := RunModeCatalog.get_all()
	if modes.is_empty():
		_add_hint(body, tr("BOARD_NO_MODES"))
		return
	var counters := ProgressCounters.snapshot()
	for mode in modes:
		var mode_id := str(mode.get("id", ""))
		_add_body(body, str(mode.get("name", mode_id)))
		_add_hint(body, ContentText.description(mode))
		var rules := RunModeCatalog.describe_rules(mode_id)
		if rules != "":
			_add_body(body, rules)
		var flavour := str(mode.get("flavour", ""))
		if flavour != "":
			_add_hint(body, flavour)
		var unlocked := RunModeCatalog.is_unlocked(mode_id, counters)
		if not unlocked:
			_add_hint(body, RunModeCatalog.unlock_hint(mode_id, counters))
		var button := GameUISkinScript.make_button(tr("BOARD_BEGIN"))
		button.disabled = not unlocked or not _can_start_run()
		button.pressed.connect(_on_mode_pressed.bind(mode_id))
		body.add_child(button)
		if _first_focus == null and not button.disabled:
			_first_focus = button


func _build_standing_section() -> void:
	var frame := GameUISkinScript.make_pixel_frame(tr("BOARD_STANDING"))
	frame.name = "StandingFrame"
	_sections.add_child(frame)
	var body: VBoxContainer = GameUISkinScript.pixel_frame_content(frame)
	var rows := HubGrowthService.get_standing()
	if rows.is_empty():
		_add_hint(body, tr("BOARD_NOTHING_TO_SHOW"))
		return
	var next_goal := HubGrowthService.get_next_goal()
	if not next_goal.is_empty():
		_add_hint(
			body,
			tr("TOWER_PRIMARY_GOAL").format(
				{
					"name": str(next_goal.get("name", "")),
					"requirement": str(next_goal.get("requirement", "")),
					"change": ContentText.description(next_goal),
				}
			)
		)
	_add_hint(
		body,
		"%d of %d raised" % [HubGrowthService.unlocked_count(), HubGrowthService.total_count()]
	)
	for row in rows:
		if bool(row.get("unlocked", false)):
			_add_body(body, "%s — %s" % [str(row.get("name", "")), ContentText.description(row)])
		else:
			_add_hint(body, "%s — %s" % [str(row.get("name", "")), str(row.get("requirement", ""))])


func _on_challenge_pressed() -> void:
	if not _can_start_run():
		return
	close()
	RunFlow.start_challenge_run()


func _on_mode_pressed(mode_id: String) -> void:
	if not _can_start_run():
		return
	close()
	RunFlow.start_alternate_mode_run(mode_id)


func _on_cancel_requested() -> void:
	close()


