extends RefCounted
class_name DioramaInteractableSkin


const VISUAL_NAME := "DioramaVisual"

const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")

const WAVES_RARITY_GLOW: Array[Color] = [
	Color(0.72, 0.72, 0.78),
	Color(0.35, 0.82, 0.42),
	Color(0.38, 0.58, 0.95),
	Color(0.82, 0.38, 0.95),
	Color(1.0, 0.72, 0.22),
	Color(0.55, 0.78, 0.42),
]


static func resolve_biome(node: Node, fallback: String = BiomeRegistry.BIOME_CASTLE) -> String:
	if node.has_meta("biome_id"):
		var meta := str(node.get_meta("biome_id"))
		if meta != "":
			return meta
	if node.is_in_group("waves_run"):
		return BiomeRegistry.BIOME_UMBRAL
	if RunFlow.is_run_active():
		return RunFlow.current_biome_id
	return fallback


static func build_chest(
	parent: Node3D, biome_id: String, glow_color: Color = Color(0, 0, 0, 0)
) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	var theme := PixelStyle.theme_from_biome(biome_id)
	var wall := PixelStyle.make_wall_material(theme)
	var accent := PixelStyle.make_accent_material(theme)
	var timber := PixelStyle.make_prop_material(theme, false)
	var iron := PixelStyle.make_metal_material(Color(0.22, 0.21, 0.25), 0.34)
	var glow := glow_color
	if glow == Color(0, 0, 0, 0):
		glow = PixelStyle.get_palette_color(theme, PixelStyle.PaletteSlot.EMISSIVE)

	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_box(root, Vector3(0.16, 0.12, 0.16), iron, Vector3(sx * 0.48, 0.06, sz * 0.33))
	_add_box(root, Vector3(1.18, 0.46, 0.86), timber, Vector3(0.0, 0.35, 0.0))
	_add_box(root, Vector3(1.22, 0.08, 0.9), iron, Vector3(0.0, 0.22, 0.0))
	for sx in [-1.0, 1.0]:
		_add_box(root, Vector3(0.09, 0.5, 0.9), iron, Vector3(sx * 0.42, 0.35, 0.0))
	_add_box(root, Vector3(1.2, 0.06, 0.9), iron, Vector3(0.0, 0.6, 0.0))
	_add_box(root, Vector3(0.3, 0.26, 0.07), iron, Vector3(0.0, 0.46, 0.45))
	_add_box(root, Vector3(0.07, 0.09, 0.1), wall, Vector3(0.0, 0.44, 0.47))
	for sx in [-1.0, 1.0]:
		_add_box(root, Vector3(0.2, 0.12, 0.14), iron, Vector3(sx * 0.28, 0.6, -0.44))

	var lid := Node3D.new()
	lid.name = LID_NAME
	lid.position = Vector3(0.0, 0.6, -0.44)
	root.add_child(lid)
	_add_box(lid, Vector3(1.2, 0.16, 0.88), timber, Vector3(0.0, 0.08, 0.44))
	_add_box(lid, Vector3(1.04, 0.14, 0.72), timber, Vector3(0.0, 0.21, 0.44))
	_add_box(lid, Vector3(0.78, 0.1, 0.5), accent, Vector3(0.0, 0.31, 0.44))
	for sx in [-1.0, 1.0]:
		_add_box(lid, Vector3(0.09, 0.34, 0.92), iron, Vector3(sx * 0.42, 0.14, 0.44))
	_add_box(lid, Vector3(0.16, 0.22, 0.09), accent, Vector3(0.0, 0.04, 0.9))

	_add_box(
		root,
		Vector3(1.08, 0.03, 0.78),
		PixelStyle.make_material(glow, glow),
		Vector3(0.0, 0.57, 0.0)
	)
	_add_orb(root, glow, Vector3(0.0, 1.06, 0.0), 0.09)
	return root


const LID_NAME := "Lid"
const LID_OPEN_ANGLE := -1.95


static func find_chest_lid(visual: Node3D) -> Node3D:
	if visual == null:
		return null
	return visual.get_node_or_null(LID_NAME) as Node3D


static func build_waves_chest(parent: Node3D, rarity_index: int) -> Node3D:
	var glow := WAVES_RARITY_GLOW[clampi(rarity_index, 0, WAVES_RARITY_GLOW.size() - 1)]
	return build_chest(parent, BiomeRegistry.BIOME_UMBRAL, glow)


