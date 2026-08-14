extends Node

## Prints the world-space extents of every mesh in a built character rig.
##
## The rig is assembled at runtime from a manifest plus voxel meshes, and several of those meshes
## ship as binary resources whose extents cannot be read from the content files. Building the rig
## in-engine and measuring it is the only way to see where the parts actually land.
##
## Usage:
##   godot --headless --path apps/game/client res://scenes/debug/dump_rig_layout.tscn

const CharacterSkinScript := preload("res://scripts/art/characters/diorama_character_skin.gd")
const CharacterRigCatalogScript := preload("res://scripts/art/characters/character_rig_catalog.gd")

const ARCHETYPES: Array[String] = [
	"player_warden",
	"player_warden_tall",
	"player_warden_compact",
	"enemy_melee",
	"enemy_dummy",
]


func _ready() -> void:
	for archetype in ARCHETYPES:
		_dump(archetype)
	get_tree().quit(0)


func _dump(archetype: String) -> void:
	var host := Node3D.new()
	add_child(host)
	var visual := Node3D.new()
	visual.name = "DioramaVisual"
	host.add_child(visual)
	var root := CharacterSkinScript.build_from_manifest(visual, archetype, 0)
	if root == null:
		print("%s: manifest missing" % archetype)
		host.queue_free()
		return
	print("=== %s" % archetype)
	var total := AABB()
	var first := true
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := node as MeshInstance3D
		if mesh_inst.mesh == null:
			continue
		var world := mesh_inst.global_transform * mesh_inst.mesh.get_aabb()
		var part := mesh_inst.get_parent()
		var label: String = str(part.name) if part else "?"
		print(
			"  %-10s y %6.2f .. %5.2f   x %6.2f .. %5.2f   z %6.2f .. %5.2f"
			% [
				label,
				world.position.y,
				world.position.y + world.size.y,
				world.position.x,
				world.position.x + world.size.x,
				world.position.z,
				world.position.z + world.size.z,
			]
		)
		total = world if first else total.merge(world)
		first = false
	if not first:
		print(
			"  TOTAL      height %.2f  width %.2f  depth %.2f  (feet at y %.2f)"
			% [total.size.y, total.size.x, total.size.z, total.position.y]
		)
	host.queue_free()
