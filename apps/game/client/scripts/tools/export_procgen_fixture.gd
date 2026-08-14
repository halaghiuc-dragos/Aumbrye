extends Node

## Regenerates content/fixtures/dungeon_definition_v2_gdscript.json from the GDScript generator.
##
## This fixture is the reference sample of the v2 dungeon-definition shape, used by content
## validation and cross-stack parity checks. It used to be written as a side effect of running the
## procgen validation suite, which meant a test mutated tracked content: running the suite dirtied
## the working tree, and refreshing the fixture required running tests.
##
## Runs as a scene rather than via --script because the generator reaches autoload singletons,
## which are not registered during the bare --script compile pass.
##
## Usage:
##   godot --headless --path apps/game/client res://scenes/debug/export_procgen_fixture.tscn

const DungeonProcgenScript := preload("res://scripts/dungeon/procgen/dungeon_procgen.gd")

const FIXTURE_RELATIVE := "content/fixtures/dungeon_definition_v2_gdscript.json"
const BIOME_ID := "forgotten_castle"
const FIXTURE_SEED := 4242


func _ready() -> void:
	var result: Dictionary = DungeonProcgenScript.generate(BIOME_ID, FIXTURE_SEED, 1, 1, 1, false, false)
	if not result.get("ok", false):
		push_error(
			"export_procgen_fixture: generation failed — %s" % str(result.get("reason", "unknown"))
		)
		get_tree().quit(1)
		return

	var definition: Dictionary = result.get("definition", {})
	var empty_templates: Array[String] = []
	for room in definition.get("rooms", []):
		if room is Dictionary and str((room as Dictionary).get("templateId", "")).is_empty():
			empty_templates.append(str((room as Dictionary).get("id", "?")))
	if not empty_templates.is_empty():
		push_error(
			"export_procgen_fixture: rooms without a template cannot be built — %s"
			% ", ".join(empty_templates)
		)
		get_tree().quit(1)
		return

	var path := ContentLoader.content_path(FIXTURE_RELATIVE)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("export_procgen_fixture: could not write %s" % path)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(definition, "	"))
	file.close()

	print(
		"Wrote %s (%d rooms, seed %d)"
		% [FIXTURE_RELATIVE, definition.get("rooms", []).size(), FIXTURE_SEED]
	)
	get_tree().quit(0)
