extends RefCounted
class_name DioramaCharacterSkin


const VISUAL_NAME := "DioramaVisual"
const ROOT_NAME := "Root"
const WEAPON_MOUNT := "WeaponMount"
const SHIELD_MOUNT := "ShieldMount"

const PART_ROOT := ROOT_NAME
const PART_HEAD := "Head"
const PART_VISOR := "Visor"
const PART_HOOD := "Hood"
const FACE_PLATE_NAME := "FacePlate"
const CLASS_GARMENT_NAME := "ClassGarment"
const PART_TORSO := "Torso"
const PART_ARM_L := "ArmL"
const PART_ARM_R := "ArmR"
const PART_BELT_TRIM := "BeltTrim"
const PART_PAULDRON := "Pauldron"
const PART_PAULDRON_R := "PauldronR"

const APPEARANCE_EXTRAS := [PART_VISOR, PART_HOOD, PART_BELT_TRIM, PART_PAULDRON, PART_PAULDRON_R]

static var _warned_missing_parts: Dictionary = {}

const FIRST_PERSON_HIDDEN_PARTS := ["Torso"]

const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const WeaponKit := preload("res://scripts/art/props/diorama_weapon_kit.gd")
const RigCatalog := preload("res://scripts/art/characters/character_rig_catalog.gd")
const VoxelGridScript := preload("res://scripts/art/characters/voxel_grid.gd")
const VoxelMeshBuilderScript := preload("res://scripts/art/characters/voxel_mesh_builder.gd")
const CharacterRigCatalogScript := preload("res://scripts/art/characters/character_rig_catalog.gd")
const MeshMergerScript := preload("res://scripts/art/characters/character_mesh_merger.gd")
const EquipmentKitScript := preload("res://scripts/art/characters/equipment_model_kit.gd")

const EQUIP_VISUAL_PREFIX := "EquipVisual_"

## Marks a node as a mounted equipment model.
##
## The name alone is not enough to find these again. Two pieces of gear can mount to the
## same body part -- a breastplate and an amulet both hang off the torso -- and when the
## second holder is added under a name a sibling already has, Godot drops the name and
## auto-generates `@Node3D@N` instead of suffixing it. That holder then no longer matches
## the `EquipVisual_` prefix, so it survives every later clear: a stale model welded to
## the body, and its geometry counted as part of the body when fitting the next item.
## Metadata survives the rename, so the mark is what clearing and fitting both go by.
const EQUIP_VISUAL_META := &"aumbrye_equip_visual"
const SKIN_TINT_PARAM := &"skin_tint"

const ARENA_DUMMY_ACCENT := Color(1.0, 0.35, 0.1)
const ARENA_DUMMY_GLOW := Color(0.6, 0.2, 0.05)

const PROFILES := {
	"player":
	{
		"leg": Vector3(0.22, 0.46, 0.26),
		"torso": Vector3(0.5, 0.62, 0.34),
		"head": Vector3(0.32, 0.32, 0.32),
		"arm": Vector3(0.2, 0.52, 0.2),
		"hip_x": 0.13,
		"shoulder_x": 0.3,
		"visor": true,
	},
	"melee":
	{
		"leg": Vector3(0.24, 0.48, 0.28),
		"torso": Vector3(0.55, 0.64, 0.38),
		"head": Vector3(0.36, 0.36, 0.36),
		"arm": Vector3(0.22, 0.54, 0.22),
		"hip_x": 0.14,
		"shoulder_x": 0.33,
		"head_accent": true,
	},
	"ranged":
	{
		"leg": Vector3(0.18, 0.44, 0.24),
		"torso": Vector3(0.42, 0.56, 0.3),
		"head": Vector3(0.28, 0.28, 0.28),
		"arm": Vector3(0.16, 0.48, 0.16),
		"hip_x": 0.11,
		"shoulder_x": 0.25,
		"extras": ["bow"],
	},
	"shield":
	{
		"leg": Vector3(0.24, 0.46, 0.3),
		"torso": Vector3(0.64, 0.68, 0.44),
		"head": Vector3(0.34, 0.34, 0.34),
		"arm": Vector3(0.22, 0.52, 0.22),
		"hip_x": 0.15,
		"shoulder_x": 0.36,
		"extras": ["shield"],
	},
	"brute":
	{
		"leg": Vector3(0.28, 0.5, 0.32),
		"torso": Vector3(0.78, 0.82, 0.5),
		"head": Vector3(0.42, 0.42, 0.42),
		"arm": Vector3(0.3, 0.66, 0.3),
		"hip_x": 0.18,
		"shoulder_x": 0.46,
		"head_accent": true,
	},
	"dummy":
	{
		"leg": Vector3(0.24, 0.46, 0.3),
		"torso": Vector3(0.55, 0.66, 0.38),
		"head": Vector3(0.38, 0.38, 0.38),
		"arm": Vector3(0.24, 0.54, 0.24),
		"hip_x": 0.15,
		"shoulder_x": 0.32,
	},
}


static func _character_service() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("CharacterService")


static func build_player_body(facing: Node3D, theme: int = -1) -> Node3D:
	_remove_visual(facing)
	PixelStyle.hide_legacy_meshes(facing)
	var visual := _make_visual(facing)
	var profile := CharacterAppearance.from_service()
	if theme < 0:
		theme = int(profile.get("theme", PixelStyle.PaletteTheme.CASTLE))
	var archetype := CharacterRigCatalogScript.archetype_for_player(profile)
	var root := build_from_manifest(visual, archetype, theme)
	if root == null:
		push_error("DioramaCharacterSkin: %s manifest missing — using box fallback" % archetype)
		_build_humanoid(visual, "player", _body_materials(theme, "player"))
		_apply_player_appearance(visual, profile, _body_materials(theme, "player"))
	else:
		_apply_player_appearance(visual, profile, _body_materials(theme, "player"))
	_ground_rig(visual)
	MeshMergerScript.merge(visual)
	return visual


static func build_preview_body(parent: Node3D, profile: Dictionary) -> Node3D:
	for child in parent.get_children():
		child.queue_free()
	var facing := Node3D.new()
	facing.name = "Facing"
	parent.add_child(facing)
	var clean := CharacterAppearance.sanitize(profile)
	var theme := int(clean.get("theme", PixelStyle.PaletteTheme.CASTLE))
	_warned_missing_parts.clear()
	var visual := _make_visual(facing)
	var archetype := CharacterRigCatalogScript.archetype_for_player(clean)
	var root := build_from_manifest(visual, archetype, theme)
	if root == null:
		_build_humanoid(visual, "player", _body_materials(theme, "player"))
	_apply_player_appearance(visual, clean, _body_materials(theme, "player"))
	_ground_rig(visual)
	MeshMergerScript.merge(visual)
	return visual


