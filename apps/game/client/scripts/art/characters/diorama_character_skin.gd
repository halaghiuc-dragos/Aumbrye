extends RefCounted
class_name DioramaCharacterSkin

## Chunky pixel-diorama rigs for players, enemies, and training dummies.
##
## Every body is a hierarchy of pivot Node3Ds with the box mesh offset beneath the
## joint, so an arm rotates about the shoulder rather than about the middle of its
## own mesh. AnimationPlayer clips drive those pivots by name, which is why the
## node names here are a contract shared with DioramaAnimLibrary.
##
##   DioramaVisual/Root/LegL|LegR
##   DioramaVisual/Root/Torso/Head
##   DioramaVisual/Root/Torso/ArmL/ShieldMount
##   DioramaVisual/Root/Torso/ArmR/WeaponMount

const VISUAL_NAME := "DioramaVisual"
const ROOT_NAME := "Root"
const WEAPON_MOUNT := "WeaponMount"
const SHIELD_MOUNT := "ShieldMount"

## Hidden in first person. Torso is a pivot, so its children (head, arms, weapon)
## go with it while the legs stay visible under the camera.
const FIRST_PERSON_HIDDEN_PARTS := ["Torso"]

const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const WeaponKit := preload("res://scripts/art/props/diorama_weapon_kit.gd")

const ARENA_DUMMY_ACCENT := Color(1.0, 0.35, 0.1)
const ARENA_DUMMY_GLOW := Color(0.6, 0.2, 0.05)

## Body proportions per profile, in metres. torso/head/arm/leg are box sizes.
const PROFILES := {
	"player": {
		"leg": Vector3(0.22, 0.46, 0.26),
		"torso": Vector3(0.5, 0.62, 0.34),
		"head": Vector3(0.32, 0.32, 0.32),
		"arm": Vector3(0.2, 0.52, 0.2),
		"hip_x": 0.13,
		"shoulder_x": 0.3,
		"visor": true,
	},
	"melee": {
		"leg": Vector3(0.24, 0.48, 0.28),
		"torso": Vector3(0.55, 0.64, 0.38),
		"head": Vector3(0.36, 0.36, 0.36),
		"arm": Vector3(0.22, 0.54, 0.22),
		"hip_x": 0.14,
		"shoulder_x": 0.33,
		"head_accent": true,
	},
	"ranged": {
		"leg": Vector3(0.18, 0.44, 0.24),
		"torso": Vector3(0.42, 0.56, 0.3),
		"head": Vector3(0.28, 0.28, 0.28),
		"arm": Vector3(0.16, 0.48, 0.16),
		"hip_x": 0.11,
		"shoulder_x": 0.25,
		"extras": ["bow"],
	},
	"shield": {
		"leg": Vector3(0.24, 0.46, 0.3),
		"torso": Vector3(0.64, 0.68, 0.44),
		"head": Vector3(0.34, 0.34, 0.34),
		"arm": Vector3(0.22, 0.52, 0.22),
		"hip_x": 0.15,
		"shoulder_x": 0.36,
		"extras": ["shield"],
	},
	"brute": {
		"leg": Vector3(0.28, 0.5, 0.32),
		"torso": Vector3(0.78, 0.82, 0.5),
		"head": Vector3(0.42, 0.42, 0.42),
		"arm": Vector3(0.3, 0.66, 0.3),
		"hip_x": 0.18,
		"shoulder_x": 0.46,
		"head_accent": true,
	},
	"dummy": {
		"leg": Vector3(0.24, 0.46, 0.3),
		"torso": Vector3(0.55, 0.66, 0.38),
		"head": Vector3(0.38, 0.38, 0.38),
		"arm": Vector3(0.24, 0.54, 0.24),
		"hip_x": 0.15,
		"shoulder_x": 0.32,
	},
}


static func build_player_body(facing: Node3D, theme: int = -1) -> Node3D:
	_remove_visual(facing)
	PixelStyle.hide_legacy_meshes(facing)
	var visual := _make_visual(facing)
	if theme < 0:
		theme = CharacterService.appearance_theme if CharacterService else PixelStyle.PaletteTheme.HUB
	_build_humanoid(visual, "player", _body_materials(theme))
	return visual


