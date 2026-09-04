extends Control


enum RevealTier { UNKNOWN = 0, SEEN = 1, VISITED = 2 }

const PADDING := 6.0
const HUD_SIZE := Vector2(140, 140)
const ICON_CELL := 8
const PLAYER_ARROW_HALF := 3.5
const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0
const STICK_PAN_SPEED := 700.0
const FALLBACK_ROOM_PX := 9.0

const COLOR_VISITED := Color(0.55, 0.52, 0.48, 0.95)
const COLOR_CURRENT := Color(0.95, 0.78, 0.28, 1.0)
const COLOR_SEEN := Color(0.32, 0.30, 0.28, 0.75)
const COLOR_EDGE := Color(0.35, 0.33, 0.30, 0.7)
const COLOR_ONE_WAY := Color(0.85, 0.7, 0.35, 0.85)
const COLOR_BG := Color(0.05, 0.05, 0.08, 0.82)
const COLOR_PLAYER := Color(0.95, 0.92, 0.82, 1.0)

const ICON_ATLAS_PATH := "res://assets/ui/minimap_icons.png"

const KIND_CELLS := {
	"combat": Vector2i(0, 0),
	"treasure": Vector2i(1, 0),
	"shop": Vector2i(2, 0),
	"key": Vector2i(3, 0),
	"hazard": Vector2i(4, 0),
	"npc": Vector2i(5, 0),
	"vault": Vector2i(6, 0),
	"lore": Vector2i(7, 0),
	"boss": Vector2i(0, 1),
	"entrance": Vector2i(1, 1),
	"stairs": Vector2i(2, 1),
	"unknown": Vector2i(3, 1),
	"rest": Vector2i(4, 1),
	"puzzle": Vector2i(5, 1),
	"secret": Vector2i(6, 1),
}

const LEGEND_ENTRIES := [
	{"kind": "combat", "label_key": "MAP_LEGEND_COMBAT"},
	{"kind": "treasure", "label_key": "MAP_LEGEND_TREASURE"},
	{"kind": "shop", "label_key": "MAP_LEGEND_SHOP"},
	{"kind": "key", "label_key": "MAP_LEGEND_KEY"},
	{"kind": "hazard", "label_key": "MAP_LEGEND_HAZARD"},
	{"kind": "npc", "label_key": "MAP_LEGEND_NPC"},
	{"kind": "vault", "label_key": "MAP_LEGEND_VAULT"},
	{"kind": "lore", "label_key": "MAP_LEGEND_LORE"},
	{"kind": "boss", "label_key": "MAP_LEGEND_BOSS"},
	{"kind": "entrance", "label_key": "MAP_LEGEND_ENTRANCE"},
	{"kind": "stairs", "label_key": "MAP_LEGEND_STAIRS"},
	{"kind": "rest", "label_key": "MAP_LEGEND_REST"},
	{"kind": "puzzle", "label_key": "MAP_LEGEND_PUZZLE"},
	{"kind": "secret", "label_key": "MAP_LEGEND_SECRET"},
]

const COLOR_CLEARED := Color(0.42, 0.52, 0.44, 0.95)
const COLOR_LOCKED := Color(0.86, 0.44, 0.32, 1.0)
const CLEARED_TINT := Color(0.72, 0.82, 0.72, 1.0)
const LOCK_MARK_HALF := 2.0

var _rooms: Array = []
var _edges: Array = []
var _branch_previews: Array = []
var _reveal: Dictionary = {}
var _current_room_id := ""
var _bounds := Rect2()
var _room_by_id: Dictionary = {}
var _center_by_id: Dictionary = {}
var _neighbors: Dictionary = {}
var _player: Node3D
var _redraw_timer := 0.0
var _last_player_pos := Vector3(INF, INF, INF)
var _overlay_mode := false
var _zoom := 1.0
var _pan := Vector2.ZERO
var _middle_drag := false
var _drag_last := Vector2.ZERO
var _icon_atlas: Texture2D
var _cleared: Dictionary = {}
var _fog_of_war := false
var _floor_number := 0