static func _require_part(visual: Node3D, part_path: String) -> Node3D:
	if visual == null:
		return null
	var part: Node3D = null
	if part_path.contains("/"):
		var parent_name := part_path.split("/")[0]
		var child_path := part_path.substr(part_path.find("/") + 1)
		var parent_part := find_part(visual, parent_name)
		if parent_part:
			part = parent_part.get_node_or_null(child_path) as Node3D
	else:
		part = find_part(visual, part_path)
	if part == null and not _warned_missing_parts.get(part_path, false):
		_warned_missing_parts[part_path] = true
		push_warning("DioramaCharacterSkin: missing appearance part '%s'" % part_path)
	return part


static func _apply_player_appearance(visual: Node3D, profile: Dictionary, mats: Dictionary) -> void:
	var root := _require_part(visual, PART_ROOT)
	if root:
		root.scale = Vector3.ONE
		root.position = Vector3.ZERO
	_apply_skin_tone(visual, profile, mats)
	var head_style := str(profile.get("head", CharacterAppearance.HEAD_VISOR))
	var head := _require_part(visual, PART_HEAD)
	if head:
		var visor := head.get_node_or_null(PART_VISOR) as Node3D
		if visor:
			visor.visible = head_style == CharacterAppearance.HEAD_VISOR
		var hood := head.get_node_or_null(PART_HOOD) as Node3D
		if hood:
			hood.visible = head_style == CharacterAppearance.HEAD_HOOD
	var trim := int(profile.get("trim", 0))
	var belt := _require_part(visual, PART_BELT_TRIM)
	if belt:
		belt.visible = trim >= 1
	var pauldron_l := _require_part(visual, PART_PAULDRON)
	if pauldron_l:
		pauldron_l.visible = trim >= 2
	var pauldron_r := _require_part(visual, PART_PAULDRON_R)
	if pauldron_r:
		pauldron_r.visible = trim >= 2
	if head_style == CharacterAppearance.HEAD_OPEN:
		_apply_hair(visual, profile, mats)
	_apply_face(visual, profile, mats)
	_apply_class_armor(visual, profile, mats)


static func _apply_skin_tone(visual: Node3D, _profile: Dictionary, _mats: Dictionary) -> void:
	_set_skin_tint(visual, Vector3.ONE)


const AUTHORED_HEAD_VOXELS := 8.0


static func _head_scale(head: Node3D) -> float:
	var head_mesh := head.get_node_or_null("Mesh") as MeshInstance3D
	if head_mesh == null or head_mesh.mesh == null:
		return 1.0
	var side := head_mesh.mesh.get_aabb().size.x / VoxelGridScript.EDGE
	if side <= 0.0:
		return 1.0
	return side / AUTHORED_HEAD_VOXELS


static func _apply_hair(visual: Node3D, profile: Dictionary, mats: Dictionary) -> void:
	var hair := str(profile.get("hair", CharacterAppearance.HAIR_NONE))
	var head := find_part(visual, "Head")
	if head == null or hair == CharacterAppearance.HAIR_NONE:
		return
	var existing := head.get_node_or_null("Hair")
	if existing:
		existing.queue_free()
	var mesh_path := "res://assets/characters/player_warden/hair_%s.voxels.json" % hair
	if not ResourceLoader.exists(mesh_path):
		return
	var mesh: ArrayMesh = VoxelMeshBuilderScript.load_mesh(mesh_path, -1)
	if mesh == null:
		return
	var holder := Node3D.new()
	holder.name = "Hair"
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	mesh_inst.mesh = mesh
	mesh_inst.material_override = _make_voxel_material(int(mats.get("theme", 0)))
	mesh_inst.position = _centre_offset(mesh)
	holder.scale = Vector3.ONE * _head_scale(head)
	var hair_color := CharacterAppearance.hair_color_rgb(
		str(profile.get("hairColor", CharacterAppearance.HAIR_COLOR_BROWN))
	)
	holder.add_child(mesh_inst)
	head.add_child(holder)
	mesh_inst.set_instance_shader_parameter(
		SKIN_TINT_PARAM, Vector3(hair_color.r, hair_color.g, hair_color.b)
	)


static func _apply_face(visual: Node3D, profile: Dictionary, _mats: Dictionary) -> void:
	var head := find_part(visual, PART_HEAD)
	if head == null:
		return
	var existing := head.get_node_or_null(FACE_PLATE_NAME)
	if existing:
		head.remove_child(existing)
		existing.queue_free()
	var head_style := str(profile.get("head", CharacterAppearance.HEAD_VISOR))
	if head_style != CharacterAppearance.HEAD_OPEN:
		return
	var face := str(profile.get("face", CharacterAppearance.FACE_OPEN))
	var mesh_path := "res://assets/characters/player_warden/face_%s.voxels.json" % face
	if not ResourceLoader.exists(mesh_path):
		return
	var mesh: ArrayMesh = VoxelMeshBuilderScript.load_mesh(mesh_path, -1)
	if mesh == null:
		return
	var holder := _add_pivot(head, FACE_PLATE_NAME, Vector3.ZERO)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	mesh_inst.mesh = mesh
	mesh_inst.material_override = _make_voxel_material(0)
	var head_mesh := head.get_node_or_null("Mesh") as MeshInstance3D
	var head_front := 0.16
	var head_base := 0.0
	if head_mesh != null and head_mesh.mesh != null:
		var bounds := head_mesh.mesh.get_aabb()
		head_front = head_mesh.position.z + bounds.position.z + bounds.size.z
		head_base = head_mesh.position.y + bounds.position.y
	var plate := mesh.get_aabb()
	mesh_inst.position = Vector3(
		-(plate.position.x + plate.size.x * 0.5),
		head_base + VoxelGridScript.EDGE * 2.0 - plate.position.y,
		head_front - plate.position.z - VoxelGridScript.EDGE * 0.25
	)
	var skin := CharacterAppearance.skin_color_rgb(
		str(profile.get("skinTone", CharacterAppearance.SKIN_TONE_NEUTRAL))
	)
	mesh_inst.scale = Vector3.ONE * _head_scale(head)
	holder.add_child(mesh_inst)
	mesh_inst.set_instance_shader_parameter(SKIN_TINT_PARAM, Vector3(skin.r, skin.g, skin.b))


