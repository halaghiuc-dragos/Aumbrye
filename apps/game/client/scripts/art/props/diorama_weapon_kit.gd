class_name DioramaWeaponKit
extends RefCounted

## Voxel weapon meshes mounted on character hands.
##
## Built from boxes on the same 0.02 m grid as the bodies so silhouettes stay
## readable at 480x270. Each weapon is authored hanging downward from its grip,
## matching the hand mount at the bottom of the arm pivot.

const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")

const BLADE_STEEL := Color(0.74, 0.78, 0.84)
const BLADE_DARK := Color(0.34, 0.36, 0.42)
const GRIP_LEATHER := Color(0.3, 0.2, 0.14)

## Maps content weapon ids and archetypes onto a kit entry.
const ARCHETYPE_ALIASES := {
	"sword_basic": "sword",
	"training_sword": "sword",
	"training_greatsword": "greatsword",
	"rogue_dagger": "dagger",
	"hunter_bow": "bow",
	"guard_spear": "spear",
}


static func resolve_id(weapon_id: String, archetype: String = "") -> String:
	if ARCHETYPE_ALIASES.has(weapon_id):
		return ARCHETYPE_ALIASES[weapon_id]
	if archetype != "":
		return archetype
	return weapon_id


static func build(weapon_id: String, theme: int) -> Node3D:
	var kit_id := resolve_id(weapon_id)
	match kit_id:
		"sword":
			return _build_sword(theme, 0.62, 0.09)
		"greatsword":
			return _build_sword(theme, 0.95, 0.13)
		"dagger":
			return _build_sword(theme, 0.34, 0.07)
		"spear":
			return _build_spear(theme)
		"bow":
			return _build_bow(theme)
		"shield":
			return _build_shield(theme)
		"":
			return null
		_:
			return _build_sword(theme, 0.62, 0.09)


static func _root(weapon_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Weapon"
	root.set_meta("weapon_kit_id", weapon_name)
	return root


## Blades point down the -Y axis of the mount; attack clips rotate the arm, and
## the blade follows because it is parented to the hand.
static func _build_sword(theme: int, blade_length: float, blade_width: float) -> Node3D:
	var root := _root("sword")
	var steel := PixelStyle.make_material(BLADE_STEEL)
	var dark := PixelStyle.make_material(BLADE_DARK)
	var grip := PixelStyle.make_material(GRIP_LEATHER)
	var accent := PixelStyle.make_accent_material(theme)

	PixelStyle.add_box(root, Vector3(blade_width * 0.7, 0.16, blade_width * 0.7), Vector3(0.0, 0.02, 0.0), grip, "Grip")
	PixelStyle.add_box(root, Vector3(blade_width * 2.6, 0.05, blade_width * 1.1), Vector3(0.0, -0.07, 0.0), accent, "Guard")
	PixelStyle.add_box(
		root,
		Vector3(blade_width, blade_length, blade_width * 0.4),
		Vector3(0.0, -0.09 - blade_length * 0.5, 0.0),
		steel,
		"Blade"
	)
	PixelStyle.add_box(
		root,
		Vector3(blade_width * 0.4, blade_length * 0.9, blade_width * 0.5),
		Vector3(0.0, -0.09 - blade_length * 0.5, 0.0),
		dark,
		"Fuller"
	)
	PixelStyle.add_box(root, Vector3(blade_width * 0.9, 0.06, blade_width * 0.9), Vector3(0.0, 0.11, 0.0), accent, "Pommel")
	return root


static func _build_spear(theme: int) -> Node3D:
	var root := _root("spear")
	var steel := PixelStyle.make_material(BLADE_STEEL)
	var shaft := PixelStyle.make_material(GRIP_LEATHER.lightened(0.18))
	var accent := PixelStyle.make_accent_material(theme)
	PixelStyle.add_box(root, Vector3(0.07, 0.12, 0.07), Vector3(0.0, 0.04, 0.0), shaft, "Grip")
	PixelStyle.add_box(root, Vector3(0.07, 1.45, 0.07), Vector3(0.0, 0.82, 0.0), shaft, "Shaft")
	PixelStyle.add_box(root, Vector3(0.11, 0.3, 0.05), Vector3(0.0, 1.68, 0.0), steel, "Head")
	PixelStyle.add_box(root, Vector3(0.13, 0.05, 0.09), Vector3(0.0, 1.5, 0.0), accent, "Collar")
	return root


static func _build_bow(theme: int) -> Node3D:
	var root := _root("bow")
	var wood := PixelStyle.make_material(GRIP_LEATHER.lightened(0.1))
	var string_mat := PixelStyle.make_material(Color(0.82, 0.8, 0.72))
	var accent := PixelStyle.make_accent_material(theme)
	PixelStyle.add_box(root, Vector3(0.07, 0.34, 0.07), Vector3(0.0, 0.0, 0.0), wood, "Riser")
	PixelStyle.add_box(root, Vector3(0.06, 0.3, 0.06), Vector3(0.0, 0.3, 0.06), wood, "LimbUpper")
	PixelStyle.add_box(root, Vector3(0.06, 0.3, 0.06), Vector3(0.0, -0.3, 0.06), wood, "LimbLower")
	PixelStyle.add_box(root, Vector3(0.02, 0.92, 0.02), Vector3(0.0, 0.0, 0.14), string_mat, "String")
	PixelStyle.add_box(root, Vector3(0.09, 0.06, 0.09), Vector3(0.0, 0.0, -0.02), accent, "Grip")
	return root


static func _build_shield(theme: int) -> Node3D:
	var root := _root("shield")
	var plate := PixelStyle.make_material(Color(0.46, 0.44, 0.5))
	var accent := PixelStyle.make_accent_material(theme)
	PixelStyle.add_box(root, Vector3(0.1, 0.62, 0.5), Vector3(-0.06, 0.06, 0.0), plate, "Plate")
	PixelStyle.add_box(root, Vector3(0.05, 0.16, 0.16), Vector3(-0.13, 0.06, 0.0), accent, "Boss")
	PixelStyle.add_box(root, Vector3(0.04, 0.66, 0.06), Vector3(-0.11, 0.06, 0.2), accent, "RimTop")
	PixelStyle.add_box(root, Vector3(0.04, 0.66, 0.06), Vector3(-0.11, 0.06, -0.2), accent, "RimBottom")
	return root
