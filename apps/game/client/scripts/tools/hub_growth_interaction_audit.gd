extends Node3D

const HubDioramaScript := preload("res://scripts/hub/hub_diorama.gd")

var _failures := 0


func _ready() -> void:
	_check_interaction("shelf", "archive_shelves", "growth:shelf:archive_shelves")
	_check_interaction("marker", "record_stone", "growth:marker:record_stone")
	print("HUB GROWTH INTERACTION RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_interaction(prop: String, entry_id: String, expected_id: String) -> void:
	var growth := Node3D.new()
	add_child(growth)
	HubDioramaScript._add_growth_interaction(growth, {"id": entry_id, "prop": prop})
	var area := growth.get_node_or_null("InteractArea") as HubInteractable
	_check(
		area != null
		and area.interact_id == expected_id
		and area.collision_mask == 2
		and area.get_node_or_null("CollisionShape3D") is CollisionShape3D,
		"%s growth has a stable reachable interaction contract" % prop
	)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(label)