const COLOR_STAIRS_OUTLINE := Color(0.95, 0.78, 0.28, 0.9)
const COLOR_FLOOR_LABEL := Color(0.88, 0.85, 0.78, 0.95)

## HD-05: the Vigil arena has no room graph, so it gets a radar draw path instead of the dungeon
## one -- arena bounds, the player arrow (already works unmodified, it only needs `_bounds`), a
## dot per live enemy in the health-bar red, and a pulsing dot per pending spawn in the telegraph
## amber. Reuses `_map_point()` by pointing `_bounds` at a fixed square instead of the graph's.
var _radar_mode := false
var _radar_spawn_markers: Array[Node3D] = []
var _radar_pulse := 0.0
const COLOR_RADAR_BOUNDS := Color(0.35, 0.33, 0.30, 0.7)
const COLOR_RADAR_ENEMY := Color(0.71, 0.17, 0.19, 1.0)
const COLOR_RADAR_SPAWN := Color(0.98, 0.68, 0.20, 1.0)
const RADAR_ENEMY_DOT := 2.5
const RADAR_SPAWN_DOT := 3.0


func configure(definition: Dictionary) -> void:
	_rooms = definition.get("rooms", [])
	_edges = definition.get("edges", [])
	_branch_previews = definition.get("branchPreviews", [])
	_reveal.clear()
	_cleared.clear()
	_current_room_id = ""
	_build_caches()
	_recompute_bounds()
	queue_redraw()


## HD-05: switches the minimap into arena-radar mode -- no room graph, just a fixed square of
## `half_extent` world units centred on the origin (the Vigil arena is centred there).
func enable_radar_mode(half_extent: float) -> void:
	_radar_mode = true
	_rooms = []
	_edges = []
	_branch_previews = []
	_bounds = Rect2(-half_extent, -half_extent, half_extent * 2.0, half_extent * 2.0)
	queue_redraw()


func set_radar_spawn_markers(markers: Array) -> void:
	_radar_spawn_markers = []
	for marker in markers:
		if marker is Node3D and is_instance_valid(marker):
			_radar_spawn_markers.append(marker)
	queue_redraw()


## HD-10: shown in the map corner so the floor number is legible without opening the overlay.
func set_floor_number(floor_number: int) -> void:
	_floor_number = floor_number
	queue_redraw()


func has_graph() -> bool:
	return not _rooms.is_empty()


func mark_visited(room_id: String) -> void:
	if room_id == "":
		return
	_reveal[room_id] = RevealTier.VISITED
	for neighbor in _neighbors.get(room_id, []):
		if get_reveal_tier(neighbor) < RevealTier.SEEN:
			_reveal[neighbor] = RevealTier.SEEN
	queue_redraw()


func set_current_room(room_id: String) -> void:
	_current_room_id = room_id
	queue_redraw()


func bind_player(player: Node3D) -> void:
	_player = player
	_last_player_pos = Vector3(INF, INF, INF)
	queue_redraw()


func get_reveal_tier(room_id: String) -> int:
	var tier := int(_reveal.get(room_id, RevealTier.UNKNOWN))
	if _fog_of_war and tier == RevealTier.SEEN:
		return RevealTier.UNKNOWN
	return tier


func mark_cleared(room_id: String) -> void:
	if room_id == "" or _cleared.has(room_id):
		return
	_cleared[room_id] = true
	queue_redraw()


func set_fog_of_war(enabled: bool) -> void:
	if _fog_of_war == enabled:
		return
	_fog_of_war = enabled
	queue_redraw()


func icon_cell_for_kind(kind: String) -> Vector2i:
	return KIND_CELLS.get(kind, KIND_CELLS["unknown"])


func export_state() -> Dictionary:
	return {
		"definition":
		{
			"rooms": _rooms,
			"edges": _edges,
			"branchPreviews": _branch_previews,
		},
		"reveal": _reveal.duplicate(),
		"cleared": _cleared.duplicate(),
		"current_room_id": _current_room_id,
	}


func import_state(state: Dictionary) -> void:
	configure(state.get("definition", {}))
	_reveal = state.get("reveal", {}).duplicate()
	var cleared: Variant = state.get("cleared", {})
	_cleared = (cleared as Dictionary).duplicate() if cleared is Dictionary else {}
	_current_room_id = str(state.get("current_room_id", ""))
	queue_redraw()


