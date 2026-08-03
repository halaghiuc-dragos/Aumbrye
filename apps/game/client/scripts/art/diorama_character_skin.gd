extends RefCounted
class_name DioramaCharacterSkin

## Chunky pixel-diorama meshes for player and training-dummy characters.

const VISUAL_NAME := "DioramaVisual"
const FIRST_PERSON_HIDDEN_PARTS := ["Torso", "Head", "ArmL", "ArmR", "Visor"]

const PixelStyle := preload("res://scripts/art/pixel_diorama_style.gd")

const ARENA_DUMMY_ACCENT := Color(1.0, 0.35, 0.1)
const ARENA_DUMMY_GLOW := Color(0.6, 0.2, 0.05)


static func build_player_body(facing: Node3D) -> Node3D:
	_remove_visual(facing)
	PixelStyle.hide_legacy_meshes(facing)
	var root := _make_root(facing)
	var theme := PixelStyle.PaletteTheme.HUB
	var wall := PixelStyle.make_wall_material(theme)
	var palette := PixelStyle.get_palette(theme)
	var accent := PixelStyle.make_surface_material(PixelStyle.SurfaceKind.PROP, theme, 0.38).duplicate() as ShaderMaterial
	accent.set_shader_parameter("color_base", palette[PixelStyle.PaletteSlot.ACCENT])
	accent.set_shader_parameter("color_shadow", palette[PixelStyle.PaletteSlot.ACCENT].darkened(0.22))
	accent.set_shader_parameter("color_accent", palette[PixelStyle.PaletteSlot.EMISSIVE])
	PixelStyle.add_box(root, Vector3(0.5, 0.7, 0.35), Vector3(0.0, 0.95, 0.0), wall, "Torso")
	PixelStyle.add_box(root, Vector3(0.32, 0.32, 0.32), Vector3(0.0, 1.42, 0.0), wall, "Head")
	PixelStyle.add_box(root, Vector3(0.22, 0.55, 0.22), Vector3(-0.28, 0.95, 0.0), wall, "ArmL")
	PixelStyle.add_box(root, Vector3(0.22, 0.55, 0.22), Vector3(0.28, 0.95, 0.0), wall, "ArmR")
	PixelStyle.add_box(root, Vector3(0.22, 0.5, 0.28), Vector3(-0.14, 0.35, 0.0), wall, "LegL")
	PixelStyle.add_box(root, Vector3(0.22, 0.5, 0.28), Vector3(0.14, 0.35, 0.0), wall, "LegR")
	PixelStyle.add_box(root, Vector3(0.15, 0.15, 0.12), Vector3(0.0, 1.52, 0.18), accent, "Visor")
	return root


