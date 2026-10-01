@tool
extends Node3D
class_name CastleBlockout

## A room scene's authored `door_*` values and socket transforms are editor preview only.
## `DungeonBuilder._close_all_blockout_doors()` clears every door flag on every room at build time
## and `_open_blockout_door_toward()` re-opens exactly the ones the floor's room graph names, and
## `CastleRoomScene._ensure_socket_completeness()` recomputes every socket's position from the
## room's actual dimensions regardless of what a scene authored. The builder is authoritative;
## nothing a designer sets here survives past opening the scene standalone in the editor.

const NAV_TEMPLATE_CACHE_LIMIT := 96
const NAV_CELL_SIZE := 0.25
const NAV_AGENT_HEIGHT := 1.8
const NAV_AGENT_RADIUS := 0.45

const CEILING_THICKNESS := 0.4
const RoomTemplateCatalogScript := preload("res://scripts/dungeon/procgen/room_template_catalog.gd")

## Rotunda and octagon wall segment counts. A round room still reserves a square footprint
## on the lattice (`RoomGraphLayout.footprint_cells()` is untouched) -- only the geometry built
## inside that square changes.
const ROUND_WALL_SEGMENTS := 24
const OCTAGON_WALL_SEGMENTS := 8
const CURVED_SEGMENT_OVERLAP := 0.06

@export var kind: StringName = &"":
	set(value):
		kind = value
		_request_rebuild()

## `rect`, `round` or `octagon`. Only the geometry built *inside* the reserved square
## footprint changes -- the lattice, door sliding, loop scoring, overlap validation and the minimap
## all keep reading `room_width`/`room_depth` as a rectangle regardless of this. See
## `RoomTemplate.contains_world_point()`, which stays a rectangle test on purpose (Trap 1).
@export var shape: StringName = &"rect":
	set(value):
		shape = value
		_request_rebuild()

## A biome layout variant's `"shape"` override, applied on top of the kind spec's own
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
var _walls_body: StaticBody3D
var _nav_region: NavigationRegion3D
var _nav_links: Array[NavigationLink3D] = []
var _pending_stairs: Array[Dictionary] = []
var _navigation_map: RID = RID()
var _geometry_dirty: bool = true
var _nav_bake_count: int = 0
static var _navigation_template_cache: Dictionary = {}
## Solid props standing on the floor, as {"pos": Vector3, "size": Vector3} in this room's space.
var _nav_obstacles: Array = []
## Sets what the room's floors sound like underfoot; the room scene fills it from its biome.
var floor_surface: StringName = &"stone"
## Which biome this room belongs to, so its walls get that biome's relief (trim, cornice, pilasters).
var relief_biome: String = ""
static var _navigation_template_max_usec := 0
var _applying_kind_spec := false
var _rebuild_queued := false


func _ready() -> void:
	_apply_kind_spec(true)
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


## Closing all four doors and re-opening one is several `@export` setters firing in a row, and a
## synchronous `_rebuild()` from each would be six to eight rebuilds where one will do. Deferring
## through `call_deferred` and guarding on `_geometry_dirty` coalesces any number of setter calls
## within one frame into a single rebuild.
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
	_apply_floor_surface()
	_build_navigation_mesh()
	_geometry_dirty = false


func _apply_floor_surface() -> void:
	if _geometry_root == null or not is_instance_valid(_geometry_root):
		return
	for body in _geometry_root.find_children("*", "StaticBody3D", true, false):
		if body.is_in_group("walkable_floor"):
			body.set_meta("surface", String(floor_surface))


