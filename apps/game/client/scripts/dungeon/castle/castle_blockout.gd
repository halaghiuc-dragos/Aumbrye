@tool
extends Node3D
class_name CastleBlockout

## RM-22: a room scene's authored `door_*` values and socket transforms are editor preview only.
## `DungeonBuilder._close_all_blockout_doors()` clears every door flag on every room at build time
## and `_open_blockout_door_toward()` re-opens exactly the ones the floor's room graph names, and
## `CastleRoomScene._ensure_socket_completeness()` recomputes every socket's position from the
## room's actual dimensions regardless of what a scene authored. The builder is authoritative;
## nothing a designer sets here survives past opening the scene standalone in the editor.

const NAV_CELL_SIZE := 0.25
const NAV_AGENT_HEIGHT := 1.8
const NAV_AGENT_RADIUS := 0.45

const CEILING_THICKNESS := 0.4
const RoomTemplateCatalogScript := preload("res://scripts/dungeon/procgen/room_template_catalog.gd")

## `RM-01`: rotunda and octagon wall segment counts. A round room still reserves a square footprint
## on the lattice (`RoomGraphLayout.footprint_cells()` is untouched) -- only the geometry built
## inside that square changes.
const ROUND_WALL_SEGMENTS := 24
const OCTAGON_WALL_SEGMENTS := 8
const CURVED_SEGMENT_OVERLAP := 0.06

@export var kind: StringName = &"":
	set(value):
		kind = value
		_request_rebuild()

## `RM-01`: `rect`, `round` or `octagon`. Only the geometry built *inside* the reserved square
## footprint changes -- the lattice, door sliding, loop scoring, overlap validation and the minimap
## all keep reading `room_width`/`room_depth` as a rectangle regardless of this. See
## `RoomTemplate.contains_world_point()`, which stays a rectangle test on purpose (Trap 1).
@export var shape: StringName = &"rect":
	set(value):
		shape = value
		_request_rebuild()

## RM-03: a biome layout variant's `"shape"` override, applied on top of the kind spec's own
## default every time `_apply_kind_spec()` runs -- setting `shape` directly does not survive the
## next `_rebuild()`, since that always re-derives it from the kind spec. Empty means "no override,
## use the kind's default shape".
@export var shape_override: StringName = &"":
	set(value):
		shape_override = value
		_request_rebuild()

@export var room_width: float = 16.0:
	set(value):
		room_width = maxf(value, CastleRoomConstants.GRID_UNIT)
		_request_rebuild()

@export var room_depth: float = 12.0:
	set(value):
		room_depth = maxf(value, CastleRoomConstants.GRID_UNIT)
		_request_rebuild()

@export var wall_height: float = CastleRoomConstants.WALL_HEIGHT:
	set(value):
		wall_height = maxf(value, CastleRoomConstants.DOOR_HEIGHT)
		_request_rebuild()

@export var door_north_offset: float = 0.0:
	set(value):
		door_north_offset = value
		_request_rebuild()

@export var door_south_offset: float = 0.0:
	set(value):
		door_south_offset = value
		_request_rebuild()

@export var door_east_offset: float = 0.0:
	set(value):
		door_east_offset = value
		_request_rebuild()

@export var door_west_offset: float = 0.0:
	set(value):
		door_west_offset = value
		_request_rebuild()

@export var door_north: bool = false:
	set(value):
		door_north = value
		_request_rebuild()

@export var door_south: bool = false:
	set(value):
		door_south = value
		_request_rebuild()

@export var door_east: bool = false:
	set(value):
		door_east = value
		_request_rebuild()

@export var door_west: bool = false:
	set(value):
		door_west = value
		_request_rebuild()

@export var floor_material: Material
@export var wall_material: Material
@export var accent_material: Material
@export var skip_floor: bool = false
@export var hide_walls: bool = false:
	set(value):
		hide_walls = value
		_request_rebuild()

## Off by default: a room's `Ceiling` StaticBody3D sat on `CombatLayers.WORLD`, the same layer
## `SpringArm3D.collision_mask` (see `orbit_camera.gd`) uses to keep the camera from clipping into
## geometry -- so every dungeon room fought the camera the moment a lock-on angle looked anywhere
## near it, unlike the open-air training platform (which was never built from `CastleBlockout` and
## so never had a `Ceiling` body to begin with). `WALL_HEIGHT` (6.0) is well above the player's max
## jump arc (~1.2m at `JUMP_VELOCITY` 4.8), so the walls alone still contain the room without it.
@export var build_ceiling: bool = false:
	set(value):
		build_ceiling = value
		_request_rebuild()

var _geometry_root: Node3D
var _cover_root: Node3D
var _walls_body: StaticBody3D
var _nav_region: NavigationRegion3D
var _nav_links: Array[NavigationLink3D] = []
var _cover_nodes: Array[Node3D] = []
var _pending_stairs: Array[Dictionary] = []
var _navigation_map: RID = RID()
var _geometry_dirty: bool = true
var _nav_bake_count: int = 0
var _applying_kind_spec := false
var _rebuild_queued := false


