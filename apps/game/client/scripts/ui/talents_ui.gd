extends Control


## UX-01: the talent tree used to be a flat ItemList of "[Branch] Name (rank/max)" rows -- no way
## to see build shape or where a node leads. This draws the actual ten-branch tree via
## `TalentTreeGraph` (requires-edges, keystone forks) and adds a detail/preview pane.
##
## UX-02: adds a preview-before-spending workflow. Hovering/focusing a node shows the stat delta
## it would add. Nodes can be queued ("planned") without spending a point, and the queue is only
## committed to real talent points on an explicit confirm -- see `ProgressionService.plan_talent`
## / `commit_planned_talents`. A free respec is offered inside the grace window opened by
## `ProgressionService.is_talent_respec_free`.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const TalentTreeGraphScript := preload("res://scripts/ui/talent_tree_view.gd")

const MULTIPLIER_DAMAGE_STAT := "physicalDamage"

signal closed

var _open := false
var _graph: TalentTreeGraph
var _points_label: Label
var _detail_label: Label
var _preview_label: Label
var _plan_button: Button
var _clear_plan_button: Button
var _free_respec_button: Button
var _by_id: Dictionary = {}


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_open() -> bool:
	return _open


func open_talents() -> void:
	move_to_front()
	_build_ui_if_needed()
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if MenuStack:
		MenuStack.push(self)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_reload_nodes()
	_refresh()


func close_talents() -> void:
	if not _open:
		return
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if MenuStack:
		MenuStack.pop(self)
	else:
		PlayerControls.capture_mouse_if_allowed()
	closed.emit()


func _on_cancel_requested() -> void:
	close_talents()


func _build_ui_if_needed() -> void:
	if _graph != null and is_instance_valid(_graph):
		return
	for child in get_children():
		child.queue_free()
	GameUISkinScript.ensure_full_rect(self)
	var shell: Dictionary = MenuShellScript.build_modal(
		self, tr("TALENTS_TITLE"), GameUISkinScript.PANEL_HALF_W, GameUISkinScript.PANEL_HALF_H
	)
	var vbox: VBoxContainer = shell["content_vbox"]

	_points_label = Label.new()
	_points_label.name = "PointsLabel"
	GameUISkinScript.style_body_label(_points_label)
	vbox.add_child(_points_label)

	var split := HBoxContainer.new()
	split.name = "TalentsSplit"
	split.add_theme_constant_override("separation", GameUISkinScript.SECTION_SEPARATION)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(split)

	var tree_frame := GameUISkinScript.make_pixel_frame("Tree")
	tree_frame.name = "TreeFrame"
	tree_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_frame.size_flags_stretch_ratio = 2.6
	split.add_child(tree_frame)
	var scroller := ScrollContainer.new()
	scroller.name = "TreeScroll"
	scroller.custom_minimum_size = Vector2(700, 360)
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	GameUISkinScript.pixel_frame_content(tree_frame).add_child(scroller)
	_graph = TalentTreeGraphScript.new()
	_graph.name = "TalentTreeGraph"
	scroller.add_child(_graph)
	_graph.node_focus_changed.connect(_on_node_focus_changed)
	_graph.node_activated.connect(_on_node_activated)

	var detail_frame := GameUISkinScript.make_pixel_frame("Node")
	detail_frame.name = "DetailFrame"
	detail_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_frame.size_flags_stretch_ratio = 1.4
	split.add_child(detail_frame)
	var detail_vbox := GameUISkinScript.pixel_frame_content(detail_frame)
	_detail_label = Label.new()
	_detail_label.name = "DetailLabel"
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(_detail_label)
	detail_vbox.add_child(_detail_label)
	_preview_label = Label.new()
	_preview_label.name = "PreviewLabel"
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_stat_delta(_preview_label, true)
	detail_vbox.add_child(_preview_label)

	var button_row := HBoxContainer.new()
	button_row.name = "ButtonRow"
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 12)
	vbox.add_child(button_row)
	_plan_button = MenuShellScript.make_menu_button(tr("TALENTS_QUEUE"), _on_plan_pressed)
	button_row.add_child(_plan_button)
	var commit_button := MenuShellScript.make_menu_button(tr("TALENTS_COMMIT"), _on_commit_pressed)
	button_row.add_child(commit_button)
	_clear_plan_button = MenuShellScript.make_menu_button(
		tr("TALENTS_CLEAR_PLAN"), _on_clear_plan_pressed
	)
	button_row.add_child(_clear_plan_button)
	_free_respec_button = MenuShellScript.make_menu_button(
		tr("TALENTS_FREE_RESPEC"), _on_free_respec_pressed
	)
	button_row.add_child(_free_respec_button)
	var close_btn := MenuShellScript.make_menu_button(tr("UI_CLOSE"), close_talents)
	button_row.add_child(close_btn)

	MenuShellScript.add_hint(vbox, tr("TALENTS_HINT"))
	GameUISkinScript.apply_pixel_theme(self)
	if ProgressionService and not ProgressionService.progression_changed.is_connected(_refresh):
		ProgressionService.progression_changed.connect(_refresh)
	if ProgressionService and not ProgressionService.talent_plan_changed.is_connected(_refresh):
		ProgressionService.talent_plan_changed.connect(_refresh)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("talents") and not _open:
		open_talents()
		get_viewport().set_input_as_handled()
		return
	if not _open or (MenuStack != null and not MenuStack.handles_cancel(self)):
		return
	if event.is_action_pressed("ui_accept"):
		_on_node_activated(_graph.focused_node_id())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_graph.move_focus(Vector2i(0, -1))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_graph.move_focus(Vector2i(0, 1))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_graph.move_focus(Vector2i(-1, 0))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_graph.move_focus(Vector2i(1, 0))
		get_viewport().set_input_as_handled()
	elif MenuStack == null and event.is_action_pressed("ui_cancel"):
		close_talents()
		get_viewport().set_input_as_handled()