func enable_overlay_mode() -> void:
	_overlay_mode = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_STOP
	_zoom = 1.0
	_pan = Vector2.ZERO
	queue_redraw()


func _ready() -> void:
	if not _overlay_mode:
		custom_minimum_size = HUD_SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_atlas = load(ICON_ATLAS_PATH) as Texture2D


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(is_visible_in_tree())


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		set_process(false)
		return
	if _overlay_mode:
		_apply_stick_pan(delta)
	if _radar_mode:
		_radar_pulse = fmod(_radar_pulse + delta * 0.8, 1.0)
		queue_redraw()
		return
	if _player == null or not is_instance_valid(_player):
		return
	_redraw_timer += delta
	if _redraw_timer < 0.1:
		return
	_redraw_timer = 0.0
	var pos := _player.global_position
	if _last_player_pos.distance_squared_to(pos) > 0.0625:
		_last_player_pos = pos
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _overlay_mode:
		return
	if event.is_action_pressed("ui_page_next"):
		_apply_zoom(1.1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_page_prev"):
		_apply_zoom(1.0 / 1.1)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = clampf(_zoom * 1.1, ZOOM_MIN, ZOOM_MAX)
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = clampf(_zoom / 1.1, ZOOM_MIN, ZOOM_MAX)
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_middle_drag = mb.pressed
			_drag_last = mb.position
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _middle_drag:
		var motion := event as InputEventMouseMotion
		_pan += motion.position - _drag_last
		_drag_last = motion.position
		queue_redraw()
		get_viewport().set_input_as_handled()


func _apply_zoom(factor: float) -> void:
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	queue_redraw()


func _apply_stick_pan(delta: float) -> void:
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length_squared() < 0.04:
		return
	_pan -= stick * STICK_PAN_SPEED * delta
	queue_redraw()


func _draw() -> void:
	if _radar_mode:
		var radar_rect := _content_rect()
		draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.18, 0.16), false, 1.0)
		_draw_radar(radar_rect)
		_draw_player_marker(radar_rect)
		return
	if _rooms.is_empty():
		return
	var map_rect := _content_rect()
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.18, 0.16), false, 1.0)
	_draw_edges(map_rect)
	_draw_rooms(map_rect)
	_draw_stairs_outline(map_rect)
	_draw_branch_previews(map_rect)
	_draw_player_marker(map_rect)
	_draw_floor_number()
	if _overlay_mode:
		_draw_legend()


func _content_rect() -> Rect2:
	if _overlay_mode:
		return Rect2(PADDING, PADDING, size.x - PADDING * 2.0, size.y - PADDING * 2.0 - 32.0)
	return Rect2(PADDING, PADDING, size.x - PADDING * 2.0, size.y - PADDING * 2.0)


func _draw_edges(map_rect: Rect2) -> void:
	for edge in _edges:
		if not edge is Dictionary:
			continue
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		if not _should_draw_edge(from_id, to_id):
			continue
		var from_pos := _room_center(from_id)
		var to_pos := _room_center(to_id)
		if from_pos == Vector2.INF or to_pos == Vector2.INF:
			continue
		var a := _map_point(from_pos, map_rect)
		var b := _map_point(to_pos, map_rect)
		var dashed := (
			get_reveal_tier(from_id) == RevealTier.SEEN
			or get_reveal_tier(to_id) == RevealTier.SEEN
		)
		if dashed:
			draw_dashed_line(a, b, COLOR_EDGE, 1.0, 4.0, true)
		else:
			draw_line(a, b, COLOR_EDGE, 1.0)
		_draw_one_way_chevron(edge, from_id, to_id, a, b)