static func _apply_class_armor(visual: Node3D, profile: Dictionary, _mats: Dictionary) -> void:
	var torso := find_part(visual, PART_TORSO)
	if torso == null:
		return
	var existing := torso.get_node_or_null(CLASS_GARMENT_NAME)
	if existing:
		torso.remove_child(existing)
		existing.queue_free()
	var class_id := str(profile.get("classId", ""))
	if class_id == "":
		var svc := _character_service()
		if svc and svc.has_method("get_class_id"):
			class_id = str(svc.call("get_class_id"))
	if class_id == "":
		return
	var mesh_path := _garment_path(profile, class_id)
	if mesh_path == "":
		return
	var mesh: ArrayMesh = VoxelMeshBuilderScript.load_mesh(mesh_path, -1)
	if mesh == null:
		return
	var torso_mesh := torso.get_node_or_null("Mesh") as MeshInstance3D
	if torso_mesh == null or torso_mesh.mesh == null:
		return
	var torso_bounds := torso_mesh.mesh.get_aabb()
	var torso_base := torso_mesh.position.y + torso_bounds.position.y
	var garment := mesh.get_aabb()
	var holder := _add_pivot(torso, CLASS_GARMENT_NAME, Vector3.ZERO)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	mesh_inst.mesh = mesh
	mesh_inst.material_override = _make_voxel_material(0)
	mesh_inst.position = Vector3(
		-(garment.position.x + garment.size.x * 0.5),
		torso_base - VoxelGridScript.EDGE * float(_garment_skirt_drop(mesh_path)),
		-(garment.position.z + garment.size.z * 0.5)
	)
	holder.add_child(mesh_inst)


static func _garment_path(profile: Dictionary, class_id: String) -> String:
	var archetype := CharacterRigCatalogScript.archetype_for_player(profile)
	var path := "res://assets/characters/%s/garment_%s.voxels.json" % [archetype, class_id]
	if ResourceLoader.exists(path):
		return path
	push_warning("DioramaCharacterSkin: no %s garment for %s, using the base warden's"
		% [class_id, archetype])
	var fallback := "res://assets/characters/player_warden/garment_%s.voxels.json" % class_id
	return fallback if ResourceLoader.exists(fallback) else ""


static func _garment_skirt_drop(mesh_path: String) -> int:
	var text := FileAccess.get_file_as_string(mesh_path)
	if text.is_empty():
		return 0
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return 0
	return int((parsed as Dictionary).get("skirtDrop", 0))


static func build_enemy_body(
	parent: Node3D,
	enemy_type: String = "melee",
	theme: int = PixelStyle.PaletteTheme.CASTLE,
	enemy_id: String = "",
	enemy_data: Dictionary = {}
) -> Node3D:
	_remove_visual(parent)
	PixelStyle.hide_legacy_meshes(parent)
	var visual := _make_visual(parent)
	var mats := _body_materials(theme)
	var profile := enemy_type.to_lower()
	if profile == "hound":
		var hound_archetype := CharacterRigCatalogScript.archetype_for_enemy(enemy_id, enemy_data)
		if CharacterRigCatalogScript.has_manifest(hound_archetype):
			var hound_root := build_from_manifest(visual, hound_archetype, theme)
			if hound_root != null:
				_ground_rig(visual)
				MeshMergerScript.merge(visual)
				return visual
		_build_quadruped(visual, mats)
	else:
		var resolved := profile if PROFILES.has(profile) else "melee"
		var archetype := CharacterRigCatalogScript.archetype_for_enemy(enemy_id, enemy_data)
		if not CharacterRigCatalogScript.has_manifest(archetype):
			archetype = _archetype_id_for_profile(profile if PROFILES.has(profile) else "melee")
		var root := build_from_manifest(visual, archetype, theme)
		if root == null:
			push_error(
				"DioramaCharacterSkin: %s manifest missing — using box fallback" % archetype
			)
			_build_humanoid(visual, resolved if PROFILES.has(profile) else "melee", mats)
	_ground_rig(visual)
	MeshMergerScript.merge(visual)
	return visual


static func build_training_dummy(parent: Node3D) -> Node3D:
	_remove_visual(parent)
	PixelStyle.hide_legacy_meshes(parent)
	var visual := _make_visual(parent)
	var theme := PixelStyle.PaletteTheme.CASTLE
	var mats := _body_materials(theme, "dummy")
	mats["accent"] = PixelStyle.make_material(ARENA_DUMMY_ACCENT, ARENA_DUMMY_GLOW)
	var root := build_from_manifest(visual, "enemy_dummy", theme)
	if root == null:
		push_error("DioramaCharacterSkin: enemy_dummy manifest missing — using box fallback")
		_build_humanoid(visual, "dummy", mats)
	_ground_rig(visual)
	MeshMergerScript.merge(visual)
	return visual


const MAX_GROUNDING_CORRECTION := 0.8


const HANGING_PARTS: PackedStringArray = ["LegL", "LegR", "LegBL", "LegBR"]


static func _hang_offset(mesh: ArrayMesh) -> float:
	if mesh == null:
		return 0.0
	var aabb := mesh.get_aabb()
	if aabb.size.y <= 0.0:
		return 0.0
	return -(aabb.position.y + aabb.size.y)


static func _centre_offset(mesh: ArrayMesh) -> Vector3:
	if mesh == null:
		return Vector3.ZERO
	var aabb := mesh.get_aabb()
	return Vector3(
		-(aabb.position.x + aabb.size.x * 0.5), 0.0, -(aabb.position.z + aabb.size.z * 0.5)
	)


static func _ground_rig(visual: Node3D) -> void:
	if visual == null:
		return
	var min_y := rig_mesh_min_y(visual)
	if absf(min_y) <= 0.001:
		return
	if absf(min_y) > MAX_GROUNDING_CORRECTION:
		push_error(
			"DioramaCharacterSkin: rig %s sits %.3f from the floor, too far to be a limb offset"
			% [String(visual.get_parent().name) if visual.get_parent() else "visual", min_y]
		)
		return
	var root := visual.get_node_or_null(NodePath(ROOT_NAME)) as Node3D
	var target := root if root != null else visual
	target.position.y -= min_y


