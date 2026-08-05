extends Control

## Room-graph minimap — reveals visited rooms from dungeon definition.

const CELL := 10.0
const PADDING := 6.0
const COLOR_VISITED := Color(0.55, 0.52, 0.48, 0.95)
const COLOR_CURRENT := Color(0.95, 0.78, 0.28, 1.0)
const COLOR_EDGE := Color(0.35, 0.33, 0.30, 0.7)
const COLOR_BG := Color(0.05, 0.05, 0.08, 0.82)

var _rooms: Array = []
var _edges: Array = []
var _visited: Dictionary = {}
var _current_room_id := ""
var _branch_previews: Array = []
var _bounds := Rect2()


func configure(definition: Dictionary) -> void:
	_rooms = definition.get("rooms", [])
	_edges = definition.get("edges", [])
	_branch_previews = definition.get("branchPreviews", [])
	_visited.clear()
	_current_room_id = ""
	_recompute_bounds()
	queue_redraw()


func mark_visited(room_id: String) -> void:
	if room_id == "":
		return
	_visited[room_id] = true
	queue_redraw()


func set_current_room(room_id: String) -> void:
	_current_room_id = room_id
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(140, 140)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if _rooms.is_empty():
		return
	var map_rect := Rect2(PADDING, PADDING, size.x - PADDING * 2.0, size.y - PADDING * 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.18, 0.16), false, 1.0)
	for edge in _edges:
		if not edge is Dictionary:
			continue
		var from_pos := _room_center(str(edge.get("from", "")))
		var to_pos := _room_center(str(edge.get("to", "")))
		if from_pos == Vector2.INF or to_pos == Vector2.INF:
			continue
		draw_line(_map_point(from_pos, map_rect), _map_point(to_pos, map_rect), COLOR_EDGE, 1.0)
	for room_def in _rooms:
		if not room_def is Dictionary:
			continue
		var room_id := str(room_def.get("id", ""))
		if not _visited.has(room_id):
			continue
		var center := _map_point(_room_center(room_id), map_rect)
		var color := COLOR_CURRENT if room_id == _current_room_id else COLOR_VISITED
		draw_rect(Rect2(center - Vector2(CELL * 0.45, CELL * 0.45), Vector2(CELL * 0.9, CELL * 0.9)), color)
	_draw_branch_previews(map_rect)


func _recompute_bounds() -> void:
	var min_x := 0.0
	var max_x := 0.0
	var min_z := 0.0
	var max_z := 0.0
	for room_def in _rooms:
		if not room_def is Dictionary:
			continue
		var t: Dictionary = room_def.get("transform", {})
		var x := float(t.get("x", 0.0))
		var z := float(t.get("z", 0.0))
		min_x = minf(min_x, x)
		max_x = maxf(max_x, x)
		min_z = minf(min_z, z)
		max_z = maxf(max_z, z)
	_bounds = Rect2(min_x, min_z, maxf(1.0, max_x - min_x), maxf(1.0, max_z - min_z))


func _room_center(room_id: String) -> Vector2:
	for room_def in _rooms:
		if not room_def is Dictionary:
			continue
		if str(room_def.get("id", "")) != room_id:
			continue
		var t: Dictionary = room_def.get("transform", {})
		return Vector2(float(t.get("x", 0.0)), float(t.get("z", 0.0)))
	return Vector2.INF


func _map_point(world_xz: Vector2, map_rect: Rect2) -> Vector2:
	if world_xz == Vector2.INF:
		return Vector2.ZERO
	var nx := 0.5
	var ny := 0.5
	if _bounds.size.x > 0.0:
		nx = (world_xz.x - _bounds.position.x) / _bounds.size.x
	if _bounds.size.y > 0.0:
		ny = (world_xz.y - _bounds.position.y) / _bounds.size.y
	return Vector2(
		map_rect.position.x + nx * map_rect.size.x,
		map_rect.position.y + ny * map_rect.size.y
	)


func _draw_branch_previews(map_rect: Rect2) -> void:
	if _current_room_id == "":
		return
	for preview in _branch_previews:
		if not preview is Dictionary:
			continue
		if str(preview.get("fromRoomId", "")) != _current_room_id:
			continue
		var to_id := str(preview.get("toRoomId", ""))
		if to_id == "" or _visited.has(to_id):
			continue
		var center := _map_point(_room_center(to_id), map_rect)
		if center == Vector2.ZERO and _room_center(to_id) == Vector2.INF:
			continue
		var hint := str(preview.get("hint", "danger"))
		if hint == "reward":
			draw_circle(center, 3.0, Color(0.95, 0.78, 0.2, 0.95))
		else:
			var half := 3.0
			draw_colored_polygon(
				PackedVector2Array([
					center + Vector2(0.0, -half),
					center + Vector2(half, 0.0),
					center + Vector2(0.0, half),
					center + Vector2(-half, 0.0),
				]),
				Color(0.9, 0.22, 0.15, 0.95)
			)