func _ready() -> void:
	_apply_kind_spec()
	_rebuild()
	if Engine.is_editor_hint():
		_verify_socket_positions()


## A blockout with no materials assigned builds its floors and walls in Godot's default grey.
##
## CastleRoomScene fills these in before the first build, so a room instanced the normal way is
## fine. A blockout dropped straight into a scene as a bare Node3D is not -- the two shortcut
## rooms in the castle slice are exactly that, and their walls, floor and ceiling came out grey.
## Falling back to the biome's own materials here means the geometry is skinned wherever it is
## built from, rather than only on the path that happens to remember.
func _ensure_materials() -> void:
	var biome_id := str(get_meta("biome_id", BiomeRegistry.BIOME_CASTLE))
	if floor_material == null:
		floor_material = BiomeRegistry.get_floor_material(biome_id)
	if wall_material == null:
		wall_material = BiomeRegistry.get_wall_material(biome_id)
	if accent_material == null:
		accent_material = BiomeRegistry.get_accent_material(biome_id)


## RM-22: closing all four doors and re-opening one is several `@export` setters firing in a row,
## each of which used to call `_rebuild()` synchronously -- six to eight rebuilds where one would
## do. Deferring through `call_deferred` and guarding on `_geometry_dirty` coalesces any number of
## setter calls within one frame into a single rebuild.
func _request_rebuild() -> void:
	if _applying_kind_spec:
		return
	_geometry_dirty = true
	if not is_inside_tree():
		return
	if Engine.is_editor_hint() and not _rebuild_queued:
		_rebuild_queued = true
		call_deferred("_deferred_rebuild")


func _deferred_rebuild() -> void:
	_rebuild_queued = false
	if not _geometry_dirty:
		return
	_rebuild()
	_build_navigation_mesh()


func finalize_geometry() -> void:
	if _geometry_dirty:
		_rebuild()
	_build_navigation_mesh()
	_geometry_dirty = false


func _rebuild() -> void:
	_ensure_materials()
	_apply_kind_spec()
	_clear_geometry_children()
	_geometry_root = Node3D.new()
	_geometry_root.name = "Geometry"
	add_child(_geometry_root)
	if Engine.is_editor_hint():
		_geometry_root.owner = get_tree().edited_scene_root
	_walls_body = null

	if shape == &"round" or shape == &"octagon":
		if not skip_floor:
			_build_curved_floor()
		_build_curved_perimeter(ROUND_WALL_SEGMENTS if shape == &"round" else OCTAGON_WALL_SEGMENTS)
		_build_pending_stairs()
		if build_ceiling:
			_build_curved_ceiling()
	else:
		if not skip_floor:
			if shape == &"split":
				_build_split_floor()
			else:
				_build_floor()
		_build_wall(
			Vector3(0.0, 0.0, -room_depth * 0.5),
			Vector3(room_width, wall_height, CastleRoomConstants.WALL_THICKNESS),
			door_north,
			true,
			door_north_offset
		)
		_build_wall(
			Vector3(0.0, 0.0, room_depth * 0.5),
			Vector3(room_width, wall_height, CastleRoomConstants.WALL_THICKNESS),
			door_south,
			true,
			door_south_offset
		)
		_build_wall(
			Vector3(room_width * 0.5, 0.0, 0.0),
			Vector3(CastleRoomConstants.WALL_THICKNESS, wall_height, room_depth),
			door_east,
			false,
			door_east_offset
		)
		_build_wall(
			Vector3(-room_width * 0.5, 0.0, 0.0),
			Vector3(CastleRoomConstants.WALL_THICKNESS, wall_height, room_depth),
			door_west,
			false,
			door_west_offset
		)
		_build_pending_stairs()
		if build_ceiling:
			_build_ceiling()
	_add_room_occluder()
	_geometry_dirty = false


func _clear_geometry_children() -> void:
	for child in get_children():
		if child.name == "CoverObstacles":
			continue
		if child.name == "Geometry" or child is NavigationRegion3D or child is NavigationLink3D:
			remove_child(child)
			child.free()
	_geometry_root = null
	_walls_body = null
	_nav_region = null
	_nav_links.clear()


func _ensure_cover_root() -> Node3D:
	if _cover_root != null and is_instance_valid(_cover_root):
		return _cover_root
	_cover_root = get_node_or_null("CoverObstacles") as Node3D
	if _cover_root == null:
		_cover_root = Node3D.new()
		_cover_root.name = "CoverObstacles"
		add_child(_cover_root)
		if Engine.is_editor_hint():
			_cover_root.owner = get_tree().edited_scene_root
	return _cover_root


func _create_walls_body() -> StaticBody3D:
	if _walls_body != null and is_instance_valid(_walls_body):
		return _walls_body
	_walls_body = StaticBody3D.new()
	_walls_body.name = "Walls"
	_walls_body.collision_layer = 1
	_walls_body.collision_mask = 0
	_geometry_root.add_child(_walls_body)
	if Engine.is_editor_hint():
		_walls_body.owner = get_tree().edited_scene_root
	return _walls_body