## RM-04: a chevron toward whichever end is actually approachable -- the open side of a barred
## gate, or the lower room of a "down"-only drop -- instead of a plain line for both. `edges`
## carries `oneWay` (see `DungeonProcgen._annotate_one_way_edges` for "gate",
## `RoomGraphGeometry.build_edges` for "down"); everything else about the line is unchanged.
func _draw_one_way_chevron(
	edge: Dictionary, from_id: String, to_id: String, a: Vector2, b: Vector2
) -> void:
	var one_way := str(edge.get("oneWay", ""))
	if one_way == "":
		return
	var point_to_b := true
	if one_way == "gate":
		var open_room := str(edge.get("openRoomId", ""))
		point_to_b = open_room == to_id or open_room != from_id
	elif one_way == "down":
		var from_height := _room_height_level(from_id)
		var to_height := _room_height_level(to_id)
		point_to_b = to_height < from_height
	else:
		return
	var tip := b if point_to_b else a
	var tail := a if point_to_b else b
	var dir := (tip - tail).normalized()
	if dir == Vector2.ZERO:
		return
	var mid := (a + b) * 0.5
	var perp := Vector2(-dir.y, dir.x)
	var chevron_size := 3.5
	var points := PackedVector2Array(
		[
			mid + dir * chevron_size,
			mid - dir * chevron_size + perp * chevron_size,
			mid - dir * chevron_size - perp * chevron_size,
		]
	)
	draw_colored_polygon(points, COLOR_ONE_WAY)


func _room_height_level(room_id: String) -> int:
	for room_def in _rooms:
		if not room_def is Dictionary:
			continue
		if str((room_def as Dictionary).get("id", "")) == room_id:
			return int((room_def as Dictionary).get("heightLevel", 0))
	return 0


func _draw_rooms(map_rect: Rect2) -> void:
	for room_def in _rooms:
		if not room_def is Dictionary:
			continue
		var room_id := str(room_def.get("id", ""))
		var tier := get_reveal_tier(room_id)
		if tier == RevealTier.UNKNOWN:
			continue
		var center := _map_point(_room_center(room_id), map_rect)
		var room_px := _room_pixel_size(room_def, map_rect)
		var rect := Rect2(center - room_px * 0.5, room_px)
		var fill := COLOR_VISITED
		if _cleared.has(room_id):
			fill = COLOR_CLEARED
		if room_id == _current_room_id:
			fill = COLOR_CURRENT
		if tier == RevealTier.SEEN:
			draw_rect(rect, COLOR_SEEN, false, 1.0)
		else:
			draw_rect(rect, fill)
		if tier >= RevealTier.VISITED:
			_draw_room_icon(room_def, center, _cleared.has(room_id))
			if bool(room_def.get("locked", false)):
				_draw_lock_mark(rect, str(room_def.get("lockColor", "")))
			var key_color := str(room_def.get("keyColor", ""))
			if key_color != "":
				_draw_key_room_mark(rect, key_color)


## HD-10: a persistent gold outline on the stairs room once seen -- separate from `COLOR_CURRENT`
## (which moves with the player) so the goal stays marked after you walk away from it.
func _draw_stairs_outline(map_rect: Rect2) -> void:
	for room_def in _rooms:
		if not room_def is Dictionary:
			continue
		if str(room_def.get("kind", "")) != "stairs":
			continue
		var room_id := str(room_def.get("id", ""))
		if get_reveal_tier(room_id) == RevealTier.UNKNOWN:
			continue
		var center := _map_point(_room_center(room_id), map_rect)
		var room_px := _room_pixel_size(room_def, map_rect)
		var rect := Rect2(center - room_px * 0.5, room_px).grow(1.0)
		draw_rect(rect, COLOR_STAIRS_OUTLINE, false, 1.5)
		return


## HD-10: the floor number in the minimap corner, so it reads without opening the map overlay.
func _draw_floor_number() -> void:
	if _floor_number <= 0:
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var text := "F%d" % _floor_number
	var pos := Vector2(PADDING + 2.0, PADDING + 9.0)
	draw_string(
		font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 0, 0, 0.85)
	)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLOR_FLOOR_LABEL)