static func build_lever(parent: Node3D, biome_id: String) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	var theme := PixelStyle.theme_from_biome(biome_id)
	var wall := PixelStyle.make_wall_material(theme)
	var accent := PixelStyle.make_accent_material(theme)
	_add_box(root, Vector3(0.9, 0.55, 0.9), wall, Vector3(0.0, 0.28, 0.0))
	_add_box(root, Vector3(0.16, 0.75, 0.16), accent, Vector3(0.0, 0.78, 0.0))
	_add_box(root, Vector3(0.55, 0.12, 0.12), accent, Vector3(0.0, 1.05, 0.0))
	_add_orb(
		root,
		PixelStyle.get_palette_color(theme, PixelStyle.PaletteSlot.EMISSIVE),
		Vector3(0.28, 1.05, 0.0),
		0.1
	)
	return root


static func build_bonfire(parent: Node3D, biome_id: String) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	var theme := PixelStyle.theme_from_biome(biome_id)
	var wall := PixelStyle.make_wall_material(theme)
	var accent := PixelStyle.make_accent_material(theme)
	_add_box(root, Vector3(0.7, 0.35, 0.7), wall, Vector3(0.0, 0.18, 0.0))
	_add_box(root, Vector3(0.45, 0.55, 0.45), accent, Vector3(0.0, 0.55, 0.0))
	_add_orb(root, Color(1.0, 0.55, 0.15), Vector3(0.0, 1.05, 0.0), 0.22)
	_add_orb(root, Color(1.0, 0.35, 0.05, 0.45), Vector3(0.0, 1.35, 0.0), 0.14)
	return root


static func build_lectern(parent: Node3D, biome_id: String) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	var theme := PixelStyle.theme_from_biome(biome_id)
	var wall := PixelStyle.make_wall_material(theme)
	var accent := PixelStyle.make_accent_material(theme)
	_add_box(root, Vector3(0.55, 1.1, 0.55), wall, Vector3(0.0, 0.55, 0.0))
	_add_box(root, Vector3(0.75, 0.08, 0.55), accent, Vector3(0.0, 1.15, 0.0))
	_add_box(root, Vector3(0.35, 0.45, 0.08), accent, Vector3(0.0, 1.35, 0.22))
	return root


static func build_npc(parent: Node3D, biome_id: String) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	var theme := PixelStyle.theme_from_biome(biome_id)
	var wall := PixelStyle.make_wall_material(theme)
	var accent := PixelStyle.make_accent_material(theme)
	_add_box(root, Vector3(0.55, 0.9, 0.35), wall, Vector3(0.0, 0.45, 0.0))
	_add_box(root, Vector3(0.35, 0.35, 0.35), accent, Vector3(0.0, 1.15, 0.0))
	_add_orb(root, PixelStyle.get_palette_color(theme, PixelStyle.PaletteSlot.ACCENT), Vector3(0.0, 1.55, 0.0), 0.18)
	return root


static func build_portal(parent: Node3D, biome_id: String) -> Node3D:
	_remove_visual(parent)
	var portal_id := PortalCatalog.portal_id_for_biome(biome_id)
	var def := PortalCatalog.resolve(portal_id)
	return PixelStyle.build_portal(parent, def, 1.0)


static func build_exit_portal(parent: Node3D, biome_id: String) -> Node3D:
	_remove_visual(parent)
	var portal_id := PortalCatalog.portal_id_for_biome(biome_id)
	var def := PortalCatalog.resolve(portal_id)
	return PixelStyle.build_portal(parent, def, 0.85)


static func build_merchant_stall(parent: Node3D, biome_id: String) -> Node3D:
	return PixelStyle.build_merchant_stall(parent, biome_id)


static func build_loot_pickup(parent: Node3D, biome_id: String) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	var theme := PixelStyle.theme_from_biome(biome_id)
	var wall := PixelStyle.make_wall_material(theme)
	var accent := PixelStyle.make_accent_material(theme)
	_add_box(root, Vector3(0.45, 0.45, 0.45), wall, Vector3(0.0, 0.35, 0.0))
	_add_box(root, Vector3(0.52, 0.1, 0.52), accent, Vector3(0.0, 0.62, 0.0))
	_add_orb(root, PixelStyle.get_palette_color(theme, PixelStyle.PaletteSlot.EMISSIVE), Vector3(0.0, 0.85, 0.0), 0.16)
	root.set_meta("bob_base_y", root.position.y)
	return root


