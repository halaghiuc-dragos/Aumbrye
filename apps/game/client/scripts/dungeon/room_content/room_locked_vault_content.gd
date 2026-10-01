extends "res://scripts/dungeon/room_content/room_content_base.gd"

const FloorKeyringScript := preload("res://scripts/dungeon/floor_keyring.gd")

const CHEST_SCENE := preload("res://scenes/loot/loot_chest.tscn")
const DIORAMA_SKIN := preload("res://scripts/art/props/diorama_interactable_skin.gd")

var _key_id := ""
var _chest: Node3D


## The key vault is one chest: opening it grants the room's items and the floor key together, and
## the chest's own state is what a floor snapshot keeps.
func configure(entry: Dictionary, _definition: Dictionary) -> void:
	_key_id = str(entry.get("keyId", ""))
	_chest = CHEST_SCENE.instantiate() as Node3D
	_chest.name = "KeyVaultChest"
	_chest.position = _anchor(0).position
	_content_root().add_child(_chest)
	if _chest.has_method("configure"):
		_chest.call(
			"configure",
			{
				"items": entry.get("items", []),
				"keyFragmentId": str(entry.get("keyFragmentId", _key_id)),
				"keyLabel": str(entry.get("keyLabel", "Dungeon Key")),
			}
		)
	_style_key_chest()


func get_chests() -> Array[Node3D]:
	return [_chest] if _chest != null else []


## The same colour as the door it opens, not a fixed amber -- a red door and a blue door
## hand back visibly different chests, so finding a key says which door it belongs to.
func _style_key_chest() -> void:
	var mesh := _chest.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh:
		var tint := FloorKeyringScript.tint_for(_key_id)
		if tint == Color.WHITE:
			tint = Color(0.85, 0.65, 0.15)
		mesh.material_override = DIORAMA_SKIN.make_telegraph_material(tint)