static func rig_mesh_min_y(visual: Node3D) -> float:
	var aabb := _combined_mesh_aabb_local(visual)
	return aabb.position.y if aabb.size != Vector3.ZERO else 0.0


static func _combined_mesh_aabb_local(root: Node3D) -> AABB:
	var result := AABB()
	var has_any := false
	for mesh in _gather_mesh_instances(root):
		if mesh.mesh == null:
			continue
		var mesh_aabb := mesh.mesh.get_aabb()
		var local_xform := root.global_transform.affine_inverse() * mesh.global_transform
		var local_aabb := local_xform * mesh_aabb
		if not has_any:
			result = local_aabb
			has_any = true
		else:
			result = result.merge(local_aabb)
	return result if has_any else AABB()


static func _gather_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_gather_mesh_instances(child))
	return out


static func theme_for_enemy_id(enemy_id: String) -> int:
	var prefix := enemy_id.split("_")[0] if "_" in enemy_id else enemy_id
	match prefix:
		"crystal":
			return PixelStyle.PaletteTheme.CRYSTAL
		"swamp":
			return PixelStyle.PaletteTheme.SWAMP
		"frost":
			return PixelStyle.PaletteTheme.FROZEN
		"cathedral":
			return PixelStyle.PaletteTheme.CATHEDRAL
		"iron", "vault":
			return PixelStyle.PaletteTheme.VAULT
		"prism":
			return PixelStyle.PaletteTheme.PRISM
		"venom", "mire":
			return PixelStyle.PaletteTheme.MIRE
		"glacial", "hollow":
			return PixelStyle.PaletteTheme.HOLLOW
		"umbral", "dark":
			return PixelStyle.PaletteTheme.UMBRAL
		"training", "castle", "forgotten":
			return PixelStyle.PaletteTheme.CASTLE
		_:
			return PixelStyle.PaletteTheme.CASTLE


static func profile_for_enemy_data(data: Dictionary) -> String:
	var enemy_type: String = data.get("enemy_type", "melee")
	var enemy_id: String = data.get("id", "")
	if enemy_id.contains("hound"):
		return "hound"
	if enemy_id.contains("brute") or enemy_id.contains("golem") or enemy_id.contains("guardian"):
		return "brute"
	return enemy_type


static func rest_pose_for_profile(profile: String) -> Dictionary:
	var holder := Node3D.new()
	var visual := _make_visual(holder)
	if profile == "hound":
		_build_reference_quadruped(visual)
	elif PROFILES.has(profile):
		_build_reference_humanoid(visual, profile)
	else:
		holder.free()
		return {}
	var pose := collect_rest_pose(visual)
	holder.free()
	return pose


static func _build_reference_humanoid(visual: Node3D, profile: String) -> Node3D:
	var spec: Dictionary = PROFILES.get(profile, PROFILES["melee"])
	var leg: Vector3 = spec["leg"]
	var torso: Vector3 = spec["torso"]
	var arm: Vector3 = spec["arm"]
	var hip_x: float = spec["hip_x"]
	var shoulder_x: float = spec["shoulder_x"]
	var root := _add_pivot(visual, ROOT_NAME, Vector3.ZERO)
	var waist_y := leg.y
	for side in [-1.0, 1.0]:
		var leg_name := "LegL" if side < 0.0 else "LegR"
		_add_pivot(root, leg_name, Vector3(hip_x * side, waist_y, 0.0))
	var torso_pivot := _add_pivot(root, "Torso", Vector3(0.0, waist_y, 0.0))
	_add_pivot(torso_pivot, "Head", Vector3(0.0, torso.y, 0.0))
	var shoulder_y := torso.y * 0.88
	for side in [-1.0, 1.0]:
		var arm_name := "ArmL" if side < 0.0 else "ArmR"
		var shoulder := _add_pivot(
			torso_pivot, arm_name, Vector3(shoulder_x * side, shoulder_y, 0.0)
		)
		var mount_name := SHIELD_MOUNT if side < 0.0 else WEAPON_MOUNT
		_add_pivot(shoulder, mount_name, Vector3(0.0, -arm.y, 0.0))
	var extras: Array = spec.get("extras", [])
	if extras.has("bow"):
		var bow_mount := find_part(root, WEAPON_MOUNT)
		if bow_mount:
			_add_pivot(bow_mount, "Bow", Vector3.ZERO)
	if extras.has("shield"):
		var shield_mount := find_part(root, SHIELD_MOUNT)
		if shield_mount:
			_add_pivot(shield_mount, "Shield", Vector3.ZERO)
	return root


static func _build_reference_quadruped(visual: Node3D) -> Node3D:
	var root := _add_pivot(visual, ROOT_NAME, Vector3.ZERO)
	var leg_h := 0.3
	var body_y := leg_h
	var torso_pivot := _add_pivot(root, "Torso", Vector3(0.0, body_y, 0.0))
	_add_pivot(torso_pivot, "Head", Vector3(0.0, 0.2, 0.36))
	_add_pivot(torso_pivot, "Tail", Vector3(0.0, 0.24, -0.38))
	for entry in [
		{"name": "LegL", "pos": Vector3(-0.16, body_y, 0.26)},
		{"name": "LegR", "pos": Vector3(0.16, body_y, 0.26)},
		{"name": "LegBL", "pos": Vector3(-0.16, body_y, -0.26)},
		{"name": "LegBR", "pos": Vector3(0.16, body_y, -0.26)},
	]:
		_add_pivot(root, entry["name"], entry["pos"])
	return root


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
		if child.name in ["Bow", "Shield"]:
			continue
		mount.remove_child(child)
		child.queue_free()
	if weapon_id == "":
		return
	var weapon := WeaponKit.build(weapon_id, theme)
	if weapon:
		var kit_id := WeaponKit.resolve_id(weapon_id)
		var target_mount := mount
		if kit_id == "bow":
			var bow_pivot := find_part(visual, "Bow")
			if bow_pivot == null:
				bow_pivot = _add_pivot(mount, "Bow", Vector3.ZERO)
			for child in bow_pivot.get_children():
				bow_pivot.remove_child(child)
				child.queue_free()
			target_mount = bow_pivot
		if kit_id == "spear":
			weapon.position = Vector3(0.04, -0.12, -0.22)
			weapon.rotation = Vector3(deg_to_rad(82.0), 0.0, deg_to_rad(2.0))
		if visual.name == "ViewRoot":
			_disable_cast_shadows(weapon)
		target_mount.add_child(weapon)


