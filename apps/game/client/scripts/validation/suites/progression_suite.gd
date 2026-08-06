extends "res://scripts/validation/validation_suite.gd"

const WeaponControllerScript := preload("res://scripts/combat/weapon_controller.gd")


func get_category() -> String:
	return "progression"


func run() -> void:
	_test_xp_grant()
	_test_death_xp_fraction()
	_test_run_buffs()
	_test_talent_unlock()
	_test_m4_content_schemas()
	_test_xp_curve_runtime_keys()
	_test_talent_points_from_curve()
	_test_content_schema_validator()
	_test_character_service_fields()
	_test_character_quests()
	_test_character_flags()
	_test_character_signals()
	_test_character_save_round_trip()
	_test_character_currency()
	_test_talent_xp_gain_applies()
	_test_talent_loot_quality_shifts_weights()
	_test_talent_gold_find_applies()
	_test_talent_cooldown_reduction_applies()
	_test_talent_each_node_has_consumer()
	_test_abandon_xp_fraction()
	_test_xp_granted_reason_hook()


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
			ok = (
				ok
				and (parsed as Dictionary).has("levels")
				and (parsed as Dictionary).has("baseXpPerKill")
			)
		if test_id == "progression.talent_tree":
			ok = ok and (parsed as Dictionary).has("branches")
			ok = ok and not (parsed as Dictionary).has("talentPointsPerLevel")
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


func _test_xp_curve_runtime_keys() -> void:
	var start := Time.get_ticks_msec()
	var curve: Dictionary = ContentLoader.load_json("content/progression/xp_curve.json")
	var per_kill: int = int(curve.get("baseXpPerKill", 0))
	var expected := per_kill
	var actual := ProgressionService.calculate_run_xp(1, false, false)
	var boss_actual := ProgressionService.calculate_run_xp(0, true, false)
	var escape_actual := ProgressionService.calculate_run_xp(0, false, true)
	var ok: bool = (
		per_kill > 0
		and actual == expected
		and boss_actual == int(curve.get("bossBonusXp", 0))
		and escape_actual == int(curve.get("escapeBonusXp", 0))
	)
	ctx.timed_record(
		"progression.xp_curve_runtime_keys",
		get_category(),
		ok,
		"calculate_run_xp reads baseXpPerKill/boss/escape from xp_curve.json",
		start,
		"prog.curve.keys_match_reader"
	)


func _test_talent_points_from_curve() -> void:
	var start := Time.get_ticks_msec()
	var curve: Dictionary = ContentLoader.load_json("content/progression/xp_curve.json")
	var per_level: int = int(curve.get("talentPointsPerLevel", 1))
	ProgressionService.from_save_dict({"level": 5, "xp": 500, "talents": {}})
	var points_at_5 := ProgressionService.get_available_talent_points()
	var expected := (5 - 1) * per_level
	ProgressionService.from_save_dict({"level": 1, "xp": 0, "talents": {}})
	ctx.timed_record(
		"progression.talent_points_from_curve",
		get_category(),
		points_at_5 == expected,
		"talent points derive from xp_curve talentPointsPerLevel",
		start,
		"M4.prog.talents"
	)


