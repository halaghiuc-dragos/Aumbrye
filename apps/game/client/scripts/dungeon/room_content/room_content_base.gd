extends Node3D
class_name RoomContentBase


func configure(_entry: Dictionary, _definition: Dictionary) -> void:
	pass


## Chests this content spawned. The spawner registers them with the builder so their state is
## saved and restored with the floor.
func get_chests() -> Array[Node3D]:
	return []


func _content_root() -> Node3D:
	var props := get_parent().get_node_or_null("Props")
	return props as Node3D if props else get_parent() as Node3D


var _prepared_placements: Dictionary = {}


## Resolves and reserves an actual local placement before a content script creates world nodes.
## Optional content may deliberately use identity (root-local) fallback; required content is never
## allowed to masquerade as placed when its authored anchor is unavailable.
func prepare_placement(required: bool, index: int = 0, footprint_radius: float = 0.75) -> Dictionary:
	var placement := resolve_placement(index, required, footprint_radius)
	if bool(placement.get("ok", false)):
		_prepared_placements[index] = placement
	return placement


func resolve_placement(index: int = 0, required: bool = false, footprint_radius: float = 0.75) -> Dictionary:
	if _prepared_placements.has(index):
		return _prepared_placements[index] as Dictionary
	var root := _content_root()
	var reservations: Dictionary = root.get_meta("content_anchor_reservations", {}) as Dictionary
	var reservation_owner := str(get_instance_id())
	var marker := root.get_node_or_null("PropAnchor_%d" % index) as Node3D
	if marker and not _anchor_available(marker, reservations, reservation_owner, footprint_radius):
		marker = null
		for candidate in root.get_children():
			if candidate is Node3D and candidate.name.begins_with("PropAnchor_") and _anchor_available(candidate as Node3D, reservations, reservation_owner, footprint_radius):
				marker = candidate as Node3D
				break
	if marker == null and not required:
		# Identity is the only safe fallback transform: it is root-local rather than accidentally
		# inheriting a translated room/world position. It is named in the result so audits can tell
		# intentional fallback content from authored-anchor placement.
		return {"ok": true, "fallback": true, "anchor": "root_local", "transform": Transform3D.IDENTITY}
	if marker == null:
		return {"ok": false, "reason": "missing_or_reserved_anchor", "index": index}
	reservations[marker.name] = {"owner": reservation_owner, "radius": footprint_radius, "position": marker.position}
	root.set_meta("content_anchor_reservations", reservations)
	return {"ok": true, "fallback": false, "anchor": marker.name, "transform": marker.transform, "node": marker}


func _anchor_available(marker: Node3D, reservations: Dictionary, reservation_owner: String, radius: float) -> bool:
	if not reservations.has(marker.name):
		for existing in reservations.values():
			if not (existing is Dictionary):
				continue
			var existing_record := existing as Dictionary
			if str(existing_record.get("owner", "")) == reservation_owner:
				continue
			var existing_position: Variant = existing_record.get("position")
			if existing_position is Vector3 and marker.position.distance_to(existing_position as Vector3) < radius + float(existing_record.get("radius", 0.75)):
				return false
		return true
	var existing: Variant = reservations.get(marker.name)
	if existing is String:
		return str(existing) == reservation_owner
	if existing is Dictionary:
		return str((existing as Dictionary).get("owner", "")) == reservation_owner
	return false


func _anchor(index: int = 0) -> Node3D:
	var required := bool(get_meta("required_content", false))
	var placement := resolve_placement(index, required)
	var marker := placement.get("node") as Node3D
	if marker:
		return marker
	# Optional root-local fallback is explicit and cannot inherit a room's translated position.
	var fallback := Node3D.new()
	fallback.name = "RootLocalContentAnchor_%d" % index
	fallback.transform = placement.get("transform", Transform3D.IDENTITY) as Transform3D
	_content_root().add_child(fallback)
	return fallback


## Calls `on_entered` once, the first time the player walks into this room's interior (not the
## doorway), for content that starts something when the room is entered.
func watch_room_entry(on_entered: Callable) -> void:
	var room := get_parent() as RoomTemplate
	var blockout := room.get_blockout() if room != null and room.has_method("get_blockout") else null
	if blockout == null:
		return
	var area := Area3D.new()
	area.name = "EntryTrigger"
	area.collision_layer = 0
	area.collision_mask = 2
	add_child(area)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(
		maxf(1.0, blockout.room_width - CastleRoomConstants.DOOR_WIDTH),
		CastleRoomConstants.WALL_HEIGHT,
		maxf(1.0, blockout.room_depth - CastleRoomConstants.DOOR_WIDTH)
	)
	shape.shape = box
	shape.position = Vector3(0.0, CastleRoomConstants.WALL_HEIGHT * 0.5, 0.0)
	area.add_child(shape)
	area.body_entered.connect(
		func(body: Node3D) -> void:
			if body.is_in_group("player"):
				area.queue_free()
				on_entered.call(body),
		CONNECT_ONE_SHOT
	)