static func apply_body_tint(visual: Node3D, tint: Color) -> void:
	if visual == null:
		return
	for mesh_inst in _collect_mesh_instances(visual):
		var mat := mesh_inst.material_override
		if mat is ShaderMaterial:
			var shader_mat := (mat as ShaderMaterial).duplicate() as ShaderMaterial
			var base: Variant = shader_mat.get_shader_parameter("color_base")
			var blended := tint if not (base is Color) else (base as Color).lerp(tint, 0.65)
			shader_mat.set_shader_parameter("color_base", blended)
			shader_mat.set_shader_parameter("color_shadow", blended.darkened(0.28))
			mesh_inst.material_override = shader_mat
		elif mat is StandardMaterial3D:
			var standard := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			standard.albedo_color = standard.albedo_color.lerp(tint, 0.65)
			mesh_inst.material_override = standard


static func _collect_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_collect_mesh_instances(child))
	return out


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
	_apply_first_person_weapon_shadows(visual, enabled)
	if not enabled:
		_set_meshes_visible(visual, true)


static func sync_first_person_weapon_shadows(visual: Node3D, first_person: bool) -> void:
	_apply_first_person_weapon_shadows(visual, first_person)


## Keeps the held weapon in step with the body it hangs off.
##
## The mounts sit under `Torso`, so the loop above has already put them in shadows-only -- but a
## weapon model built *after* that call, which is every weapon swap, comes in drawing normally. This
## used to set the mounts to `SHADOW_CASTING_SETTING_OFF`, and `OFF` does not mean hidden: it means
## drawn, casting nothing. That re-showed the third-person weapon at the player's hand, a few
## centimetres from a first-person camera, so the real sword swung through the view alongside the
## viewmodel's. Matching the torso keeps the silhouette's shadow armed and the geometry out of frame.
static func _apply_first_person_weapon_shadows(visual: Node3D, first_person: bool) -> void:
	for mount_name in [WEAPON_MOUNT, SHIELD_MOUNT, "Bow"]:
		var mount := find_part(visual, mount_name)
		if mount:
			_set_shadows_only(mount, first_person)


static func _disable_cast_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_cast_shadows(child)


static func _set_meshes_visible(node: Node, visible: bool) -> void:
	if node is GeometryInstance3D:
		var already_merged := visible and MeshMergerScript.is_merged_source(node as MeshInstance3D)
		if not already_merged:
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


static func _body_materials(theme: int, profile: String = "melee") -> Dictionary:
	var palette := PixelStyle.get_palette(theme)
	var accent_base := palette[PixelStyle.PaletteSlot.ACCENT]
	match profile:
		"shield":
			accent_base = palette[PixelStyle.PaletteSlot.PROP_METAL].lerp(accent_base, 0.55)
		"brute":
			accent_base = palette[PixelStyle.PaletteSlot.WALL_SHADOW].lerp(accent_base, 0.35)
		"ranged":
			accent_base = palette[PixelStyle.PaletteSlot.EMISSIVE].darkened(0.12)
		"melee", "player":
			accent_base = accent_base.lightened(0.04)
	var accent := (
		PixelStyle.make_surface_material(PixelStyle.SurfaceKind.PROP, theme, 0.38).duplicate()
		as ShaderMaterial
	)
	accent.set_shader_parameter("color_base", accent_base)
	accent.set_shader_parameter("color_shadow", accent_base.darkened(0.22))
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
		var shoulder := _add_pivot(
			torso_pivot, arm_name, Vector3(shoulder_x * side, shoulder_y, 0.0)
		)
		PixelStyle.add_box(shoulder, arm, Vector3(0.0, -arm.y * 0.5, 0.0), body, "Mesh")
		var mount_name := SHIELD_MOUNT if side < 0.0 else WEAPON_MOUNT
		_add_pivot(shoulder, mount_name, Vector3(0.0, -arm.y, 0.0))

	var extras: Array = spec.get("extras", [])
	if extras.has("bow"):
		var bow_mount := find_part(root, WEAPON_MOUNT)
		if bow_mount:
			var bow := _add_pivot(bow_mount, "Bow", Vector3.ZERO)
			PixelStyle.add_box(
				bow, Vector3(0.07, 0.62, 0.07), Vector3(0.0, 0.0, 0.06), accent, "Mesh"
			)
	if extras.has("shield"):
		var shield_mount := find_part(root, SHIELD_MOUNT)
		if shield_mount:
			var shield := _add_pivot(shield_mount, "Shield", Vector3.ZERO)
			PixelStyle.add_box(
				shield, Vector3(0.12, 0.58, 0.46), Vector3(-0.06, 0.1, 0.06), accent, "Mesh"
			)

	return root


static func _build_quadruped(visual: Node3D, mats: Dictionary) -> Node3D:
	var body: Material = mats["body"]
	var accent: Material = mats["accent"]
	var root := _add_pivot(visual, ROOT_NAME, Vector3.ZERO)
	var leg_h := 0.3
	var body_y := leg_h

	var torso_pivot := _add_pivot(root, "Torso", Vector3(0.0, body_y, 0.0))
	PixelStyle.add_box(
		torso_pivot, Vector3(0.42, 0.34, 0.78), Vector3(0.0, 0.17, 0.0), body, "Mesh"
	)

	var head_pivot := _add_pivot(torso_pivot, "Head", Vector3(0.0, 0.2, 0.36))
	PixelStyle.add_box(
		head_pivot, Vector3(0.3, 0.26, 0.34), Vector3(0.0, 0.04, 0.14), accent, "Mesh"
	)
	PixelStyle.add_box(
		head_pivot, Vector3(0.08, 0.12, 0.08), Vector3(-0.09, 0.2, 0.02), body, "EarL"
	)
	PixelStyle.add_box(
		head_pivot, Vector3(0.08, 0.12, 0.08), Vector3(0.09, 0.2, 0.02), body, "EarR"
	)

	var tail := _add_pivot(torso_pivot, "Tail", Vector3(0.0, 0.24, -0.38))
	PixelStyle.add_box(tail, Vector3(0.1, 0.1, 0.3), Vector3(0.0, 0.02, -0.15), body, "Mesh")

	for entry in [
		{"name": "LegL", "pos": Vector3(-0.16, body_y, 0.26)},
		{"name": "LegR", "pos": Vector3(0.16, body_y, 0.26)},
		{"name": "LegBL", "pos": Vector3(-0.16, body_y, -0.26)},
		{"name": "LegBR", "pos": Vector3(0.16, body_y, -0.26)},
	]:
		var hip := _add_pivot(root, entry["name"], entry["pos"])
		PixelStyle.add_box(
			hip, Vector3(0.13, leg_h, 0.13), Vector3(0.0, -leg_h * 0.5, 0.0), body, "Mesh"
		)

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


