extends Control

## Optional quest board — accept quests without blocking portals (QUEST-4.1).

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

signal closed

@onready var _available_list: ItemList = $Panel/Margin/VBox/AvailableList
@onready var _active_list: ItemList = $Panel/Margin/VBox/ActiveList
@onready var _completed_list: ItemList = $Panel/Margin/VBox/CompletedList
@onready var _detail_label: Label = $Panel/Margin/VBox/DetailLabel
@onready var _accept_button: Button = $Panel/Margin/VBox/Buttons/AcceptButton
@onready var _close_button: Button = $Panel/Margin/VBox/Buttons/CloseButton

var _available_ids: Array[String] = []


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkinScript.apply_modal_menu(self, "Panel", "Backdrop")
	_accept_button.pressed.connect(_on_accept_pressed)
	_close_button.pressed.connect(close)
	_available_list.item_selected.connect(_on_available_selected)
	# Bound method rather than a lambda: QuestService is an autoload and outlives this menu, and a
	# lambda connection is not auto-disconnected when the capturing node is freed.
	QuestService.quest_updated.connect(_on_quest_updated)
	if CharacterService:
		CharacterService.quests_changed.connect(_refresh)
		CharacterService.quest_progress_changed.connect(_refresh)


func _on_quest_updated(_quest_id: String, _status: String) -> void:
	_refresh()


func is_open() -> bool:
	return visible


func open() -> void:
	_refresh()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_available_list.grab_focus()


func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _refresh() -> void:
	_available_list.clear()
	_available_ids.clear()
	for quest in QuestService.get_available_quests():
		var quest_id: String = quest.get("id", "")
		_available_list.add_item("%s — %s" % [quest.get("title", quest_id), quest.get("type", "")])
		_available_ids.append(quest_id)
	_active_list.clear()
	for quest in QuestService.get_active_quests():
		var quest_id: String = quest.get("id", "")
		var progress: Dictionary = CharacterService.get_quest_progress(quest_id)
		var detail: String = str(quest.get("description", ""))
		if quest.get("type", "") == "kill":
			detail += (
				" (%d/%d)" % [int(progress.get("count", 0)), int(quest.get("requiredCount", 1))]
			)
		_active_list.add_item("%s — %s" % [quest.get("title", quest_id), detail])
	_completed_list.clear()
	for quest in QuestService.get_completed_quests():
		var completed_id: String = quest.get("id", "")
		_completed_list.add_item("%s — completed" % quest.get("title", completed_id))


func _on_available_selected(index: int) -> void:
	if index < 0 or index >= _available_ids.size():
		return
	var quest_id: String = _available_ids[index]
	var def: Dictionary = QuestCatalog.get_definition(quest_id)
	_detail_label.text = def.get("description", "")


func _on_accept_pressed() -> void:
	var selected: PackedInt32Array = _available_list.get_selected_items()
	if selected.is_empty():
		_detail_label.text = "Select a quest to accept"
		return
	var quest_id: String = _available_ids[selected[0]]
	if QuestService.accept_quest(quest_id):
		_detail_label.text = "Quest accepted: %s" % quest_id
	else:
		_detail_label.text = "Could not accept quest"
	_refresh()