func _rebuild() -> void:
	_ensure_materials()
	_apply_kind_spec(false)
	_clear_geometry_children()
	_geometry_root = Node3D.new()
	_geometry_root.name = "Geometry"
	add_child(_geometry_root)
	if Engine.is_editor_hint():
		_geometry_root.owner = get_tree().edited_scene_root
	_walls_body = null
	_relief.clear()

	if shape == &"round" or shape == &"octagon":
		if not skip_floor:
			_build_curved_floor()
		_build_curved_perimeter(ROUND_WALL_SEGMENTS if shape == &"round" else OCTAGON_WALL_SEGMENTS)
		_build_pending_stairs()
		if build_ceiling:
			_build_curved_ceiling()
	else:
		var structural_height := _structural_wall_height()
		if not skip_floor:
			if shape == &"split":
				_build_split_floor()
			else:
				_build_floor()
		_build_wall(
			Vector3(0.0, 0.0, -room_depth * 0.5),
			Vector3(room_width, structural_height, CastleRoomConstants.WALL_THICKNESS),
			door_north,
			true,
			door_north_offset,
			socket_landing_height(CastleRoomConstants.Direction.NORTH)
		)
		_build_wall(
			Vector3(0.0, 0.0, room_depth * 0.5),
			Vector3(room_width, structural_height, CastleRoomConstants.WALL_THICKNESS),
			door_south,
			true,
			door_south_offset,
			socket_landing_height(CastleRoomConstants.Direction.SOUTH)
		)
		_build_wall(
			Vector3(room_width * 0.5, 0.0, 0.0),
			Vector3(CastleRoomConstants.WALL_THICKNESS, structural_height, room_depth),
			door_east,
			false,
			door_east_offset,
			socket_landing_height(CastleRoomConstants.Direction.EAST)
		)
		_build_wall(
			Vector3(-room_width * 0.5, 0.0, 0.0),
			Vector3(CastleRoomConstants.WALL_THICKNESS, structural_height, room_depth),
			door_west,
			false,
			door_west_offset,
			socket_landing_height(CastleRoomConstants.Direction.WEST)
		)
		_build_pending_stairs()
		if build_ceiling:
			_build_ceiling()
	_flush_wall_relief()
	_add_room_occluder()
	_geometry_dirty = false


## Wall relief is gathered while the walls are built and placed once at the end, as instanced
## meshes: the trim along a wall is dozens of repeats of the same two-metre piece.
var _relief: Dictionary = {}

const RELIEF_MODULE := 2.0
const RELIEF_CAPITAL_HEIGHT := 0.3
const RELIEF_BASE_HEIGHT := 0.38
const PILASTER_SPACING := 4.0


func _queue_wall_relief(center: Vector3, size: Vector3) -> void:
	if hide_walls:
		return
	var spans_x := size.x > size.z
	var length := size.x if spans_x else size.z
	var thickness := size.z if spans_x else size.x
	var inward := Vector3(0.0, 0.0, -signf(center.z)) if spans_x else Vector3(-signf(center.x), 0.0, 0.0)
	if inward == Vector3.ZERO or length < 0.8:
		return
	var along := Vector3.RIGHT if spans_x else Vector3.BACK
	var face := Vector3(center.x, 0.0, center.z) + inward * (thickness * 0.5)
	var facing := Basis(Vector3.UP, atan2(inward.x, inward.z))
	_queue_masonry(face, inward, length, center.y, size.y)
	if size.y < 3.0:
		return
	var count := maxi(1, roundi(length / RELIEF_MODULE))
	var stretch := length / (float(count) * RELIEF_MODULE)
	for i in count:
		var offset := -length * 0.5 + (float(i) + 0.5) * length / float(count)
		var origin := face + along * offset
		var strip := facing * Basis.from_scale(Vector3(stretch, 1.0, 1.0))
		_relief_add("base", Transform3D(strip, origin))
		_relief_add("cornice", Transform3D(strip, origin + Vector3(0.0, size.y, 0.0)))
	var spots: Array[float] = []
	if length >= 1.5:
		spots.append(-length * 0.5 + 0.3)
		spots.append(length * 0.5 - 0.3)
		var step := -length * 0.5 + 0.3 + PILASTER_SPACING
		while step < length * 0.5 - 1.2:
			spots.append(step)
			step += PILASTER_SPACING
	var shaft_height := size.y - RELIEF_BASE_HEIGHT - RELIEF_CAPITAL_HEIGHT
	for spot in spots:
		var origin := face + along * spot
		_relief_add(
			"pilaster",
			Transform3D(facing * Basis.from_scale(Vector3(1.0, shaft_height, 1.0)), origin + Vector3(0.0, RELIEF_BASE_HEIGHT, 0.0))
		)
		_relief_add("capital", Transform3D(facing, origin + Vector3(0.0, size.y - RELIEF_CAPITAL_HEIGHT, 0.0)))


## Courses of Blender ashlar over a wall face, so the bare box behind only shows as mortar.
func _queue_masonry(face: Vector3, normal: Vector3, length: float, base_y: float, height: float) -> void:
	for placement in WallCladding.face_transforms(face, normal, length, base_y, height):
		_relief_add("masonry", placement)


