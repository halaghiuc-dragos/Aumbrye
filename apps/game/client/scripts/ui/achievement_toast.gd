extends Control

## Achievement unlock toast (M6 META-6.1).

@onready var _label: Label = $Panel/Margin/Label


func _ready() -> void:
	visible = false
	modulate.a = 0.0


func show_achievement(display_name: String) -> void:
	_label.text = "Achievement: %s" % display_name
	visible = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.tween_interval(2.5)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)
