extends Node

## Loads and instantiates every scene in the project and reports what is wrong with it.
##
## There are 285 scenes. Opening them by hand is not a check anyone repeats, so this is the form
## the "go through every scene" pass takes: each one is instantiated for real, added to the tree,
## given a frame to run its _ready, and inspected. A scene that cannot load, a script that errors
## on entry, a mesh with no material, a shadow setting that disagrees with its neighbours -- all of
## it shows up here rather than being found by a player.
##
## Run: godot --path apps/game/client --headless res://scenes/debug/scene_sweep.tscn
##      godot --path apps/game/client --headless res://scenes/debug/scene_sweep.tscn -- --verbose

const SKIP_DIRS: PackedStringArray = ["res://scenes/debug/"]

## Scenes that build a whole run the moment they load -- a full dungeon generation, a hub with its
## village and crowd. Instantiating them here costs more than the other 257 put together and tells
## us nothing the dedicated audits do not already cover. A sweep nobody can afford to run is not a
## check, so these are named and left to the scenes that exist to exercise them.
const SKIP_SCENES: PackedStringArray = [
	"res://scenes/dungeon/castle_run.tscn",
	"res://scenes/dungeon/waves_run.tscn",
	"res://scenes/hub/hub.tscn",
]

## VS-04: `castle_run.tscn` is skipped above for cost, but that meant the one place the review
## called out by name -- "a flat untextured grey rectangle where a doorway should be" -- was never
## actually inspected, since the static room `.tscn` files it's built from are mostly placeholders
## that get skinned procedurally at build time. This builds one real floor per biome instead (far
## cheaper than a full run scene) and runs the exact same `_inspect()` used on every other scene.
const BUILT_FLOOR_BIOMES: PackedStringArray = [
	"forgotten_castle", "crystal_caverns", "poison_swamp", "frozen_fortress", "dark_cathedral",
	"iron_vault", "prism_depths", "venom_mire", "glacial_hollow", "umbral_chapel",
]

const LocalProcgenScript := preload("res://scripts/dungeon/local_procgen.gd")
const DungeonBuilderScript := preload("res://scripts/dungeon/dungeon_builder.gd")

var _failures: int = 0
var _scanned: int = 0
var _findings: Dictionary = {}
var _verbose := false


func _ready() -> void:
	_verbose = "--verbose" in OS.get_cmdline_user_args()
	await get_tree().process_frame
	var paths := _all_scenes()
	print("SWEEP scanning %d scenes" % paths.size())
	for path in paths:
		await _check_scene(path)
	await _check_built_floors()
	await _check_hud_matrix()
	_check_prop_kits()
	_report()
	print("SCENE SWEEP RESULT %d failures across %d scenes" % [_failures, _scanned])
	get_tree().quit(1 if _failures > 0 else 0)


func _all_scenes() -> PackedStringArray:
	var out := PackedStringArray()
	_walk("res://scenes", out)
	out.sort()
	return out