func _build_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	_geometry_root.add_child(floor_body)
	if Engine.is_editor_hint():
		floor_body.owner = get_tree().edited_scene_root

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(room_width, CastleRoomConstants.FLOOR_THICKNESS, room_depth)
	mesh_instance.mesh = box
	mesh_instance.position = Vector3(0.0, -CastleRoomConstants.FLOOR_THICKNESS * 0.5, 0.0)
	if floor_material:
		mesh_instance.material_override = floor_material
	floor_body.add_child(mesh_instance)
	if Engine.is_editor_hint():
		mesh_instance.owner = get_tree().edited_scene_root

	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	collision.shape = box_shape
	collision.position = mesh_instance.position
	floor_body.add_child(collision)
	if Engine.is_editor_hint():
		collision.owner = get_tree().edited_scene_root


## RM-19: `shape == &"split"` -- a balcony. The room's outer walls and doors are unchanged (a
## balcony is still a plain rectangular footprint); only the floor is built in two halves at
## different heights, with a railing along the seam. `BALCONY_RISE` matches
## `RoomGraphGeometry.HEIGHT_STEP` (both 3.0) on purpose -- the raised half reads as "the next
## height level", the same rise a real room-to-room height transition uses, not an arbitrary step.
const BALCONY_RISE := 3.0


func _build_split_floor() -> void:
	var half_w := room_width * 0.5
	var half_d := room_depth * 0.5
	_build_split_floor_half(
		Vector3(0.0, 0.0, -half_d * 0.5), Vector2(room_width, half_d), BALCONY_RISE, "FloorRaised"
	)
	_build_split_floor_half(Vector3(0.0, 0.0, half_d * 0.5), Vector2(room_width, half_d), 0.0, "Floor")
	_build_balcony_railing(half_w, BALCONY_RISE)


func _build_split_floor_half(center: Vector3, xz_size: Vector2, base_y: float, body_name: String) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = body_name
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	_geometry_root.add_child(floor_body)
	if Engine.is_editor_hint():
		floor_body.owner = get_tree().edited_scene_root
	var size := Vector3(xz_size.x, CastleRoomConstants.FLOOR_THICKNESS, xz_size.y)
	var local_pos := center + Vector3(0.0, base_y - CastleRoomConstants.FLOOR_THICKNESS * 0.5, 0.0)
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = local_pos
	if floor_material:
		mesh_instance.material_override = floor_material
	floor_body.add_child(mesh_instance)
	if Engine.is_editor_hint():
		mesh_instance.owner = get_tree().edited_scene_root
	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	collision.position = local_pos
	floor_body.add_child(collision)
	if Engine.is_editor_hint():
		collision.owner = get_tree().edited_scene_root


## Solid over most of the split edge so a player does not just wander off the raised half, with a
## door-width gap in the middle to walk (or deliberately drop) through -- the room-scale version of
## RM-04's "down" one-way drop-down.
func _build_balcony_railing(half_w: float, rise: float) -> void:
	var gap := CastleRoomConstants.DOOR_WIDTH
	var rail_height := 1.0
	var side_len := half_w - gap * 0.5
	if side_len <= 0.2:
		return
	var sides: Array[float] = [-1.0, 1.0]
	for side in sides:
		var seg_center_x: float = side * (gap * 0.5 + side_len * 0.5)
		_add_wall_segment(
			Vector3(seg_center_x, rise, 0.0),
			Vector3(side_len, rail_height, CastleRoomConstants.WALL_THICKNESS * 0.6),
			wall_material
		)


func _build_ceiling() -> void:
	var ceiling_body := StaticBody3D.new()
	ceiling_body.name = "Ceiling"
	ceiling_body.collision_layer = 1
	ceiling_body.collision_mask = 0
	_geometry_root.add_child(ceiling_body)
	if Engine.is_editor_hint():
		ceiling_body.owner = get_tree().edited_scene_root

	var size := Vector3(room_width, CEILING_THICKNESS, room_depth)
	var center_y := wall_height + CEILING_THICKNESS * 0.5
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = Vector3(0.0, center_y, 0.0)
	if wall_material:
		mesh_instance.material_override = wall_material
	ceiling_body.add_child(mesh_instance)
	if Engine.is_editor_hint():
		mesh_instance.owner = get_tree().edited_scene_root

	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	collision.position = mesh_instance.position
	ceiling_body.add_child(collision)
	if Engine.is_editor_hint():
		collision.owner = get_tree().edited_scene_root

	var occluder := OccluderInstance3D.new()
	occluder.name = "CeilingOccluder"
	var occluder_mesh := _make_box_occluder(size)
	occluder.occluder = occluder_mesh
	occluder.position = mesh_instance.position
	_geometry_root.add_child(occluder)
	if Engine.is_editor_hint():
		occluder.owner = get_tree().edited_scene_root


