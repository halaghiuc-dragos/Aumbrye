extends "res://scripts/validation/validation_suite.gd"

const RoomTemplateCatalogScript := preload("res://scripts/dungeon/procgen/room_template_catalog.gd")
const FloorSeedMixScript := preload("res://scripts/dungeon/floor_seed_mix.gd")
const DungeonProcgenScript := preload("res://scripts/dungeon/procgen/dungeon_procgen.gd")

const BIOME_IDS := [
	"forgotten_castle",
	"crystal_caverns",
	"poison_swamp",
	"frozen_fortress",
	"dark_cathedral",
	"iron_vault",
	"prism_depths",
	"venom_mire",
	"glacial_hollow",
	"umbral_chapel",
]

const MIX_SEED_SEEDS := [1, 2, 12345, 2147483646]
const ROOM_KIT_PREFIXES := [
	"castle",
	"crystal",
	"swamp",
	"frozen",
	"cathedral",
	"vault",
	"prism",
	"mire",
	"hollow",
	"umbral",
]
const ROOM_KIT_KINDS := [
	"entrance",
	"stairs",
	"corridor",
	"courtyard",
	"hall",
	"treasure",
	"secret",
	"arena",
	"boss",
	"puzzle",
]


func get_category() -> String:
	return "cross_stack_parity"


func run() -> void:
	_test_mix_seed_parity()
	_test_kind_spec_parity()
	_test_biome_catalog_parity()
	_test_cli_output_is_v1_valid()


func _fixture_text(relative_path: String) -> String:
	return FileAccess.get_file_as_string(ContentLoader.content_path(relative_path))


func _test_mix_seed_parity() -> void:
	var start := Time.get_ticks_msec()
	var fixture_text := _fixture_text("content/fixtures/mix_seed_parity.json")
	var fixture_rows: Variant = JSON.parse_string(fixture_text)
	var ok := fixture_rows is Array and not (fixture_rows as Array).is_empty()
	if ok:
		for row in fixture_rows:
			if not row is Dictionary:
				ok = false
				break
			var seed: int = int(row.get("seed", 0))
			var floor: int = int(row.get("floor", 0))
			var expected: int = int(row.get("mixed", -1))
			var actual := FloorSeedMixScript.mix(seed, floor)
			if actual != expected:
				ok = false
				break
	ctx.timed_record(
		"cross_stack.mix_seed_parity",
		get_category(),
		ok,
		"GDScript FloorSeedMix matches mix_seed_parity.json fixture",
		start,
		"RGP-05"
	)


func _test_kind_spec_parity() -> void:
	var start := Time.get_ticks_msec()
	var fixture_text := _fixture_text("content/fixtures/room_kit_specs.json")
	var fixture_rows: Variant = JSON.parse_string(fixture_text)
	var fixture_by_id := {}
	if fixture_rows is Array:
		for row in fixture_rows:
			if row is Dictionary:
				fixture_by_id[str(row.get("templateId", ""))] = row
	var ok := not fixture_by_id.is_empty()
	if ok:
		for prefix in ROOM_KIT_PREFIXES:
			for kind in ROOM_KIT_KINDS:
				var template_id := "%s_%s" % [prefix, kind]
				var fixture: Dictionary = fixture_by_id.get(template_id, {})
				if fixture.is_empty():
					ok = false
					break
				var spec := RoomTemplateCatalogScript.get_spec(template_id)
				if (
					not is_equal_approx(float(spec.get("width", -1)), float(fixture.get("width", -2)))
					or not is_equal_approx(float(spec.get("depth", -1)), float(fixture.get("depth", -2)))
					or int(spec.get("doors", -1)) != int(fixture.get("doors", -2))
				):
					ok = false
					break
			if not ok:
				break
	ctx.timed_record(
		"cross_stack.kind_spec_parity",
		get_category(),
		ok,
		"GDScript KIND_SPECS match C# room_kit_specs.json fixture",
		start,
		"RGP-05"
	)


func _test_biome_catalog_parity() -> void:
	var start := Time.get_ticks_msec()
	BiomeRegistry.warm_index()
	var ok := BiomeRegistry.ALL_BIOMES.size() == 10
	if ok:
		for biome_id in BiomeRegistry.ALL_BIOMES:
			var biome := BiomeRegistry.get_biome(biome_id)
			var prefix := str(biome.get("templatePrefix", ""))
			if RoomTemplateCatalogScript.template_prefix_for_biome(biome_id) != prefix:
				ok = false
			var room_count: Dictionary = biome.get("roomCount", {})
			if int(room_count.get("min", 0)) <= 0 or int(room_count.get("max", 0)) <= 0:
				ok = false
	ctx.timed_record(
		"cross_stack.biome_catalog_parity",
		get_category(),
		ok,
		"GDScript BiomeRegistry matches templatePrefix and roomCount per biome JSON",
		start,
		"BIO-13"
	)


func _test_cli_output_is_v1_valid() -> void:
	var start := Time.get_ticks_msec()
	var fixture_text := _fixture_text("content/fixtures/dungeon_definition_v1_minimal.json")
	var fixture: Variant = JSON.parse_string(fixture_text)
	var ok := fixture is Dictionary and int(fixture.get("schemaVersion", 0)) == 1
	if ok:
		var required := [
			"runId",
			"seed",
			"biomeId",
			"tier",
			"playerLevelSnapshot",
			"rooms",
			"edges",
			"placements",
			"budgets",
		]
		for key in required:
			if not fixture.has(key):
				ok = false
				break
	ctx.timed_record(
		"cross_stack.cli_v1_fixture",
		get_category(),
		ok,
		"Checked-in v1 dungeon fixture has required CLI-shaped keys",
		start,
		"RGP-05"
	)
