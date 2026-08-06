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

const PART_ROOT := ROOT_NAME
const PART_HEAD := "Head"
const PART_VISOR := "Visor"
const PART_HOOD := "Hood"
const PART_TORSO := "Torso"
const PART_ARM_L := "ArmL"
const PART_ARM_R := "ArmR"
const PART_BELT_TRIM := "BeltTrim"
const PART_PAULDRON := "Pauldron"
const PART_PAULDRON_R := "PauldronR"

const APPEARANCE_EXTRAS := [PART_VISOR, PART_HOOD, PART_BELT_TRIM, PART_PAULDRON, PART_PAULDRON_R]

static var _warned_missing_parts: Dictionary = {}

## Hidden in first person. Torso is a pivot, so its children (head, arms, weapon)
## go with it while the legs stay visible under the camera.
const FIRST_PERSON_HIDDEN_PARTS := ["Torso"]

const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const WeaponKit := preload("res://scripts/art/props/diorama_weapon_kit.gd")
const RigCatalog := preload("res://scripts/art/characters/character_rig_catalog.gd")
const VoxelGridScript := preload("res://scripts/art/characters/voxel_grid.gd")
const VoxelMeshBuilderScript := preload("res://scripts/art/characters/voxel_mesh_builder.gd")
const CharacterRigCatalogScript := preload("res://scripts/art/characters/character_rig_catalog.gd")

const EQUIP_VISUAL_PREFIX := "EquipVisual_"

const ARENA_DUMMY_ACCENT := Color(1.0, 0.35, 0.1)
const ARENA_DUMMY_GLOW := Color(0.6, 0.2, 0.05)

## Body proportions per profile, in metres. torso/head/arm/leg are box sizes.
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
	_apply_hair(visual, profile, mats)
	_apply_face(visual, profile, mats)
	_apply_class_armor(visual, profile, mats)


static func _apply_bulk_joint_offsets(visual: Node3D, profile: Dictionary) -> void:
	var bulk := str(profile.get("bulkVariant", CharacterAppearance.BULK_VARIANT_STANDARD))
	var x_shift := 0.0
	match bulk:
		CharacterAppearance.BULK_VARIANT_LEAN:
			x_shift = -VoxelGridScript.EDGE
		CharacterAppearance.BULK_VARIANT_HEAVY:
			x_shift = VoxelGridScript.EDGE
		_:
			pass
	if is_zero_approx(x_shift):
		return
	for part_name in ["LegL", "LegR", "ArmL", "ArmR"]:
		var part := find_part(visual, part_name)
		if part == null:
			continue
		var side := -1.0 if part_name.ends_with("L") else 1.0
		part.position.x += x_shift * side


static func _apply_skin_tone(visual: Node3D, profile: Dictionary, mats: Dictionary) -> void:
	var tint := CharacterAppearance.skin_tint_vector(
		str(profile.get("skinTone", CharacterAppearance.SKIN_TONE_NEUTRAL))
	)
	var head := find_part(visual, "Head")
	if head == null:
		return
	var mesh_inst := head.get_node_or_null("Mesh") as MeshInstance3D
	if mesh_inst and mesh_inst.material_override is ShaderMaterial:
		(mesh_inst.material_override as ShaderMaterial).set_shader_parameter("skin_tint", tint)


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
	var mesh: ArrayMesh = VoxelMeshBuilderScript.load_mesh(mesh_path, int(mats.get("theme", 0)))
	if mesh == null:
		return
	var holder := Node3D.new()
	holder.name = "Hair"
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	mesh_inst.mesh = mesh
	mesh_inst.material_override = _make_voxel_material(int(mats.get("theme", 0)))
	holder.position = Vector3(0.0, VoxelGridScript.EDGE * 3.0, 0.0)
	holder.add_child(mesh_inst)
	head.add_child(holder)