## Flagstones over a rectangle of floor, in four-metre tiles stretched to fit.
func _queue_floor_tiles(centre: Vector3, xz: Vector2, base_y: float) -> void:
	var columns := maxi(1, roundi(xz.x / 4.0))
	var rows := maxi(1, roundi(xz.y / 4.0))
	var stretch := Basis.from_scale(Vector3(xz.x / (float(columns) * 4.0), 1.0, xz.y / (float(rows) * 4.0)))
	for column in columns:
		for row in rows:
			var origin := centre + Vector3(
				(float(column) + 0.5 - float(columns) * 0.5) * xz.x / float(columns),
				base_y,
				(float(row) + 0.5 - float(rows) * 0.5) * xz.y / float(rows)
			)
			_relief_add("floor", Transform3D(stretch, origin))


func _relief_add(piece: String, placement: Transform3D) -> void:
	if not _relief.has(piece):
		_relief[piece] = [] as Array[Transform3D]
	(_relief[piece] as Array[Transform3D]).append(placement)


func _flush_wall_relief() -> void:
	if _geometry_root == null or _relief.is_empty():
		return
	var style := str(PropLibrary.BIOME_STYLES.get(relief_biome, "castle"))
	var theme := PixelDioramaStyle.theme_from_biome(relief_biome if relief_biome != "" else BiomeRegistry.BIOME_CASTLE)
	var options := {}
	var materials := {}
	if wall_material != null:
		materials["wall"] = wall_material
	if accent_material != null:
		materials["accent"] = accent_material
	if floor_material != null:
		materials["floor"] = floor_material
	if not materials.is_empty():
		options["materials"] = materials
	for piece: String in _relief:
		PropLibrary.scatter_themed(
			_geometry_root, "walls/%s_%s" % [piece, style], theme, _relief[piece] as Array[Transform3D],
			"Relief_%s" % piece, options
		)
	_relief.clear()


func _clear_geometry_children() -> void:
	for child in get_children():
		if child.name == "Geometry" or child is NavigationRegion3D or child is NavigationLink3D:
			remove_child(child)
			child.free()
	_geometry_root = null
	_walls_body = null
	_nav_region = null
	_nav_links.clear()


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
	floor_body.add_to_group("walkable_floor")
	_geometry_root.add_child(floor_body)
	if Engine.is_editor_hint():
		floor_body.owner = get_tree().edited_scene_root

	_queue_floor_tiles(Vector3.ZERO, Vector2(room_width, room_depth), 0.0)

	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(room_width, CastleRoomConstants.FLOOR_THICKNESS, room_depth)
	collision.shape = box_shape
	collision.position = Vector3(0.0, -CastleRoomConstants.FLOOR_THICKNESS * 0.5, 0.0)
	floor_body.add_child(collision)
	if Engine.is_editor_hint():
		collision.owner = get_tree().edited_scene_root


## `shape == &"split"` -- a balcony. The room's outer walls and doors are unchanged (a
## balcony is still a plain rectangular footprint); only the floor is built in two halves at
## different heights, with a railing along the seam. `BALCONY_RISE` matches
## `RoomGraphGeometry.HEIGHT_STEP` (both 3.0) on purpose -- the raised half reads as "the next
## height level", the same rise a real room-to-room height transition uses, not an arbitrary step.
const BALCONY_RISE := 3.0


## The raised half of a split room is north of the internal seam. East/west exterior doors are
## intentionally unsupported by the template catalog because they would land on that seam.
func socket_landing_height(direction: CastleRoomConstants.Direction) -> float:
	if shape == &"split" and direction == CastleRoomConstants.Direction.NORTH:
		return BALCONY_RISE
	return 0.0


func _structural_wall_height() -> float:
	# A raised doorway still needs a full-height player opening and lintel. Raising only the floor
	# beneath it would otherwise cut the opening above the ceiling.
	return wall_height + BALCONY_RISE if shape == &"split" else wall_height


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
	floor_body.add_to_group("walkable_floor")
	_geometry_root.add_child(floor_body)
	if Engine.is_editor_hint():
		floor_body.owner = get_tree().edited_scene_root
	var size := Vector3(xz_size.x, CastleRoomConstants.FLOOR_THICKNESS, xz_size.y)
	var local_pos := center + Vector3(0.0, base_y - CastleRoomConstants.FLOOR_THICKNESS * 0.5, 0.0)
	_queue_floor_tiles(center, xz_size, base_y)
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
## "down" one-way drop-down.
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
	var center_y := _structural_wall_height() + CEILING_THICKNESS * 0.5
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