## `RM-01`: a `CylinderMesh` with `radial_segments` set to the wall segment count doubles as both
## the round floor and the octagon floor -- an octagon prism is just a very-low-poly cylinder, so
## one mesh covers the "PrismMesh-style fan" the action text asks for without a second code path.
func _curved_radius() -> float:
	return minf(room_width, room_depth) * 0.5


func _build_curved_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	_geometry_root.add_child(floor_body)
	if Engine.is_editor_hint():
		floor_body.owner = get_tree().edited_scene_root

	var segments := ROUND_WALL_SEGMENTS if shape == &"round" else OCTAGON_WALL_SEGMENTS
	var radius := _curved_radius()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = CastleRoomConstants.FLOOR_THICKNESS
	cyl.radial_segments = segments
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = cyl
	mesh_instance.position = Vector3(0.0, -CastleRoomConstants.FLOOR_THICKNESS * 0.5, 0.0)
	if floor_material:
		mesh_instance.material_override = floor_material
	floor_body.add_child(mesh_instance)
	if Engine.is_editor_hint():
		mesh_instance.owner = get_tree().edited_scene_root

	var collision := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = radius
	cyl_shape.height = CastleRoomConstants.FLOOR_THICKNESS
	collision.shape = cyl_shape
	collision.position = mesh_instance.position
	floor_body.add_child(collision)
	if Engine.is_editor_hint():
		collision.owner = get_tree().edited_scene_root


func _build_curved_ceiling() -> void:
	var ceiling_body := StaticBody3D.new()
	ceiling_body.name = "Ceiling"
	ceiling_body.collision_layer = 1
	ceiling_body.collision_mask = 0
	_geometry_root.add_child(ceiling_body)
	if Engine.is_editor_hint():
		ceiling_body.owner = get_tree().edited_scene_root

	var segments := ROUND_WALL_SEGMENTS if shape == &"round" else OCTAGON_WALL_SEGMENTS
	var radius := _curved_radius()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = CEILING_THICKNESS
	cyl.radial_segments = segments
	var center_y := wall_height + CEILING_THICKNESS * 0.5
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = cyl
	mesh_instance.position = Vector3(0.0, center_y, 0.0)
	if wall_material:
		mesh_instance.material_override = wall_material
	ceiling_body.add_child(mesh_instance)
	if Engine.is_editor_hint():
		mesh_instance.owner = get_tree().edited_scene_root

	var collision := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = radius
	cyl_shape.height = CEILING_THICKNESS
	collision.shape = cyl_shape
	collision.position = mesh_instance.position
	ceiling_body.add_child(collision)
	if Engine.is_editor_hint():
		collision.owner = get_tree().edited_scene_root


## Each active door gets a bearing (the angle on the circle its socket sits at, computed exactly
## from `RoomTemplateCatalog.socket_wall_position()` rather than the linear approximation the plan
## sketches -- Trap 2's actual failure mode is "doors cut in the wrong place", and going through the
## same socket helper the rectangular path already uses can't disagree with it about where the door
## is) and a half-angle (how much of the circle's circumference the doorway itself covers).
func _curved_doorways() -> Array:
	var radius := _curved_radius()
	var half_w := room_width * 0.5
	var half_d := room_depth * 0.5
	var half_door_angle := (CastleRoomConstants.DOOR_WIDTH * 0.5) / radius
	var doorways: Array = []
	var entries := [
		[door_north, CastleRoomConstants.Direction.NORTH, door_north_offset],
		[door_south, CastleRoomConstants.Direction.SOUTH, door_south_offset],
		[door_east, CastleRoomConstants.Direction.EAST, door_east_offset],
		[door_west, CastleRoomConstants.Direction.WEST, door_west_offset],
	]
	for entry in entries:
		if not bool(entry[0]):
			continue
		var direction: CastleRoomConstants.Direction = entry[1]
		var lateral: float = entry[2]
		var socket_pos := RoomTemplateCatalogScript.socket_wall_position(
			direction, half_w, half_d, lateral
		)
		var bearing := atan2(socket_pos.x, -socket_pos.z)
		doorways.append(
			{
				"direction": direction,
				"lateral": lateral,
				"bearing": bearing,
				"half_angle": half_door_angle,
			}
		)
	return doorways


func _angle_diff(a: float, b: float) -> float:
	var d := fmod(a - b + PI, TAU)
	if d < 0.0:
		d += TAU
	return d - PI


## Places `segment_count` tangent wall segments evenly around the circle, skipping any segment
## whose centre falls inside an active doorway's angular span, then builds a stub from each gap out
## to that doorway's rectangular socket (see `_build_curved_stub()`).
func _build_curved_perimeter(segment_count: int) -> void:
	var radius := _curved_radius()
	var seg_angle := TAU / float(segment_count)
	var doorways := _curved_doorways()
	var half_thickness := CastleRoomConstants.WALL_THICKNESS * 0.5
	var chord := 2.0 * radius * tan(seg_angle * 0.5) + CURVED_SEGMENT_OVERLAP
	for i in segment_count:
		var center_angle := float(i) * seg_angle
		var blocked := false
		for doorway in doorways:
			if absf(_angle_diff(center_angle, doorway["bearing"])) < float(doorway["half_angle"]) + seg_angle * 0.5:
				blocked = true
				break
		if blocked:
			continue
		var tangent_center := Vector3(
			sin(center_angle) * (radius + half_thickness),
			0.0,
			-cos(center_angle) * (radius + half_thickness)
		)
		_add_curved_wall_segment(
			tangent_center,
			Vector3(chord, wall_height, CastleRoomConstants.WALL_THICKNESS),
			center_angle
		)
	for doorway in doorways:
		_build_curved_stub(doorway["direction"], doorway["lateral"], radius)


