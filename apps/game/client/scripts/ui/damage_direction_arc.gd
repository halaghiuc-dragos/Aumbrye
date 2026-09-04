extends Control

## HD-07: a short arc at the screen edge, in the bearing the last hit came from, fading over 0.6 s.
## `combat_hud.gd` drives `bearing`/`radius`/`alpha` and calls `queue_redraw()`; this script only
## draws.

var bearing := 0.0
var radius := 200.0
var alpha := 0.0

const ARC_SPAN := 0.8726646259971648 # 50 degrees
const ARC_WIDTH := 5.0
const ARC_COLOR := Color(0.9, 0.15, 0.12, 1.0)


func _draw() -> void:
	if alpha <= 0.0:
		return
	draw_arc(
		Vector2.ZERO,
		radius,
		bearing - ARC_SPAN * 0.5,
		bearing + ARC_SPAN * 0.5,
		16,
		Color(ARC_COLOR.r, ARC_COLOR.g, ARC_COLOR.b, alpha),
		ARC_WIDTH,
		true
	)