## A `CylinderMesh` with `radial_segments` set to the wall segment count doubles as both
## the round floor and the octagon floor -- an octagon prism is just a very-low-poly cylinder, so
## one mesh covers the "PrismMesh-style fan" the action text asks for without a second code path.
func _curved_radius() -> float:
	return minf(room_width, room_depth) * 0.5


func _build_curved_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.add_to_group("walkable_floor")
	_geometry_root.add_child(floor_body)
	if Engine.is_editor_hint():
		floor_body.owner = get_tree().edited_scene_root

	var segments := ROUND_WALL_SEGMENTS if shape == &"round" else OCTAGON_WALL_SEGMENTS
	var radius := _curved_radius()
	_relief_add("disc%d" % segments, Transform3D(Basis.from_scale(Vector3(radius, 1.0, radius)), Vector3.ZERO))

	var collision := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = radius
	cyl_shape.height = CastleRoomConstants.FLOOR_THICKNESS
	collision.shape = cyl_shape
	collision.position = Vector3(0.0, -CastleRoomConstants.FLOOR_THICKNESS * 0.5, 0.0)
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
	# CylinderMesh floors are inscribed polygons. Seat each wall on that polygon's
	# apothem, with its inner face over the floor edge, including octagon corners.
	var wall_apothem := radius * cos(seg_angle * 0.5)
	var doorways := _curved_doorways()
	var half_thickness := CastleRoomConstants.WALL_THICKNESS * 0.5
	for i in segment_count:
		var center_angle := float(i) * seg_angle
		var remaining: Array[Vector2] = [Vector2(-seg_angle * 0.5, seg_angle * 0.5)]
		for doorway in doorways:
			var relative := _angle_diff(center_angle, float(doorway["bearing"]))
			var cut_start := -float(doorway["half_angle"]) - relative
			var cut_end := float(doorway["half_angle"]) - relative
			var next_remaining: Array[Vector2] = []
			for interval in remaining:
				if cut_end <= interval.x or cut_start >= interval.y:
					next_remaining.append(interval)
					continue
				if cut_start > interval.x:
					next_remaining.append(Vector2(interval.x, cut_start))
				if cut_end < interval.y:
					next_remaining.append(Vector2(cut_end, interval.y))
			remaining = next_remaining
		for interval in remaining:
			var width := interval.y - interval.x
			if width < 0.01:
				continue
			var angle := center_angle + (interval.x + interval.y) * 0.5
			var chord := 2.0 * radius * tan(width * 0.5) + CURVED_SEGMENT_OVERLAP
			var tangent_center := Vector3(
				sin(angle) * (wall_apothem + half_thickness),
				0.0,
				-cos(angle) * (wall_apothem + half_thickness)
			)
			_add_curved_wall_segment(
				tangent_center,
				Vector3(chord, wall_height, CastleRoomConstants.WALL_THICKNESS),
				angle,
				null,
				true
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
	floor_body.add_to_group("walkable_floor")
	floor_body.set_meta("surface", "stone")
	_geometry_root.add_child(floor_body)
	if Engine.is_editor_hint():
		floor_body.owner = get_tree().edited_scene_root
	var floor_size := Vector3(door, CastleRoomConstants.FLOOR_THICKNESS, padded_len)
	_relief_add(
		"floor", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(door / 4.0, 1.0, padded_len / 4.0)), mid)
	)
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = floor_size
	floor_collision.shape = floor_shape
	floor_collision.position = mid + Vector3(0.0, -CastleRoomConstants.FLOOR_THICKNESS * 0.5, 0.0)
	floor_collision.rotation.y = yaw
	floor_body.add_child(floor_collision)
	if Engine.is_editor_hint():
		floor_collision.owner = get_tree().edited_scene_root