static func _apply_face(visual: Node3D, profile: Dictionary, mats: Dictionary) -> void:
	var face := str(profile.get("face", CharacterAppearance.FACE_OPEN))
	if face == CharacterAppearance.FACE_OPEN:
		return
	var head := find_part(visual, "Head")
	if head == null:
		return
	var existing := head.get_node_or_null("FaceAccent")
	if existing:
		existing.queue_free()
	var existing_r := head.get_node_or_null("FaceAccentR")
	if existing_r:
		existing_r.queue_free()
	var spec: Dictionary = PROFILES["player"]
	var head_size: Vector3 = spec["head"]
	var accent: Material = mats["accent"] as Material
	match face:
		CharacterAppearance.FACE_STERN:
			PixelStyle.add_box(
				head,
				Vector3(head_size.x * 0.55, head_size.y * 0.12, head_size.z * 0.08),
				Vector3(0.0, head_size.y * 0.42, head_size.z * 0.46),
				accent,
				"FaceAccent"
			)
		CharacterAppearance.FACE_KIND:
			PixelStyle.add_box(
				head,
				Vector3(head_size.x * 0.18, head_size.y * 0.08, head_size.z * 0.06),
				Vector3(-head_size.x * 0.22, head_size.y * 0.2, head_size.z * 0.44),
				accent,
				"FaceAccent"
			)
			PixelStyle.add_box(
				head,
				Vector3(head_size.x * 0.18, head_size.y * 0.08, head_size.z * 0.06),
				Vector3(head_size.x * 0.22, head_size.y * 0.2, head_size.z * 0.44),
				accent,
				"FaceAccentR"
			)


static func _apply_class_armor(visual: Node3D, _profile: Dictionary, mats: Dictionary) -> void:
	var class_id := CharacterService.class_id if CharacterService else ""
	if class_id == "":
		return
	var torso := find_part(visual, "Torso")
	if torso == null:
		return
	var existing := torso.get_node_or_null("ClassArmor")
	if existing:
		existing.queue_free()
	var spec: Dictionary = PROFILES["player"]
	var torso_size: Vector3 = spec["torso"]
	match class_id:
		"knight":
			PixelStyle.add_box(
				torso,
				Vector3(torso_size.x * 1.02, torso_size.y * 0.72, torso_size.z * 0.18),
				Vector3(0.0, torso_size.y * 0.18, torso_size.z * 0.42),
				mats["accent"],
				"ClassArmor"
			)
		"rogue":
			PixelStyle.add_box(
				torso,
				Vector3(torso_size.x * 0.92, torso_size.y * 0.9, torso_size.z * 0.12),
				Vector3(0.0, torso_size.y * 0.42, -torso_size.z * 0.48),
				mats["body"],
				"ClassArmor"
			)
		"scholar":
			PixelStyle.add_box(
				torso,
				Vector3(torso_size.x * 1.1, torso_size.y * 0.14, torso_size.z * 1.02),
				Vector3(0.0, -torso_size.y * 0.08, 0.0),
				mats["accent"],
				"ClassArmor"
			)
		"berserker":
			PixelStyle.add_box(
				torso,
				Vector3(torso_size.x * 1.12, torso_size.y * 0.2, torso_size.z * 0.88),
				Vector3(0.0, torso_size.y * 0.62, 0.0),
				mats["accent"],
				"ClassArmor"
			)
		"sentinel":
			PixelStyle.add_box(
				torso,
				Vector3(torso_size.x * 0.14, torso_size.y * 0.55, torso_size.z * 0.72),
				Vector3(-torso_size.x * 0.52, torso_size.y * 0.2, 0.0),
				mats["accent"],
				"ClassArmor"
			)


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
	return visual


## Feet sit on the rig origin, so the visual root can be placed straight on the
## floor without a per-profile fudge factor.
static func feet_local_y(_profile: String) -> float:
	return 0.0


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
	# Anim pivots (Bow/Shield) must survive kit swaps — attack clips key them by name.
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
			# Shaft along -Z (forward thrust), grip at hand mount.
			weapon.position = Vector3(0.04, -0.12, -0.22)
			weapon.rotation = Vector3(deg_to_rad(82.0), 0.0, deg_to_rad(2.0))
		if visual.name == "ViewRoot":
			_disable_cast_shadows(weapon)
		target_mount.add_child(weapon)


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
	_apply_first_person_weapon_shadows(visual, enabled)
	if not enabled:
		_set_meshes_visible(visual, true)


static func sync_first_person_weapon_shadows(visual: Node3D, first_person: bool) -> void:
	_apply_first_person_weapon_shadows(visual, first_person)


static func _apply_first_person_weapon_shadows(visual: Node3D, first_person: bool) -> void:
	# Third-person rig weapons still cast shadows in FP; viewmodel weapon is screen-only.
	for mount_name in [WEAPON_MOUNT, SHIELD_MOUNT, "Bow"]:
		var mount := find_part(visual, mount_name)
		if mount:
			_set_cast_shadow_hidden(mount, first_person)


