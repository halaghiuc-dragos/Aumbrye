extends Node

## Checks the item condition roll: that every equipment type gets a tier, that the ladder is
## honest about what it does to an item's numbers, and that the distribution is centred.
##
## Run: godot --path apps/game/client --headless res://scenes/debug/item_quality_audit.tscn

const ItemQualityScript := preload("res://scripts/items/item_quality.gd")
const SAMPLES := 20000

var _failures: int = 0


func _ready() -> void:
	await get_tree().process_frame
	_audit_ladders()
	_audit_distribution()
	_audit_stat_application()
	print("QUALITY AUDIT RESULT %d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL %s" % message)


func _audit_ladders() -> void:
	for item_type in ["weapon", "armor", "accessory"]:
		var ladder := ItemQualityScript.ladder_for(item_type)
		if ladder.size() != 5:
			_fail("%s ladder has %d rungs, expected 5" % [item_type, ladder.size()])
			continue
		var multipliers: PackedFloat32Array = []
		for quality_id in ladder:
			if not ItemQualityScript.exists(str(quality_id)):
				_fail("%s ladder names unknown tier '%s'" % [item_type, quality_id])
			multipliers.append(ItemQualityScript.stat_multiplier(str(quality_id)))
		# Worst to best, and the top rung is the +20% the design promises.
		for i in range(1, multipliers.size()):
			if multipliers[i] <= multipliers[i - 1]:
				_fail("%s ladder is not strictly ascending at rung %d" % [item_type, i])
		if not is_equal_approx(multipliers[multipliers.size() - 1], 1.2):
			_fail("%s best tier is %.2fx, expected 1.20x" % [item_type, multipliers[-1]])
		if not is_equal_approx(multipliers[ItemQualityScript.NEUTRAL_INDEX], 1.0):
			_fail("%s middle tier is not neutral" % item_type)
		print(
			"LADDER %-10s %s"
			% [item_type, ", ".join(_describe(ladder))]
		)
	for item_type in ["consumable", "material", "key"]:
		if ItemQualityScript.applies_to(item_type):
			_fail("'%s' has no base stats but is rolled a condition" % item_type)


func _describe(ladder: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for quality_id in ladder:
		out.append(
			"%s %+d%%"
			% [
				ItemQualityScript.display_name(str(quality_id)),
				roundi((ItemQualityScript.stat_multiplier(str(quality_id)) - 1.0) * 100.0),
			]
		)
	return out


## The point of a symmetric ladder is that loot is not quietly inflated or quietly nerfed. At
## common rarity the average item should come out of the roll worth exactly what it says it is.
func _audit_distribution() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for rarity in ["common", "rare", "legendary", "aumbral"]:
		var total := 0.0
		var counts: Dictionary = {}
		for _i in SAMPLES:
			var quality: String = ItemQualityScript.roll("weapon", rarity, rng)
			total += ItemQualityScript.stat_multiplier(quality)
			counts[quality] = int(counts.get(quality, 0)) + 1
		var mean := total / float(SAMPLES)
		print("DISTRIBUTION %-10s mean %.3fx  %s" % [rarity, mean, counts])
		if rarity == "common" and absf(mean - 1.0) > 0.01:
			_fail("common drops average %.3fx, expected neutral" % mean)
		if rarity == "aumbral" and mean <= 1.0:
			_fail("aumbral drops average %.3fx, expected better than neutral" % mean)
		# The condition has to stay a live axis at every rarity. If the top rung swallows a rarity
		# the word stops telling the player anything about the drop in front of them.
		var top: String = str(ItemQualityScript.ladder_for("weapon")[4])
		if float(counts.get(top, 0)) / float(SAMPLES) > 0.45:
			_fail(
				"%s drops are %.0f%% top-condition; the axis is dead there"
				% [rarity, 100.0 * float(counts.get(top, 0)) / float(SAMPLES)]
			)


## The multiplier has to actually reach the equipped stats, not just the item's name.
func _audit_stat_application() -> void:
	var item_id := "castle_sword"
	var def := ItemCatalog.get_definition(item_id)
	if def.is_empty():
		_fail("no definition for %s" % item_id)
		return
	var resolver := Callable(AffixRoller, "get_affix_stat")
	var base := Equipment.slot_stats({"itemId": item_id}, resolver)
	for quality_id in ItemQualityScript.ladder_for("weapon"):
		var scaled := Equipment.slot_stats(
			{"itemId": item_id, "quality": str(quality_id)}, resolver
		)
		var want := ItemQualityScript.stat_multiplier(str(quality_id))
		for stat in base:
			var base_value := float(base[stat])
			if is_zero_approx(base_value):
				continue
			var got := float(scaled.get(stat, 0.0)) / base_value
			if not is_equal_approx(got, want):
				_fail(
					"%s %s scaled %.3fx, expected %.3fx"
					% [quality_id, stat, got, want]
				)
	print("STAT APPLICATION %s scales with every rung" % item_id)