static func build_enemy_body(parent: Node3D, enemy_type: String = "melee", theme: int = PixelStyle.PaletteTheme.CASTLE) -> Node3D:
	_remove_visual(parent)
	PixelStyle.hide_legacy_meshes(parent)
	var root := _make_root(parent)
	var wall := PixelStyle.make_wall_material(theme)
	var palette := PixelStyle.get_palette(theme)
	var accent := PixelStyle.make_surface_material(PixelStyle.SurfaceKind.PROP, theme, 0.38).duplicate() as ShaderMaterial
	accent.set_shader_parameter("color_base", palette[PixelStyle.PaletteSlot.ACCENT])
	accent.set_shader_parameter("color_shadow", palette[PixelStyle.PaletteSlot.ACCENT].darkened(0.22))
	accent.set_shader_parameter("color_accent", palette[PixelStyle.PaletteSlot.EMISSIVE])
	var profile := enemy_type.to_lower()
	match profile:
		"ranged":
			PixelStyle.add_box(root, Vector3(0.42, 0.62, 0.3), Vector3(0.0, 0.92, 0.0), wall, "Torso")
			PixelStyle.add_box(root, Vector3(0.28, 0.28, 0.28), Vector3(0.0, 1.32, 0.0), wall, "Head")
			PixelStyle.add_box(root, Vector3(0.16, 0.48, 0.16), Vector3(-0.24, 0.92, 0.0), wall, "ArmL")
			PixelStyle.add_box(root, Vector3(0.16, 0.48, 0.16), Vector3(0.24, 0.92, 0.0), wall, "ArmR")
			PixelStyle.add_box(root, Vector3(0.18, 0.44, 0.24), Vector3(-0.12, 0.34, 0.0), wall, "LegL")
			PixelStyle.add_box(root, Vector3(0.18, 0.44, 0.24), Vector3(0.12, 0.34, 0.0), wall, "LegR")
			PixelStyle.add_box(root, Vector3(0.08, 0.55, 0.08), Vector3(0.28, 1.0, 0.18), accent, "Bow")
		"shield":
			PixelStyle.add_box(root, Vector3(0.62, 0.72, 0.42), Vector3(0.0, 0.95, 0.0), wall, "Torso")
			PixelStyle.add_box(root, Vector3(0.34, 0.34, 0.34), Vector3(0.0, 1.42, 0.0), wall, "Head")
			PixelStyle.add_box(root, Vector3(0.2, 0.55, 0.2), Vector3(-0.32, 0.95, 0.0), wall, "ArmL")
			PixelStyle.add_box(root, Vector3(0.2, 0.55, 0.2), Vector3(0.32, 0.95, 0.0), wall, "ArmR")
			PixelStyle.add_box(root, Vector3(0.22, 0.5, 0.28), Vector3(-0.14, 0.35, 0.0), wall, "LegL")
			PixelStyle.add_box(root, Vector3(0.22, 0.5, 0.28), Vector3(0.14, 0.35, 0.0), wall, "LegR")
			PixelStyle.add_box(root, Vector3(0.12, 0.55, 0.45), Vector3(-0.42, 0.95, 0.12), accent, "Shield")
		"hound":
			PixelStyle.add_box(root, Vector3(0.7, 0.38, 0.42), Vector3(0.0, 0.62, 0.0), wall, "Torso")
			PixelStyle.add_box(root, Vector3(0.32, 0.28, 0.38), Vector3(0.0, 0.78, 0.28), accent, "Head")
			PixelStyle.add_box(root, Vector3(0.14, 0.28, 0.14), Vector3(-0.22, 0.55, 0.0), wall, "LegL")
			PixelStyle.add_box(root, Vector3(0.14, 0.28, 0.14), Vector3(0.22, 0.55, 0.0), wall, "LegR")
			PixelStyle.add_box(root, Vector3(0.12, 0.12, 0.28), Vector3(0.0, 0.62, -0.32), wall, "Tail")
		"brute":
			PixelStyle.add_box(root, Vector3(0.72, 0.88, 0.48), Vector3(0.0, 1.05, 0.0), wall, "Torso")
			PixelStyle.add_box(root, Vector3(0.42, 0.42, 0.42), Vector3(0.0, 1.62, 0.0), accent, "Head")
			PixelStyle.add_box(root, Vector3(0.28, 0.68, 0.28), Vector3(-0.38, 1.0, 0.0), wall, "ArmL")
			PixelStyle.add_box(root, Vector3(0.28, 0.68, 0.28), Vector3(0.38, 1.0, 0.0), wall, "ArmR")
			PixelStyle.add_box(root, Vector3(0.26, 0.58, 0.32), Vector3(-0.18, 0.38, 0.0), wall, "LegL")
			PixelStyle.add_box(root, Vector3(0.26, 0.58, 0.32), Vector3(0.18, 0.38, 0.0), wall, "LegR")
		_:
			PixelStyle.add_box(root, Vector3(0.55, 0.75, 0.38), Vector3(0.0, 0.95, 0.0), wall, "Torso")
			PixelStyle.add_box(root, Vector3(0.38, 0.38, 0.38), Vector3(0.0, 1.48, 0.0), accent, "Head")
			PixelStyle.add_box(root, Vector3(0.24, 0.58, 0.24), Vector3(-0.3, 0.95, 0.0), wall, "ArmL")
			PixelStyle.add_box(root, Vector3(0.24, 0.58, 0.24), Vector3(0.3, 0.95, 0.0), wall, "ArmR")
			PixelStyle.add_box(root, Vector3(0.24, 0.52, 0.3), Vector3(-0.15, 0.35, 0.0), accent, "LegL")
			PixelStyle.add_box(root, Vector3(0.24, 0.52, 0.3), Vector3(0.15, 0.35, 0.0), accent, "LegR")
	return root


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


static func build_training_dummy(parent: Node3D) -> Node3D:
	_remove_visual(parent)
	PixelStyle.hide_legacy_meshes(parent)
	var root := _make_root(parent)
	var theme := PixelStyle.PaletteTheme.CASTLE
	var wall := PixelStyle.make_wall_material(theme)
	var accent := PixelStyle.make_material(ARENA_DUMMY_ACCENT, ARENA_DUMMY_GLOW)
	PixelStyle.add_box(root, Vector3(0.55, 0.75, 0.38), Vector3(0.0, 0.95, 0.0), wall, "Torso")
	PixelStyle.add_box(root, Vector3(0.38, 0.38, 0.38), Vector3(0.0, 1.48, 0.0), accent, "Head")
	PixelStyle.add_box(root, Vector3(0.24, 0.58, 0.24), Vector3(-0.3, 0.95, 0.0), wall, "ArmL")
	PixelStyle.add_box(root, Vector3(0.24, 0.58, 0.24), Vector3(0.3, 0.95, 0.0), wall, "ArmR")
	PixelStyle.add_box(root, Vector3(0.24, 0.52, 0.3), Vector3(-0.15, 0.35, 0.0), accent, "LegL")
	PixelStyle.add_box(root, Vector3(0.24, 0.52, 0.3), Vector3(0.15, 0.35, 0.0), accent, "LegR")
	PixelStyle.add_box(root, Vector3(0.7, 0.12, 0.12), Vector3(0.0, 0.95, 0.35), accent, "TargetStripe")
	return root


static func _make_root(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = VISUAL_NAME
	parent.add_child(root)
	return root


static func apply_first_person(facing: Node3D, enabled: bool) -> void:
	if facing == null:
		return
	PixelStyle.hide_legacy_meshes(facing)
	var visual := facing.get_node_or_null(VISUAL_NAME) as Node3D
	if visual == null:
		return
	for child in visual.get_children():
		if child is Node3D:
			child.visible = not enabled or not FIRST_PERSON_HIDDEN_PARTS.has(child.name)


static func _remove_visual(parent: Node3D) -> void:
	var existing := parent.get_node_or_null(VISUAL_NAME)
	if existing:
		existing.queue_free()
