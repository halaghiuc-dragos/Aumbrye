class_name RoomGraphDebug
extends RefCounted


static func print_graph(graph: RoomGraph) -> void:
	print(render_ascii(graph))


static func render_ascii(graph: RoomGraph) -> String:
	if graph == null or graph.config == null:
		return "<empty graph>"
	var config := graph.config
	var lines: PackedStringArray = []
	lines.append("=== Room Graph (Phase 1) ===")
	for y in config.grid_height:
		var row := ""
		var conn_row := ""
		for x in config.grid_width:
			var cell := Vector2i(x, y)
			var slot: RoomGraphSlot = graph.slots.get(cell) as RoomGraphSlot
			if slot == null:
				row += "   "
				conn_row += "   "
			else:
				row += " %s " % slot.type_letter()
				conn_row += _connection_glyph(slot)
		lines.append(row)
		lines.append(conn_row)
	(
		lines
		. append(
			(
				"Start=%s Boss=%s Treasure=%s Stairs=%s Secrets=%s"
				% [
					graph.start_id,
					graph.boss_id,
					graph.treasure_id,
					graph.stairs_id,
					",".join(graph.secret_ids),
				]
			)
		)
	)
	return "\n".join(lines)


static func _connection_glyph(slot: RoomGraphSlot) -> String:
	var north := "│" if slot.door_mask & RoomGraphSlot.DOOR_NORTH else " "
	var south := "│" if slot.door_mask & RoomGraphSlot.DOOR_SOUTH else " "
	var east := "─" if slot.door_mask & RoomGraphSlot.DOOR_EAST else " "
	var west := "─" if slot.door_mask & RoomGraphSlot.DOOR_WEST else " "
	return "%s%s%s" % [west, north if north != " " else south if south != " " else east, east]