func _reload_nodes() -> void:
	_by_id.clear()
	var tree := ProgressionService.get_available_talent_tree()
	var branches: Array[Dictionary] = []
	for branch in tree.get("branches", []):
		if not branch is Dictionary:
			continue
		branches.append(branch)
		for node in (branch as Dictionary).get("nodes", []):
			if node is Dictionary:
				var copy: Dictionary = (node as Dictionary).duplicate()
				copy["branchName"] = (branch as Dictionary).get("name", "")
				copy["branchNameKey"] = (branch as Dictionary).get("nameKey", "")
				_by_id[str(copy.get("id", ""))] = copy
	_graph.set_tree(branches)


func _refresh() -> void:
	if _graph == null:
		return
	var state: Dictionary = {}
	for node_id in _by_id:
		var node: Dictionary = _by_id[node_id]
		state[node_id] = {
			"rank": ProgressionService.get_talent_rank(node_id),
			"max_rank": int(node.get("maxRank", 1)),
			"planned": ProgressionService.get_planned_rank(node_id),
			"can_unlock": ProgressionService.can_unlock_talent(node_id),
			"can_plan": ProgressionService.can_plan_talent(node_id),
			"locked_reason": _locked_reason(node_id, node),
			"keystone": bool(node.get("keystone", false)),
			"label": _talent_display_name(node),
		}
	_graph.refresh_state(state)
	if _points_label:
		var planned_cost := (
			ProgressionService.get_available_talent_points()
			- ProgressionService.get_talent_points_available_after_plan()
		)
		var text := tr("TALENTS_POINTS") % ProgressionService.get_available_talent_points()
		if planned_cost > 0:
			text += "  " + (tr("TALENTS_QUEUED_COST") % planned_cost)
		_points_label.text = text
	if _free_respec_button:
		_free_respec_button.visible = ProgressionService.is_talent_respec_free()
	if _clear_plan_button:
		_clear_plan_button.disabled = ProgressionService.get_planned_talents().is_empty()
	_update_detail(_graph.focused_node_id())


func _on_node_focus_changed(node_id: String) -> void:
	_update_detail(node_id)


func _on_node_activated(node_id: String) -> void:
	if node_id == "":
		return
	_graph.focus_node(node_id)
	_update_detail(node_id)


## UX-02: queues (or unqueues, if already queued) the focused node without spending anything.
func _on_plan_pressed() -> void:
	var node_id := _graph.focused_node_id() if _graph else ""
	if node_id == "":
		return
	if ProgressionService.get_planned_rank(node_id) > 0:
		ProgressionService.unplan_talent(node_id)
	else:
		ProgressionService.plan_talent(node_id)


## UX-02: spends real talent points for everything queued. Nothing before this point touched
## `talent_points_spent`.
func _on_commit_pressed() -> void:
	var result := ProgressionService.commit_planned_talents()
	if int(result.get("committed", 0)) > 0:
		InventoryService.apply_equipment_to_player_node(get_tree().get_first_node_in_group("player"))


func _on_clear_plan_pressed() -> void:
	ProgressionService.clear_planned_talents()


