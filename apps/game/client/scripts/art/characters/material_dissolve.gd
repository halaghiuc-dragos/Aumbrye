extends RefCounted
class_name MaterialDissolve

## Death dissolve via dither-clip on pixel_diorama_surface materials.
##
## REF-06: dissolve uniforms are `instance uniform` on the shared pixel-diorama shaders, so
## dissolving a character is a per-`MeshInstance3D` shader-parameter write, not a per-death
## material duplication across every mesh part.

const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")
const CharacterRigCatalogScript := preload("res://scripts/art/characters/character_rig_catalog.gd")
const VfxServiceScript := preload("res://scripts/art/vfx/vfx_service.gd")

const DISSOLVE_PARAM := &"dissolve_clip"
const FLASH_PARAM := &"flash_amount"
const ORIGIN_PARAM := &"dissolve_origin"
const DIR_PARAM := &"dissolve_dir"
const SWEEP_PARAM := &"dissolve_sweep"
static func default_dissolve_duration() -> float:
	return VfxServiceScript.get_death_burst_lifetime()
const META_ACTIVE_TWEEN := &"material_dissolve_tween"
const META_DEATH_STATE := &"death_visual_state"
const SINK_DELAY := 0.45
const SINK_DEPTH := 1.2
const SINK_DURATION := 0.4

const DEATH_DEFAULTS: Dictionary = {
	"humanoid": {"duration": 0.65, "stagger": 0.12, "sweep": "up", "debris": 6},
	"quadruped": {"duration": 0.6, "stagger": 0.10, "sweep": "up", "debris": 5},
	"blob": {"duration": 0.45, "stagger": 0.0, "sweep": "out", "debris": 4},
	"flyer": {"duration": 0.5, "stagger": 0.0, "sweep": "down", "debris": 3},
	"boss_humanoid": {"duration": 1.4, "stagger": 0.35, "sweep": "up", "debris": 14},
	"construct": {"duration": 1.1, "stagger": 0.4, "sweep": "up", "debris": 10},
}

const PROFILE_RIG_KIND: Dictionary = {
	"player": "humanoid",
	"melee": "humanoid",
	"ranged": "humanoid",
	"shield": "humanoid",
	"dummy": "humanoid",
	"hound": "quadruped",
	"brute": "humanoid",
}


static func play_death_visual(visual: Node3D, opts: Dictionary = {}) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var merged := _merge_opts(visual, opts)
	_record_death_state(visual)
	if merged.has("vfx_position"):
		var tint: Color = merged.get("vfx_tint", Color(0.55, 0.22, 0.18))
		var debris := int(merged.get("debris", 6))
		VfxService.play_death(merged["vfx_position"] as Vector3, tint, debris)
	dissolve(visual, merged)
	_apply_sink_and_scale(visual, merged)


static func reset_death_visual(visual: Node3D) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	restore(visual)
	_restore_death_state(visual)


static func dissolve(node: Node3D, opts: Dictionary = {}) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not node.is_inside_tree():
		return
	var tree := node.get_tree()
	var merged := _merge_opts(node, opts)
	var meshes := _gather_meshes(node)
	if meshes.is_empty():
		return
	var duration := float(merged.get("duration", default_dissolve_duration()))
	var max_stagger := float(merged.get("stagger", 0.0))
	var sweep_dir := merged.get("sweep_dir", Vector3.ZERO) as Vector3
	var object_sweep := _object_sweep_dir(node, sweep_dir, str(merged.get("sweep", "up")))
	var sweep_strength := _sweep_strength(str(merged.get("sweep", "up")))
	var targets: Array[Dictionary] = []
	for mesh in meshes:
		if not _has_dissolve_shader(mesh):
			continue
		MaterialFlashScript.cancel(mesh)
		mesh.set_instance_shader_parameter(DISSOLVE_PARAM, 1.0)
		mesh.set_instance_shader_parameter(ORIGIN_PARAM, Vector3.ZERO)
		mesh.set_instance_shader_parameter(DIR_PARAM, object_sweep)
		mesh.set_instance_shader_parameter(SWEEP_PARAM, sweep_strength)
		var stagger := _stagger_for_mesh(mesh, max_stagger)
		targets.append({"mesh": mesh, "stagger": stagger})
	if targets.is_empty():
		return
	for entry in targets:
		var mesh: MeshInstance3D = entry["mesh"]
		var stagger := float(entry["stagger"])
		var mesh_tween := tree.create_tween()
		mesh.set_meta(META_ACTIVE_TWEEN, mesh_tween)
		if stagger > 0.0:
			mesh_tween.tween_interval(stagger)
		mesh_tween.tween_method(
			func(v: float) -> void:
				if is_instance_valid(mesh):
					mesh.set_instance_shader_parameter(DISSOLVE_PARAM, v),
			1.0,
			0.0,
			duration
		)