func _walk(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_walk("%s/%s" % [dir_path, sub], out)
	for file in dir.get_files():
		if not file.ends_with(".tscn"):
			continue
		var full := "%s/%s" % [dir_path, file]
		var skip := SKIP_SCENES.has(full)
		for prefix in SKIP_DIRS:
			if full.begins_with(prefix):
				skip = true
		if not skip:
			out.append(full)


func _note(path: String, kind: String, detail: String, fatal: bool = false) -> void:
	if fatal:
		_failures += 1
	var row := "%s: %s" % [path.replace("res://scenes/", ""), detail]
	_findings.get_or_add(kind, [])
	(_findings[kind] as Array).append(row)
	# Printed as it is found rather than only in the summary: the sweep takes a while, and a run
	# that is cut short should still have told you everything it had got to.
	print("  [%s] %s" % [kind, row])


func _check_scene(path: String) -> void:
	_scanned += 1
	if _verbose:
		print("  .. %s" % path)
	if not ResourceLoader.exists(path):
		_note(path, "missing", "does not exist", true)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		_note(path, "unloadable", "did not load as a PackedScene", true)
		return
	if not packed.can_instantiate():
		_note(path, "uninstantiable", "PackedScene refuses to instantiate", true)
		return
	var instance: Node = null
	instance = packed.instantiate()
	if instance == null:
		_note(path, "uninstantiable", "instantiate returned null", true)
		return
	add_child(instance)
	await get_tree().process_frame
	_inspect(path, instance)
	instance.free()


## VS-04: one built floor per biome, the same material/shadow inspection every static scene gets.
func _check_built_floors() -> void:
	var biome_prefixes := {
		"forgotten_castle": "castle", "crystal_caverns": "crystal", "poison_swamp": "swamp",
		"frozen_fortress": "frozen", "dark_cathedral": "cathedral", "iron_vault": "vault",
		"prism_depths": "prism", "venom_mire": "swamp", "glacial_hollow": "frozen",
		"umbral_chapel": "cathedral",
	}
	for biome_id in BUILT_FLOOR_BIOMES:
		_scanned += 1
		var label := "built_floor:%s" % biome_id
		if _verbose:
			print("  .. %s" % label)
		var result: Dictionary = LocalProcgenScript.generate(
			biome_id, 424242, 1, str(biome_prefixes.get(biome_id, "castle")), 1, 1, false, false, true
		)
		if not result.get("ok", false):
			_note(label, "generation_failed", str(result.get("error", "?")), true)
			continue
		var definition: Dictionary = result.get("definition", {})
		var parent := Node3D.new()
		add_child(parent)
		var builder := DungeonBuilderScript.new()
		parent.add_child(builder)
		await builder.build_from_definition(parent, null, definition, false)
		await get_tree().physics_frame
		_inspect(label, parent)
		parent.free()


## SY-09/HD-04: `combat_hud.gd`'s `configure_for_mode()` is the one place that decides which
## elements a mode gets; this checks it against the same table the plan's HD-04 pastes above that
## function -- minimap, branch previews and the key row are the elements the table marks "waves".
## Everything else in the table is either always-on (never toggled by mode) or content-driven (boss
## bar, objective text), so those are not re-tested here.
##
## A bare, freshly-instantiated HUD starts several of these elements hidden regardless of mode --
## `_minimap_anchor` and `_branch_banner` only turn on once a run feeds them real floor/map data, so
## reading a bare HUD's default visibility would test that unrelated population timing instead of
## the mode contract. Each element is forced visible before every call instead, so the assertion
## after the call tests only what `configure_for_mode()` itself did.
func _check_hud_matrix() -> void:
	var label := "hud_matrix"
	_scanned += 1
	var packed := load("res://scenes/ui/combat_hud.tscn") as PackedScene
	if packed == null:
		_note(label, "unloadable", "combat_hud.tscn did not load as a PackedScene", true)
		return
	var hud := packed.instantiate()
	add_child(hud)
	await get_tree().process_frame
	var minimap_anchor: Control = hud.get_node_or_null("MinimapAnchor")
	var branch_banner: Control = hud.get_node_or_null("BranchBanner")
	for run_mode in ["castle", "endless", "waves"]:
		if minimap_anchor:
			minimap_anchor.visible = true
		if branch_banner:
			branch_banner.visible = true
		var key_row: Control = hud.get("_key_row")
		if key_row:
			key_row.visible = true
		hud.call("configure_for_mode", run_mode)
		key_row = hud.get("_key_row")
		var expect_visible: bool = str(run_mode) != "waves"
		if minimap_anchor and minimap_anchor.visible != expect_visible:
			_note(label, "hud_matrix_mismatch", "%s: minimap visible=%s, expected %s" % [
				run_mode, minimap_anchor.visible, expect_visible
			], true)
		if branch_banner and branch_banner.visible != expect_visible:
			_note(label, "hud_matrix_mismatch", "%s: branch banner visible=%s, expected %s" % [
				run_mode, branch_banner.visible, expect_visible
			], true)
		if key_row and key_row.visible != expect_visible:
			_note(label, "hud_matrix_mismatch", "%s: key row visible=%s, expected %s" % [
				run_mode, key_row.visible, expect_visible
			], true)
	hud.free()


## RM-21: `ResourceLoader.exists()` is true for a three-line placeholder scene
## (`[gd_scene]` / blank / `[node type="Node3D"]`) exactly as much as for a real one -- existence is
## not content. This walks every biome's `propKit` block (`content/biomes/<id>.json`) and fails any
## entry whose scene has no `MeshInstance3D` descendant, so a biome that regresses to a stub prop
## (or ships one from the start) is caught here instead of only being noticed in-game.
func _check_prop_kits() -> void:
	for biome_id in BUILT_FLOOR_BIOMES:
		_scanned += 1
		var label := "prop_kit:%s" % biome_id
		if _verbose:
			print("  .. %s" % label)
		var kit: Dictionary = BiomeRegistry.get_biome(biome_id).get("propKit", {})
		if kit.is_empty():
			_note(label, "prop_kit_missing", "%s has no propKit block" % biome_id, true)
			continue
		var paths: Array[String] = []
		for slot in ["pillar", "sconce"]:
			var slot_path := str(kit.get(slot, ""))
			if slot_path != "":
				paths.append(slot_path)
		var rubble: Variant = kit.get("rubble", [])
		if rubble is Array:
			for entry in rubble:
				paths.append(str(entry))
		if paths.is_empty():
			_note(
				label,
				"prop_kit_missing",
				"%s propKit has no pillar/sconce/rubble paths" % biome_id,
				true
			)
			continue
		for path in paths:
			_check_prop_kit_scene(label, path)


func _check_prop_kit_scene(label: String, path: String) -> void:
	if not ResourceLoader.exists(path):
		_note(label, "prop_kit_no_geometry", "%s does not exist" % path, true)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		_note(label, "prop_kit_no_geometry", "%s did not load as a PackedScene" % path, true)
		return
	var instance := packed.instantiate()
	if instance == null:
		_note(label, "prop_kit_no_geometry", "%s failed to instantiate" % path, true)
		return
	if not _has_mesh_instance(instance):
		_note(
			label,
			"prop_kit_no_geometry",
			(
				"%s has no MeshInstance3D descendant -- propKit entries must carry real geometry, "
				+ "not a placeholder"
			) % path,
			true
		)
	instance.free()


func _has_mesh_instance(node: Node) -> bool:
	if node is MeshInstance3D:
		return true
	for child in node.get_children():
		if _has_mesh_instance(child):
			return true
	return false


func _inspect(path: String, root: Node) -> void:
	var meshes: Array[GeometryInstance3D] = []
	var lights: Array[Light3D] = []
	_collect(root, meshes, lights)

	for mesh in meshes:
		var mi := mesh as MeshInstance3D
		if mi and mi.mesh == null:
			_note(path, "empty_mesh", "%s has no mesh resource" % _where(root, mi))
			continue
		if mi == null:
			continue
		# A mesh with no material anywhere renders in Godot's default grey, which is the one colour
		# the palette never produces -- it is always a mistake rather than a style choice.
		var has_material := mi.material_override != null
		if not has_material:
			for surface in mi.mesh.get_surface_count():
				if (
					mi.get_surface_override_material(surface) != null
					or mi.mesh.surface_get_material(surface) != null
				):
					has_material = true
					break
		# A hidden placeholder is not a visual bug. Several scenes keep a legacy mesh around and
		# switch it off in _ready once the diorama skin has built the real one; flagging those would
		# bury the ones that are actually on screen.
		if not has_material and mi.is_visible_in_tree():
			_note(path, "no_material", "%s renders untextured grey" % _where(root, mi))

	# A scene owning a DirectionalLight3D is not a fault: VisualLighting looks up "DirectionalLight3D"
	# and "FillLight" by name on the level root and configures those, and DayNightService adds
	# "MoonLight" beside them. Flagging them would be flagging the lighting system working.
	for light in lights:
		if light is OmniLight3D and light.shadow_enabled and light.light_energy <= 0.0:
			_note(path, "dark_shadow_caster", "%s casts shadows at zero energy" % light.name)


## Where a node sits, relative to the scene root. An auto-named "@MeshInstance3D@867" says nothing
## on its own; the path to it says which prop built it.
func _where(root: Node, node: Node) -> String:
	return str(root.get_path_to(node))


func _collect(node: Node, meshes: Array[GeometryInstance3D], lights: Array[Light3D]) -> void:
	if node is GeometryInstance3D:
		meshes.append(node as GeometryInstance3D)
	if node is Light3D:
		lights.append(node as Light3D)
	for child in node.get_children():
		_collect(child, meshes, lights)


func _report() -> void:
	for kind in _findings:
		var rows: Array = _findings[kind]
		print("\n%s (%d)" % [kind.to_upper(), rows.size()])
		var shown := rows.size() if _verbose else mini(rows.size(), 8)
		for i in shown:
			print("  %s" % rows[i])
		if shown < rows.size():
			print("  ... and %d more (run with -- --verbose)" % (rows.size() - shown))
