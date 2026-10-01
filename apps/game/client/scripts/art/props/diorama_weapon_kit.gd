class_name DioramaWeaponKit
extends RefCounted


## The kit id a weapon reports in its `weapon_kit_id` meta: the blades share one.
const KIT_META_IDS := {"greatsword": "sword", "dagger": "sword"}

const KNOWN_KITS := [
	"sword", "greatsword", "dagger", "spear", "bow", "shield", "axe", "staff", "unknown"
]

const ARCHETYPE_ALIASES := {
	"sword_basic": "sword",
	"training_sword": "sword",
	"castle_sword": "sword",
	"iron_sword": "sword",
	"knight_blade": "sword",
	"flame_sword": "sword",
	"frost_glacier_sword": "sword",
	"frost_warlord_blade": "sword",
	"crystal_shard_blade": "sword",
	"mythic_blade": "sword",
	"training_greatsword": "greatsword",
	"greatsword": "greatsword",
	"greatsword_item": "greatsword",
	"rogue_dagger": "dagger",
	"swamp_toxin_dagger": "dagger",
	"venom_dagger": "dagger",
	"cathedral_shadow_dagger": "dagger",
	"hunter_bow": "bow",
	"crystal_bow": "bow",
	"guard_spear": "spear",
	"war_hammer": "axe",
	"sage_staff": "staff",
	"cathedral_arcane_staff": "staff",
	"castle_buckler": "shield",
	"mythic_aegis": "shield",
}

static var _warned_unknown: Dictionary = {}


static func resolve_id(weapon_id: String, archetype: String = "") -> String:
	if ARCHETYPE_ALIASES.has(weapon_id):
		return ARCHETYPE_ALIASES[weapon_id]
	if archetype != "":
		return archetype
	var def := ContentLoader.load_json("content/weapons/%s.json" % weapon_id)
	if not def.is_empty():
		var arch := str(def.get("archetype", ""))
		if arch != "":
			return arch
	return weapon_id


static func build(weapon_id: String, theme: int) -> Node3D:
	var kit_id := resolve_id(weapon_id)
	if kit_id == "":
		return null
	if not KNOWN_KITS.has(kit_id):
		if not _warned_unknown.has(kit_id):
			push_warning("DioramaWeaponKit: unknown weapon '%s' — using unknown mesh" % kit_id)
			_warned_unknown[kit_id] = true
		kit_id = "unknown"
	var mesh := ModelLoader.load_mesh("res://assets/weapons/%s.glb" % kit_id, theme)
	if mesh == null:
		return null
	var root := Node3D.new()
	root.name = "Weapon"
	root.set_meta("weapon_kit_id", KIT_META_IDS.get(kit_id, kit_id))
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = DioramaCharacterSkin.voxel_material(theme)
	root.add_child(mesh_instance)
	return root
