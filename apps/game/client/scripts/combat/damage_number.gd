extends Node3D
class_name DamageNumberSpawner

const SCENE := preload("res://scenes/combat/damage_number.tscn")

const LIFETIME := 0.65
const RISE_SPEED := 1.2
const BASE_FONT_SIZE := 48
## A crit reading the same size as any other hit is a stat the player has to check a log for. This
## is the one place its whole point -- "that landed harder" -- can be read at a glance instead.
const CRIT_FONT_SIZE := 72
const CRIT_OUTLINE_SIZE := 10

@onready var _label: Label3D = $Label3D


func _ready() -> void:
	add_to_group("damage_number")


static func spawn(
	world_position: Vector3,
	amount: float,
	parent: Node,
	damage_type: String = "physical",
	is_crit: bool = false
) -> void:
	var node := SCENE.instantiate()
	parent.add_child(node)
	node.global_position = world_position + Vector3(0.0, 1.8, 0.0)
	if node.has_method("show_amount"):
		node.call("show_amount", amount, damage_type, is_crit)


static func spawn_text(
	world_position: Vector3, text: String, parent: Node, color: Color = Color.WHITE
) -> void:
	var node := SCENE.instantiate()
	parent.add_child(node)
	node.global_position = world_position + Vector3(0.0, 2.0, 0.0)
	if node.has_method("show_text"):
		node.call("show_text", text, color)


func show_amount(amount: float, damage_type: String = "physical", is_crit: bool = false) -> void:
	if _label:
		_label.text = str(int(round(amount)))
		_label.modulate = AccessibilitySettings.get_damage_color(damage_type)
		_label.font_size = CRIT_FONT_SIZE if is_crit else BASE_FONT_SIZE
		_label.outline_size = CRIT_OUTLINE_SIZE if is_crit else 8
	_animate_float(is_crit)


func show_text(text: String, color: Color) -> void:
	if _label:
		_label.text = text
		_label.modulate = color
	_animate_float()


func _animate_float(is_crit: bool = false) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y + RISE_SPEED * LIFETIME, LIFETIME)
	tween.tween_property(_label, "modulate:a", 0.0, LIFETIME)
	tween.chain().tween_callback(queue_free)
	if is_crit:
		# A quick overshoot-and-settle so a crit visibly *lands* instead of just appearing at its
		# final (larger) size -- the same punch language the hitstop/camera-punch system already
		# uses for a critical impact, just on the number instead of the camera. Its own tween, since
		# it needs to finish in a couple of frames while the float/fade above runs the full lifetime.
		_label.scale = Vector3(0.55, 0.55, 0.55)
		var punch := create_tween()
		punch.tween_property(_label, "scale", Vector3(1.15, 1.15, 1.15), 0.09).set_trans(
			Tween.TRANS_BACK
		).set_ease(Tween.EASE_OUT)
		punch.tween_property(_label, "scale", Vector3.ONE, 0.1).set_trans(Tween.TRANS_SINE)
