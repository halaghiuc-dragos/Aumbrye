extends Control
class_name StatusPip

const StatusIconAtlasScript := preload("res://scripts/ui/status_icon_atlas.gd")

@onready var _frame: TextureRect = $Frame
@onready var _icon: TextureRect = $Icon
@onready var _duration_arc: TextureProgressBar = $DurationArc
@onready var _stack_label: Label = $StackLabel


func configure(
	status_id: String,
	stacks: int,
	icon_texture: Texture2D,
	polarity: String = "debuff"
) -> void:
	var icon_dim := StatusIconAtlasScript.icon_size()
	custom_minimum_size = Vector2(icon_dim + 4, icon_dim + 8)
	_frame.texture = StatusIconAtlasScript.get_polarity_frame(polarity)
	_frame.custom_minimum_size = Vector2(icon_dim, icon_dim)
	_icon.texture = icon_texture
	_icon.custom_minimum_size = Vector2(icon_dim, icon_dim)
	_icon.modulate = Color.WHITE
	_stack_label.visible = stacks > 1
	_stack_label.text = "x%d" % stacks
	tooltip_text = status_id


func update_timer(remaining: float, duration: float) -> void:
	if duration > 0.0:
		_duration_arc.max_value = duration
		_duration_arc.value = remaining
		_duration_arc.visible = true
	else:
		_duration_arc.visible = false


func set_stacks(stacks: int) -> void:
	_stack_label.visible = stacks > 1
	_stack_label.text = "x%d" % stacks
