extends "res://scripts/validation/validation_suite.gd"

const AffixRollerScript := preload("res://scripts/loot/affix_roller.gd")


func get_category() -> String:
	return "affix"


func run() -> void:
	_test_affix_determinism()
	_test_stored_roll_seed_reproduces_roll()
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


## BUG-15 regression: the old code stored RandomNumberGenerator.seed *after* rolling — that
## property reads the generator's current state, not the value it was seeded with, so it looked
## deterministic when both calls passed the same explicit seed (as _test_affix_determinism
## does) but could not actually reproduce a roll from its own stored rollSeed. This rolls
## without an explicit seed (a natural drop), then feeds the *returned* rollSeed back through
## roll_identical and asserts the reproduction matches.
func _test_stored_roll_seed_reproduces_roll() -> void:
	var start := Time.get_ticks_msec()
	var original := AffixRollerScript.roll_instance("iron_sword")
	var stored_seed := int(original.get("rollSeed", -1))
	var reproduced := AffixRollerScript.roll_identical("iron_sword", stored_seed)
	var ok: bool = (
		stored_seed >= 0
		and not original.is_empty()
		and original.get("rarity", "") == reproduced.get("rarity", "?")
		and original.get("affixes", []) == reproduced.get("affixes", [])
		and int(reproduced.get("rollSeed", -1)) == stored_seed
	)
	ctx.timed_record(
		"affix.stored_roll_seed_reproduces_roll",
		get_category(),
		ok,
		"roll_identical(item_id, storedRollSeed) reproduces an unseeded natural roll",
		start,
		"BUG-15"
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
