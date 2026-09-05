class_name TalentTreeGraph
extends Control

## UX-01: draws the talent tree as an actual tree -- one column per branch, `requires` edges as
## lines between cells, keyboard/pad navigation that walks the graph instead of a flat index.
## `talents_ui.gd` owns all game-state reads (ranks, planning, lock reasons); this node only owns
## layout, drawing and focus geometry, and reports back through signals + a state-provider
## callback so it never has to know about ProgressionService itself.

signal node_activated(node_id: String)
signal node_focus_changed(node_id: String)

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

const COLUMN_WIDTH := 168.0
const ROW_HEIGHT := 104.0
const SIBLING_GAP := 96.0
const CELL_SIZE := Vector2(140.0, 78.0)
const TOP_MARGIN := 24.0
const LEFT_MARGIN := 24.0

const EDGE_COLOR := Color(0.55, 0.42, 0.78, 0.85)
const EDGE_COLOR_LOCKED := Color(0.45, 0.30, 0.72, 0.28)
const EDGE_WIDTH := 3.0

## Per-node visual state the owner recomputes on every refresh and hands back in here, keyed by
## node id: {"rank": int, "max_rank": int, "planned": int, "can_unlock": bool, "can_plan": bool,
## "locked_reason": String, "keystone": bool, "label": String}.
var _state: Dictionary = {}
var _branches: Array[Dictionary] = []
var _node_positions: Dictionary = {}
var _node_parent_of: Dictionary = {}
var _edges: Array = []
var _cells: Dictionary = {}
var _focused_id := ""


func set_tree(branches: Array[Dictionary]) -> void:
	_branches = branches
	_layout()
	_rebuild_cells()
	if _focused_id == "" or not _node_positions.has(_focused_id):
		_focused_id = _first_node_id()
	_apply_states()
	queue_redraw()


## `state_by_id` is {node_id: Dictionary} as described above. Cheap to call every refresh -- it
## only recolors existing cells, it does not rebuild the layout.
func refresh_state(state_by_id: Dictionary) -> void:
	_state = state_by_id
	_apply_states()
	queue_redraw()


func focused_node_id() -> String:
	return _focused_id


func focus_node(node_id: String) -> void:
	if not _node_positions.has(node_id):
		return
	_focused_id = node_id
	_apply_states()
	node_focus_changed.emit(_focused_id)
	_scroll_to_focused()
	queue_redraw()


func activate_focused() -> void:
	if _focused_id != "":
		node_activated.emit(_focused_id)


func move_focus(dir: Vector2i) -> void:
	var next_id := _neighbor_in_direction(Vector2(dir.x, dir.y))
	if next_id != "":
		focus_node(next_id)


func _first_node_id() -> String:
	for branch in _branches:
		for node in branch.get("nodes", []):
			if node is Dictionary:
				return str((node as Dictionary).get("id", ""))
	return ""


## Row = 1 + the deepest `requires` parent within the same branch (0 for a root node). Nodes that
## land on the same row under the same parent are spread as siblings around the branch column's
## centerline, which is exactly what the tree content actually looks like (three linear nodes,
## then a pair of exclusive keystones side by side).
func _layout() -> void:
	_node_positions.clear()
	_node_parent_of.clear()
	_edges.clear()
	var col_index := 0
	for branch in _branches:
		if not branch is Dictionary:
			continue
		var nodes: Array = (branch as Dictionary).get("nodes", [])
		var by_id: Dictionary = {}
		for node in nodes:
			if node is Dictionary:
				by_id[str((node as Dictionary).get("id", ""))] = node
		var depth: Dictionary = {}
		for node_id in by_id:
			_compute_depth(node_id, by_id, depth)
		var rows: Dictionary = {}
		for node_id in by_id:
			var d: int = int(depth.get(node_id, 0))
			var bucket: Array = rows.get(d, [])
			bucket.append(node_id)
			rows[d] = bucket
		var col_x := LEFT_MARGIN + float(col_index) * COLUMN_WIDTH
		for d in rows:
			var bucket: Array = rows[d]
			var count := bucket.size()
			for i in count:
				var offset := (float(i) - float(count - 1) * 0.5) * SIBLING_GAP
				var pos := Vector2(col_x + offset, TOP_MARGIN + float(d) * ROW_HEIGHT)
				_node_positions[bucket[i]] = pos
		for node_id in by_id:
			var reqs: Array = (by_id[node_id] as Dictionary).get("requires", [])
			for req in reqs:
				var parent_id := str(req)
				if by_id.has(parent_id):
					_edges.append([parent_id, node_id])
					_node_parent_of[node_id] = parent_id
		col_index += 1