## The socket a neighbouring room's door slides to sits on the *square* footprint's edge (Trap 1
## keeps `contains_world_point()` a rectangle test, and the lattice, loop scoring and door sliding
## all still reason in that same square); the round room's own wall opening sits on the *circle*.
## For an on-axis, uncentred door those coincide exactly (radius equals the square's half-extent on
## a cardinal bearing), so most stubs are zero-length and this returns immediately. A door slid off
## a cardinal bearing needs an actual connector, built here as two side walls, a lintel and a floor
## patch running straight from the circle point to the socket point.
func _build_curved_stub(
	direction: CastleRoomConstants.Direction, lateral: float, radius: float
) -> void:
	var half_w := room_width * 0.5
	var half_d := room_depth * 0.5
	var socket_pos := RoomTemplateCatalogScript.socket_wall_position(
		direction, half_w, half_d, lateral
	)
	var bearing := atan2(socket_pos.x, -socket_pos.z)
	var circle_pos := Vector3(sin(bearing) * radius, 0.0, -cos(bearing) * radius)
	var delta := socket_pos - circle_pos
	var flat_delta := Vector2(delta.x, delta.z)
	var stub_len := flat_delta.length()
	if stub_len < 0.1:
		return
	var dir_norm := Vector3(flat_delta.x, 0.0, flat_delta.y) / stub_len
	var yaw := atan2(dir_norm.x, dir_norm.z)
	var perp := Vector3(dir_norm.z, 0.0, -dir_norm.x)
	var mid := (circle_pos + socket_pos) * 0.5
	var door := CastleRoomConstants.DOOR_WIDTH
	var padded_len := stub_len + CastleRoomConstants.WALL_THICKNESS * 2.0
	var side_size := Vector3(CastleRoomConstants.WALL_THICKNESS, wall_height, padded_len)
	var sides: Array[float] = [-1.0, 1.0]
	for side in sides:
		var seg_center: Vector3 = (
			mid + perp * (door * 0.5 + CastleRoomConstants.WALL_THICKNESS * 0.5) * side
		)
		_add_curved_wall_segment(seg_center, side_size, yaw)
	var lintel_h := wall_height - CastleRoomConstants.DOOR_HEIGHT
	if lintel_h > 0.0:
		_add_curved_wall_segment(
			mid + Vector3(0.0, CastleRoomConstants.DOOR_HEIGHT, 0.0),
			Vector3(door, lintel_h, padded_len),
			yaw
		)
	var floor_body := StaticBody3D.new()
	floor_body.name = "StubFloor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.set_meta("surface", "stone")
	_geometry_root.add_child(floor_body)
	if Engine.is_editor_hint():
		floor_body.owner = get_tree().edited_scene_root
	var floor_size := Vector3(door, CastleRoomConstants.FLOOR_THICKNESS, padded_len)
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = floor_size
	floor_mesh.mesh = floor_box
	floor_mesh.position = mid + Vector3(0.0, -CastleRoomConstants.FLOOR_THICKNESS * 0.5, 0.0)
	floor_mesh.rotation.y = yaw
	if floor_material:
		floor_mesh.material_override = floor_material
	floor_body.add_child(floor_mesh)
	if Engine.is_editor_hint():
		floor_mesh.owner = get_tree().edited_scene_root
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = floor_size
	floor_collision.shape = floor_shape
	floor_collision.position = floor_mesh.position
	floor_collision.rotation.y = yaw
	floor_body.add_child(floor_collision)
	if Engine.is_editor_hint():
		floor_collision.owner = get_tree().edited_scene_root


## Same as `_add_wall_segment()`, with an added Y rotation -- curved-perimeter and stub segments
## are not axis-aligned, unlike every rectangular wall in the game.
func _add_curved_wall_segment(
	center: Vector3, size: Vector3, y_rotation: float, material_override: Material = null
) -> void:
	var wall_body := _create_walls_body()
	if not hide_walls:
		var mesh_instance := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh_instance.mesh = box
		mesh_instance.position = center + Vector3(0.0, size.y * 0.5, 0.0)
		mesh_instance.rotation.y = y_rotation
		mesh_instance.lod_bias = 0.8
		var mat := material_override if material_override else wall_material
		if mat:
			mesh_instance.material_override = mat
		wall_body.add_child(mesh_instance)
		if Engine.is_editor_hint():
			mesh_instance.owner = get_tree().edited_scene_root

	var collision := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	col_shape.size = size
	collision.shape = col_shape
	collision.position = center + Vector3(0.0, size.y * 0.5, 0.0)
	collision.rotation.y = y_rotation
	wall_body.add_child(collision)
	if Engine.is_editor_hint():
		collision.owner = get_tree().edited_scene_root