static func build_cannon(parent: Node3D, biome_id: String) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	var theme := PixelStyle.theme_from_biome(biome_id)
	var wall := PixelStyle.make_wall_material(theme)
	var accent := PixelStyle.make_accent_material(theme)
	_add_box(root, Vector3(1.8, 0.35, 1.4), wall, Vector3(0.0, 0.18, 0.0))
	_add_box(root, Vector3(1.5, 0.55, 0.55), accent, Vector3(0.0, 0.55, 0.35))
	_add_box(root, Vector3(0.35, 0.35, 0.9), accent, Vector3(0.55, 0.72, 0.55))
	for i in 3:
		var offset := Vector3(-0.35 + float(i) * 0.35, 0.42, -0.25)
		_add_orb(
			root,
			PixelStyle.get_palette_color(PixelStyle.PaletteTheme.CRYSTAL, PixelStyle.PaletteSlot.EMISSIVE),
			offset,
			0.12
		)
	return root


## `BS-05`: the requirement reads as icons on the frame, not only in the interact prompt's text --
## a tinted keyhole inset per required lock (the same read `build_locked_door_frame()` already
## gives an ordinary locked door, so a red/blue/yellow icon here means what it means everywhere
## else on the floor) or one diamond sigil icon for the sigil requirement. The two frame torches
## double as "the light behind you" that `boss_room_door.gd` dims on `seal_door()` and relights on
## `release_door()` -- named so a caller can find them by `get_node_or_null()` without this
## function needing to hand back anything but the usual visual root.
static func build_boss_door_frame(
	parent: Node3D, biome_id: String, requirement: String = "none", lock_key_ids: Array = []
) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	root.name = "DoorFrameVisual"
	var theme := PixelStyle.theme_from_biome(biome_id)
	var wall := PixelStyle.make_wall_material(theme)
	var accent := PixelStyle.make_accent_material(theme)
	_add_box(root, Vector3(0.4, 4.2, 0.4), wall, Vector3(-2.6, 2.1, 0.0))
	_add_box(root, Vector3(0.4, 4.2, 0.4), wall, Vector3(2.6, 2.1, 0.0))
	_add_box(root, Vector3(5.6, 0.4, 0.4), wall, Vector3(0.0, 4.2, 0.0))
	_add_box(root, Vector3(4.8, 0.15, 0.15), accent, Vector3(0.0, 2.1, -0.1))
	for side in [-1.0, 1.0]:
		var torch := OmniLight3D.new()
		torch.name = "FrameTorch%s" % ("R" if side > 0.0 else "L")
		torch.light_color = Color(1.0, 0.68, 0.32)
		torch.light_energy = 0.85
		torch.omni_range = 4.5
		torch.shadow_enabled = false
		torch.position = Vector3(side * 2.6, 2.6, 0.3)
		torch.add_to_group(NightLights.GROUP)
		root.add_child(torch)
	_build_boss_door_requirement_icons(root, requirement, lock_key_ids)
	return root


static func _build_boss_door_requirement_icons(
	root: Node3D, requirement: String, lock_key_ids: Array
) -> void:
	if requirement == "sigil":
		var sigil := _add_box(
			root,
			Vector3(0.36, 0.36, 0.1),
			PixelStyle.make_glow_material(Color(0.95, 0.8, 0.3), Color(0.6, 0.48, 0.15), 1.4),
			Vector3(0.0, 4.55, 0.0)
		)
		sigil.rotation.z = PI * 0.25
		return
	if requirement != "all_keys" or lock_key_ids.is_empty():
		return
	var count := lock_key_ids.size()
	var spacing := 0.5
	var start_x := -float(count - 1) * spacing * 0.5
	for i in count:
		var tint := FloorKeyring.tint_for(str(lock_key_ids[i]))
		if tint == Color.WHITE:
			tint = Color(0.85, 0.75, 0.4)
		_add_box(
			root,
			Vector3(0.3, 0.3, 0.1),
			PixelStyle.make_glow_material(tint, tint * 0.6, 1.4),
			Vector3(start_x + float(i) * spacing, 4.55, 0.0)
		)


