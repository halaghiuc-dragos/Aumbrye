extends Node3D
class_name DamageNumberSpawner

const SCENE := preload("res://scenes/combat/damage_number.tscn")

const LIFETIME := 0.65
const RISE_SPEED := 1.2

@onready var _label: Label3D = $Label3D


func _ready() -> void:
	add_to_group("damage_number")


static func spawn(
	world_position: Vector3, amount: float, parent: Node, damage_type: String = "physical"
) -> void:
	var node := SCENE.instantiate()
	parent.add_child(node)
	node.global_position = world_position + Vector3(0.0, 1.8, 0.0)
	if node.has_method("show_amount"):
		node.call("show_amount", amount, damage_type)


static func spawn_text(
	world_position: Vector3, text: String, parent: Node, color: Color = Color.WHITE
) -> void:
	var node := SCENE.instantiate()
	parent.add_child(node)
	node.global_position = world_position + Vector3(0.0, 2.0, 0.0)
	if node.has_method("show_text"):
		node.call("show_text", text, color)


func show_amount(amount: float, damage_type: String = "physical") -> void:
	if _label:
		_label.text = str(int(round(amount)))
		_label.modulate = AccessibilitySettings.get_damage_color(damage_type)
	_animate_float()


func show_text(text: String, color: Color) -> void:
	if _label:
		_label.text = text
		_label.modulate = color
	_animate_float()


func _animate_float() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y + RISE_SPEED * LIFETIME, LIFETIME)
	tween.tween_property(_label, "modulate:a", 0.0, LIFETIME)
	tween.chain().tween_callback(queue_free)