static func restore(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	for mesh in _gather_meshes(node):
		_restore_mesh(mesh)


static func death_opts_for_profile(profile: String, archetype_id: String = "") -> Dictionary:
	var rig_kind: String = str(PROFILE_RIG_KIND.get(profile, "humanoid"))
	return _death_opts_for_rig_kind(rig_kind, archetype_id)


static func death_opts_for_enemy(
	profile: String, is_boss: bool, data: Dictionary, archetype_id: String = ""
) -> Dictionary:
	var rig_kind: String = str(PROFILE_RIG_KIND.get(profile, "humanoid"))
	if is_boss:
		rig_kind = "boss_humanoid"
	elif profile == "brute" and str(data.get("enemy_type", "")) == "construct":
		rig_kind = "construct"
	return _death_opts_for_rig_kind(rig_kind, archetype_id)


static func _death_opts_for_rig_kind(rig_kind: String, archetype_id: String) -> Dictionary:
	var defaults: Dictionary = (
		DEATH_DEFAULTS.get(rig_kind, DEATH_DEFAULTS["humanoid"]) as Dictionary
	).duplicate()
	if archetype_id != "":
		var manifest := CharacterRigCatalogScript.get_manifest(archetype_id)
		var death_block: Variant = manifest.get("death", null)
		if death_block is Dictionary:
			for key in death_block.keys():
				defaults[key] = death_block[key]
	defaults["rig_kind"] = rig_kind
	return defaults


static func _merge_opts(node: Node3D, opts: Dictionary) -> Dictionary:
	var merged: Dictionary = {}
	if opts.has("rig_kind"):
		merged = _death_opts_for_rig_kind(str(opts["rig_kind"]), "")
	else:
		merged = (DEATH_DEFAULTS["humanoid"] as Dictionary).duplicate()
		merged["rig_kind"] = "humanoid"
	for key in opts.keys():
		merged[key] = opts[key]
	if not merged.has("duration"):
		merged["duration"] = default_dissolve_duration()
	return merged


static func _record_death_state(visual: Node3D) -> void:
	visual.set_meta(
		META_DEATH_STATE,
		{
			"position": visual.position,
			"scale": visual.scale,
		}
	)


static func _restore_death_state(visual: Node3D) -> void:
	if not visual.has_meta(META_DEATH_STATE):
		return
	var state: Dictionary = visual.get_meta(META_DEATH_STATE)
	visual.position = state.get("position", visual.position)
	visual.scale = state.get("scale", visual.scale)
	visual.remove_meta(META_DEATH_STATE)


static func _apply_sink_and_scale(visual: Node3D, opts: Dictionary) -> void:
	var tree := visual.get_tree()
	if tree == null:
		return
	var rig_kind := str(opts.get("rig_kind", "humanoid"))
	if rig_kind == "blob":
		var squash := tree.create_tween()
		squash.tween_property(visual, "scale", Vector3(visual.scale.x, visual.scale.y * 0.6, visual.scale.z), 0.15)
	if bool(opts.get("has_animator", false)):
		var sink := tree.create_tween()
		sink.tween_interval(SINK_DELAY)
		sink.tween_property(visual, "position:y", visual.position.y - SINK_DEPTH, SINK_DURATION)
		return
	var death_scale := Vector3(0.2, 0.05, 0.2)
	var tween := tree.create_tween()
	tween.tween_property(visual, "scale", death_scale, 0.35)
	tween.parallel().tween_property(visual, "position:y", -0.8, 0.35)


static func _restore_mesh(mesh: MeshInstance3D) -> void:
	if mesh == null or not is_instance_valid(mesh):
		return
	if mesh.has_meta(META_ACTIVE_TWEEN):
		var active_tween := mesh.get_meta(META_ACTIVE_TWEEN) as Tween
		if active_tween and active_tween.is_valid():
			active_tween.kill()
		mesh.remove_meta(META_ACTIVE_TWEEN)
	if _has_dissolve_shader(mesh):
		mesh.set_instance_shader_parameter(DISSOLVE_PARAM, 1.0)


static func _has_dissolve_shader(mesh: MeshInstance3D) -> bool:
	var mat := mesh.material_override as ShaderMaterial
	if mat == null:
		mat = mesh.get_active_material(0) as ShaderMaterial
	return mat != null and mat.shader != null


static func _object_sweep_dir(node: Node3D, world_dir: Vector3, sweep_mode: String) -> Vector3:
	if world_dir.length_squared() > 0.01:
		var local := node.global_transform.basis.inverse() * world_dir.normalized()
		return local.normalized()
	match sweep_mode:
		"down":
			return Vector3.DOWN
		"out":
			return Vector3.ZERO
		_:
			return Vector3.UP


static func _sweep_strength(sweep_mode: String) -> float:
	match sweep_mode:
		"down":
			return 0.6
		"out":
			return 0.75
		_:
			return 0.6


static func _stagger_for_mesh(mesh: MeshInstance3D, max_stagger: float) -> float:
	if max_stagger <= 0.0:
		return 0.0
	var pivot := _mesh_pivot_name(mesh)
	match pivot:
		"LegL", "LegR", "LegFL", "LegFR", "LegBL", "LegBR":
			return 0.0
		"ArmL", "ArmR", "WingL", "WingR":
			return max_stagger * 0.35
		"Torso", "Tail":
			return max_stagger * 0.55
		"Head":
			return max_stagger
		_:
			return max_stagger * 0.25


static func _mesh_pivot_name(mesh: MeshInstance3D) -> String:
	var parent := mesh.get_parent()
	if parent is Node3D:
		return parent.name
	return ""


static func _gather_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_gather_meshes(child))
	return out