func _test_content_schema_validator() -> void:
	var start := Time.get_ticks_msec()
	var curve: Dictionary = ContentLoader.load_json("content/progression/xp_curve.json")
	var ok: bool = (
		curve.has("baseXpPerKill")
		and not curve.has("baseXpPerRun")
		and ctx.file_contains(
			"res://scripts/app/content_loader.gd", "ContentSchemaValidator.validate_loaded"
		)
		and ctx.file_contains(
			"res://scripts/app/content_schema_validator.gd", "validate_roll_instance"
		)
	)
	ctx.timed_record(
		"progression.content_schema_validator",
		get_category(),
		ok,
		"debug ContentSchemaValidator guards hot-path content loads",
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
		and CharacterService.quest_states is Dictionary
		and CharacterService.quest_progress is Dictionary
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


func _test_character_quests() -> void:
	var start := Time.get_ticks_msec()
	CharacterService.reset_to_defaults()
	CharacterService.set_quest_state("relic_progress", "active")
	CharacterService.set_quest_progress("relic", {"count": 3})
	var ok: bool = (
		CharacterService.get_quest_state("relic_progress") == "active"
		and int(CharacterService.get_quest_progress("relic").get("count", 0)) == 3
	)
	ctx.timed_record(
		"character.quests.state_and_progress_are_separate",
		get_category(),
		ok,
		"quest state and progress keys do not collide",
		start,
		"CHS-01"
	)

	start = Time.get_ticks_msec()
	CharacterService.set_quest_state("relic", "banana")
	var rejected := CharacterService.get_quest_state("relic") == "inactive"
	ctx.timed_record(
		"character.quests.rejects_unknown_state",
		get_category(),
		rejected,
		"unknown quest state is rejected",
		start,
		"CHS-01"
	)

	start = Time.get_ticks_msec()
	CharacterService.set_quest_state("kill_a", "active")
	CharacterService.set_quest_state("kill_b", "completed")
	CharacterService.set_quest_progress("kill_b", {"count": 1})
	var active_ids := CharacterService.active_quest_ids()
	var active_ok := active_ids.size() == 1 and active_ids[0] == "kill_a"
	ctx.timed_record(
		"character.quests.active_ids_excludes_progress",
		get_category(),
		active_ok,
		"active_quest_ids returns only active states",
		start,
		"CHS-01"
	)

	start = Time.get_ticks_msec()
	var nested := {"nested": {"count": 1}}
	CharacterService.set_quest_progress("deep", nested)
	nested["nested"]["count"] = 99
	var deep_ok := int(CharacterService.get_quest_progress("deep").get("nested", {}).get("count", 0)) == 1
	ctx.timed_record(
		"character.quests.progress_is_deep_copied",
		get_category(),
		deep_ok,
		"quest progress is deep-copied on set",
		start,
		"CHS-12"
	)
	CharacterService.reset_to_defaults()


func _test_character_flags() -> void:
	var start := Time.get_ticks_msec()
	CharacterService.reset_to_defaults()
	CharacterService.set_flag("deaths", "7")
	CharacterService.set_flag("story_completed", 1)
	var deaths_ok := CharacterService.get_flag("deaths") is int and int(CharacterService.get_flag("deaths")) == 7
	var story_ok: bool = CharacterService.get_flag("story_completed") is bool and CharacterService.get_flag("story_completed") == true
	ctx.timed_record(
		"character.flags.registry_coerces_types",
		get_category(),
		deaths_ok and story_ok,
		"registered flags coerce to declared types",
		start,
		"CHS-06"
	)

	start = Time.get_ticks_msec()
	CharacterService.reset_to_defaults()
	CharacterService.set_flag("deaths", Callable())
	var reject_ok := int(CharacterService.get_flag("deaths")) == 0
	ctx.timed_record(
		"character.flags.rejects_unserialisable",
		get_category(),
		reject_ok,
		"unserialisable flag values fall back to default",
		start,
		"CHS-06"
	)

	start = Time.get_ticks_msec()
	CharacterService.reset_to_defaults()
	var tier_default := int(CharacterService.get_flag("dungeon_max_tier"))
	ctx.timed_record(
		"character.flags.default_from_registry",
		get_category(),
		tier_default == 1,
		"registry default for dungeon_max_tier is 1",
		start,
		"CHS-06"
	)

	start = Time.get_ticks_msec()
	CharacterService.reset_to_defaults()
	ProgressionService.from_save_dict({"level": 1, "xp": 0, "talents": {}})
	RunFlow._mark_dungeon_cleared("forgotten_castle")
	var LoadoutUIScript := preload("res://scripts/ui/loadout_ui.gd")
	var loadout := LoadoutUIScript.new()
	var unlocked := loadout._is_weapon_unlocked("guard_spear")
	loadout.free()
	ctx.timed_record(
		"character.flags.clear_flag_set_on_escape",
		get_category(),
		CharacterService.is_flag_truthy("theme_forgotten_castle_cleared") and unlocked,
		"forgotten_castle clear unlocks guard_spear at level 1",
		start,
		"CHS-02"
	)
	CharacterService.reset_to_defaults()


func _test_character_signals() -> void:
	var start := Time.get_ticks_msec()
	CharacterService.reset_to_defaults()
	var counts := {
		"gold": 0,
		"coins": 0,
		"level": 0,
		"flags": 0,
		"quests": 0,
	}
	var on_gold := func(_a: int) -> void: counts["gold"] += 1
	var on_coins := func(_a: int) -> void: counts["coins"] += 1
	var on_level := func(_a: int) -> void: counts["level"] += 1
	var on_flags := func() -> void: counts["flags"] += 1
	var on_quests := func() -> void: counts["quests"] += 1
	CharacterService.gold_changed.connect(on_gold)
	CharacterService.coins_changed.connect(on_coins)
	CharacterService.level_changed.connect(on_level)
	CharacterService.flags_changed.connect(on_flags)
	CharacterService.quests_changed.connect(on_quests)
	CharacterService.from_save_dict(
		{
			"gold": 50,
			"flags": {"heard_castle_lore": true},
			"quests": {"states": {"kill_grunts": "active"}, "progress": {}},
		}
	)
	var load_ok: bool = (
		counts["gold"] == 1
		and counts["coins"] == 1
		and counts["level"] == 1
		and counts["flags"] == 1
		and counts["quests"] == 1
	)
	CharacterService.gold_changed.disconnect(on_gold)
	CharacterService.coins_changed.disconnect(on_coins)
	CharacterService.level_changed.disconnect(on_level)
	CharacterService.flags_changed.disconnect(on_flags)
	CharacterService.quests_changed.disconnect(on_quests)
	ctx.timed_record(
		"character.signals.emitted_on_load",
		get_category(),
		load_ok,
		"from_save_dict emits all character signals once",
		start,
		"CHS-03"
	)

	start = Time.get_ticks_msec()
	counts = {"gold": 0, "coins": 0, "level": 0, "flags": 0, "quests": 0}
	CharacterService.gold_changed.connect(on_gold)
	CharacterService.coins_changed.connect(on_coins)
	CharacterService.level_changed.connect(on_level)
	CharacterService.flags_changed.connect(on_flags)
	CharacterService.quests_changed.connect(on_quests)
	CharacterService.reset_to_defaults()
	var reset_ok: bool = (
		counts["gold"] == 1
		and counts["coins"] == 1
		and counts["level"] == 1
		and counts["flags"] == 1
		and counts["quests"] == 1
	)
	CharacterService.gold_changed.disconnect(on_gold)
	CharacterService.coins_changed.disconnect(on_coins)
	CharacterService.level_changed.disconnect(on_level)
	CharacterService.flags_changed.disconnect(on_flags)
	CharacterService.quests_changed.disconnect(on_quests)
	ctx.timed_record(
		"character.signals.emitted_on_reset",
		get_category(),
		reset_ok,
		"reset_to_defaults emits all character signals once",
		start,
		"CHS-03"
	)


func _test_character_save_round_trip() -> void:
	var start := Time.get_ticks_msec()
	CharacterService.reset_to_defaults()
	CharacterService.set_flag("runs_started", 2)
	CharacterService.set_quest_state("fetch_scrap", "active")
	CharacterService.set_quest_progress("fetch_scrap", {"count": 1})
	var before := CharacterService.to_save_dict()
	CharacterService.from_save_dict(before)
	var after := CharacterService.to_save_dict()
	var ok: bool = (
		after.get("gold", -1) == before.get("gold", -2)
		and str(after.get("classId", "")) == str(before.get("classId", "x"))
		and after.get("flags", {}) == before.get("flags", {})
		and after.get("quests", {}) == before.get("quests", {})
	)
	ctx.timed_record(
		"character.save.round_trip_via_to_save_dict",
		get_category(),
		ok,
		"to_save_dict/from_save_dict is a fixed point",
		start,
		"CHS-05"
	)
	CharacterService.reset_to_defaults()


func _test_character_currency() -> void:
	var start := Time.get_ticks_msec()
	CharacterService.reset_to_defaults()
	var gold_before := CharacterService.gold
	var coins_before := CharacterService.get_coins()
	var gold_hits := 0
	var coin_hits := 0
	var on_gold := func(_a: int) -> void: gold_hits += 1
	var on_coins := func(_a: int) -> void: coin_hits += 1
	CharacterService.gold_changed.connect(on_gold)
	CharacterService.coins_changed.connect(on_coins)
	CharacterService.add_coins(10)
	var alias_ok := (
		CharacterService.gold == gold_before + 10
		and CharacterService.get_coins() == coins_before + 10
		and gold_hits == 1
		and coin_hits == 1
	)
	CharacterService.gold_changed.disconnect(on_gold)
	CharacterService.coins_changed.disconnect(on_coins)
	ctx.timed_record(
		"character.currency.coins_alias_tracks_gold",
		get_category(),
		alias_ok,
		"coins alias tracks gold and emits both signals",
		start,
		"CHS-08"
	)
	CharacterService.reset_to_defaults()


func _test_talent_xp_gain_applies() -> void:
	var start := Time.get_ticks_msec()
	_unlock_aptitude_through("apt_4")
	var result := ProgressionService.grant_xp(100, "validation")
	var gained: int = int(result.get("gained", 0))
	_reset_progression()
	ctx.timed_record(
		"prog.talent.xp_gain_applies",
		get_category(),
		gained > 100,
		"apt_4 xpGain multiplies grant_xp above raw amount",
		start,
		"PRG-02"
	)


func _test_talent_loot_quality_shifts_weights() -> void:
	var start := Time.get_ticks_msec()
	var baseline: Dictionary = AffixRoller.rarity_weights("", 0.0)
	var boosted: Dictionary = AffixRoller.rarity_weights("", 0.02)
	var rare_base: int = int(baseline.get("rare", 0)) + int(baseline.get("epic", 0))
	var rare_boost: int = int(boosted.get("rare", 0)) + int(boosted.get("epic", 0))
	ctx.timed_record(
		"prog.talent.loot_quality_shifts_weights",
		get_category(),
		rare_boost > rare_base,
		"lootQuality bonus increases rare+ rarity weights",
		start,
		"PRG-02"
	)


func _test_talent_gold_find_applies() -> void:
	var start := Time.get_ticks_msec()
	_unlock_aptitude_through("apt_5")
	CharacterService.reset_to_defaults()
	var before_gold := CharacterService.gold
	CharacterService.add_gold(100)
	var delta := CharacterService.gold - before_gold
	_reset_progression()
	CharacterService.reset_to_defaults()
	ctx.timed_record(
		"prog.talent.gold_find_applies",
		get_category(),
		delta > 100,
		"apt_5 goldFind multiplies add_gold above raw amount",
		start,
		"PRG-02"
	)


func _test_talent_cooldown_reduction_applies() -> void:
	var start := Time.get_ticks_msec()
	var weapon := WeaponControllerScript.new()
	weapon.set_combat_stat_modifiers({}, {"cooldownReduction": 0.05}, {})
	weapon.load_weapon_from_path("content/weapons/sword_basic.json")
	var scaled := weapon.get_weapon_art_cooldown_duration()
	weapon.free()
	ctx.timed_record(
		"prog.talent.cooldown_reduction_applies",
		get_category(),
		scaled > 0.0 and scaled < 5.0,
		"cooldownReduction shortens weapon art cooldown duration",
		start,
		"PRG-02"
	)


func _test_talent_each_node_has_consumer() -> void:
	var start := Time.get_ticks_msec()
	var applicators := {
		"physicalDamage": "res://scripts/combat/combat_stat_modifiers.gd",
		"staminaCostReduction": "res://scripts/combat/combat_stat_modifiers.gd",
		"critChance": "res://scripts/combat/combat_stat_modifiers.gd",
		"poiseDamage": "res://scripts/combat/combat_stat_modifiers.gd",
		"maxHealth": "res://scripts/inventory/inventory_service.gd",
		"armor": "res://scripts/combat/combat_stat_modifiers.gd",
		"blockReduction": "res://scripts/combat/guard.gd",
		"poise": "res://scripts/combat/combat_stat_modifiers.gd",
		"damageReduction": "res://scripts/combat/combat_stat_modifiers.gd",
		"staminaRegen": "res://scripts/combat/combat_stat_modifiers.gd",
		"moveSpeed": "res://scripts/combat/combat_stat_modifiers.gd",
		"lootQuality": "res://scripts/loot/affix_roller.gd",
		"xpGain": "res://scripts/progression/progression_service.gd",
		"goldFind": "res://scripts/save/character_service.gd",
		"cooldownReduction": "res://scripts/combat/weapon_controller.gd",
	}
	var ok := true
	for stat in applicators:
		if not ctx.file_contains(applicators[stat], stat):
			ok = false
			break
	ctx.timed_record(
		"prog.talent.each_node_has_consumer",
		get_category(),
		ok,
		"every talent stat key has a runtime applicator",
		start,
		"PRG-02"
	)


func _test_abandon_xp_fraction() -> void:
	var start := Time.get_ticks_msec()
	var curve: Dictionary = ContentLoader.load_json("content/progression/xp_curve.json")
	var fraction: float = float(curve.get("abandonedXpFraction", 0.0))
	var full_xp := 200
	var abandon_xp := ProgressionService.apply_abandon_xp_fraction(full_xp)
	var ok := abandon_xp == int(full_xp * fraction)
	ok = ok and ctx.file_contains("res://scripts/app/run_flow.gd", "apply_abandon_xp_fraction")
	ctx.timed_record(
		"prog.abandon_xp_fraction",
		get_category(),
		ok,
		"abandon XP uses abandonedXpFraction from curve",
		start,
		"PRG-04"
	)


func _test_xp_granted_reason_hook() -> void:
	var start := Time.get_ticks_msec()
	_reset_progression()
	CharacterService.reset_to_defaults()
	ProgressionService.grant_xp(50, "validation_reason")
	var tracked := int(CharacterService.get_flag("xp_granted_validation_reason", 0))
	_reset_progression()
	CharacterService.reset_to_defaults()
	ctx.timed_record(
		"prog.xp_granted_reason_hook",
		get_category(),
		tracked == 50,
		"grant_xp reason forwards to achievement analytics flag",
		start,
		"PRG-05"
	)


func _unlock_aptitude_through(node_id: String) -> void:
	var chain := ["apt_1", "apt_2", "apt_3", "apt_4", "apt_5", "apt_6"]
	ProgressionService.from_save_dict(
		{"level": 20, "xp": 10000, "talents": {}, "talentPointsSpent": 0}
	)
	for id in chain:
		ProgressionService.unlock_talent(id)
		if id == node_id:
			return


func _reset_progression() -> void:
	ProgressionService.from_save_dict(
		{"level": 1, "xp": 0, "talents": {}, "talentPointsSpent": 0}
	)


func _read_content_json(relative_path: String) -> String:
	var full := ProjectSettings.globalize_path("res://").path_join("../../..").path_join(
		relative_path
	)
	if not FileAccess.file_exists(full):
		return ""
	return FileAccess.get_file_as_string(full)
