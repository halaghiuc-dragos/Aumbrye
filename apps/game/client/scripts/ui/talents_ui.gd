extends Control


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")

const MULTIPLIER_DAMAGE_STAT := "physicalDamage"

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
	var shell: Dictionary = MenuShellScript.build_modal(self, tr("TALENTS_TITLE"), 340.0, 230.0)
	var vbox: VBoxContainer = shell["content_vbox"]
	_points_label = Label.new()
	_points_label.name = "PointsLabel"
	GameUISkinScript.style_body_label(_points_label)
	vbox.add_child(_points_label)
	_node_list = ItemList.new()
	_node_list.custom_minimum_size = Vector2(560, 260)
	vbox.add_child(_node_list)
	_detail_label = Label.new()
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(_detail_label)
	vbox.add_child(_detail_label)
	MenuShellScript.add_hint(vbox, tr("TALENTS_HINT"))


func is_open() -> bool:
	return _open


func open_talents() -> void:
	move_to_front()
	_open = true
	visible = true
	_reload_nodes()
	_refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_talents() -> void:
	_open = false
	visible = false
	closed.emit()
	PlayerControls.capture_mouse_if_allowed()


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
	var tree := ProgressionService.get_available_talent_tree()
	for branch in tree.get("branches", []):
		if not branch is Dictionary:
			continue
		for node in branch.get("nodes", []):
			if node is Dictionary:
				var copy: Dictionary = node.duplicate()
				copy["branchName"] = branch.get("name", "")
				copy["branchNameKey"] = branch.get("nameKey", "")
				_nodes.append(copy)


func _refresh() -> void:
	_node_list.clear()
	for i in _nodes.size():
		var node := _nodes[i]
		var rank := ProgressionService.get_talent_rank(node.get("id", ""))
		var max_rank: int = int(node.get("maxRank", 1))
		var is_keystone := bool(node.get("keystone", false))
		var label := (
			"[%s] %s (%d/%d)"
			% [_branch_display_name(node), _talent_display_name(node), rank, max_rank]
		)
		if is_keystone:
			label = "◆ " + label
		var index := _node_list.add_item(label)
		if is_keystone:
			_node_list.set_item_custom_fg_color(index, GameUISkinScript.FOCUS_RING_COLOR)
	if _points_label:
		_points_label.text = tr("TALENTS_POINTS") % ProgressionService.get_available_talent_points()
	_cursor = clampi(_cursor, 0, maxi(0, _nodes.size() - 1))
	if _nodes.size() > 0:
		_node_list.select(_cursor)
	_update_detail()


func _update_detail() -> void:
	if _cursor < 0 or _cursor >= _nodes.size():
		_detail_label.text = ""
		return
	var node := _nodes[_cursor]
	var effect_lines: PackedStringArray = []
	for effect in node.get("effects", []):
		if not effect is Dictionary:
			continue
		var stat: String = str(effect.get("stat", ""))
		var value: float = float(effect.get("valuePerRank", 0.0))
		var line := ""
		if stat == MULTIPLIER_DAMAGE_STAT:
			line = "%+.0f%% %s" % [value * 100.0, Equipment.stat_display_name(stat)]
		else:
			line = Equipment.format_stat_line(stat, value)
		if line != "":
			effect_lines.append(line)
	var can := ProgressionService.can_unlock_talent(node.get("id", ""))
	var display_name: String = _talent_display_name(node)
	if bool(node.get("keystone", false)):
		display_name = "◆ %s" % display_name
	_detail_label.text = (
		"%s\n%s\n%s"
		% [
			display_name,
			", ".join(effect_lines),
			tr("TALENTS_CAN_UNLOCK") if can else tr("TALENTS_LOCKED"),
		]
	)


func _unlock_selected() -> void:
	if _cursor < 0 or _cursor >= _nodes.size():
		return
	var node_id: String = _nodes[_cursor].get("id", "")
	if ProgressionService.unlock_talent(node_id):
		InventoryService.apply_equipment_to_player_node(
			get_tree().get_first_node_in_group("player")
		)
		_refresh()


func _talent_display_name(node: Dictionary) -> String:
	return _localized_label(node.get("nameKey", ""), node.get("name", ""), node.get("id", ""))


func _branch_display_name(node: Dictionary) -> String:
	return _localized_label(node.get("branchNameKey", ""), node.get("branchName", ""), "")


func _localized_label(key: String, fallback: String, id_fallback: String) -> String:
	var lookup: String = str(key)
	if lookup != "":
		var translated := tr(lookup)
		if translated != lookup:
			return translated
	var name_text: String = str(fallback)
	if name_text != "":
		return name_text
	return str(id_fallback)
