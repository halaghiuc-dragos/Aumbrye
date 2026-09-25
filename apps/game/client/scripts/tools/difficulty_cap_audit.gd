extends Node

const CastleTierDifficultyScript := preload("res://scripts/dungeon/castle_tier_difficulty.gd")
const WavesDifficultyScript := preload("res://scripts/dungeon/waves_difficulty.gd")
const DifficultyProfileScript := preload("res://scripts/dungeon/difficulty_profile.gd")
const RunModifierServiceScript := preload("res://scripts/dungeon/run_modifier_service.gd")
const WavesRunServiceScript := preload("res://scripts/dungeon/waves_run_service.gd")

const CASTLE_HP_CAP := 4.0
const CASTLE_DAMAGE_CAP := 2.6
const WAVES_HP_CAP := 4.5
const WAVES_DAMAGE_CAP := 3.0

var _failures := 0


func _ready() -> void:
	RunModifierServiceScript.clear()
	var dungeon_id := "forgotten_castle"
	var tier := DungeonCatalog.max_difficulty_tier(dungeon_id)
	var castle := DifficultyProfileScript.for_run("castle", dungeon_id, tier)
	_check(castle.hp_multiplier(1000) <= CASTLE_HP_CAP, "unmodified castle health respects its combined cap")
	_check(castle.damage_multiplier(1000) <= CASTLE_DAMAGE_CAP, "unmodified castle damage respects its combined cap")

	RunModifierServiceScript.set_modifiers([RunModifierServiceScript.MODIFIER_ARMOURED_FOES])
	castle = DifficultyProfileScript.for_run("castle", dungeon_id, tier)
	_check(castle.hp_multiplier(1000) <= CASTLE_HP_CAP, "armoured run factor is included inside castle HP cap")
	_check(castle.damage_multiplier(1000) <= CASTLE_DAMAGE_CAP, "armoured run factor is included inside castle damage cap")
	var waves := DifficultyProfileScript.for_run("waves")
	_check(waves.hp_multiplier(50) <= WAVES_HP_CAP, "armoured run factor cannot exceed waves HP cap")
	_check(waves.damage_multiplier(50) <= WAVES_DAMAGE_CAP, "armoured run factor cannot exceed waves damage cap")
	RunModifierServiceScript.set_modifiers([RunModifierServiceScript.MODIFIER_VOLATILE_FOES])
	castle = DifficultyProfileScript.for_run("castle", dungeon_id, tier)
	_check(castle.hp_multiplier(1000) <= CASTLE_HP_CAP, "volatile run factor remains within castle HP cap")
	_check(castle.damage_multiplier(1000) <= CASTLE_DAMAGE_CAP, "volatile run factor is included inside castle damage cap")
	waves = DifficultyProfileScript.for_run("waves")
	_check(waves.hp_multiplier(50) <= WAVES_HP_CAP, "volatile run factor cannot exceed waves HP cap")
	_check(waves.damage_multiplier(50) <= WAVES_DAMAGE_CAP, "volatile run factor cannot exceed waves damage cap")
	RunModifierServiceScript.set_modifiers([
		RunModifierServiceScript.MODIFIER_ARMOURED_FOES,
		RunModifierServiceScript.MODIFIER_VOLATILE_FOES,
	])
	castle = DifficultyProfileScript.for_run("castle", dungeon_id, tier)
	_check(castle.hp_multiplier(1000) <= CASTLE_HP_CAP, "combined modifiers remain inside castle HP cap")
	_check(castle.damage_multiplier(1000) <= CASTLE_DAMAGE_CAP, "combined modifiers remain inside castle damage cap")
	waves = DifficultyProfileScript.for_run("waves")
	for wave in [1, 10, 35, 40, 45, 50]:
		_check(waves.hp_multiplier(wave) <= WAVES_HP_CAP, "wave %d combined modifiers remain inside HP cap" % wave)
		_check(waves.damage_multiplier(wave) <= WAVES_DAMAGE_CAP, "wave %d combined modifiers remain inside damage cap" % wave)

	RunModifierServiceScript.clear()
	_audit_wave_export_parity()

	print("DIFFICULTY CAP RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)


func _audit_wave_export_parity() -> void:
	var service = WavesRunServiceScript.new()
	service._load_definition()
	for wave in range(1, 51):
		var row := _exported_wave_row(wave)
		_check(service._enemy_count_for_wave(wave) == int(row.get("baseEnemyCount", -1)), "wave %d exported base enemy count matches runtime" % wave)
		var unlocked_bands: Array = service._definition.get("roster_unlocks", []).filter(
			func(entry: Dictionary) -> bool: return wave >= int(entry.get("wave", 0))
		)
		var expected_roster: Array = []
		if unlocked_bands.size() >= 3:
			var active_bands: Array = unlocked_bands.slice(maxi(0, unlocked_bands.size() - 3))
			for band in active_bands:
				for enemy_id in band.get("ids", []): expected_roster.append(str(enemy_id))
		var roster: Array = row.get("activeRosterIds", [])
		var exported_expected_roster: Array = [] if unlocked_bands.size() < 3 else expected_roster
		_check(roster.size() == exported_expected_roster.size(), "wave %d exported active roster size matches authored rules" % wave)
		for enemy_id in exported_expected_roster:
			_check(str(enemy_id) in roster, "wave %d exported active roster contains %s" % [wave, str(enemy_id)])
		var expected_spawn_pool: Array = expected_roster.duplicate()
		if unlocked_bands.size() < 3 or expected_spawn_pool.is_empty():
			expected_spawn_pool = service._definition.get("base_roster", []).duplicate()
		var runtime_bosses: Array = service._bosses_for_wave(wave) if service.is_boss_wave(wave) else []
		if service.is_boss_wave(wave):
			for boss_id in runtime_bosses:
				if str(boss_id) not in expected_spawn_pool:
					expected_spawn_pool.append(str(boss_id))
		var exported_spawn_pool: Array = row.get("spawnPoolIds", [])
		_check(exported_spawn_pool.size() == expected_spawn_pool.size(), "wave %d exported spawn pool size matches runtime rules" % wave)
		for enemy_id in expected_spawn_pool:
			_check(str(enemy_id) in exported_spawn_pool, "wave %d exported spawn pool contains %s" % [wave, str(enemy_id)])
		var boss_value: Variant = row.get("boss")
		if runtime_bosses.is_empty():
			_check(boss_value == null, "wave %d has no runtime boss pool" % wave)
		else:
			var boss_pool: Array = (boss_value as Dictionary).get("eligiblePool", []) if boss_value is Dictionary else []
			_check(boss_pool.size() == runtime_bosses.size(), "wave %d exported boss pool size matches runtime" % wave)
			for boss_id in runtime_bosses:
				_check(str(boss_id) in boss_pool, "wave %d runtime boss pool contains %s" % [wave, str(boss_id)])
	service.free()


func _exported_wave_row(wave: int) -> Dictionary:
	var report_path := ProjectSettings.globalize_path("res://../../../reports/balance_export.json")
	var file := FileAccess.open(report_path, FileAccess.READ)
	if file == null:
		_check(false, "balance export is available for runtime parity audit")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_check(false, "balance export parses as a dictionary")
		return {}
	var curves: Variant = (parsed as Dictionary).get("difficultyCurves")
	if not curves is Dictionary:
		_check(false, "balance export includes difficulty curves")
		return {}
	var waves_data: Variant = (curves as Dictionary).get("waves")
	if not waves_data is Dictionary:
		_check(false, "balance export includes waves composition")
		return {}
	var rows: Variant = (waves_data as Dictionary).get("sampledCurve")
	if not rows is Array:
		_check(false, "balance export includes sampled wave rows")
		return {}
	for candidate in rows:
		if candidate is Dictionary and int((candidate as Dictionary).get("wave", -1)) == wave:
			return candidate
	_check(false, "balance export contains wave %d" % wave)
	return {}