static func build_enemy_body(
	parent: Node3D,
	enemy_type: String = "melee",
	theme: int = PixelStyle.PaletteTheme.CASTLE
) -> Node3D:
	_remove_visual(parent)
	PixelStyle.hide_legacy_meshes(parent)
	var visual := _make_visual(parent)
	var mats := _body_materials(theme)
	var profile := enemy_type.to_lower()
	if profile == "hound":
		_build_quadruped(visual, mats)
	else:
		_build_humanoid(visual, profile if PROFILES.has(profile) else "melee", mats)
	return visual


static func build_training_dummy(parent: Node3D) -> Node3D:
	_remove_visual(parent)
	PixelStyle.hide_legacy_meshes(parent)
	var visual := _make_visual(parent)
	var mats := _body_materials(PixelStyle.PaletteTheme.CASTLE)
	mats["accent"] = PixelStyle.make_material(ARENA_DUMMY_ACCENT, ARENA_DUMMY_GLOW)
	var root := _build_humanoid(visual, "dummy", mats)
	var torso := root.get_node_or_null("Torso") as Node3D
	if torso:
		var spec: Dictionary = PROFILES["dummy"]
		var torso_size: Vector3 = spec["torso"]
		PixelStyle.add_box(
			torso,
			Vector3(torso_size.x + 0.15, 0.12, 0.12),
			Vector3(0.0, torso_size.y * 0.55, torso_size.z * 0.55),
			mats["accent"],
			"TargetStripe"
		)
	return visual


## Feet sit on the rig origin, so the visual root can be placed straight on the
## floor without a per-profile fudge factor.
static func feet_local_y(_profile: String) -> float:
	return 0.0


static func theme_for_enemy_id(enemy_id: String) -> int:
	var prefix := enemy_id.split("_")[0] if "_" in enemy_id else enemy_id
	match prefix:
		"crystal": return PixelStyle.PaletteTheme.CRYSTAL
		"swamp": return PixelStyle.PaletteTheme.SWAMP
		"frost": return PixelStyle.PaletteTheme.FROZEN
		"cathedral": return PixelStyle.PaletteTheme.CATHEDRAL
		"training": return PixelStyle.PaletteTheme.CASTLE
		_: return PixelStyle.PaletteTheme.CASTLE


static func profile_for_enemy_data(data: Dictionary) -> String:
	var enemy_type: String = data.get("enemy_type", "melee")
	var enemy_id: String = data.get("id", "")
	if enemy_id.contains("hound"):
		return "hound"
	if enemy_id.contains("brute") or enemy_id.contains("golem") or enemy_id.contains("guardian"):
		return "brute"
	return enemy_type


## Maps every animatable pivot to its rest transform and path from the visual root.
## DioramaAnimController feeds this to DioramaAnimLibrary to compile clips.
static func collect_rest_pose(visual: Node3D) -> Dictionary:
	var pose: Dictionary = {}
	if visual == null:
		return pose
	_collect_rest_pose_recursive(visual, visual, pose)
	return pose


static func attach_weapon(visual: Node3D, weapon_id: String, theme: int) -> void:
	var mount := find_part(visual, WEAPON_MOUNT)
	if mount == null:
		return
	for child in mount.get_children():
		mount.remove_child(child)
		child.queue_free()
	if weapon_id == "":
		return
	var weapon := WeaponKit.build(weapon_id, theme)
	if weapon:
		var kit_id := WeaponKit.resolve_id(weapon_id)
		if kit_id == "spear":
			# Tip up (+Y mesh), shaft lowered and shifted forward (-Z) in front of the body.
			weapon.position = Vector3(0.07, -0.48, -0.34)
			weapon.rotation = Vector3(deg_to_rad(14.0), 0.0, deg_to_rad(4.0))
		mount.add_child(weapon)


static func find_part(visual: Node3D, part_name: String) -> Node3D:
	if visual == null:
		return null
	if visual.name == part_name:
		return visual
	for child in visual.get_children():
		if child is Node3D:
			var found := find_part(child as Node3D, part_name)
			if found:
				return found
	return null


