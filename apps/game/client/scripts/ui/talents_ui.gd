extends Control

## Talent tree UI — spend points on level up (PROG-4.2 client).

signal closed

var _node_list: ItemList
var _detail_label: Label
var _points_label: Label
var _open := false
var _cursor := 0
var _nodes: Array[Dictionary] = []


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_reload_nodes()
	if ProgressionService:
		ProgressionService.progression_changed.connect(_refresh)


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -300
	panel.offset_top = -220
	panel.offset_right = 300
	panel.offset_bottom = 220
	add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	var title := Label.new()
	title.text = "Talents (K)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_points_label = Label.new()
	_points_label.name = "PointsLabel"
	vbox.add_child(_points_label)
	_node_list = ItemList.new()
	_node_list.custom_minimum_size = Vector2(520, 220)
	vbox.add_child(_node_list)
	_detail_label = Label.new()
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_detail_label)
	var hint := Label.new()
	hint.text = "Enter: unlock | Esc: close"
	vbox.add_child(hint)


func is_open() -> bool:
	return _open


func open_talents() -> void:
	_open = true
	visible = true
	_reload_nodes()
	_refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_talents() -> void:
	_open = false
	visible = false
	closed.emit()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("talents") and not _open:
		open_talents()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		close_talents()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_unlock_selected()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_cursor = maxi(0, _cursor - 1)
		_node_list.select(_cursor)
		_update_detail()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_cursor = mini(_nodes.size() - 1, _cursor + 1)
		_node_list.select(_cursor)
		_update_detail()
		get_viewport().set_input_as_handled()


func _reload_nodes() -> void:
	_nodes.clear()
	var tree := ProgressionService.get_talent_tree()
	for branch in tree.get("branches", []):
		if not branch is Dictionary:
			continue
		for node in branch.get("nodes", []):
			if node is Dictionary:
				var copy: Dictionary = node.duplicate()
				copy["branchName"] = branch.get("name", "")
				_nodes.append(copy)


func _refresh() -> void:
	_node_list.clear()
	for i in _nodes.size():
		var node := _nodes[i]
		var rank := ProgressionService.get_talent_rank(node.get("id", ""))
		var max_rank: int = int(node.get("maxRank", 1))
		_node_list.add_item(
			"[%s] %s (%d/%d)" % [node.get("branchName", ""), node.get("name", ""), rank, max_rank]
		)
	if _points_label:
		_points_label.text = "Points: %d" % ProgressionService.get_available_talent_points()
	_cursor = clampi(_cursor, 0, maxi(0, _nodes.size() - 1))
	if _nodes.size() > 0:
		_node_list.select(_cursor)
	_update_detail()


func _update_detail() -> void:
	if _cursor < 0 or _cursor >= _nodes.size():
		_detail_label.text = ""
		return
	var node := _nodes[_cursor]
	var stats: Dictionary = node.get("stats", {})
	var stat_lines: PackedStringArray = []
	for stat in stats:
		stat_lines.append("%s +%s" % [stat, stats[stat]])
	var can := ProgressionService.can_unlock_talent(node.get("id", ""))
	_detail_label.text = "%s\n%s\n%s" % [
		node.get("name", ""),
		", ".join(stat_lines),
		"Can unlock" if can else "Locked",
	]


func _unlock_selected() -> void:
	if _cursor < 0 or _cursor >= _nodes.size():
		return
	var node_id: String = _nodes[_cursor].get("id", "")
	if ProgressionService.unlock_talent(node_id):
		InventoryService.apply_equipment_to_player_node(get_tree().get_first_node_in_group("player"))
		_refresh()