func _compute_depth(node_id: String, by_id: Dictionary, depth: Dictionary) -> int:
	if depth.has(node_id):
		return int(depth[node_id])
	var node: Dictionary = by_id.get(node_id, {})
	var reqs: Array = node.get("requires", [])
	var d := 0
	for req in reqs:
		var parent_id := str(req)
		if by_id.has(parent_id):
			d = maxi(d, 1 + _compute_depth(parent_id, by_id, depth))
	depth[node_id] = d
	return d


func _rebuild_cells() -> void:
	for child in get_children():
		child.queue_free()
	_cells.clear()
	var max_pos := Vector2.ZERO
	for node_id in _node_positions:
		var pos: Vector2 = _node_positions[node_id]
		max_pos = Vector2(maxf(max_pos.x, pos.x), maxf(max_pos.y, pos.y))
	custom_minimum_size = Vector2(
		max_pos.x + CELL_SIZE.x * 0.5 + LEFT_MARGIN, max_pos.y + CELL_SIZE.y + TOP_MARGIN
	)
	for branch in _branches:
		if not branch is Dictionary:
			continue
		for node in (branch as Dictionary).get("nodes", []):
			if not node is Dictionary:
				continue
			var node_id: String = str((node as Dictionary).get("id", ""))
			if not _node_positions.has(node_id):
				continue
			_make_cell(node_id, node)


func _make_cell(node_id: String, node: Dictionary) -> void:
	var frame := GameUISkinScript.make_pixel_frame("")
	frame.name = "Node_%s" % node_id
	frame.custom_minimum_size = CELL_SIZE
	frame.size = CELL_SIZE
	var pos: Vector2 = _node_positions[node_id]
	frame.position = pos - CELL_SIZE * 0.5
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.focus_mode = Control.FOCUS_NONE
	add_child(frame)
	var content := GameUISkinScript.pixel_frame_content(frame)
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = str(node.get("name", node_id))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(name_label)
	content.add_child(name_label)
	var pip_row := HBoxContainer.new()
	pip_row.name = "PipRow"
	pip_row.add_theme_constant_override("separation", 3)
	content.add_child(pip_row)
	var max_rank := int(node.get("maxRank", 1))
	for i in max_rank:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(10, 6)
		pip.color = GameUISkinScript.FRAME_BEVEL_DARK
		pip_row.add_child(pip)
	var lock_label := Label.new()
	lock_label.name = "LockLabel"
	lock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_hint_label(lock_label)
	content.add_child(lock_label)
	frame.gui_input.connect(_on_cell_gui_input.bind(node_id))
	frame.mouse_entered.connect(_on_cell_mouse_entered.bind(node_id))
	_cells[node_id] = frame