func _on_free_respec_pressed() -> void:
	ProgressionService.free_respec_talents()


func _locked_reason(node_id: String, node: Dictionary) -> String:
	if ProgressionService.get_effective_talent_rank(node_id) > 0:
		return ""
	var blocker := ProgressionService.blocked_by(node_id)
	if blocker != "":
		return tr("TALENTS_BLOCKED_BY") % _node_name_for_id(blocker)
	for req in node.get("requires", []):
		if ProgressionService.get_effective_talent_rank(str(req)) <= 0:
			return tr("TALENTS_LOCKED")
	return ""


func _update_detail(node_id: String) -> void:
	if node_id == "" or not _by_id.has(node_id):
		_detail_label.text = ""
		_preview_label.text = ""
		return
	var node: Dictionary = _by_id[node_id]
	var display_name: String = _talent_display_name(node)
	if bool(node.get("keystone", false)):
		display_name = "◆ %s" % display_name
	var lines: PackedStringArray = [display_name]
	var description: String = str(node.get("description", ""))
	if description != "":
		lines.append(description)
	var effect_lines: PackedStringArray = []
	for effect in node.get("effects", []):
		if not effect is Dictionary:
			continue
		var stat: String = str((effect as Dictionary).get("stat", ""))
		var value: float = float((effect as Dictionary).get("valuePerRank", 0.0))
		var line := ""
		if stat == MULTIPLIER_DAMAGE_STAT:
			line = "%+.0f%% %s" % [value * 100.0, Equipment.stat_display_name(stat)]
		else:
			line = Equipment.format_stat_line(stat, value)
		if line != "":
			effect_lines.append(line)
	var effects_line := ", ".join(effect_lines)
	if effects_line != "":
		lines.append(effects_line)
	lines.append_array(_exclusivity_lines(node, node_id))
	var rank := ProgressionService.get_talent_rank(node_id)
	var planned := ProgressionService.get_planned_rank(node_id)
	if planned > 0:
		lines.append(tr("TALENTS_QUEUED"))
	elif rank > 0:
		lines.append(tr("TALENTS_TAKEN"))
	elif ProgressionService.can_unlock_talent(node_id) or ProgressionService.can_plan_talent(node_id):
		lines.append(tr("TALENTS_CAN_UNLOCK"))
	else:
		lines.append(tr("TALENTS_LOCKED"))
	_detail_label.text = "\n".join(lines)
	_update_preview(node_id)


## UX-02: the stat delta the node would add if taken right now, diffed against the active build
## by `ProgressionService.preview_talent_delta` -- rendered as +X/-Y so the player can weigh a
## node before spending (or even queuing) a point on it.
func _update_preview(node_id: String) -> void:
	var deltas := ProgressionService.preview_talent_delta(node_id)
	if deltas.is_empty():
		_preview_label.text = ""
		return
	var parts: PackedStringArray = []
	var any_negative := false
	for stat in deltas:
		var value: float = float(deltas[stat])
		if value < 0.0:
			any_negative = true
		var line := ""
		if str(stat) == MULTIPLIER_DAMAGE_STAT:
			line = "%+.0f%% %s" % [value * 100.0, Equipment.stat_display_name(str(stat))]
		else:
			line = Equipment.format_stat_line(str(stat), value)
		if line != "":
			parts.append(line)
	GameUISkinScript.style_stat_delta(_preview_label, not any_negative)
	_preview_label.text = tr("TALENTS_PREVIEW") % ", ".join(parts)


## Paired keystones are the one real decision in the tree, so say out loud what taking one costs.
func _exclusivity_lines(node: Dictionary, node_id: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	var excludes: Variant = node.get("excludes", [])
	if not excludes is Array or (excludes as Array).is_empty():
		return lines
	var blocker := ProgressionService.blocked_by(node_id)
	if blocker != "":
		lines.append(tr("TALENTS_BLOCKED_BY") % _node_name_for_id(blocker))
		return lines
	var names: PackedStringArray = []
	for excluded in (excludes as Array):
		names.append(_node_name_for_id(str(excluded)))
	lines.append(tr("TALENTS_CLOSES_OFF") % ", ".join(names))
	return lines


func _node_name_for_id(node_id: String) -> String:
	if _by_id.has(node_id):
		return _talent_display_name(_by_id[node_id])
	return node_id


func _talent_display_name(node: Dictionary) -> String:
	return _localized_label(node.get("nameKey", ""), node.get("name", ""), node.get("id", ""))


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
