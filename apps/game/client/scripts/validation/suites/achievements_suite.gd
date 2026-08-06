extends "res://scripts/validation/validation_suite.gd"

const SteamServiceScript := preload("res://scripts/platform/steam_service.gd")
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")


func get_category() -> String:
	return "achievements"


func run() -> void:
	_test_catalog_every_id_has_hook()
	_test_unlock_first_blood()
	_test_unlock_aumbral_loot()
	await _test_steam_sync_on_load()


func _test_catalog_every_id_has_hook() -> void:
	var start := Time.get_ticks_msec()
	var ok := false
	var message := "AchievementService missing"
	if AchievementService:
		var result: Dictionary = AchievementService.validate_catalog_coverage()
		ok = bool(result.get("ok", false))
		var missing: PackedStringArray = result.get("missing", PackedStringArray())
		message = (
			"every catalog id has notify hook or manualUnlock entry"
			if ok
			else "missing hooks: %s" % ", ".join(missing)
		)
	ctx.timed_record(
		"ach.catalog.every_id_has_hook",
		get_category(),
		ok,
		message,
		start,
		"ACH-01"
	)
	start = Time.get_ticks_msec()
	var catalog: Dictionary = ContentLoader.load_json("content/achievements/catalog.json")
	var has_mythic := false
	for entry in catalog.get("achievements", []):
		if entry is Dictionary and str(entry.get("id", "")) == "mythic_loot":
			has_mythic = true
			break
	ctx.timed_record(
		"ach.catalog.no_mythic_loot",
		get_category(),
		not has_mythic,
		"mythic_loot absent from catalog (renamed to aumbral_loot)",
		start,
		"ACH-02"
	)


func _test_unlock_first_blood() -> void:
	var start := Time.get_ticks_msec()
	var ok := false
	if AchievementService:
		var before := AchievementService.is_unlocked("first_blood")
		AchievementService.notify("enemy_killed")
		ok = AchievementService.is_unlocked("first_blood")
		if not before:
			# Leave unlocked for other tests; counter already incremented.
			pass
	ctx.timed_record(
		"ach.unlock.first_blood",
		get_category(),
		ok,
		"enemy_killed notify unlocks first_blood",
		start,
		"ACH-01"
	)


func _test_unlock_aumbral_loot() -> void:
	var start := Time.get_ticks_msec()
	var ok := false
	if AchievementService:
		AchievementService.notify(
			"item_obtained", {"rarity": RarityRegistryScript.normalize("aumbral")}
		)
		ok = AchievementService.is_unlocked("aumbral_loot")
	ctx.timed_record(
		"ach.unlock.aumbral_loot",
		get_category(),
		ok,
		"item_obtained aumbral rarity unlocks aumbral_loot",
		start,
		"ACH-02"
	)


func _test_steam_sync_on_load() -> void:
	var start := Time.get_ticks_msec()
	var ok := false
	if AchievementService:
		AchievementService.unlock("boss_slayer")
		var steam := SteamServiceScript.new()
		ctx.owner.add_child(steam)
		await ctx.owner.get_tree().process_frame
		var synced: Dictionary = steam.sync_achievements(AchievementService.get_unlocked_ids())
		ok = steam.is_stub_mode and int(synced.get("synced", -1)) == 0
		steam.queue_free()
	ctx.timed_record(
		"ach.steam.sync_on_load",
		get_category(),
		ok,
		"sync_achievements callable with seeded unlock ids",
		start,
		"ACH-03"
	)
