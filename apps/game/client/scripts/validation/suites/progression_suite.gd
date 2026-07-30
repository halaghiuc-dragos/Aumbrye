extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "progression"


func run() -> void:
	_test_xp_grant()
	_test_death_xp_fraction()
	_test_run_buffs()
	_test_talent_unlock()
	_test_run_economy_docs()
	_test_m4_content_schemas()
	_test_character_service_fields()


func _test_xp_grant() -> void:
	var start := Time.get_ticks_msec()
	var before_level := ProgressionService.level
	var before_xp := ProgressionService.xp
	ProgressionService.grant_xp(100, "validation")
	var gained := ProgressionService.xp > before_xp or ProgressionService.level > before_level
	ProgressionService.from_save_dict({"level": before_level, "xp": before_xp, "talents": {}})
	ctx.timed_record(
		"progression.grant_xp",
		get_category(),
		gained,
		"grant_xp increases xp or level",
		start,
		"M4.prog.xp"
	)


func _test_death_xp_fraction() -> void:
	var start := Time.get_ticks_msec()
	var full := ProgressionService.calculate_run_xp(4, false, false)
	var death := ProgressionService.apply_death_xp_fraction(full)
	ctx.timed_record(
		"progression.death_xp_half",
		get_category(),
		death == int(full * 0.5),
		"death XP fraction is 50%",
		start,
		"M4.prog.death_xp"
	)


func _test_run_buffs() -> void:
	var start := Time.get_ticks_msec()
	RunBuffs.clear_all()
	var added := RunBuffs.add_relic("iron_will")
	var stats := RunBuffs.get_stat_totals()
	RunBuffs.clear_all()
	ctx.timed_record(
		"progression.run_relic_buff",
		get_category(),
		added and stats.get("maxHealth", 0.0) > 0.0 and RunBuffs.get_active_buffs().is_empty(),
		"run relic modifies stats and clears after run end",
		start,
		"M4.prog.relics"
	)


func _test_talent_unlock() -> void:
	var start := Time.get_ticks_msec()
	ProgressionService.from_save_dict({"level": 5, "xp": 500, "talents": {}})
	var can := ProgressionService.can_unlock_talent("guard_1")
	var unlocked := false
	if can:
		unlocked = ProgressionService.unlock_talent("guard_1")
	ProgressionService.from_save_dict({"level": 1, "xp": 0, "talents": {}})
	ctx.timed_record(
		"progression.talent_unlock",
		get_category(),
		can and unlocked and ProgressionService.get_talent_rank("guard_1") == 0,
		"talent unlock spends points at sufficient level",
		start,
		"M4.prog.talents"
	)


func _test_run_economy_docs() -> void:
	var start := Time.get_ticks_msec()
	var exists := FileAccess.file_exists(
		ProjectSettings.globalize_path("res://").path_join("../../..").path_join("docs/design/run_economy.md")
	)
	ctx.timed_record(
		"progression.run_economy_doc",
		get_category(),
		exists,
		"run economy rules documented",
		start,
		"M4.flow.economy"
	)


func _test_m4_content_schemas() -> void:
	var files := {
		"progression.affix_prefixes": "content/affixes/prefixes.json",
		"progression.affix_suffixes": "content/affixes/suffixes.json",
		"progression.affix_rarity": "content/affixes/rarity_rules.json",
		"progression.xp_curve": "content/progression/xp_curve.json",
		"progression.talent_tree": "content/talents/tree.json",
	}
	for test_id in files:
		var start := Time.get_ticks_msec()
		var path: String = files[test_id]
		var parsed: Variant = JSON.parse_string(_read_content_json(path))
		var ok: bool = parsed is Dictionary and not (parsed as Dictionary).is_empty()
		if test_id == "progression.xp_curve":
			ok = ok and (parsed as Dictionary).has("levels") and (parsed as Dictionary).has("baseXpPerRun")
		if test_id == "progression.talent_tree":
			ok = ok and (parsed as Dictionary).has("branches")
		if test_id.begins_with("progression.affix"):
			ok = ok and (parsed as Dictionary).has("schemaVersion")
		ctx.timed_record(
			test_id,
			get_category(),
			ok,
			"M4 content file loads: %s" % path,
			start,
			"M4.prog.content"
		)


func _test_character_service_fields() -> void:
	var start := Time.get_ticks_msec()
	CharacterService.reset_to_defaults()
	var has_core := (
		CharacterService.gold >= 0
		and CharacterService.level >= 1
		and CharacterService.flags is Dictionary
		and CharacterService.quests is Dictionary
	)
	CharacterService.set_flag("validation_test", true)
	CharacterService.set_quest_state("fetch_scrap", "active")
	var flag_ok := CharacterService.has_flag("validation_test")
	var quest_ok := CharacterService.get_quest_state("fetch_scrap") == "active"
	CharacterService.reset_to_defaults()
	ctx.timed_record(
		"progression.character_service",
		get_category(),
		has_core and flag_ok and quest_ok,
		"CharacterService gold/level/flags/quests round-trip",
		start,
		"M4.prog.character"
	)


func _read_content_json(relative_path: String) -> String:
	var full := ProjectSettings.globalize_path("res://").path_join("../../..").path_join(relative_path)
	if not FileAccess.file_exists(full):
		return ""
	return FileAccess.get_file_as_string(full)
