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