## RM-05: a locked door reads as a door -- two jambs, a lintel, and a keyhole-sized emissive inset
## tinted with the key's colour -- instead of an untextured slab the same shape as every other
## telegraph box in the dungeon. `key_tint` is `FloorKeyring.tint_for(key_id)`; pass `Color.WHITE`
## for a door whose key id didn't resolve to one of Doom's three colours.
static func build_locked_door_frame(parent: Node3D, biome_id: String, key_tint: Color) -> Node3D:
	var root := _make_root(parent)
	root.name = "LockedDoorFrameVisual"
	var theme := PixelStyle.theme_from_biome(biome_id)
	var wall := PixelStyle.make_wall_material(theme)
	var half_w := CastleRoomConstants.DOOR_WIDTH * 0.5
	var jamb_x := half_w + 0.15
	_add_box(root, Vector3(0.3, CastleRoomConstants.DOOR_HEIGHT, 0.3), wall, Vector3(-jamb_x, CastleRoomConstants.DOOR_HEIGHT * 0.5, 0.0))
	_add_box(root, Vector3(0.3, CastleRoomConstants.DOOR_HEIGHT, 0.3), wall, Vector3(jamb_x, CastleRoomConstants.DOOR_HEIGHT * 0.5, 0.0))
	_add_box(
		root,
		Vector3(CastleRoomConstants.DOOR_WIDTH + 0.6, 0.3, 0.3),
		wall,
		Vector3(0.0, CastleRoomConstants.DOOR_HEIGHT + 0.15, 0.0)
	)
	var keyhole := PixelStyle.make_glow_material(key_tint, key_tint * 0.6, 1.4)
	_add_box(
		root,
		Vector3(0.5, 0.5, 0.12),
		keyhole,
		Vector3(0.0, CastleRoomConstants.DOOR_HEIGHT * 0.5, -0.05)
	)
	return root


static func build_spikes(parent: Node3D, biome_id: String) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	var theme := PixelStyle.theme_from_biome(biome_id)
	var wall := PixelStyle.make_floor_material(theme)
	var accent := PixelStyle.make_prop_material(theme, true)
	_add_box(root, Vector3(2.8, 0.08, 2.8), wall, Vector3(0.0, 0.04, 0.0))
	for x in 4:
		for z in 4:
			var px := -0.9 + float(x) * 0.6
			var pz := -0.9 + float(z) * 0.6
			_add_box(root, Vector3(0.14, 0.65, 0.14), accent, Vector3(px, 0.36, pz))
	return root


static func build_falling_block(parent: Node3D, biome_id: String) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	var theme := PixelStyle.theme_from_biome(biome_id)
	var wall := PixelStyle.make_wall_material(theme)
	var accent := PixelStyle.make_accent_material(theme)
	_add_box(root, Vector3(1.9, 1.45, 1.9), wall, Vector3.ZERO)
	_add_box(root, Vector3(1.95, 0.12, 1.95), accent, Vector3(0.0, 0.68, 0.0))
	return root


static func build_crystal_pillar(
	parent: Node3D, biome_id: String = BiomeRegistry.BIOME_CRYSTAL
) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	var theme := PixelStyle.theme_from_biome(biome_id)
	var crystal := PixelStyle.make_emissive_material(theme, 1.1)
	_add_box(root, Vector3(0.35, 1.1, 0.35), crystal, Vector3(0.0, 0.55, 0.0))
	_add_box(root, Vector3(0.55, 0.55, 0.55), crystal, Vector3(0.0, 1.25, 0.0))
	return root


static func make_telegraph_material(color: Color) -> Material:
	return PixelStyle.make_material(color, color * 0.5)


## RM-16 item 4: every gate (locked door, shortcut gate, puzzle gate, boss door) used to just
## vanish -- `visible = false` the instant it opened. This sinks the barrier into the floor over
## 0.4s instead. Collision drops immediately, same as before (a player already leaning on the door
## should not feel it disappear from under them, but should also not get stuck waiting on the
## animation to pass through).
static func animate_gate_open(barrier: StaticBody3D) -> void:
	barrier.collision_layer = 0
	var start_y := barrier.position.y
	var tween := barrier.create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(barrier, "position:y", start_y - 2.4, 0.4)
	tween.tween_callback(func() -> void: barrier.visible = false)


const FOG_GATE_SHADER_PATH := "res://assets/shared/fog_gate.gdshader"


