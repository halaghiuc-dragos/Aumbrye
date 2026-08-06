extends Control

## Compact HUD panel listing active quest objectives.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

@onready var _quest_list: VBoxContainer = $Panel/Margin/VBox/QuestList


func _ready() -> void:
	GameUISkinScript.apply_pixel_theme(self)
	QuestService.quest_updated.connect(_on_quest_updated)
	_refresh()


func _on_quest_updated(_quest_id: String, _state: String) -> void:
	_refresh()


func _refresh() -> void:
	for child in _quest_list.get_children():
		child.queue_free()
	var active := QuestService.get_active_quests()
	visible = not active.is_empty()
	if active.is_empty():
		return
	for quest in active:
		var quest_id: String = quest.get("id", "")
		var progress: Dictionary = CharacterService.get_quest_progress(quest_id)
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var title: String = str(quest.get("title", quest_id))
		var detail: String = _format_progress(quest, progress)
		line.text = "%s — %s" % [title, detail]
		line.add_theme_font_size_override("font_size", 12)
		_quest_list.add_child(line)


func _format_progress(quest: Dictionary, progress: Dictionary) -> String:
	var quest_type: String = str(quest.get("type", ""))
	match quest_type:
		"kill":
			return (
				"%d/%d"
				% [
					int(progress.get("count", 0)),
					int(quest.get("requiredCount", 1)),
				]
			)
		"fetch":
			return str(quest.get("description", ""))
		"escape":
			return "Escape alive"
	return str(quest.get("description", ""))
