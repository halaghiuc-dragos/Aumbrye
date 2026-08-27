@tool
extends Node3D


const PROP_SPACING := 2.5


func _ready() -> void:
	if get_child_count() > 0:
		return
	_build_kit()


func _build_kit() -> void:
	var kinds: Array[DioramaPropFactory.PropKind] = [
		DioramaPropFactory.PropKind.CRATE,
		DioramaPropFactory.PropKind.PILLAR,
		DioramaPropFactory.PropKind.TORCH,
		DioramaPropFactory.PropKind.BANNER,
	]
	for i in kinds.size():
		var prop := DioramaPropFactory.create_prop(kinds[i], BiomeRegistry.BIOME_CASTLE)
		prop.position.x = float(i) * PROP_SPACING
		add_child(prop)
		if Engine.is_editor_hint() and get_tree():
			prop.owner = get_tree().edited_scene_root