## Same as `_add_wall_segment()`, with an added Y rotation -- curved-perimeter and stub segments
## are not axis-aligned, unlike every rectangular wall in the game.
func _add_curved_wall_segment(
	center: Vector3, size: Vector3, y_rotation: float, material_override: Material = null, masonry: bool = false
) -> void:
	if masonry and not hide_walls:
		var inward := Vector3(-center.x, 0.0, -center.z).normalized()
		_queue_masonry(center + inward * (size.z * 0.5), inward, size.x, center.y, size.y)
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
	center: Vector3,
	size: Vector3,
	has_door: bool,
	spans_x: bool,
	door_offset: float = 0.0,
	door_base_y: float = 0.0
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

	# A raised landing must not leave a full-height hole under the floor. The sill and lintel make
	# the opening exactly [door_base_y, door_base_y + DOOR_HEIGHT], matching the socket contract.
	if door_base_y > 0.0:
		if spans_x:
			_add_wall_segment(
				Vector3(center.x + offset, center.y, center.z),
				Vector3(door, door_base_y, size.z)
			)
		else:
			_add_wall_segment(
				Vector3(center.x, center.y, center.z + offset),
				Vector3(size.x, door_base_y, door)
			)
	var lintel_h := size.y - door_base_y - CastleRoomConstants.DOOR_HEIGHT
	if lintel_h > 0.0:
		var lintel_y := door_base_y + CastleRoomConstants.DOOR_HEIGHT
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
	_queue_wall_relief(center, size)
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
	if (
		not build_ceiling
		or shape == &"round"
		or shape == &"octagon"
		or door_north
		or door_south
		or door_east
		or door_west
	):
		return
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
	_nav_region.enabled = true
	add_child(_nav_region)
	if Engine.is_editor_hint():
		_nav_region.owner = get_tree().edited_scene_root

	var nav_mesh := _navigation_template()
	# Geometry doors are joined by DungeonBuilder's explicit links. Their immutable room footprint
	# needs no collider parsing or synchronous bake on every rebuild.
	_nav_region.navigation_mesh = nav_mesh
	if _navigation_map != RID():
		_nav_region.set_navigation_map(_navigation_map)
		# Region server state is created as the node enters the tree. Synchronize on the next idle
		# frame so a runtime rebuild cannot publish the empty pre-build snapshot.
		call_deferred("_sync_navigation_region_server")


func _sync_navigation_region_server() -> void:
	var region := _nav_region
	if region == null or not is_instance_valid(region):
		return
	if _navigation_map == RID():
		return
	var nav_mesh := region.navigation_mesh
	if nav_mesh == null:
		return
	var region_rid := region.get_region_rid()
	NavigationServer3D.region_set_map(region_rid, _navigation_map)
	NavigationServer3D.region_set_navigation_mesh(region_rid, nav_mesh)
	NavigationServer3D.region_set_transform(region_rid, global_transform)


## Cuts the room's solid props out of the walkable floor so agents path around them. A bare room
## keeps its cached rectangle; a dressed one bakes once per distinct arrangement and is cached by it.
func carve_obstacles(obstacles: Array) -> void:
	_nav_obstacles = obstacles
	if _nav_region != null and is_instance_valid(_nav_region):
		_build_navigation_mesh()


func _carvable() -> bool:
	return not _nav_obstacles.is_empty() and shape not in [&"round", &"octagon", &"split"]


func _navigation_template() -> NavigationMesh:
	var key := "%s:%.2f:%.2f" % [shape, room_width, room_depth]
	if _carvable():
		key += ":" + _obstacle_signature()
	var cached := _navigation_template_cache.get(key) as NavigationMesh
	if cached != null:
		return cached
	var started_usec := Time.get_ticks_usec()
	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = NAV_CELL_SIZE
	nav_mesh.cell_height = NAV_CELL_SIZE
	nav_mesh.agent_height = ceilf(NAV_AGENT_HEIGHT / NAV_CELL_SIZE) * NAV_CELL_SIZE
	nav_mesh.agent_radius = ceilf(NAV_AGENT_RADIUS / NAV_CELL_SIZE) * NAV_CELL_SIZE
	nav_mesh.agent_max_climb = 0.5
	if _carvable():
		_bake_carved_navigation_mesh(nav_mesh)
	elif shape == &"split":
		_build_split_navigation_mesh(nav_mesh)
	else:
		_build_flat_navigation_mesh(nav_mesh)
	nav_mesh.emit_changed()
	if _navigation_template_cache.size() >= NAV_TEMPLATE_CACHE_LIMIT:
		_navigation_template_cache.clear()
	_navigation_template_cache[key] = nav_mesh
	_navigation_template_max_usec = maxi(_navigation_template_max_usec, Time.get_ticks_usec() - started_usec)
	_nav_bake_count += 1
	return nav_mesh


