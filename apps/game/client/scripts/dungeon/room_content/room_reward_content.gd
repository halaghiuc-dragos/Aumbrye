extends "res://scripts/dungeon/room_content/room_content_base.gd"

const CHEST_SCENE := preload("res://scenes/loot/loot_chest.tscn")


func configure(entry: Dictionary, _definition: Dictionary) -> void:
	var chest: Node3D = CHEST_SCENE.instantiate() as Node3D
	chest.name = "RewardChest"
	chest.position = _anchor(0).position
	_content_root().add_child(chest)
	if chest.has_method("configure"):
		chest.call("configure", {"items": entry.get("items", [])})