## Builds one wall, cutting the doorway at `door_offset` along the wall rather than at its centre.
##
## The two flanking segments are sized independently because an off-centre door leaves a longer
## stretch of wall on one side than the other. `door_offset` is clamped so the opening always stays
## fully inside the wall -- a door that ran off the end would leave a hole into solid rock.
func _build_wall(
	center: Vector3, size: Vector3, has_door: bool, spans_x: bool, door_offset: float = 0.0
) -> void:
	if not has_door:
		_add_wall_segment(center, size)
		return

	var span := size.x if spans_x else size.z
	var door := CastleRoomConstants.DOOR_WIDTH
	if span - door <= 0.0:
		_add_wall_segment(center, size)
		return

	var limit := (span - door) * 0.5
	var offset := clampf(door_offset, -limit, limit)
	var low := offset - door * 0.5 + span * 0.5
	var high := span * 0.5 - (offset + door * 0.5)
	if spans_x:
		if low > 0.0:
			_add_wall_segment(
				Vector3(center.x - span * 0.5 + low * 0.5, center.y, center.z),
				Vector3(low, size.y, size.z)
			)
		if high > 0.0:
			_add_wall_segment(
				Vector3(center.x + span * 0.5 - high * 0.5, center.y, center.z),
				Vector3(high, size.y, size.z)
			)
	else:
		if low > 0.0:
			_add_wall_segment(
				Vector3(center.x, center.y, center.z - span * 0.5 + low * 0.5),
				Vector3(size.x, size.y, low)
			)
		if high > 0.0:
			_add_wall_segment(
				Vector3(center.x, center.y, center.z + span * 0.5 - high * 0.5),
				Vector3(size.x, size.y, high)
			)

	var lintel_h := wall_height - CastleRoomConstants.DOOR_HEIGHT
	if lintel_h > 0.0:
		var lintel_y := CastleRoomConstants.DOOR_HEIGHT + lintel_h * 0.5
		if spans_x:
			_add_wall_segment(
				Vector3(center.x + offset, lintel_y, center.z),
				Vector3(door, lintel_h, size.z)
			)
		else:
			_add_wall_segment(
				Vector3(center.x, lintel_y, center.z + offset),
				Vector3(size.x, lintel_h, door)
			)


func _add_wall_segment(center: Vector3, size: Vector3, material_override: Material = null) -> void:
	var wall_body := _create_walls_body()
	if not hide_walls:
		var mesh_instance := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh_instance.mesh = box
		mesh_instance.position = center + Vector3(0.0, size.y * 0.5, 0.0)
		mesh_instance.lod_bias = 0.8
		var mat := material_override if material_override else wall_material
		if mat:
			mesh_instance.material_override = mat
		wall_body.add_child(mesh_instance)
		if Engine.is_editor_hint():
			mesh_instance.owner = get_tree().edited_scene_root

	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	collision.position = center + Vector3(0.0, size.y * 0.5, 0.0)
	wall_body.add_child(collision)
	if Engine.is_editor_hint():
		collision.owner = get_tree().edited_scene_root


func _add_room_occluder() -> void:
	var size := Vector3(room_width, wall_height, room_depth)
	var occluder := OccluderInstance3D.new()
	occluder.name = "RoomOccluder"
	occluder.occluder = _make_box_occluder(size)
	occluder.position = Vector3(0.0, wall_height * 0.5, 0.0)
	_geometry_root.add_child(occluder)
	if Engine.is_editor_hint():
		occluder.owner = get_tree().edited_scene_root


func _make_box_occluder(size: Vector3) -> ArrayOccluder3D:
	var occluder_mesh := ArrayOccluder3D.new()
	occluder_mesh.vertices = PackedVector3Array(
		[
			Vector3(-size.x * 0.5, 0.0, -size.z * 0.5),
			Vector3(size.x * 0.5, 0.0, -size.z * 0.5),
			Vector3(size.x * 0.5, size.y, -size.z * 0.5),
			Vector3(-size.x * 0.5, size.y, -size.z * 0.5),
			Vector3(-size.x * 0.5, 0.0, size.z * 0.5),
			Vector3(size.x * 0.5, 0.0, size.z * 0.5),
			Vector3(size.x * 0.5, size.y, size.z * 0.5),
			Vector3(-size.x * 0.5, size.y, size.z * 0.5),
		]
	)
	occluder_mesh.indices = PackedInt32Array(
		[
			0, 1, 2, 0, 2, 3, 5, 4, 7, 5, 7, 6, 4, 0, 3, 4, 3, 7, 1, 5, 6, 1, 6, 2, 3, 2, 6, 3,
			6, 7, 4, 5, 1, 4, 1, 0,
		]
	)
	return occluder_mesh


