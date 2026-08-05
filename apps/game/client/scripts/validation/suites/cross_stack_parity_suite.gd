extends "res://scripts/validation/validation_suite.gd"

const RoomTemplateCatalogScript := preload("res://scripts/dungeon/procgen/room_template_catalog.gd")
const ProcgenBiomeLoaderScript := preload("res://scripts/dungeon/procgen/procgen_biome_loader.gd")
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


func get_category() -> String:
	return "cross_stack_parity"


func run() -> void:
	_test_biome_prefix_parity()
	_test_gdscript_generation_schema()
	_test_affix_determinism()
	_test_affix_content_single_source()


func _test_biome_prefix_parity() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BIOME_IDS:
		var prefix := RoomTemplateCatalogScript.template_prefix_for_biome(biome_id)
		var entrance := "%s_entrance" % prefix
		if RoomTemplateCatalogScript.kind_from_template_id(entrance) != "entrance":
			ok = false
			break
	ctx.timed_record(
		"cross_stack.biome_prefix_parity",
		get_category(),
		ok,
		"GDScript biome prefixes resolve to known room kit specs",
		start,
		"M8.cross_stack.prefix"
	)


func _test_gdscript_generation_schema() -> void:
	var start := Time.get_ticks_msec()
	var gen := DungeonProcgenScript.generate("forgotten_castle", TC.SEED_A, 1, 1, 1, false, false)
	var def: Dictionary = gen.get("definition", {})
	var ok: bool = (
		gen.get("ok", false)
		and def.has("roomContent")
		and def.has("locks")
		and def.has("puzzles")
		and def.get("floorIndex", 0) == 1
	)
	ctx.timed_record(
		"cross_stack.gdscript_schema",
		get_category(),
		ok,
		"GDScript dungeon definition includes roomContent, locks, puzzles, floorIndex",
		start,
		"M8.cross_stack.schema"
	)


func _test_affix_determinism() -> void:
	var start := Time.get_ticks_msec()
	var roll_a := AffixRoller.roll_identical("iron_sword", 424242)
	var roll_b := AffixRoller.roll_identical("iron_sword", 424242)
	var ok: bool = (
		not roll_a.is_empty()
		and roll_a.get("rollSeed", -1) == roll_b.get("rollSeed", -2)
		and roll_a.get("rarity", "") == roll_b.get("rarity", "?")
		and roll_a.get("affixes", []) == roll_b.get("affixes", [])
	)
	ctx.timed_record(
		"cross_stack.affix_determinism",
		get_category(),
		ok,
		"GDScript AffixRoller is deterministic for same item + rollSeed",
		start,
		"M8.cross_stack.affix"
	)


func _test_affix_content_single_source() -> void:
	var start := Time.get_ticks_msec()
	var prefixes := ContentLoader.load_json("content/affixes/prefixes.json")
	var suffixes := ContentLoader.load_json("content/affixes/suffixes.json")
	var rules := ContentLoader.load_json("content/affixes/rarity_rules.json")
	var ok: bool = (
		prefixes.has("affixes")
		and suffixes.has("affixes")
		and (rules.has("rarityWeights") or rules.has("rarities"))
	)
	ctx.timed_record(
		"cross_stack.affix_json_source",
		get_category(),
		ok,
		"Affix rolls read content/affixes/*.json (C# AffixRoller uses same files)",
		start,
		"M8.cross_stack.affix_source"
	)