const CONTACT_SHADOW_SIZE := Vector3(1.35, 1.5, 1.35)
const CONTACT_SHADOW_ALPHA := 0.88
const CONTACT_SHADOW_NAME := "ContactShadow"


static func _make_visual(parent: Node3D) -> Node3D:
	var visual := Node3D.new()
	visual.name = VISUAL_NAME
	visual.set_meta(&"owned_materials", true)
	parent.add_child(visual)
	_attach_contact_shadow(visual)
	return visual


static func _attach_contact_shadow(visual: Node3D) -> void:
	if visual.has_node(CONTACT_SHADOW_NAME):
		return
	var decal := Decal.new()
	decal.name = CONTACT_SHADOW_NAME
	decal.size = CONTACT_SHADOW_SIZE
	decal.position = Vector3(0.0, 0.45, 0.0)
	decal.texture_albedo = _contact_shadow_texture()
	decal.modulate = Color(0.0, 0.0, 0.0, CONTACT_SHADOW_ALPHA)
	decal.albedo_mix = 1.0
	decal.upper_fade = 0.15
	decal.lower_fade = 0.25
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 22.0
	decal.distance_fade_length = 8.0
	visual.add_child(decal)


static var _contact_shadow_tex: Texture2D


static func _contact_shadow_texture() -> Texture2D:
	if _contact_shadow_tex != null:
		return _contact_shadow_tex
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.55, Color(1, 1, 1, 0.65))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	_contact_shadow_tex = tex
	return tex


static func _remove_visual(parent: Node3D) -> void:
	var existing := parent.get_node_or_null(VISUAL_NAME)
	if existing:
		parent.remove_child(existing)
		existing.queue_free()


static func build_from_manifest(visual: Node3D, archetype_id: String, theme: int) -> Node3D:
	var manifest := CharacterRigCatalogScript.get_manifest(archetype_id)
	if manifest.is_empty():
		return null
	var grid: float = float(manifest.get("grid", VoxelGridScript.EDGE))
	var parts: Dictionary = manifest.get("parts", {})
	if parts.is_empty():
		return null
	var mat := _make_voxel_material(theme)
	var root := _add_pivot(visual, ROOT_NAME, Vector3.ZERO)
	var built: Dictionary = {ROOT_NAME: root}
	var remaining: Array = parts.keys()
	while remaining.size() > 0:
		var progressed := false
		for i in range(remaining.size() - 1, -1, -1):
			var part_name: String = str(remaining[i])
			var part_def: Dictionary = parts[part_name]
			var parent_name := str(part_def.get("parent", ROOT_NAME))
			if not built.has(parent_name):
				continue
			var parent_node := built[parent_name] as Node3D
			var joint_arr: Array = part_def.get("joint", [0, 0, 0])
			var pivot := _add_pivot(
				parent_node, part_name, VoxelGridScript.joint_to_metres(joint_arr)
			)
			built[part_name] = pivot
			var mesh_path: String = str(part_def.get("mesh", ""))
			var mesh: ArrayMesh = VoxelMeshBuilderScript.load_mesh(mesh_path, theme)
			if mesh == null:
				push_error(
					"DioramaCharacterSkin: missing mesh %s for %s" % [mesh_path, archetype_id]
				)
				return null
			var mesh_inst := MeshInstance3D.new()
			mesh_inst.name = "Mesh"
			mesh_inst.mesh = mesh
			mesh_inst.material_override = mat
			var mesh_offset_arr: Array = part_def.get("meshOffset", [0, 0, 0])
			var mesh_offset := Vector3(
				float(mesh_offset_arr[0]) * grid,
				float(mesh_offset_arr[1]) * grid,
				float(mesh_offset_arr[2]) * grid
			)
			if not part_def.has("meshOffset") and part_name in HANGING_PARTS:
				mesh_offset.y = _hang_offset(mesh)
			var centred := _centre_offset(mesh)
			mesh_offset.x += centred.x
			mesh_offset.z += centred.z
			mesh_inst.position = mesh_offset
			pivot.add_child(mesh_inst)
			if part_def.has("mount"):
				_add_pivot(pivot, str(part_def.get("mount")), mesh_inst.position)
			remaining.remove_at(i)
			progressed = true
		if not progressed:
			push_error(
				"DioramaCharacterSkin: unresolved part hierarchy in manifest %s" % archetype_id
			)
			return null
	_attach_manifest_extras(visual, manifest.get("extras", {}), grid, mat)
	return root


static func _attach_manifest_extras(
	visual: Node3D,
	extras: Dictionary,
	grid: float,
	mat: Material
) -> void:
	for extra_name in extras:
		var extra_def: Dictionary = extras[extra_name]
		var parent_name := str(extra_def.get("parent", ROOT_NAME))
		var parent := find_part(visual, parent_name)
		if parent == null:
			continue
		var offset_arr: Array = extra_def.get("offset", [0, 0, 0])
		var offset := Vector3(
			float(offset_arr[0]) * grid,
			float(offset_arr[1]) * grid,
			float(offset_arr[2]) * grid
		)
		var mesh_path := str(extra_def.get("mesh", ""))
		var mesh: ArrayMesh = VoxelMeshBuilderScript.load_mesh(mesh_path, -1)
		if mesh == null:
			push_warning("DioramaCharacterSkin: missing extra mesh %s" % mesh_path)
			continue
		var holder := _add_pivot(parent, str(extra_name), offset)
		if str(extra_name) in APPEARANCE_EXTRAS:
			holder.visible = false
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "Mesh"
		mesh_inst.mesh = mesh
		mesh_inst.position = _centre_offset(mesh)
		mesh_inst.material_override = mat
		holder.add_child(mesh_inst)


static func _archetype_id_for_profile(profile: String) -> String:
	match profile:
		"player":
			return "player_warden"
		"ranged":
			return "enemy_ranged"
		"brute":
			return "enemy_brute"
		_:
			return "enemy_melee"


static var _untinted_material_cache: Dictionary = {}