static func _set_cast_shadow_hidden(node: Node, hidden: bool) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if hidden
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)
	for child in node.get_children():
		_set_cast_shadow_hidden(child, hidden)


static func _disable_cast_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_cast_shadows(child)


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

	# Front pair carries the LegL/LegR names the shared clips animate; the rear
	# pair mirrors them through a duplicate of the same names' motion.
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


static func build_from_manifest(visual: Node3D, archetype_id: String, theme: int) -> Node3D:
	var manifest := CharacterRigCatalogScript.get_manifest(archetype_id)
	if manifest.is_empty():
		return null
	var grid: float = float(manifest.get("grid", VoxelGridScript.EDGE))
	var parts: Dictionary = manifest.get("parts", {})
	if parts.is_empty():
		return null
	var skin_tint := CharacterAppearance.skin_tint_vector(
		CharacterAppearance.SKIN_TONE_NEUTRAL
	)
	if CharacterService:
		skin_tint = CharacterAppearance.skin_tint_vector(
			str(CharacterService.appearance_profile.get("skinTone", CharacterAppearance.SKIN_TONE_NEUTRAL))
		)
	var mat := _make_voxel_material(theme, skin_tint)
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
			mesh_inst.position = Vector3(
				float(mesh_offset_arr[0]) * grid,
				float(mesh_offset_arr[1]) * grid,
				float(mesh_offset_arr[2]) * grid
			)
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


static func _make_voxel_material(theme: int, skin_tint: Vector3 = Vector3.ONE) -> ShaderMaterial:
	var mat := (
		PixelStyle.make_surface_material(PixelStyle.SurfaceKind.PROP, theme, 0.38).duplicate()
		as ShaderMaterial
	)
	mat.set_shader_parameter("use_vertex_color", true)
	mat.set_shader_parameter("skin_tint", skin_tint)
	return mat


static func apply_equipment(visual: Node3D, equipped: Dictionary, theme: int) -> void:
	if visual == null:
		return
	_clear_equipment_visuals(visual)
	for slot_name in equipped:
		var inst: Dictionary = equipped.get(slot_name, {})
		if inst.is_empty():
			continue
		var item_id := str(inst.get("itemId", ""))
		if item_id == "":
			continue
		var def := ItemCatalog.get_definition(item_id)
		var vis: Dictionary = def.get("visual", {})
		if vis.is_empty():
			continue
		_apply_equipment_visual(visual, vis, theme)


static func _clear_equipment_visuals(visual: Node3D) -> void:
	for node in _collect_nodes_named(visual, EQUIP_VISUAL_PREFIX):
		node.queue_free()
	for part_name in ["LegL", "LegR", "Torso", "Head", "ArmL", "ArmR"]:
		var part := find_part(visual, part_name)
		if part:
			_set_meshes_visible(part, true)


static func _collect_nodes_named(root: Node, prefix: String) -> Array[Node]:
	var found: Array[Node] = []
	if str(root.name).begins_with(prefix):
		found.append(root)
	for child in root.get_children():
		found.append_array(_collect_nodes_named(child, prefix))
	return found


static func _apply_equipment_visual(visual: Node3D, vis: Dictionary, theme: int) -> void:
	var attach_name := str(vis.get("attach", ""))
	if attach_name == "":
		return
	var mount := find_part(visual, attach_name)
	if mount == null:
		return
	for hide_name in vis.get("hide", []):
		var hidden := find_part(visual, str(hide_name))
		if hidden:
			_set_meshes_visible(hidden, false)
	var mesh_path := str(vis.get("mesh", ""))
	if mesh_path == "":
		return
	var mesh: ArrayMesh = VoxelMeshBuilderScript.load_mesh(mesh_path, theme)
	if mesh == null:
		push_error("DioramaCharacterSkin: equipment mesh missing %s" % mesh_path)
		return
	var holder := Node3D.new()
	holder.name = "%s%s" % [EQUIP_VISUAL_PREFIX, attach_name]
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	mesh_inst.mesh = mesh
	mesh_inst.material_override = _make_voxel_material(theme)
	holder.add_child(mesh_inst)
	mount.add_child(holder)
