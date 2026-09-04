extends Node

## Checks that the stats gear advertises actually reach combat, and that the caps hold.
##
## Four stats -- attackSpeed, healthRegen, evasion, and cooldownReduction from gear -- were
## authored on items, priced by the merchant and shown in tooltips while nothing read them. A stat
## that does nothing is worse than a missing one: it makes the player's build decisions fiction and
## it silently unbalances every item carrying it. This is the check that they stay wired.
##
## Run: godot --path apps/game/client --headless res://scenes/debug/combat_stats_audit.tscn

const Mods := preload("res://scripts/combat/combat_stat_modifiers.gd")

## Enough rolls to see the tail of the affix distribution without the debug-build schema validator
## making the scene take a minute.
const ROLL_SAMPLES := 600

var _failures: int = 0


## SY-09: per PH-01's authored bands -- light 1.2-1.8, heavy 3.0-4.5 (greatsword's 5.5 is the one
## named exception), enemy attacks 2.0-3.5 on the player. Bow and staff are ranged/caster weapons
## the plan never bands, so they get a looser sanity check instead of the melee target.
const KNOCKBACK_RANGED_ARCHETYPES := ["bow", "staff"]
const KNOCKBACK_LIGHT_MIN := 1.0
const KNOCKBACK_LIGHT_MAX := 2.0
const KNOCKBACK_HEAVY_MIN := 2.8
const KNOCKBACK_HEAVY_MAX := 4.7
const KNOCKBACK_HEAVY_EXEMPT := {"greatsword": 5.6}
const KNOCKBACK_RANGED_MAX := 3.0
const KNOCKBACK_ENEMY_MIN := 2.0
const KNOCKBACK_ENEMY_MAX := 3.5


func _ready() -> void:
	await get_tree().process_frame
	_audit_live_stats()
	_audit_attack_speed()
	_audit_flat_damage_cap()
	_audit_affix_group_cap()
	_audit_knockback_bands()
	print("COMBAT STATS RESULT %d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL %s" % message)


## Every stat the content tree authors has to be summed by Equipment and read by something.
func _audit_live_stats() -> void:
	var authored := _authored_stat_keys()
	for stat in authored:
		if not Equipment.STAT_KEYS.has(stat) and not Equipment.FLAT_DAMAGE_STAT_KEYS.has(stat):
			_fail("'%s' is authored on items but Equipment never sums it" % stat)
	print("LIVE STATS %d authored, all summed" % authored.size())

	# Each of the four reads a non-zero value out of a stat block that carries it.
	var block := {
		"attackSpeed": 0.2,
		"healthRegen": 3.0,
		"evasion": 40.0,
		"cooldownReduction": 0.25,
	}
	var checks := {
		"attackSpeed": Mods.attack_speed_bonus(block, {}),
		"healthRegen": Mods.health_regen(block, {}),
		"evasion": Mods.evasion_chance(block, {}),
		"cooldownReduction": Mods.cooldown_reduction(block, {}),
	}
	for stat in checks:
		if is_zero_approx(float(checks[stat])):
			_fail("'%s' is on the item but reads back as zero" % stat)
		else:
			print("  %-20s -> %.3f" % [stat, float(checks[stat])])

	# And each is bounded, so no stack of gear can take it somewhere absurd.
	var huge := {"attackSpeed": 99.0, "evasion": 9999.0, "cooldownReduction": 99.0}
	if Mods.attack_speed_bonus(huge, {}) > Mods.ATTACK_SPEED_CAP:
		_fail("attackSpeed is not capped")
	if Mods.evasion_chance(huge, {}) > Mods.EVASION_CAP:
		_fail("evasion is not capped")
	if Mods.cooldown_reduction(huge, {}) > 0.6:
		_fail("cooldownReduction is not capped")


func _authored_stat_keys() -> PackedStringArray:
	var keys: Dictionary = {}
	for item_type in ["weapon", "armor", "accessory", "consumable", "material"]:
		for item_id in ItemCatalog.get_items_by_type(item_type):
			var stats: Variant = ItemCatalog.get_definition(item_id).get("stats", {})
			if stats is Dictionary:
				for key in (stats as Dictionary):
					keys[str(key)] = true
	var out := PackedStringArray(keys.keys())
	out.sort()
	return out


