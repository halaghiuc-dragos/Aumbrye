extends Control

## Deprecated — waves inventory now uses the global InventoryUI on PlayerControls.


func _ready() -> void:
	visible = false
	queue_free()