func _draw_room_icon(room_def: Dictionary, center: Vector2, cleared: bool = false) -> void:
	if _icon_atlas == null:
		return
	var kind := str(room_def.get("kind", "unknown"))
	var cell: Vector2i = icon_cell_for_kind(kind)
	var region := Rect2(cell.x * ICON_CELL, cell.y * ICON_CELL, ICON_CELL, ICON_CELL)
	var dest := Rect2(center - Vector2(ICON_CELL, ICON_CELL) * 0.5, Vector2(ICON_CELL, ICON_CELL))
	var tint := CLEARED_TINT if cleared else Color.WHITE
	draw_texture_rect_region(_icon_atlas, dest, region, tint, false)


## RM-05: `color_id` is one of `FloorKeyring.COLOR_ORDER` ("red"/"blue"/"yellow") -- an empty or
## unrecognised id falls back to the old flat `COLOR_LOCKED`, which only happens for a definition
## generated before this field existed (an in-progress save from before this change).
func _lock_color(color_id: String) -> Color:
	if color_id == "" or not FloorKeyring.COLORS.has(color_id):
		return COLOR_LOCKED
	return FloorKeyring.COLORS[color_id]["tint"]


func _draw_lock_mark(rect: Rect2, color_id: String = "") -> void:
	var corner := Vector2(rect.position.x + rect.size.x - LOCK_MARK_HALF - 1.0, rect.position.y + LOCK_MARK_HALF + 1.0)
	draw_rect(
		Rect2(corner - Vector2(LOCK_MARK_HALF, LOCK_MARK_HALF), Vector2(LOCK_MARK_HALF, LOCK_MARK_HALF) * 2.0),
		_lock_color(color_id)
	)


## The key room's mark is hollow (outline only) rather than filled, so it never gets confused with
## the solid lock mark on the door it opens even though they share a colour on purpose.
func _draw_key_room_mark(rect: Rect2, color_id: String) -> void:
	var corner := Vector2(rect.position.x + LOCK_MARK_HALF + 1.0, rect.position.y + LOCK_MARK_HALF + 1.0)
	draw_rect(
		Rect2(corner - Vector2(LOCK_MARK_HALF, LOCK_MARK_HALF), Vector2(LOCK_MARK_HALF, LOCK_MARK_HALF) * 2.0),
		_lock_color(color_id),
		false,
		1.5
	)


func _draw_radar(map_rect: Rect2) -> void:
	var bounds_rect := Rect2(_map_point(_bounds.position, map_rect), _bounds.size * _uniform_scale(map_rect) * _zoom)
	draw_rect(bounds_rect, COLOR_RADAR_BOUNDS, false, 1.0)
	var pulse_scale := 1.0 + sin(_radar_pulse * TAU) * 0.35
	for marker in _radar_spawn_markers:
		if not is_instance_valid(marker):
			continue
		var point := _map_point(Vector2(marker.global_position.x, marker.global_position.z), map_rect)
		draw_circle(point, RADAR_SPAWN_DOT * pulse_scale, COLOR_RADAR_SPAWN)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not (enemy is Node3D) or not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and enemy.call("is_dead"):
			continue
		var point := _map_point(
			Vector2((enemy as Node3D).global_position.x, (enemy as Node3D).global_position.z), map_rect
		)
		draw_circle(point, RADAR_ENEMY_DOT, COLOR_RADAR_ENEMY)


func _draw_player_marker(map_rect: Rect2) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var center := _map_point(
		Vector2(_player.global_position.x, _player.global_position.z), map_rect
	)
	var yaw := _player.global_rotation.y
	var half := PLAYER_ARROW_HALF
	var tip := center + Vector2(0.0, -half).rotated(-yaw)
	var left := center + Vector2(-half * 0.6, half * 0.55).rotated(-yaw)
	var right := center + Vector2(half * 0.6, half * 0.55).rotated(-yaw)
	draw_colored_polygon(
		PackedVector2Array([tip.floor(), left.floor(), right.floor()]), COLOR_PLAYER
	)