## Attack speed has to shorten the swing, and the shortening has to reach every phase -- the
## animation, the hitbox window and the cancel point all read their timings from the same place.
func _audit_attack_speed() -> void:
	var attack := {"startup": 0.20, "active": 0.10, "recovery": 0.30, "damage": 12.0}
	var scale := Mods.attack_phase_scale({"attackSpeed": 0.25}, {})
	if scale >= 1.0:
		_fail("attack speed does not shorten the swing (scale %.3f)" % scale)
		return
	var before := (
		float(attack["startup"]) + float(attack["active"]) + float(attack["recovery"])
	)
	var after := before * scale
	print("ATTACK SPEED +25%% -> swing %.3fs becomes %.3fs (%.0f%% faster)"
		% [before, after, (before / after - 1.0) * 100.0])
	if not is_equal_approx(scale, 1.0 / 1.25):
		_fail("attack speed scale is %.4f, expected %.4f" % [scale, 1.0 / 1.25])


## Gear may amplify the weapon, not replace it.
func _audit_flat_damage_cap() -> void:
	var stats := {"bonusDamage": 500.0}
	for base: float in [7.0, 12.0, 34.0]:
		var bonus := Mods.flat_damage_bonus(stats, 1.0, base)
		var ratio: float = bonus / base
		if ratio > Mods.FLAT_DAMAGE_CAP_RATIO + 0.001:
			_fail("flat damage on a %.0f-damage attack reached %.1fx" % [base, ratio])
	print(
		"FLAT DAMAGE 500 gear bonus on a 12-damage swing -> +%.0f (capped at %.0fx)"
		% [Mods.flat_damage_bonus(stats, 1.0, 12.0), Mods.FLAT_DAMAGE_CAP_RATIO]
	)
	# It still scales with the weight of the swing, so a heavy is worth more than a jab.
	var light := Mods.flat_damage_bonus({"bonusDamage": 20.0}, 1.0, 100.0)
	var heavy := Mods.flat_damage_bonus({"bonusDamage": 20.0}, 2.5, 100.0)
	if heavy <= light:
		_fail("flat damage no longer scales with attack weight")


## An aumbral weapon could roll five different flat-damage prefixes at once, adding more damage
## than the weapon carried. The group cap is what stops that.
func _audit_affix_group_cap() -> void:
	var worst := 0
	var rng := RandomNumberGenerator.new()
	for seed_value in 4000:
		rng.seed = seed_value
		var rolled := AffixRoller.roll_instance("mythic_blade", seed_value, "aumbral")
		var flat := 0
		for affix in rolled.get("affixes", []):
			var stat := AffixRoller.get_affix_stat(str(affix.get("affixId", "")))
			if Equipment.FLAT_DAMAGE_STAT_KEYS.has(stat):
				flat += 1
		worst = maxi(worst, flat)
	print("AFFIX GROUP CAP worst of %d rolls carried %d flat-damage affixes" % [ROLL_SAMPLES, worst])
	if worst > 2:
		_fail("an aumbral weapon rolled %d flat-damage affixes; the cap is 2" % worst)


