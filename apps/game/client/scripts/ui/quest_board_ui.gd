extends Control


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

signal closed

@onready var _available_list: ItemList = $Panel/Margin/VBox/AvailableList
@onready var _active_list: ItemList = $Panel/Margin/VBox/ActiveList
@onready var _completed_list: ItemList = $Panel/Margin/VBox/CompletedList
@onready var _detail_label: Label = $Panel/Margin/VBox/DetailLabel
@onready var _accept_button: Button = $Panel/Margin/VBox/Buttons/AcceptButton
@onready var _close_button: Button = $Panel/Margin/VBox/Buttons/CloseButton

var _available_ids: Array[String] = []
var _active_ids: Array[String] = []
var _hand_in_button: Button
var _track_primary_button: Button
var _track_secondary_button: Button
var _refresh_pending := false


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkinScript.apply_modal_menu(self, "Panel", "Backdrop")
	_accept_button.pressed.connect(_on_accept_pressed)
	_close_button.pressed.connect(close)
	_available_list.item_selected.connect(_on_available_selected)
	_active_list.item_selected.connect(_on_active_selected)
	_hand_in_button = GameUISkinScript.make_button(tr("QUEST_HAND_IN"))
	_hand_in_button.visible = false
	_accept_button.get_parent().add_child(_hand_in_button)
	_accept_button.get_parent().move_child(_hand_in_button, 1)
	_hand_in_button.pressed.connect(_on_hand_in_pressed)
	_track_primary_button = GameUISkinScript.make_button(tr("QUEST_TRACK_PRIMARY_ACTION"))
	_track_secondary_button = GameUISkinScript.make_button(tr("QUEST_TRACK_SECONDARY_ACTION"))
	_accept_button.get_parent().add_child(_track_primary_button)
	_accept_button.get_parent().add_child(_track_secondary_button)
	_track_primary_button.pressed.connect(_on_track_primary_pressed)
	_track_secondary_button.pressed.connect(_on_track_secondary_pressed)
	QuestService.quest_updated.connect(_on_quest_updated)
	if CharacterService:
		CharacterService.quests_changed.connect(_refresh)
		CharacterService.quest_progress_changed.connect(_refresh)


func _on_quest_updated(_quest_id: String, _status: String) -> void:
	_refresh()


func is_open() -> bool:
	return visible


func open() -> void:
	MenuStack.show_modal(self)
	_refresh()
	_refresh_pending = false
	_available_list.grab_focus()


func close() -> void:
	MenuStack.hide_modal(self)
	closed.emit()


func _on_cancel_requested() -> void:
	close()


func _refresh() -> void:
	if not visible:
		_refresh_pending = true
		return
	var selected_available := _selected_id(_available_list, _available_ids)
	var selected_active := _selected_id(_active_list, _active_ids)
	_available_list.clear()
	_available_ids.clear()
	for quest in QuestService.get_available_quests():
		var quest_id: String = quest.get("id", "")
		_available_list.add_item("%s — %s" % [ContentText.title(quest, quest_id), quest.get("type", "")])
		_available_ids.append(quest_id)
	_active_list.clear()
	_active_ids.clear()
	for quest in QuestService.get_active_quests():
		var quest_id: String = quest.get("id", "")
		var progress: Dictionary = CharacterService.get_quest_progress(quest_id)
		var detail: String = ContentText.description(quest)
		if quest.get("type", "") in ["kill", "fetch", "discover", "escort", "defeat_with"]:
			detail += (
				" (%d/%d)" % [int(progress.get("count", 0)), int(quest.get("requiredCount", 1))]
			)
		var tracker_role := QuestService.tracker_role_for(quest_id)
		var tracker_prefix := "★ " if tracker_role == "primary" else ("• " if tracker_role == "secondary" else "")
		_active_list.add_item("%s%s — %s" % [tracker_prefix, ContentText.title(quest, quest_id), detail])
		_active_ids.append(quest_id)
	_restore_selected(_available_list, _available_ids, selected_available)
	_restore_selected(_active_list, _active_ids, selected_active)
	_hand_in_button.visible = selected_active != "" and selected_active in _active_ids and str(QuestCatalog.get_definition(selected_active).get("objectiveMode", "")) == "delivery"
	_hand_in_button.disabled = not _hand_in_button.visible or not QuestService.can_hand_in_fetch(selected_active)
	_update_tracker_buttons(selected_active)
	_completed_list.clear()
	for quest in QuestService.get_completed_quests():
		var completed_id: String = quest.get("id", "")
		var completions := QuestService.get_completions(completed_id)
		var suffix := "completed" if completions <= 1 else "completed %d times" % completions
		_completed_list.add_item("%s — %s" % [ContentText.title(quest, completed_id), suffix])
	_refresh_pending = false


