extends "res://scripts/validation/validation_suite.gd"

const AffixRollerScript := preload("res://scripts/loot/affix_roller.gd")


func get_category() -> String:
	return "affix"


func run() -> void:
	_test_affix_determinism()
	_test_affix_content_single_source()


func _test_affix_determinism() -> void:
	var start := Time.get_ticks_msec()
	var roll_a := AffixRollerScript.roll_identical("iron_sword", 424242)
	var roll_b := AffixRollerScript.roll_identical("iron_sword", 424242)
	var ok: bool = (
		not roll_a.is_empty()
		and roll_a.get("rollSeed", -1) == roll_b.get("rollSeed", -2)
		and roll_a.get("rarity", "") == roll_b.get("rarity", "?")
		and roll_a.get("affixes", []) == roll_b.get("affixes", [])
	)
	ctx.timed_record(
		"affix.determinism",
		get_category(),
		ok,
		"AffixRoller is deterministic for same item + rollSeed",
		start,
		"M8.affix.determinism"
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
		"affix.json_source",
		get_category(),
		ok,
		"Affix rolls read content/affixes/*.json",
		start,
		"M8.affix.source"
	)
