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
	var options := {}
	if glow_color != Color(0, 0, 0, 0):
		options["glow"] = glow_color
	PropLibrary.attach(root, "chest", biome_id, options)
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
	PropLibrary.attach(root, "lever", biome_id)
	return root


static func build_bonfire(parent: Node3D, biome_id: String) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	PropLibrary.attach(root, "bonfire", biome_id)
	return root


static func build_lectern(parent: Node3D, biome_id: String) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	PropLibrary.attach(root, "lectern", biome_id)
	return root


static func build_npc(parent: Node3D, biome_id: String) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	PropLibrary.attach(root, "npc", biome_id)
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
	PropLibrary.attach(root, "loot_pickup", biome_id)
	root.set_meta("bob_base_y", root.position.y)
	return root


static func build_cannon(parent: Node3D, biome_id: String) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	PropLibrary.attach(root, "cannon", biome_id)
	return root


## The requirement reads as icons on the frame, not only in the interact prompt's text --
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
	PropLibrary.attach(root, "boss_door_frame", biome_id)
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
	_build_boss_door_requirement_icons(root, biome_id, requirement, lock_key_ids)
	return root


static func _build_boss_door_requirement_icons(
	root: Node3D, biome_id: String, requirement: String, lock_key_ids: Array
) -> void:
	if requirement == "sigil":
		var sigil := Node3D.new()
		sigil.name = "Sigil"
		sigil.position = Vector3(0.0, 4.55, 0.0)
		root.add_child(sigil)
		PropLibrary.attach(sigil, "sigil", biome_id)
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
		var icon := Node3D.new()
		icon.name = "KeyIcon%d" % i
		icon.position = Vector3(start_x + float(i) * spacing, 4.55, 0.0)
		root.add_child(icon)
		PropLibrary.attach(icon, "key_icon", biome_id, {"tint": tint})


## A locked door reads as a door -- two jambs, a lintel, and a keyhole-sized emissive inset
## tinted with the key's colour -- instead of an untextured slab the same shape as every other
## telegraph box in the dungeon. `key_tint` is `FloorKeyring.tint_for(key_id)`; pass `Color.WHITE`
## for a door whose key id didn't resolve to one of Doom's three colours.
static func build_locked_door_frame(parent: Node3D, biome_id: String, key_tint: Color) -> Node3D:
	var root := _make_root(parent)
	root.name = "LockedDoorVisual"
	PropLibrary.attach(root, "locked_door", biome_id, {"tint": key_tint})
	return root


static func build_spikes(
	parent: Node3D, biome_id: String, warning_color: Color = Color(0.75, 0.12, 0.1)
) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	PropLibrary.attach(root, "spikes", biome_id, {"warn": warning_color})
	return root


static func build_falling_block(parent: Node3D, biome_id: String) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	PropLibrary.attach(root, "falling_block", biome_id)
	return root


static func build_crystal_pillar(
	parent: Node3D, biome_id: String = BiomeRegistry.BIOME_CRYSTAL
) -> Node3D:
	_remove_visual(parent)
	var root := _make_root(parent)
	PropLibrary.attach(root, "crystal_pillar", biome_id)
	return root


static func make_telegraph_material(color: Color) -> Material:
	return PixelStyle.make_material(color, color * 0.5)


## Sinks a gate's barrier into the floor over 0.4s when it opens, instead of vanishing the instant it
## does. Collision drops immediately, so a player leaning on the door does not feel it disappear from
## under them, and does not get stuck waiting on the animation to pass through.
static func animate_gate_open(barrier: StaticBody3D, animate: bool = true) -> void:
	if barrier == null or not is_instance_valid(barrier) or not barrier.visible:
		return
	barrier.collision_layer = 0
	if not animate:
		barrier.visible = false
		return
	if barrier.has_meta(&"gate_open_tween"):
		var active := barrier.get_meta(&"gate_open_tween") as Tween
		if active != null and active.is_valid():
			active.kill()
	var start_y := barrier.position.y
	var tween := barrier.create_tween()
	barrier.set_meta(&"gate_open_tween", tween)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(barrier, "position:y", start_y - 2.4, 0.4)
	tween.tween_callback(
		func() -> void:
			if is_instance_valid(barrier):
				barrier.visible = false
				barrier.remove_meta(&"gate_open_tween")
	)


const FOG_GATE_SHADER_PATH := "res://assets/shared/fog_gate.gdshader"


## Every doorway in the game got a frame -- two jambs, a lintel with a keystone, and a
## threshold strip in the floor material -- instead of just a rectangular hole with a lintel.
## A single Blender model skinned with the wall and floor materials.
## `parent` is expected to be the doorway's own `DoorwaySocket` (a `Marker3D`, so its own transform
## already tracks the door's position/rotation across a room resize); safe to call more than once,
## the caller is expected to guard against duplicates by checking for `DoorwayFrameVisual` first.
static func build_doorway_frame(parent: Node3D, biome_id: String, width: float, height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "DoorwayFrameVisual"
	root.scale = Vector3(width / 3.0, height / 4.5, 1.0)
	parent.add_child(root)
	PropLibrary.attach(root, "doorway_frame", biome_id)
	return root


## A translucent scrolling-noise plane in `tint`, sized to a doorway. `boss_room_door.gd`
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
	# Any child with no material anywhere is dropped, whatever it is named: the exit portal in the castle
	# slice was a bare 3x3 BoxMesh called "PortalMesh" that rendered as Godot's default grey in the
	# doorway. Matching on "has no material" cannot take authored art with it, since default grey is the
	# one colour the palette never produces.
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