func _on_cell_gui_input(event: InputEvent, node_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		focus_node(node_id)
		node_activated.emit(node_id)
		accept_event()


func _on_cell_mouse_entered(node_id: String) -> void:
	focus_node(node_id)


func _apply_states() -> void:
	for node_id in _cells:
		var frame: PanelContainer = _cells[node_id]
		var info: Dictionary = _state.get(node_id, {})
		var rank := int(info.get("rank", 0))
		var planned := int(info.get("planned", 0))
		var can_unlock := bool(info.get("can_unlock", false))
		var can_plan := bool(info.get("can_plan", false))
		var locked_reason: String = str(info.get("locked_reason", ""))
		var keystone := bool(info.get("keystone", false))
		var content := GameUISkinScript.pixel_frame_content(frame)
		var name_label := content.get_node_or_null("NameLabel") as Label
		var pip_row := content.get_node_or_null("PipRow") as HBoxContainer
		var lbl := content.get_node_or_null("LockLabel") as Label
		if pip_row:
			for i in pip_row.get_child_count():
				var pip := pip_row.get_child(i) as ColorRect
				if pip == null:
					continue
				if i < rank:
					pip.color = GameUISkinScript.GOLD
				elif i < rank + planned:
					pip.color = Color(0.42, 0.70, 0.92, 1.0)
				else:
					pip.color = GameUISkinScript.FRAME_BEVEL_DARK
		if lbl:
			lbl.text = locked_reason
			lbl.visible = locked_reason != ""
		var tint := Color(1, 1, 1, 1)
		if rank > 0:
			tint = Color(1.0, 0.95, 0.78, 1.0)
		if planned > 0:
			tint = Color(0.72, 0.88, 1.0, 1.0)
		if not can_unlock and not can_plan and rank <= 0:
			tint = Color(0.5, 0.5, 0.55, 0.75)
		if node_id == _focused_id:
			tint = tint.lightened(0.15)
		frame.modulate = tint
		if name_label and keystone:
			name_label.text = "◆ %s" % str(info.get("label", name_label.text))
	queue_redraw()


func _draw() -> void:
	for edge in _edges:
		var from_id: String = edge[0]
		var to_id: String = edge[1]
		if not _node_positions.has(from_id) or not _node_positions.has(to_id):
			continue
		var from_pos: Vector2 = _node_positions[from_id] + Vector2(0, CELL_SIZE.y * 0.5)
		var to_pos: Vector2 = _node_positions[to_id] - Vector2(0, CELL_SIZE.y * 0.5)
		var from_info: Dictionary = _state.get(from_id, {})
		var to_info: Dictionary = _state.get(to_id, {})
		var lit := int(from_info.get("rank", 0)) > 0 and (
			int(to_info.get("rank", 0)) > 0 or int(to_info.get("planned", 0)) > 0
		)
		draw_line(from_pos, to_pos, EDGE_COLOR if lit else EDGE_COLOR_LOCKED, EDGE_WIDTH, false)


func _are_connected(a: String, b: String) -> bool:
	for edge in _edges:
		if (edge[0] == a and edge[1] == b) or (edge[0] == b and edge[1] == a):
			return true
	return false


## Direction-aware nearest neighbor: candidates behind the requested direction are excluded,
## the rest are scored by how far off-axis they sit (favoring the straight line), and a node
## joined to the current one by a `requires` edge is strongly preferred over an equally-placed
## unconnected one -- so up/down walks the spine of a branch and left/right hops the fork or the
## next column, matching how the tree actually reads.
func _neighbor_in_direction(dir: Vector2) -> String:
	if _focused_id == "" or not _node_positions.has(_focused_id):
		return _first_node_id()
	var origin: Vector2 = _node_positions[_focused_id]
	var best_id := ""
	var best_score := INF
	for node_id in _node_positions:
		if node_id == _focused_id:
			continue
		var offset: Vector2 = _node_positions[node_id] - origin
		var axis: float = offset.dot(dir)
		if axis <= 1.0:
			continue
		var lateral: float = absf(offset.x * dir.y - offset.y * dir.x)
		var score := axis + lateral * 3.0
		if _are_connected(_focused_id, node_id):
			score *= 0.35
		if score < best_score:
			best_score = score
			best_id = node_id
	return best_id


func _scroll_to_focused() -> void:
	if not _node_positions.has(_focused_id):
		return
	var scroller := get_parent() as ScrollContainer
	if scroller == null:
		return
	var pos: Vector2 = _node_positions[_focused_id]
	var view := scroller.size
	var target := pos - view * 0.5
	scroller.scroll_horizontal = clampi(int(target.x), 0, maxi(0, int(size.x - view.x)))
	scroller.scroll_vertical = clampi(int(target.y), 0, maxi(0, int(size.y - view.y)))
