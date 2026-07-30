extends Area3D
class_name HubInteractable

## Reusable hub interact zone — press E / gamepad to trigger (HUB-4.1).

signal player_entered
signal player_exited
signal interacted

@export var prompt_text: String = "Interact (E)"
@export var interact_id: String = ""

var _near_player := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func is_player_near() -> bool:
	return _near_player


func get_prompt() -> String:
	return prompt_text


func trigger_interact() -> void:
	interacted.emit()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = true
		player_entered.emit()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = false
		player_exited.emit()
