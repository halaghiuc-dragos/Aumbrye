class_name DungeonQuestCatalog
extends RefCounted


const QUEST_PATH := "content/quests/dungeon_quests.json"

static var _quests: Array = []


static func quests_for_biome(biome_id: String) -> Array:
	_ensure_loaded()
	var matches: Array = []
	for quest in _quests:
		if not quest is Dictionary:
			continue
		var biomes: Array = quest.get("biomes", [])
		if biome_id == "" or biome_id in biomes:
			matches.append(quest)
	return matches


static func quest_for_dialogue(dialogue_id: String) -> Dictionary:
	_ensure_loaded()
	for quest in _quests:
		if str(quest.get("dialogueId", "")) == dialogue_id:
			return quest
	return {}


static func clear_cache() -> void:
	_quests.clear()


static func _ensure_loaded() -> void:
	if not _quests.is_empty():
		return
	var parsed: Variant = ContentLoader.load_json(QUEST_PATH)
	if parsed is Dictionary:
		_quests = parsed.get("quests", [])
	elif parsed is Array:
		_quests = parsed
