extends Node

const ArtDirectionSpecScript := preload("res://scripts/art/style/art_direction_spec.gd")


func _ready() -> void:
	var failures := ArtDirectionSpecScript.validate_authored_contract()
	for failure in failures:
		push_error("ART DIRECTION SPEC: %s" % failure)
	print("ART DIRECTION SPEC RESULT %d failure(s)" % failures.size())
	get_tree().quit(1 if not failures.is_empty() else 0)