static func _make_voxel_material(theme: int) -> ShaderMaterial:
	if _untinted_material_cache.has(theme):
		return _untinted_material_cache[theme]
	var mat := (
		PixelStyle.make_surface_material(PixelStyle.SurfaceKind.PROP, theme, 0.38).duplicate()
		as ShaderMaterial
	)
	mat.set_shader_parameter("use_vertex_color", true)
	_untinted_material_cache[theme] = mat
	return mat


static func _set_skin_tint(node: Node, tint: Vector3) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null:
		mesh.set_instance_shader_parameter(SKIN_TINT_PARAM, tint)
	for child in node.get_children():
		_set_skin_tint(child, tint)


const META_DEFAULT_VISIBLE := &"skin_default_visible"


## The rig's bare state, recorded once per character and restored before every equipment pass.
## It cannot be inferred from the mesh merger's flag: a part hidden by armour is deliberately not
## merged and so never carries one, which is what used to leave the head missing on unequip.
static func _capture_default_visibility(node: Node) -> void:
	var mesh := node as GeometryInstance3D
	if mesh != null and not mesh.has_meta(META_DEFAULT_VISIBLE):
		mesh.set_meta(META_DEFAULT_VISIBLE, mesh.visible)
	for child in node.get_children():
		_capture_default_visibility(child)


static func _restore_default_visibility(node: Node) -> void:
	var mesh := node as GeometryInstance3D
	if mesh != null and mesh.has_meta(META_DEFAULT_VISIBLE):
		mesh.visible = bool(mesh.get_meta(META_DEFAULT_VISIBLE))
	for child in node.get_children():
		_restore_default_visibility(child)


## The order slots are dressed in, worst-fitting first.
##
## A dictionary iterates in insertion order, which is whatever order the save happened to equip
## things in — so a pendant could be built before the breastplate it is supposed to hang over. This
## fixes the order outright, and puts neckwear last so it is always the outermost layer.
const EQUIP_DRESS_ORDER: Array[String] = [
	"chest", "helmet", "gloves", "boots", "secondary", "weapon", "relic", "ring", "amulet"
]


static func apply_equipment(visual: Node3D, equipped: Dictionary, theme: int) -> void:
	if visual == null:
		return
	MeshMergerScript.unmerge(visual)
	_clear_equipment_visuals(visual)
	_capture_default_visibility(visual)
	_restore_default_visibility(visual)
	var slots: Array[String] = []
	for slot_name in EQUIP_DRESS_ORDER:
		if equipped.has(slot_name):
			slots.append(slot_name)
	for slot_name in equipped:
		if not (str(slot_name) in slots):
			slots.append(str(slot_name))
	for slot_name in slots:
		var inst: Dictionary = equipped.get(slot_name, {})
		if inst.is_empty():
			continue
		var item_id := str(inst.get("itemId", ""))
		if item_id == "":
			continue
		var def := ItemCatalog.get_definition(item_id)
		var vis: Dictionary = def.get("visual", {})
		if vis.is_empty():
			vis = EquipmentKitScript.visual_for(item_id, str(slot_name), def)
		if vis.is_empty():
			continue
		_apply_equipment_visual(visual, vis, theme)
	MeshMergerScript.merge(visual)


static func _clear_equipment_visuals(visual: Node3D) -> void:
	for node in _collect_equipment_visuals(visual):
		node.get_parent().remove_child(node)
		node.queue_free()