func _build_navigation_mesh() -> void:
	if _nav_region != null and is_instance_valid(_nav_region):
		remove_child(_nav_region)
		_nav_region.free()
	_nav_region = NavigationRegion3D.new()
	_nav_region.name = "NavigationRegion3D"
	add_child(_nav_region)
	if Engine.is_editor_hint():
		_nav_region.owner = get_tree().edited_scene_root

	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = NAV_CELL_SIZE
	nav_mesh.cell_height = NAV_CELL_SIZE
	nav_mesh.agent_height = ceilf(NAV_AGENT_HEIGHT / NAV_CELL_SIZE) * NAV_CELL_SIZE
	nav_mesh.agent_radius = ceilf(NAV_AGENT_RADIUS / NAV_CELL_SIZE) * NAV_CELL_SIZE
	nav_mesh.agent_max_climb = 0.5
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nav_mesh.filter_low_hanging_obstacles = true
	_nav_region.navigation_mesh = nav_mesh

	var source_data := NavigationMeshSourceGeometryData3D.new()
	if _geometry_root != null:
		NavigationServer3D.parse_source_geometry_data(nav_mesh, source_data, _geometry_root)
	var cover_root := get_node_or_null("CoverObstacles")
	if cover_root != null:
		NavigationServer3D.parse_source_geometry_data(nav_mesh, source_data, cover_root)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_data)
	_nav_bake_count += 1
	if _navigation_map != RID():
		_nav_region.set_navigation_map(_navigation_map)


func get_navigation_map() -> RID:
	if _navigation_map != RID():
		return _navigation_map
	if _nav_region == null:
		return RID()
	return _nav_region.get_navigation_map()


func set_navigation_map(map: RID) -> void:
	_navigation_map = map
	if _nav_region != null:
		_nav_region.set_navigation_map(map)
	for link in _nav_links:
		if is_instance_valid(link):
			link.set_navigation_map(map)


func sample_random_nav_point(rng: RandomNumberGenerator) -> Vector3:
	var map := get_navigation_map()
	if map == RID() or rng == null:
		return Vector3.ZERO
	var inset := 1.0
	var half_w := maxf(room_width * 0.5 - inset, 0.5)
	var half_d := maxf(room_depth * 0.5 - inset, 0.5)
	for _attempt in 8:
		var local := Vector3(
			rng.randf_range(-half_w, half_w), 0.05, rng.randf_range(-half_d, half_d)
		)
		var world := to_global(local)
		var closest := NavigationServer3D.map_get_closest_point(map, world)
		var closest_local := to_local(closest)
		if absf(closest_local.x) <= half_w and absf(closest_local.z) <= half_d:
			return closest_local
	return Vector3.ZERO


func add_cover_obstacle(local_pos: Vector3, size: Vector3, material: Material = null) -> void:
	var cover_root := _ensure_cover_root()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	cover_root.add_child(body)
	if Engine.is_editor_hint():
		body.owner = get_tree().edited_scene_root
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = local_pos + Vector3(0.0, size.y * 0.5, 0.0)
	if material:
		mesh_instance.material_override = material
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	collision.position = mesh_instance.position
	body.add_child(collision)
	_cover_nodes.append(body)


func add_height_stairs(
	step_count: int, direction: Vector2i, step_height: float = 0.5, lateral: float = 0.0
) -> void:
	if step_count <= 0:
		return
	_pending_stairs.append(
		{
			"step_count": step_count,
			"direction": direction,
			"step_height": step_height,
			"lateral": lateral,
		}
	)
	_geometry_dirty = true
	if Engine.is_editor_hint() or not is_inside_tree():
		_request_rebuild()


func _build_pending_stairs() -> void:
	for stair in _pending_stairs:
		_build_height_stairs(
			int(stair.get("step_count", 0)),
			stair.get("direction", Vector2i.ZERO),
			float(stair.get("step_height", 0.5)),
			float(stair.get("lateral", 0.0))
		)


## The invariant: the top of the flight is level with the neighbouring room's floor and sits
## directly under its doorway. Step `i` runs from the deepest tread (i = 0) to the one flush
## against the wall (i = step_count - 1), so the flight climbs toward the door rather than away
## from it. `lateral` slides the whole flight along the wall to the doorway's own offset.
##
## `_add_wall_segment()`'s `center.y` is a base, not a true centre -- it adds `size.y * 0.5` on
## top itself, the same way a wall built at `center.y = 0` sits on the floor rather than floating
## half its height above it. Tread `i` must stack from `step_height * i` to `step_height * (i+1)`,
## so its base is `step_height * i`, not `step_height * (i + 0.5)`.
func _build_height_stairs(
	step_count: int, direction: Vector2i, step_height: float, lateral: float = 0.0
) -> void:
	var step_depth := 0.8
	var width := CastleRoomConstants.DOOR_WIDTH + 1.0
	for i in step_count:
		var back := float(step_count - 1 - i) * step_depth
		var base_y := step_height * float(i)
		var center := Vector3.ZERO
		var size := Vector3(width, step_height, step_depth)
		if direction == Vector2i(0, -1):
			center = Vector3(lateral, base_y, -room_depth * 0.5 + back)
		elif direction == Vector2i(0, 1):
			center = Vector3(lateral, base_y, room_depth * 0.5 - back)
		elif direction == Vector2i(1, 0):
			center = Vector3(room_width * 0.5 - back, base_y, lateral)
			size = Vector3(step_depth, step_height, width)
		else:
			center = Vector3(-room_width * 0.5 + back, base_y, lateral)
			size = Vector3(step_depth, step_height, width)
		_add_wall_segment(center, size, floor_material)
	_build_stair_landing(step_count, direction, step_height, lateral, step_depth, width)


