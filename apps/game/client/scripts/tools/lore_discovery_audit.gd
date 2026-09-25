extends Node

const LoreContentScript := preload("res://scripts/dungeon/room_content/room_lore_content.gd")

var _failures := 0
var _saved_discoveries: Dictionary
var _saved_found := 0
var _saved_counter := 0


func _ready() -> void:
	_saved_discoveries = (CharacterService.get_flag("lore_discoveries", {}) as Dictionary).duplicate(true)
	_saved_found = int(CharacterService.get_flag("discoveries_found", 0))
	_saved_counter = int(CharacterService.get_flag("lore_forgotten_castle_read", 0))
	CharacterService.set_flag("lore_discoveries", {})
	CharacterService.set_flag("discoveries_found", 0)
	CharacterService.set_flag("lore_forgotten_castle_read", 0)

	var first := _make_lore("forgotten_castle:401:lore:room_a")
	_check(bool(first.call("_record_discovery_once")), "first inscription read earns discovery credit")
	_check(not bool(first.call("_record_discovery_once")), "re-reading one inscription cannot farm discovery credit")
	var restored_instance := _make_lore("forgotten_castle:401:lore:room_a")
	_check(not bool(restored_instance.call("_record_discovery_once")), "same inscription stays consumed after reconstruction")
	var second := _make_lore("forgotten_castle:401:lore:room_b")
	_check(bool(second.call("_record_discovery_once")), "a different placed inscription earns its own credit")
	_check(
		int(CharacterService.get_flag("discoveries_found", 0)) == 2
		and int(CharacterService.get_flag("lore_forgotten_castle_read", 0)) == 2,
		"only unique placement identities advance lore counters"
	)
	_restore()
	print("LORE DISCOVERY RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _make_lore(lore_id: String) -> Node:
	var lore := LoreContentScript.new()
	lore.set("_lore_id", lore_id)
	lore.set_meta("biome_id", "forgotten_castle")
	add_child(lore)
	return lore


func _restore() -> void:
	CharacterService.set_flag("lore_discoveries", _saved_discoveries)
	CharacterService.set_flag("discoveries_found", _saved_found)
	CharacterService.set_flag("lore_forgotten_castle_read", _saved_counter)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(label)