## First person hides the upper body but keeps it casting shadows, so the player
## still reads as a physical presence on the floor next to them.
static func apply_first_person(facing: Node3D, enabled: bool) -> void:
	if facing == null:
		return
	var visual := facing.get_node_or_null(VISUAL_NAME) as Node3D
	if visual == null:
		return
	for part_name in FIRST_PERSON_HIDDEN_PARTS:
		var part := find_part(visual, part_name)
		if part:
			_set_shadows_only(part, enabled)
	if not enabled:
		_set_meshes_visible(visual, true)


static func _set_meshes_visible(node: Node, visible: bool) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).visible = visible
	for child in node.get_children():
		_set_meshes_visible(child, visible)


static func _set_shadows_only(node: Node, shadows_only: bool) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			if shadows_only
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)
	for child in node.get_children():
		_set_shadows_only(child, shadows_only)


static func _body_materials(theme: int) -> Dictionary:
	var palette := PixelStyle.get_palette(theme)
	var accent := PixelStyle.make_surface_material(
		PixelStyle.SurfaceKind.PROP, theme, 0.38
	).duplicate() as ShaderMaterial
	accent.set_shader_parameter("color_base", palette[PixelStyle.PaletteSlot.ACCENT])
	accent.set_shader_parameter("color_shadow", palette[PixelStyle.PaletteSlot.ACCENT].darkened(0.22))
	accent.set_shader_parameter("color_accent", palette[PixelStyle.PaletteSlot.EMISSIVE])
	return {
		"body": PixelStyle.make_wall_material(theme),
		"accent": accent,
		"theme": theme,
	}


static func _build_humanoid(visual: Node3D, profile: String, mats: Dictionary) -> Node3D:
	var spec: Dictionary = PROFILES.get(profile, PROFILES["melee"])
	var leg: Vector3 = spec["leg"]
	var torso: Vector3 = spec["torso"]
	var head: Vector3 = spec["head"]
	var arm: Vector3 = spec["arm"]
	var hip_x: float = spec["hip_x"]
	var shoulder_x: float = spec["shoulder_x"]
	var body: Material = mats["body"]
	var accent: Material = mats["accent"]

	var root := _add_pivot(visual, ROOT_NAME, Vector3.ZERO)
	var waist_y := leg.y

	for side in [-1.0, 1.0]:
		var leg_name := "LegL" if side < 0.0 else "LegR"
		var hip := _add_pivot(root, leg_name, Vector3(hip_x * side, waist_y, 0.0))
		PixelStyle.add_box(hip, leg, Vector3(0.0, -leg.y * 0.5, 0.0), body, "Mesh")

	var torso_pivot := _add_pivot(root, "Torso", Vector3(0.0, waist_y, 0.0))
	PixelStyle.add_box(torso_pivot, torso, Vector3(0.0, torso.y * 0.5, 0.0), body, "Mesh")

	var head_pivot := _add_pivot(torso_pivot, "Head", Vector3(0.0, torso.y, 0.0))
	var head_mat: Material = accent if bool(spec.get("head_accent", false)) else body
	PixelStyle.add_box(head_pivot, head, Vector3(0.0, head.y * 0.5, 0.0), head_mat, "Mesh")
	if bool(spec.get("visor", false)):
		PixelStyle.add_box(
			head_pivot,
			Vector3(head.x * 0.5, head.y * 0.28, 0.1),
			Vector3(0.0, head.y * 0.62, head.z * 0.5),
			accent,
			"Visor"
		)

	var shoulder_y := torso.y * 0.88
	for side in [-1.0, 1.0]:
		var arm_name := "ArmL" if side < 0.0 else "ArmR"
		var shoulder := _add_pivot(torso_pivot, arm_name, Vector3(shoulder_x * side, shoulder_y, 0.0))
		PixelStyle.add_box(shoulder, arm, Vector3(0.0, -arm.y * 0.5, 0.0), body, "Mesh")
		var mount_name := SHIELD_MOUNT if side < 0.0 else WEAPON_MOUNT
		_add_pivot(shoulder, mount_name, Vector3(0.0, -arm.y, 0.0))

	var extras: Array = spec.get("extras", [])
	if extras.has("bow"):
		var bow_mount := find_part(root, WEAPON_MOUNT)
		if bow_mount:
			var bow := _add_pivot(bow_mount, "Bow", Vector3.ZERO)
			PixelStyle.add_box(bow, Vector3(0.07, 0.62, 0.07), Vector3(0.0, 0.0, 0.06), accent, "Mesh")
	if extras.has("shield"):
		var shield_mount := find_part(root, SHIELD_MOUNT)
		if shield_mount:
			var shield := _add_pivot(shield_mount, "Shield", Vector3.ZERO)
			PixelStyle.add_box(shield, Vector3(0.12, 0.58, 0.46), Vector3(-0.06, 0.1, 0.06), accent, "Mesh")

	return root


