extends "res://scripts/dungeon/room_content/room_content_base.gd"

const CHEST_SCENE := preload("res://scenes/loot/loot_chest.tscn")


func configure(_entry: Dictionary, _definition: Dictionary) -> void:
	var chest: Node3D = CHEST_SCENE.instantiate() as Node3D
	chest.name = "RewardChest"
	chest.position = Vector3(1.0, 0.0, -1.0)
	_content_root().add_child(chest)
