extends Area3D

## Post-boss escape portal — triggers results screen (FLOW-2.1).

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if not monitoring:
		visible = false


func activate() -> void:
	monitoring = true
	visible = true


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D and body.is_in_group("player"):
		RunFlow.call_deferred("complete_run_via_portal")