func _draw_legend() -> void:
	if _icon_atlas == null:
		return
	var font := ThemeDB.fallback_font
	var font_size := ThemeDB.fallback_font_size
	var row_height := float(ICON_CELL) + 6.0
	var y := size.y - 24.0
	var x := 12.0
	for entry in LEGEND_ENTRIES:
		var kind: String = entry.get("kind", "unknown")
		var cell: Vector2i = icon_cell_for_kind(kind)
		var region := Rect2(cell.x * ICON_CELL, cell.y * ICON_CELL, ICON_CELL, ICON_CELL)
		var label := tr(str(entry.get("label_key", "")))
		var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var entry_width := ICON_CELL + 4.0 + label_width + 14.0
		if x > 12.0 and x + entry_width > size.x - 12.0:
			x = 12.0
			y -= row_height
		var icon_rect := Rect2(x, y, ICON_CELL, ICON_CELL)
		draw_texture_rect_region(_icon_atlas, icon_rect, region, Color.WHITE, false)
		draw_string(font, Vector2(x + ICON_CELL + 4.0, y + ICON_CELL - 1.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		x += entry_width


func _build_caches() -> void:
	_room_by_id.clear()
	_center_by_id.clear()
	_neighbors.clear()
	for room_def in _rooms:
		if not room_def is Dictionary:
			continue
		var room_id := str(room_def.get("id", ""))
		if room_id == "":
			continue
		_room_by_id[room_id] = room_def
		var t: Dictionary = room_def.get("transform", {})
		_center_by_id[room_id] = Vector2(float(t.get("x", 0.0)), float(t.get("z", 0.0)))
	for edge in _edges:
		if not edge is Dictionary:
			continue
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		if from_id == "" or to_id == "":
			continue
		if not _neighbors.has(from_id):
			_neighbors[from_id] = []
		if not _neighbors.has(to_id):
			_neighbors[to_id] = []
		_neighbors[from_id].append(to_id)
		_neighbors[to_id].append(from_id)


func _recompute_bounds() -> void:
	if _rooms.is_empty():
		_bounds = Rect2()
		return
	var first := true
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
		if first:
			min_x = x
			max_x = x
			min_z = z
			max_z = z
			first = false
		else:
			min_x = minf(min_x, x)
			max_x = maxf(max_x, x)
			min_z = minf(min_z, z)
			max_z = maxf(max_z, z)
	_bounds = Rect2(min_x, min_z, maxf(1.0, max_x - min_x), maxf(1.0, max_z - min_z))


func _room_center(room_id: String) -> Vector2:
	if _center_by_id.has(room_id):
		return _center_by_id[room_id]
	return Vector2.INF


func _uniform_scale(map_rect: Rect2) -> float:
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		return 1.0
	return minf(map_rect.size.x / _bounds.size.x, map_rect.size.y / _bounds.size.y)


func _map_point(world_xz: Vector2, map_rect: Rect2) -> Vector2:
	if world_xz == Vector2.INF:
		return Vector2.ZERO
	var s := _uniform_scale(map_rect) * _zoom
	var content_size := _bounds.size * s
	var offset := map_rect.position + (map_rect.size - content_size) * 0.5 + _pan
	return (offset + (world_xz - _bounds.position) * s).floor()


func _room_pixel_size(room_def: Dictionary, map_rect: Rect2) -> Vector2:
	var size_def: Dictionary = room_def.get("size", {})
	var world_w := float(size_def.get("x", 0.0))
	var world_z := float(size_def.get("z", 0.0))
	if world_w <= 0.0 or world_z <= 0.0:
		return Vector2(FALLBACK_ROOM_PX, FALLBACK_ROOM_PX)
	var s := _uniform_scale(map_rect) * _zoom
	return Vector2(maxf(4.0, world_w * s), maxf(4.0, world_z * s)).floor()


func _should_draw_edge(from_id: String, to_id: String) -> bool:
	return (
		get_reveal_tier(from_id) >= RevealTier.SEEN
		and get_reveal_tier(to_id) >= RevealTier.SEEN
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
		if to_id == "" or get_reveal_tier(to_id) >= RevealTier.VISITED:
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
				PackedVector2Array(
					[
						(center + Vector2(0.0, -half)).floor(),
						(center + Vector2(half, 0.0)).floor(),
						(center + Vector2(0.0, half)).floor(),
						(center + Vector2(-half, 0.0)).floor(),
					]
				),
				Color(0.9, 0.22, 0.15, 0.95)
			)