func _obstacle_signature() -> String:
	var parts := PackedStringArray()
	for obstacle in _nav_obstacles:
		var pos: Vector3 = obstacle["pos"]
		var size: Vector3 = obstacle["size"]
		parts.append("%.2f,%.2f,%.2f,%.2f" % [pos.x, pos.z, size.x, size.z])
	return "|".join(parts)


## The floor rectangle with each prop's footprint carved out, baked by the navigation server. The
## floor is the room's full rectangle: the bake erodes it by the agent radius itself.
func _bake_carved_navigation_mesh(nav_mesh: NavigationMesh) -> void:
	var half_w := room_width * 0.5
	var half_d := room_depth * 0.5
	var source := NavigationMeshSourceGeometryData3D.new()
	var a := Vector3(-half_w, 0.0, -half_d)
	var b := Vector3(-half_w, 0.0, half_d)
	var c := Vector3(half_w, 0.0, half_d)
	var d := Vector3(half_w, 0.0, -half_d)
	source.add_faces(PackedVector3Array([a, c, b, a, d, c]), Transform3D.IDENTITY)
	for obstacle in _nav_obstacles:
		var pos: Vector3 = obstacle["pos"]
		var size: Vector3 = obstacle["size"]
		var hx := size.x * 0.5
		var hz := size.z * 0.5
		source.add_projected_obstruction(
			PackedVector3Array(
				[
					Vector3(pos.x - hx, 0.0, pos.z - hz),
					Vector3(pos.x + hx, 0.0, pos.z - hz),
					Vector3(pos.x + hx, 0.0, pos.z + hz),
					Vector3(pos.x - hx, 0.0, pos.z + hz),
				]
			),
			0.0,
			maxf(size.y, NAV_AGENT_HEIGHT),
			true
		)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)


static func navigation_template_cache_size() -> int:
	return _navigation_template_cache.size()


static func navigation_template_max_usec() -> int:
	return _navigation_template_max_usec


func navigation_template_build_count() -> int:
	return _nav_bake_count


## The balcony has two disconnected walkable surfaces and a one-way drop between them. Godot's
## collision-source parser omits this generated split geometry, so define its two authored floor
## polygons directly. Inter-room traversal remains governed by the builder's explicit links.
func _build_split_navigation_mesh(nav_mesh: NavigationMesh) -> void:
	var inset := NAV_AGENT_RADIUS + 0.1
	var half_w := maxf(0.25, room_width * 0.5 - inset)
	var half_d := maxf(0.25, room_depth * 0.5 - inset)
	nav_mesh.vertices = PackedVector3Array(
		[
			Vector3(-half_w, BALCONY_RISE, -half_d),
			Vector3(-half_w, BALCONY_RISE, -0.05),
			Vector3(half_w, BALCONY_RISE, -0.05),
			Vector3(half_w, BALCONY_RISE, -half_d),
			Vector3(-half_w, 0.0, 0.05),
			Vector3(-half_w, 0.0, half_d),
			Vector3(half_w, 0.0, half_d),
			Vector3(half_w, 0.0, 0.05),
		]
	)
	nav_mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	nav_mesh.add_polygon(PackedInt32Array([4, 5, 6, 7]))


func _build_flat_navigation_mesh(nav_mesh: NavigationMesh) -> void:
	var inset := NAV_AGENT_RADIUS + 0.1
	var half_w := maxf(0.25, room_width * 0.5 - inset)
	var half_d := maxf(0.25, room_depth * 0.5 - inset)
	if shape == &"round" or shape == &"octagon":
		var points := PackedVector3Array()
		var sides := ROUND_WALL_SEGMENTS if shape == &"round" else OCTAGON_WALL_SEGMENTS
		var radius := maxf(0.25, minf(half_w, half_d))
		for index in sides:
			var angle := TAU * float(index) / float(sides)
			points.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
		nav_mesh.vertices = points
		nav_mesh.add_polygon(PackedInt32Array(range(sides)))
		return
	nav_mesh.vertices = PackedVector3Array(
		[
			Vector3(-half_w, 0.0, -half_d),
			Vector3(-half_w, 0.0, half_d),
			Vector3(half_w, 0.0, half_d),
			Vector3(half_w, 0.0, -half_d),
		]
	)
	nav_mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))



