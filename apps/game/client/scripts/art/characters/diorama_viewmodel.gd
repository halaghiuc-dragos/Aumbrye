class_name DioramaViewmodel
extends RefCounted

## First-person arms and weapon, mounted on the player camera.
##
## The pivots are deliberately named ArmL/ArmR/WeaponMount/ShieldMount, matching
## the third-person rig, so the exact same attack and guard clips drive both
## views. The parent node is called ViewRoot rather than Root so the clips' body
## and root-motion tracks are skipped here: a whole-body lunge that reads well
## from behind would throw the camera around in first person.

const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")

const NODE_NAME := "Viewmodel"
const VIEW_ROOT := "ViewRoot"

## Metres from the eye. Close enough to fill the lower corners, far enough that
## the near plane never clips a swinging blade.
const SHOULDER_OFFSET := Vector3(0.3, -0.26, -0.18)
const ARM_SIZE := Vector3(0.16, 0.46, 0.16)

## Rest pose is already raised and angled inward: clips are stored as offsets, so
## this is what brings the swing into frame without touching the clip tables.
const ARM_REST_ROTATION := Vector3(-0.62, 0.0, 0.0)
const ARM_REST_ROLL := 0.22


static func build(camera: Camera3D, theme: int) -> Node3D:
	if camera == null:
		return null
	remove(camera)

	var holder := Node3D.new()
	holder.name = NODE_NAME
	camera.add_child(holder)

	var view_root := Node3D.new()
	view_root.name = VIEW_ROOT
	holder.add_child(view_root)

	var mats := _materials(theme)
	for side in [-1.0, 1.0]:
		var arm_name := "ArmL" if side < 0.0 else "ArmR"
		var shoulder := Node3D.new()
		shoulder.name = arm_name
		shoulder.position = Vector3(
			SHOULDER_OFFSET.x * side, SHOULDER_OFFSET.y, SHOULDER_OFFSET.z
		)
		shoulder.rotation = Vector3(
			ARM_REST_ROTATION.x, 0.0, ARM_REST_ROLL * -side
		)
		view_root.add_child(shoulder)

		PixelStyle.add_box(
			shoulder, ARM_SIZE, Vector3(0.0, -ARM_SIZE.y * 0.5, 0.0), mats["body"], "Mesh"
		)
		PixelStyle.add_box(
			shoulder,
			Vector3(ARM_SIZE.x * 1.12, 0.12, ARM_SIZE.z * 1.12),
			Vector3(0.0, -ARM_SIZE.y * 0.9, 0.0),
			mats["accent"],
			"Glove"
		)

		var mount := Node3D.new()
		mount.name = CharacterSkin.SHIELD_MOUNT if side < 0.0 else CharacterSkin.WEAPON_MOUNT
		mount.position = Vector3(0.0, -ARM_SIZE.y, 0.0)
		shoulder.add_child(mount)

	_disable_shadows(holder)
	return holder


static func get_root(camera: Camera3D) -> Node3D:
	if camera == null:
		return null
	var holder := camera.get_node_or_null(NODE_NAME) as Node3D
	if holder == null:
		return null
	return holder.get_node_or_null(VIEW_ROOT) as Node3D


static func remove(camera: Camera3D) -> void:
	var existing := camera.get_node_or_null(NODE_NAME)
	if existing:
		camera.remove_child(existing)
		existing.queue_free()


## The viewmodel lives inside the near plane, so a shadow from it would be a
## giant blob on the floor in front of the player.
static func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows(child)


static func _materials(theme: int) -> Dictionary:
	var palette := PixelStyle.get_palette(theme)
	var accent := PixelStyle.make_surface_material(
		PixelStyle.SurfaceKind.PROP, theme, 0.3
	).duplicate() as ShaderMaterial
	accent.set_shader_parameter("color_base", palette[PixelStyle.PaletteSlot.ACCENT])
	accent.set_shader_parameter(
		"color_shadow", palette[PixelStyle.PaletteSlot.ACCENT].darkened(0.25)
	)
	return {
		"body": PixelStyle.make_wall_material(theme),
		"accent": accent,
	}