static func _build_quadruped(visual: Node3D, mats: Dictionary) -> Node3D:
	var body: Material = mats["body"]
	var accent: Material = mats["accent"]
	var root := _add_pivot(visual, ROOT_NAME, Vector3.ZERO)
	var leg_h := 0.3
	var body_y := leg_h

	var torso_pivot := _add_pivot(root, "Torso", Vector3(0.0, body_y, 0.0))
	PixelStyle.add_box(torso_pivot, Vector3(0.42, 0.34, 0.78), Vector3(0.0, 0.17, 0.0), body, "Mesh")

	var head_pivot := _add_pivot(torso_pivot, "Head", Vector3(0.0, 0.2, 0.36))
	PixelStyle.add_box(head_pivot, Vector3(0.3, 0.26, 0.34), Vector3(0.0, 0.04, 0.14), accent, "Mesh")
	PixelStyle.add_box(head_pivot, Vector3(0.08, 0.12, 0.08), Vector3(-0.09, 0.2, 0.02), body, "EarL")
	PixelStyle.add_box(head_pivot, Vector3(0.08, 0.12, 0.08), Vector3(0.09, 0.2, 0.02), body, "EarR")

	var tail := _add_pivot(torso_pivot, "Tail", Vector3(0.0, 0.24, -0.38))
	PixelStyle.add_box(tail, Vector3(0.1, 0.1, 0.3), Vector3(0.0, 0.02, -0.15), body, "Mesh")

	# Front pair carries the LegL/LegR names the shared clips animate; the rear
	# pair mirrors them through a duplicate of the same names' motion.
	for entry in [
		{"name": "LegL", "pos": Vector3(-0.16, body_y, 0.26)},
		{"name": "LegR", "pos": Vector3(0.16, body_y, 0.26)},
		{"name": "LegBL", "pos": Vector3(-0.16, body_y, -0.26)},
		{"name": "LegBR", "pos": Vector3(0.16, body_y, -0.26)},
	]:
		var hip := _add_pivot(root, entry["name"], entry["pos"])
		PixelStyle.add_box(hip, Vector3(0.13, leg_h, 0.13), Vector3(0.0, -leg_h * 0.5, 0.0), body, "Mesh")

	return root


static func _add_pivot(parent: Node3D, pivot_name: String, position: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = pivot_name
	pivot.position = position
	parent.add_child(pivot)
	return pivot


static func _collect_rest_pose_recursive(node: Node3D, visual: Node3D, pose: Dictionary) -> void:
	for child in node.get_children():
		if not (child is Node3D):
			continue
		var part := child as Node3D
		if part is MeshInstance3D:
			continue
		pose[part.name] = {
			"path": String(visual.get_path_to(part)),
			"position": part.position,
			"rotation": part.rotation,
		}
		_collect_rest_pose_recursive(part, visual, pose)


static func _make_visual(parent: Node3D) -> Node3D:
	var visual := Node3D.new()
	visual.name = VISUAL_NAME
	parent.add_child(visual)
	return visual


static func _remove_visual(parent: Node3D) -> void:
	var existing := parent.get_node_or_null(VISUAL_NAME)
	if existing:
		parent.remove_child(existing)
		existing.queue_free()