func _selected_id(list: ItemList, ids: Array[String]) -> String:
	var selected := list.get_selected_items()
	if selected.is_empty() or selected[0] < 0 or selected[0] >= ids.size():
		return ""
	return ids[selected[0]]


func _restore_selected(list: ItemList, ids: Array[String], quest_id: String) -> void:
	if quest_id == "":
		return
	var index := ids.find(quest_id)
	if index >= 0:
		list.select(index)


func _on_available_selected(index: int) -> void:
	if index < 0 or index >= _available_ids.size():
		return
	var quest_id: String = _available_ids[index]
	var def: Dictionary = QuestCatalog.get_definition(quest_id)
	_detail_label.text = ContentText.description(def)


func _on_active_selected(index: int) -> void:
	if index < 0 or index >= _active_ids.size():
		_hand_in_button.visible = false
		_update_tracker_buttons("")
		return
	var quest_id := _active_ids[index]
	var def := QuestCatalog.get_definition(quest_id)
	_detail_label.text = ContentText.description(def)
	_hand_in_button.visible = str(def.get("objectiveMode", "")) == "delivery"
	_hand_in_button.disabled = not QuestService.can_hand_in_fetch(quest_id)
	_update_tracker_buttons(quest_id)


func _update_tracker_buttons(quest_id: String) -> void:
	var is_active := quest_id != "" and quest_id in _active_ids
	_track_primary_button.visible = is_active
	_track_secondary_button.visible = is_active
	if not is_active:
		return
	var role := QuestService.tracker_role_for(quest_id)
	_track_primary_button.text = (
		tr("QUEST_TRACKED_PRIMARY_ACTION") if role == "primary" else tr("QUEST_TRACK_PRIMARY_ACTION")
	)
	_track_primary_button.disabled = role == "primary"
	_track_secondary_button.text = (
		tr("QUEST_UNTRACK_SECONDARY_ACTION") if role == "secondary" else tr("QUEST_TRACK_SECONDARY_ACTION")
	)
	_track_secondary_button.disabled = role == "primary" or (
		role != "secondary" and _secondary_pin_count() >= QuestService.MAX_SECONDARY_TRACKER_PINS
	)


func _secondary_pin_count() -> int:
	var tracker := CharacterService.get_quest_tracker()
	var secondary: Variant = tracker.get("secondary", [])
	return secondary.size() if secondary is Array else 0


func _selected_active_id() -> String:
	return _selected_id(_active_list, _active_ids)


func _on_track_primary_pressed() -> void:
	var quest_id := _selected_active_id()
	if QuestService.set_primary_tracker_pin(quest_id):
		_detail_label.text = tr("QUEST_TRACK_PRIMARY_SET")
	_refresh()


func _on_track_secondary_pressed() -> void:
	var quest_id := _selected_active_id()
	if QuestService.toggle_secondary_tracker_pin(quest_id):
		_detail_label.text = tr("QUEST_TRACK_SECONDARY_SET")
	else:
		_detail_label.text = tr("QUEST_TRACK_SECONDARY_FULL")
	_refresh()


func _on_hand_in_pressed() -> void:
	var selected := _active_list.get_selected_items()
	if selected.is_empty() or selected[0] >= _active_ids.size():
		return
	var quest_id := _active_ids[selected[0]]
	if QuestService.hand_in_fetch_quest(quest_id):
		_detail_label.text = tr("QUEST_HAND_IN_COMPLETE")
	else:
		_detail_label.text = tr("QUEST_HAND_IN_FAILED")
	_refresh()


func _on_accept_pressed() -> void:
	var selected: PackedInt32Array = _available_list.get_selected_items()
	if selected.is_empty():
		_detail_label.text = tr("QUEST_SELECT_TO_ACCEPT")
		return
	var quest_id: String = _available_ids[selected[0]]
	if QuestService.accept_quest(quest_id):
		_detail_label.text = tr("QUEST_ACCEPTED") % QuestCatalog.get_definition(quest_id).get("title", quest_id)
	else:
		_detail_label.text = tr("QUEST_ACCEPT_FAILED")
	_refresh()