## Every mounted equipment model under `root`. Matches the metadata mark first and the
## name second, so holders written before the mark existed are still cleaned up.
static func _collect_equipment_visuals(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	if is_equipment_visual(root):
		found.append(root)
	for child in root.get_children():
		found.append_array(_collect_equipment_visuals(child))
	return found


static func is_equipment_visual(node: Node) -> bool:
	return node.has_meta(EQUIP_VISUAL_META) or str(node.name).begins_with(EQUIP_VISUAL_PREFIX)


const NESTED_PARTS: Array[String] = [
	PART_ARM_L, PART_ARM_R, PART_HEAD, PART_TORSO, "LegL", "LegR"
]


static func _part_own_aabb(part: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect_own_boxes(part, part, boxes)
	if boxes.is_empty():
		return AABB()
	var result: AABB = boxes[0]
	for i in range(1, boxes.size()):
		result = result.merge(boxes[i])
	return result


static func _collect_own_boxes(node: Node, root: Node3D, out: Array[AABB]) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		var local := root.global_transform.affine_inverse() * mesh.global_transform
		out.append(local * mesh.mesh.get_aabb())
	for child in node.get_children():
		if str(child.name) in NESTED_PARTS or is_equipment_visual(child):
			continue
		_collect_own_boxes(child, root, out)


static func _hide_part_meshes(part: Node, hidden: bool) -> void:
	if part is GeometryInstance3D:
		var already_merged := (
			not hidden and MeshMergerScript.is_merged_source(part as MeshInstance3D)
		)
		if not already_merged:
			(part as GeometryInstance3D).visible = not hidden
	for child in part.get_children():
		# Hiding a body part must not hide the gear worn on it -- a breastplate covering
		# the torso should not take an already-mounted pendant with it.
		if str(child.name) in NESTED_PARTS or is_equipment_visual(child):
			continue
		_hide_part_meshes(child, hidden)


static func _apply_equipment_visual(visual: Node3D, vis: Dictionary, theme: int) -> void:
	# `attach` is a list now: a pair of gauntlets or boots is one model worn on two limbs, and the
	# second copy is mirrored across X so the thumb and the buckles end up on the right sides.
	var attach_names: Array = []
	var raw_attach: Variant = vis.get("attach", "")
	if raw_attach is Array:
		attach_names = (raw_attach as Array).duplicate()
	elif str(raw_attach) != "":
		attach_names = [str(raw_attach)]
	if attach_names.is_empty():
		return
	var voxels: Dictionary = vis.get("voxels", {})
	var mesh: ArrayMesh = null
	var mesh_path := str(vis.get("mesh", ""))
	if mesh_path != "":
		mesh = VoxelMeshBuilderScript.load_mesh(mesh_path, theme)
		if mesh == null:
			push_error("DioramaCharacterSkin: equipment mesh missing %s" % mesh_path)
			return
	elif not voxels.is_empty():
		mesh = _kit_mesh(vis, voxels, theme, false)
	if mesh == null:
		return
	for hide_name in vis.get("hide", []):
		var hidden := find_part(visual, str(hide_name))
		if hidden:
			_hide_part_meshes(hidden, true)
	# The mirrored copy is built from mirrored *voxels* rather than from a negative scale, which
	# would flip the triangle winding and turn the model inside out.
	var mirror_extras := bool(vis.get("mirror_after_first", false)) and not voxels.is_empty()
	var mirrored_mesh: ArrayMesh = null
	for i in attach_names.size():
		var attach_name := str(attach_names[i])
		var mount := find_part(visual, attach_name)
		if mount == null:
			continue
		var use := mesh
		if mirror_extras and i > 0:
			if mirrored_mesh == null:
				mirrored_mesh = _kit_mesh(vis, voxels, theme, true)
			if mirrored_mesh != null:
				use = mirrored_mesh
		_mount_equipment_mesh(mount, attach_name, use, vis, theme)


## Kit models are rebuilt whenever equipment changes, and equipment is reapplied on every stat
## refresh — so the meshes are cached by item, slot and theme rather than remeshed each time.
static var _kit_mesh_cache: Dictionary = {}


static func _kit_mesh(
	vis: Dictionary, voxels: Dictionary, theme: int, mirrored: bool
) -> ArrayMesh:
	var key := str(vis.get("cache_key", ""))
	if key == "":
		if mirrored:
			return VoxelMeshBuilderScript.build_from_data(_mirror_voxels(voxels), theme)
		return VoxelMeshBuilderScript.build_from_data(voxels, theme)
	key = "%s|%d|%s" % [key, theme, str(mirrored)]
	if _kit_mesh_cache.has(key):
		return _kit_mesh_cache[key]
	var data := _mirror_voxels(voxels) if mirrored else voxels
	var mesh := VoxelMeshBuilderScript.build_from_data(data, theme, key)
	_kit_mesh_cache[key] = mesh
	return mesh


## The same voxel model reflected across X.
static func _mirror_voxels(voxels: Dictionary) -> Dictionary:
	var cells: Array = voxels.get("cells", [])
	var max_x := 0
	for cell in cells:
		if cell is Array and (cell as Array).size() >= 1:
			max_x = maxi(max_x, int(cell[0]))
	var flipped: Array = []
	for cell in cells:
		if not (cell is Array) or (cell as Array).size() < 3:
			continue
		var c: Array = cell
		var mat := int(c[3]) if c.size() >= 4 else 0
		flipped.append([max_x - int(c[0]), int(c[1]), int(c[2]), mat])
	var out := voxels.duplicate(true)
	out["cells"] = flipped
	return out


## The thinnest gap that can still be drawn: one voxel of the grid everything here is modelled on.
##
## A worn model that surrounds a body part by less than this puts its surface inside a single voxel
## of the skin underneath. At the resolution the diorama renders at, those two surfaces land on the
## same pixel and the depth test has no way to order them, so the seam flickers between armour and
## body as the camera moves — the "pixels clipping on equipment" the player actually sees.
##
## Measured against the authored fits, six of the eight surrounding axes were under one voxel: a
## hood cleared the head by 0.20 of a voxel, gauntlets cleared the arm by 0.37, and a breastplate
## cleared the torso's front face by 0.85. Only slots that hide the part beneath them were safe.
const EQUIP_MIN_CLEARANCE := VoxelGridScript.EDGE


## Grows a worn model just enough that it clears the part it is worn on.
##
## Only axes where the model already surrounds the part are touched, so a pendant sitting in front
## of the chest or a breastplate that stops above the waist keeps its authored proportions. The
## adjustment is the minimum that makes the surfaces separable, which keeps silhouettes as close to
## the authored intent as a renderable model allows.
static func _enforce_equipment_clearance(scale: Vector3, bounds: AABB, target: AABB) -> void:
	for axis in 3:
		var modelled := bounds.size[axis] * scale[axis]
		var part := target.size[axis]
		if modelled <= part or part <= 0.0001 or modelled <= 0.0001:
			continue
		if (modelled - part) * 0.5 >= EQUIP_MIN_CLEARANCE:
			continue
		scale[axis] *= (part + EQUIP_MIN_CLEARANCE * 2.0) / modelled


## Fits one equipment mesh onto one body part.
##
## `fit` says how big the model should be as a multiple of the part's own box and `anchor` says which
## corner, edge or face of the two boxes to line up, so a model is sized and placed by the body it is
## worn on rather than by whatever absolute coordinates it happened to be modelled at. Without this
## the old path simply centred the mesh on the part, which is why a helmet sat over the head like a
## crate and boots floated at mid-shin.
static func _mount_equipment_mesh(
	mount: Node3D, attach_name: String, mesh: ArrayMesh, vis: Dictionary, theme: int
) -> void:
	var holder := Node3D.new()
	holder.name = "%s%s" % [EQUIP_VISUAL_PREFIX, attach_name]
	var target := _part_own_aabb(mount)
	var bounds := mesh.get_aabb()
	var scale := Vector3.ONE
	var offset := Vector3.ZERO
	if target.size != Vector3.ZERO and bounds.size != Vector3.ZERO:
		var fit: Vector3 = vis.get("fit", Vector3.ONE)
		var anchor: Vector3 = vis.get("anchor", Vector3.ZERO)
		for axis in 3:
			if bounds.size[axis] <= 0.0001 or target.size[axis] <= 0.0001:
				continue
			scale[axis] = target.size[axis] * fit[axis] / bounds.size[axis]
		_enforce_equipment_clearance(scale, bounds, target)
		# The anchor point, on the part's box and on the model's, in the same relative place.
		var target_point := target.get_center() + target.size * 0.5 * anchor
		var mesh_point := bounds.get_center() + bounds.size * 0.5 * anchor
		offset = target_point - mesh_point * scale
		offset.z += target.size.z * float(vis.get("forward", 0.0))
	else:
		# A bare pivot with no geometry of its own — a weapon or shield mount. The model keeps its
		# modelled size and hangs off the mount where the kit asks.
		offset = -bounds.get_center()
	offset += vis.get("offset", Vector3.ZERO) as Vector3
	holder.scale = scale
	holder.position = offset
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	mesh_inst.mesh = mesh
	mesh_inst.material_override = _make_voxel_material(theme)
	holder.set_meta(EQUIP_VISUAL_META, true)
	holder.add_child(mesh_inst)
	# `true` = force a readable name: on a collision Godot suffixes it ("EquipVisual_Torso2")
	# rather than throwing the name away.
	mount.add_child(holder, true)