## PH-01: a greatsword and a dagger must not move a body by the same amount, and neither may drift
## outside the bands the plan set so a future weapon doesn't silently reintroduce "a hit is a flash
## and a number".
func _audit_knockback_bands() -> void:
	var weapon_checks := 0
	var weapon_dir := ContentLoader.content_root().path_join("content/weapons")
	var dir := DirAccess.open(weapon_dir)
	if dir == null:
		_fail("could not open content/weapons for the knockback audit")
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			weapon_checks += _check_weapon_knockback("content/weapons/%s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	var enemy_checks := 0
	for sub_dir in ["content/enemies", "content/bosses"]:
		var enemy_dir := ContentLoader.content_root().path_join(sub_dir)
		var enemy_dir_handle := DirAccess.open(enemy_dir)
		if enemy_dir_handle == null:
			continue
		enemy_dir_handle.list_dir_begin()
		var enemy_file := enemy_dir_handle.get_next()
		while enemy_file != "":
			if not enemy_dir_handle.current_is_dir() and enemy_file.ends_with(".json"):
				enemy_checks += _check_enemy_knockback("%s/%s" % [sub_dir, enemy_file])
			enemy_file = enemy_dir_handle.get_next()
		enemy_dir_handle.list_dir_end()
	print("KNOCKBACK %d weapon value(s), %d enemy value(s) checked against band" % [
		weapon_checks, enemy_checks
	])


func _check_weapon_knockback(relative_path: String) -> int:
	var data: Dictionary = ContentLoader.load_json(relative_path)
	if data.is_empty():
		return 0
	var archetype := str(data.get("archetype", ""))
	var owner_id := str(data.get("id", relative_path))
	var checked := 0
	var light_values: Array = []
	for entry in data.get("light_attacks", []):
		if (entry as Dictionary).has("knockback"):
			light_values.append(float(entry["knockback"]))
	var heavy_values: Array = []
	var entry: Variant = data.get("heavy_attack", {})
	if entry is Dictionary and (entry as Dictionary).has("knockback"):
		heavy_values.append(float((entry as Dictionary)["knockback"]))
	for h_entry in data.get("heavy_attacks", []):
		if (h_entry as Dictionary).has("knockback"):
			heavy_values.append(float(h_entry["knockback"]))
	# `art` and `plunge_attack` vary in weight by design (a quick special versus a slam) and the
	# plan only bands "light" and "heavy", so these get a loose sanity check instead of the strict
	# band -- wide enough to pass every authored weapon, tight enough to catch a stray typo.
	var special_values: Array = []
	for key in ["art", "plunge_attack"]:
		var special: Variant = data.get(key, {})
		if special is Dictionary and (special as Dictionary).has("knockback"):
			special_values.append(float((special as Dictionary)["knockback"]))
	var ranged := archetype in KNOCKBACK_RANGED_ARCHETYPES
	for value in light_values:
		checked += 1
		if ranged:
			if value < 0.0 or value > KNOCKBACK_RANGED_MAX:
				_fail("%s light knockback %.2f is outside the ranged sanity band" % [owner_id, value])
		elif value < KNOCKBACK_LIGHT_MIN or value > KNOCKBACK_LIGHT_MAX:
			_fail("%s light knockback %.2f is outside %.1f-%.1f" % [
				owner_id, value, KNOCKBACK_LIGHT_MIN, KNOCKBACK_LIGHT_MAX
			])
	var heavy_max: float = float(KNOCKBACK_HEAVY_EXEMPT.get(archetype, KNOCKBACK_HEAVY_MAX))
	for value in heavy_values:
		checked += 1
		if ranged:
			if value < 0.0 or value > KNOCKBACK_RANGED_MAX * 1.5:
				_fail("%s heavy knockback %.2f is outside the ranged sanity band" % [owner_id, value])
		elif value < KNOCKBACK_HEAVY_MIN or value > heavy_max:
			_fail("%s heavy knockback %.2f is outside %.1f-%.1f" % [
				owner_id, value, KNOCKBACK_HEAVY_MIN, heavy_max
			])
	for value in special_values:
		checked += 1
		if value < KNOCKBACK_LIGHT_MIN or value > heavy_max:
			_fail("%s special-attack knockback %.2f is outside %.1f-%.1f" % [
				owner_id, value, KNOCKBACK_LIGHT_MIN, heavy_max
			])
	return checked


func _check_enemy_knockback(relative_path: String) -> int:
	var data: Dictionary = ContentLoader.load_json(relative_path)
	if data.is_empty():
		return 0
	var owner_id := str(data.get("id", relative_path))
	var checked := 0
	for attack in data.get("attacks", []):
		checked += _check_enemy_attack_knockback(owner_id, attack)
	for phase in data.get("phases", []):
		for attack in phase.get("attacks", []):
			checked += _check_enemy_attack_knockback(owner_id, attack)
	return checked


func _check_enemy_attack_knockback(owner_id: String, attack: Dictionary) -> int:
	if not attack.has("knockback"):
		return 0
	var value := float(attack["knockback"])
	if value < KNOCKBACK_ENEMY_MIN or value > KNOCKBACK_ENEMY_MAX:
		_fail("%s/%s enemy knockback %.2f is outside %.1f-%.1f" % [
			owner_id, str(attack.get("id", "?")), value, KNOCKBACK_ENEMY_MIN, KNOCKBACK_ENEMY_MAX
		])
	var checked := 1
	for combo in attack.get("combo_followups", []):
		checked += _check_enemy_attack_knockback(owner_id, combo)
	return checked