## A flat tread pushed one step-depth past the wall, at the flight's full height, so the player
## arrives level in the doorway rather than mid-step -- the last riser lands under the lintel, not
## inside the room. Its base sits one `step_height` below the flight's top, same convention as the
## treads above.
func _build_stair_landing(
	step_count: int,
	direction: Vector2i,
	step_height: float,
	lateral: float,
	step_depth: float,
	width: float
) -> void:
	var base_y := step_height * float(step_count - 1)
	var center := Vector3.ZERO
	var size := Vector3(width, step_height, step_depth)
	if direction == Vector2i(0, -1):
		center = Vector3(lateral, base_y, -room_depth * 0.5 - step_depth * 0.5)
	elif direction == Vector2i(0, 1):
		center = Vector3(lateral, base_y, room_depth * 0.5 + step_depth * 0.5)
	elif direction == Vector2i(1, 0):
		center = Vector3(room_width * 0.5 + step_depth * 0.5, base_y, lateral)
		size = Vector3(step_depth, step_height, width)
	else:
		center = Vector3(-room_width * 0.5 - step_depth * 0.5, base_y, lateral)
		size = Vector3(step_depth, step_height, width)
	_add_wall_segment(center, size, floor_material)


func sync_dimensions_from_kind() -> void:
	_apply_kind_spec()
	_rebuild()


func _resolve_kind() -> String:
	if not kind.is_empty():
		return str(kind)
	var room := get_parent() as RoomTemplate
	if room != null and not room.template_id.is_empty():
		return RoomTemplateCatalogScript.kind_from_template_id(room.template_id)
	return ""


func _apply_kind_spec() -> void:
	var resolved_kind := _resolve_kind()
	if resolved_kind.is_empty():
		return
	var spec: Dictionary = RoomTemplateCatalogScript.get_spec(resolved_kind)
	var spec_width: float = float(spec.get("width", room_width))
	var spec_depth: float = float(spec.get("depth", room_depth))
	var doors: int = int(spec.get("doors", 0))
	if Engine.is_editor_hint():
		if absf(room_width - spec_width) > 0.001 or absf(room_depth - spec_depth) > 0.001:
			push_warning(
				(
					"CastleBlockout '%s': kind '%s' implies %.1fx%.1f but exports %.1fx%.1f"
					% [name, resolved_kind, spec_width, spec_depth, room_width, room_depth]
				)
			)
	_applying_kind_spec = true
	room_width = spec_width
	room_depth = spec_depth
	shape = shape_override if shape_override != &"" else StringName(str(spec.get("shape", "rect")))
	door_north = (doors & RoomGraphSlot.DOOR_NORTH) != 0
	door_south = (doors & RoomGraphSlot.DOOR_SOUTH) != 0
	door_east = (doors & RoomGraphSlot.DOOR_EAST) != 0
	door_west = (doors & RoomGraphSlot.DOOR_WEST) != 0
	# RM-14: a corridor's kind spec asks for a lower ceiling than a room -- compression, not a
	# fight. Anything without its own "wallHeight" keeps the normal height unchanged.
	wall_height = float(spec.get("wall_height", CastleRoomConstants.WALL_HEIGHT))
	_applying_kind_spec = false


func _offset_for_direction(direction: CastleRoomConstants.Direction) -> float:
	match direction:
		CastleRoomConstants.Direction.NORTH:
			return door_north_offset
		CastleRoomConstants.Direction.SOUTH:
			return door_south_offset
		CastleRoomConstants.Direction.EAST:
			return door_east_offset
		_:
			return door_west_offset


func _verify_socket_positions() -> void:
	var room := get_parent() as RoomTemplate
	if room == null:
		return
	var half_w := room_width * 0.5
	var half_d := room_depth * 0.5
	for socket in room.get_sockets():
		var expected := RoomTemplateCatalogScript.socket_wall_position(
			socket.direction, half_w, half_d, _offset_for_direction(socket.direction)
		)
		if socket.position.distance_to(expected) > 0.01:
			push_warning(
				(
					"%s socket %s is %.3f from wall face (expected %s)"
					% [
						room.template_id,
						socket.get_socket_name(),
						socket.position.distance_to(expected),
						expected,
					]
				)
			)
