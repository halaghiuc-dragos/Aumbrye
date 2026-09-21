extends Control


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

@onready var _quest_list: VBoxContainer = $Panel/Margin/VBox/QuestList
var _rows: Dictionary = {}


func _ready() -> void:
	GameUISkinScript.apply_pixel_theme(self)
	QuestService.quest_updated.connect(_on_quest_updated)
	QuestService.quest_progress_changed.connect(_on_quest_progress_changed)
	_refresh()


func _on_quest_updated(_quest_id: String, _state: String) -> void:
	_refresh()


func _on_quest_progress_changed(
	quest_id: String, _objective_id: String, _old_count: int, _new_count: int, _required: int
) -> void:
	var line := _rows.get(quest_id) as Label
	if line == null or not is_instance_valid(line):
		_refresh()
		return
	var quest := QuestCatalog.get_definition(quest_id)
	_set_row_text(line, quest, CharacterService.get_quest_progress(quest_id))


func _refresh() -> void:
	_rows.clear()
	for child in _quest_list.get_children():
		child.queue_free()
	var active := QuestService.get_active_quests()
	visible = not active.is_empty()
	if active.is_empty():
		return
	for quest in active:
		var quest_id: String = quest.get("id", "")
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_set_row_text(line, quest, CharacterService.get_quest_progress(quest_id))
		line.add_theme_font_size_override("font_size", GameUISkinScript.FONT_SIZE_SMALL)
		GameUISkinScript.style_body_label(line)
		_quest_list.add_child(line)
		_rows[quest_id] = line


func _set_row_text(line: Label, quest: Dictionary, progress: Dictionary) -> void:
	var quest_id := str(quest.get("id", ""))
	var title: String = str(quest.get("title", quest_id))
	var detail: String = _format_progress(quest, progress)
	line.text = (
		tr("QUEST_TRACKER_LINE").format({"title": title, "detail": detail})
		if detail != ""
		else title
	)


## The tracker sits in a corner of the HUD during gameplay and has to stay glanceable, not a
## reading assignment -- the fetch branch used to print the quest's full prose description here,
## which for a normal-length quest ran to two or three sentences. With more than one quest active
## the tracker's fixed-size panel had no way to hold that and would grow past its own borders and
## off the top of the screen. Every quest type now reports the same short "x/y" shape the kill
## branch already used; the full description still lives in the Quest Board where there is room
## for it and reading it does not need to be glanceable.
func _format_progress(quest: Dictionary, progress: Dictionary) -> String:
	var quest_type: String = str(quest.get("type", ""))
	match quest_type:
		"kill", "fetch", "discover", "escort", "defeat_with":
			return (
				"%d/%d"
				% [
					int(progress.get("count", 0)),
					int(quest.get("requiredCount", 1)),
				]
			)
		"escape":
			return tr("QUEST_OBJECTIVE_ESCAPE")
		"reach_depth":
			return tr("QUEST_OBJECTIVE_DEPTH").format({"depth": int(quest.get("requiredCount", 1))})
	return ""