func get_navigation_map() -> RID:
	if _navigation_map != RID():
		return _navigation_map
	if _nav_region == null:
		return RID()
	return _nav_region.get_navigation_map()


func get_navigation_vertex_count() -> int:
	if _nav_region == null or _nav_region.navigation_mesh == null:
		return 0
	return _nav_region.navigation_mesh.get_vertices().size()


func get_navigation_polygon_count() -> int:
	if _nav_region == null or _nav_region.navigation_mesh == null:
		return 0
	return _nav_region.navigation_mesh.get_polygon_count()


func set_navigation_map(map: RID) -> void:
	_navigation_map = map
	if map != RID():
		NavigationServer3D.map_set_active(map, true)
	if _nav_region != null:
		_nav_region.enabled = true
		_nav_region.set_navigation_map(map)
	for link in _nav_links:
		if is_instance_valid(link):
			link.set_navigation_map(map)


func sample_random_nav_point(rng: RandomNumberGenerator) -> Dictionary:
	var map := get_navigation_map()
	if map == RID() or rng == null:
		return {"ok": false}
	## Navigation regions are registered asynchronously after a floor build. Querying before the
	## first map iteration logs an engine error and returns an unusable point, so fall back to the
	## authored placement offset until the map has synchronized.
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return {"ok": false}
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
		if (
			absf(closest_local.x) <= half_w
			and absf(closest_local.z) <= half_d
			and closest_local.y >= -0.25
			and closest_local.y <= wall_height + 0.25
		):
			return {"ok": true, "position": closest_local}
	return {"ok": false}


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
	var stairs_body := StaticBody3D.new()
	stairs_body.name = "WalkableStairs"
	stairs_body.collision_layer = 1
	stairs_body.collision_mask = 0
	stairs_body.add_to_group("walkable_floor")
	_geometry_root.add_child(stairs_body)
	if Engine.is_editor_hint():
		stairs_body.owner = get_tree().edited_scene_root
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
		_add_stair_segment(stairs_body, center, size, direction)
	_build_stair_landing(stairs_body, step_count, direction, step_height, lateral, step_depth, width)


## The tread model faces +z, so the riser looks back down the flight: a flight climbing north is
## left as modelled and every other direction turns it.
static func _stair_yaw(direction: Vector2i) -> float:
	if direction == Vector2i(0, 1):
		return PI
	if direction == Vector2i(1, 0):
		return -PI * 0.5
	if direction == Vector2i(-1, 0):
		return PI * 0.5
	return 0.0


func _add_stair_segment(body: StaticBody3D, center: Vector3, size: Vector3, direction: Vector2i) -> void:
	var across := size.z if direction.x != 0 else size.x
	var run := size.x if direction.x != 0 else size.z
	var stretch := Basis.from_scale(Vector3(across / 4.0, size.y / 0.5, run / 0.8))
	_relief_add("step", Transform3D(Basis(Vector3.UP, _stair_yaw(direction)) * stretch, center))
	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	collision.position = center + Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(collision)
	if Engine.is_editor_hint():
		collision.owner = get_tree().edited_scene_root


## A flat tread pushed one step-depth past the wall, at the flight's full height, so the player
## arrives level in the doorway rather than mid-step -- the last riser lands under the lintel, not
## inside the room. Its base sits one `step_height` below the flight's top, same convention as the
## treads above.
func _build_stair_landing(
	body: StaticBody3D,
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
	_add_stair_segment(body, center, size, direction)


func sync_dimensions_from_kind() -> void:
	_apply_kind_spec(true)
	_rebuild()


func _resolve_kind() -> String:
	if not kind.is_empty():
		return str(kind)
	var room := get_parent() as RoomTemplate
	if room != null and not room.template_id.is_empty():
		return RoomTemplateCatalogScript.kind_from_template_id(room.template_id)
	return ""


func _apply_kind_spec(apply_door_defaults: bool) -> void:
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
	if apply_door_defaults:
		door_north = (doors & RoomGraphSlot.DOOR_NORTH) != 0
		door_south = (doors & RoomGraphSlot.DOOR_SOUTH) != 0
		door_east = (doors & RoomGraphSlot.DOOR_EAST) != 0
		door_west = (doors & RoomGraphSlot.DOOR_WEST) != 0
	# A corridor's kind spec asks for a lower ceiling than a room -- compression, not a
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
