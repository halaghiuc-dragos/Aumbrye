class_name BowReticle
extends Control

## `RG-01`: the crosshair drawn at the bow's projected impact point, with a draw-strength arc that
## fills as `_draw_charge` rises. A plain `_draw()` control rather than a texture -- the arc has to
## redraw every frame the charge changes, and there is no asset to author for a value that is
## continuous rather than a fixed set of frames.

const RING_RADIUS := 9.0
const RING_WIDTH := 1.5
const TICK_LENGTH := 4.0
const TICK_GAP := 3.0
const ARC_RADIUS := 13.0
const ARC_WIDTH := 2.0
const RETICLE_COLOR := Color(0.92, 0.9, 0.82, 0.9)
const ARC_TRACK_COLOR := Color(0.92, 0.9, 0.82, 0.25)
const ARC_FILL_COLOR := Color(0.86, 0.74, 0.36, 1.0)

var _charge := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(ARC_RADIUS, ARC_RADIUS) * 2.0
	size = custom_minimum_size


func set_charge(amount: float) -> void:
	var clamped := clampf(amount, 0.0, 1.0)
	if is_equal_approx(clamped, _charge):
		return
	_charge = clamped
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	draw_arc(center, RING_RADIUS, 0.0, TAU, 24, RETICLE_COLOR, RING_WIDTH, true)
	for i in 4:
		var angle := i * PI * 0.5
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(
			center + dir * (RING_RADIUS + TICK_GAP),
			center + dir * (RING_RADIUS + TICK_GAP + TICK_LENGTH),
			RETICLE_COLOR,
			RING_WIDTH,
			true
		)
	draw_arc(center, ARC_RADIUS, -PI * 0.5, TAU - PI * 0.5, 32, ARC_TRACK_COLOR, ARC_WIDTH, true)
	if _charge > 0.001:
		draw_arc(
			center,
			ARC_RADIUS,
			-PI * 0.5,
			-PI * 0.5 + TAU * _charge,
			maxi(2, int(32 * _charge)),
			ARC_FILL_COLOR,
			ARC_WIDTH,
			true
		)