## RM-16: every doorway in the game got a frame -- two jambs, a lintel with a keystone, and a
## threshold strip in the floor material -- instead of just a rectangular hole with a lintel.
## Batched with `PixelBoxBatch` (wall material and floor material each collapse to one draw call).
## `parent` is expected to be the doorway's own `DoorwaySocket` (a `Marker3D`, so its own transform
## already tracks the door's position/rotation across a room resize); safe to call more than once,
## the caller is expected to guard against duplicates by checking for `DoorwayFrameVisual` first.
static func build_doorway_frame(parent: Node3D, biome_id: String, width: float, height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "DoorwayFrameVisual"
	parent.add_child(root)
	var theme := PixelStyle.theme_from_biome(biome_id)
	var wall_mat := PixelStyle.make_wall_material(theme)
	var accent_mat := PixelStyle.make_accent_material(theme)
	var floor_mat := PixelStyle.make_floor_material(theme)
	var jamb_batch := PixelBoxBatch.new()
	var half_w := width * 0.5
	var jamb_x := half_w + 0.2
	jamb_batch.add(Vector3(0.4, height, 0.4), Vector3(-jamb_x, height * 0.5, 0.0), wall_mat)
	jamb_batch.add(Vector3(0.4, height, 0.4), Vector3(jamb_x, height * 0.5, 0.0), wall_mat)
	jamb_batch.add(Vector3(width + 0.8, 0.4, 0.4), Vector3(0.0, height + 0.2, 0.0), wall_mat)
	jamb_batch.commit(
		root, "FrameJambs", AABB(Vector3(-jamb_x - 0.4, 0.0, -0.4), Vector3(jamb_x * 2.0 + 0.8, height + 0.6, 0.8))
	)
	_add_box(root, Vector3(0.5, 0.5, 0.5), accent_mat, Vector3(0.0, height + 0.2, 0.0))
	var threshold := _add_box(root, Vector3(width, 0.06, 0.5), floor_mat, Vector3(0.0, 0.03, 0.0))
	threshold.name = "Threshold"
	return root


## RM-07: a translucent scrolling-noise plane in `tint`, sized to a doorway. `boss_room_door.gd`
## and the arena lock-in gate (`room_arena_gate_content.gd`) both use this -- neither shows just a
## barrier box any more, both show a wall of light the collision box (kept, unchanged) sits behind.
static func build_fog_gate(
	parent: Node3D, width: float, height: float, tint: Color
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "FogGateVisual"
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	mesh_instance.mesh = quad
	mesh_instance.position = Vector3(0.0, height * 0.5, 0.0)
	var mat := ShaderMaterial.new()
	mat.shader = load(FOG_GATE_SHADER_PATH) as Shader
	mat.set_shader_parameter("tint", tint)
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh_instance)
	return mesh_instance


static func _make_root(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = VISUAL_NAME
	parent.add_child(root)
	return root


static func _remove_visual(parent: Node3D) -> void:
	var existing := parent.get_node_or_null(VISUAL_NAME)
	if existing:
		existing.queue_free()
	var visuals := parent.get_node_or_null("DioramaVisuals")
	if visuals:
		visuals.queue_free()
	# Authored placeholder meshes.
	#
	# This used to drop only children literally named "MeshInstance3D", so a placeholder given any
	# other name survived and drew underneath the built visual. The exit portal in the castle slice
	# was one: a bare 3x3 BoxMesh called "PortalMesh" with no material on it, rendering as a slab of
	# Godot's default grey in the middle of the boss room doorway.
	#
	# Matching on "has no material" rather than on the name catches the whole class of them and
	# cannot take authored art with it: a mesh with no material anywhere is already broken, since
	# default grey is the one colour the palette never produces.
	for child in parent.get_children():
		if child is MeshInstance3D and _is_untextured(child as MeshInstance3D):
			child.queue_free()


## A mesh with nothing to draw it with -- no override, no surface material, no mesh at all.
static func _is_untextured(mesh_instance: MeshInstance3D) -> bool:
	if mesh_instance.material_override != null:
		return false
	if mesh_instance.mesh == null:
		return true
	for surface in mesh_instance.mesh.get_surface_count():
		if mesh_instance.get_surface_override_material(surface) != null:
			return false
		if mesh_instance.mesh.surface_get_material(surface) != null:
			return false
	return true


static func _add_box(
	parent: Node3D, size: Vector3, material: Material, pos: Vector3
) -> MeshInstance3D:
	return PixelStyle.add_box(parent, size, pos, material)


static func _add_orb(
	parent: Node3D, color: Color, pos: Vector3, radius: float, scale := Vector3.ONE
) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh_inst.mesh = sphere
	mesh_inst.material_override = PixelStyle.make_material(color, color)
	mesh_inst.position = pos
	mesh_inst.scale = scale
	parent.add_child(mesh_inst)
	return mesh_inst
