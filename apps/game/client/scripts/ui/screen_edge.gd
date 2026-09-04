class_name ScreenEdge
extends RefCounted

## HD-07: lifted out of the objective marker and the `EN-09` danger chevrons, which both computed
## this same "world position -> a point clamped to the screen edge when off-screen or behind the
## camera" transform independently. The damage direction indicator is the third consumer.
static func edge_position(screen_pos: Vector2, viewport_size: Vector2, behind: bool) -> Vector2:
	var center := viewport_size * 0.5
	if not behind and Rect2(Vector2.ZERO, viewport_size).has_point(screen_pos):
		return screen_pos
	var dir := (screen_pos - center).normalized()
	if behind:
		dir = -dir
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	return center + dir * minf(viewport_size.x, viewport_size.y) * 0.42
