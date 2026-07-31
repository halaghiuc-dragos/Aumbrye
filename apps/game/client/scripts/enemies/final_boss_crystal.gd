extends Area3D

## Collectible crystal for final boss puzzle phase.

signal collected

var _taken := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	monitoring = true


func _on_body_entered(body: Node3D) -> void:
	if _taken:
		return
	if body.is_in_group("player"):
		_taken = true
		collected.emit()
		queue_free()
