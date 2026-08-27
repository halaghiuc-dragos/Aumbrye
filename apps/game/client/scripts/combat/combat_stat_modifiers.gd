extends RefCounted
class_name CombatStatModifiers


static func stack_bonus(stat: String) -> float:
	if not CombatEvents:
		return 0.0
	return CombatEvents.get_stat_bonus(stat)


static func damage_multiplier(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	var mult := 1.0 + float(equipment_stats.get("damagePercent", 0.0)) / 100.0
	mult += float(equipment_stats.get("physicalDamage", 0.0))
	mult += float(talent_stats.get("physicalDamage", 0.0))
	mult += stack_bonus("damagePercent") / 100.0
	mult += stack_bonus("physicalDamage")
	return maxf(0.1, mult)


static func weapon_scaling_multiplier(weapon_scaling: Dictionary, class_stats: Dictionary) -> float:
	if weapon_scaling.is_empty():
		return 1.0
	var mult := 1.0
	for stat in weapon_scaling:
		var coeff: float = float(weapon_scaling[stat])
		var value: float = float(class_stats.get(stat, 0.0))
		mult += value * coeff
	return maxf(0.1, mult)


static func flat_damage_bonus(equipment_stats: Dictionary) -> float:
	return float(equipment_stats.get("bonusDamage", 0.0))


static func poise_damage_multiplier(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	var mult := 1.0 + float(equipment_stats.get("poiseDamage", 0.0))
	mult += float(talent_stats.get("poiseDamage", 0.0))
	return maxf(0.1, mult)


static func stamina_cost_multiplier(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	var reduction := float(equipment_stats.get("staminaCostReduction", 0.0))
	reduction += float(talent_stats.get("staminaCostReduction", 0.0))
	return maxf(0.1, 1.0 - reduction)


static func crit_chance(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	var chance := float(equipment_stats.get("critChance", 0.0))
	chance += float(talent_stats.get("critChance", 0.0))
	return clampf(chance, 0.0, 1.0)


static func crit_multiplier(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	return (
		1.5
		+ float(equipment_stats.get("critDamage", 0.0))
		+ float(talent_stats.get("critDamage", 0.0))
	)


static func max_mana_bonus(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	return float(equipment_stats.get("manaMax", 0.0)) + float(talent_stats.get("manaMax", 0.0))


static func mana_regen_multiplier(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	var mult := 1.0 + float(equipment_stats.get("manaRegen", 0.0))
	mult += float(talent_stats.get("manaRegen", 0.0))
	return maxf(0.1, mult)


static func block_reduction_bonus(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	return (
		float(equipment_stats.get("blockReduction", 0.0))
		+ float(talent_stats.get("blockReduction", 0.0))
		+ stack_bonus("blockReduction")
	)


static func max_stamina_bonus(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	return float(equipment_stats.get("staminaMax", 0.0)) + float(talent_stats.get("staminaMax", 0.0))


static func stamina_regen_multiplier(
	equipment_stats: Dictionary, talent_stats: Dictionary
) -> float:
	var mult := 1.0 + float(equipment_stats.get("staminaRegen", 0.0))
	mult += float(talent_stats.get("staminaRegen", 0.0))
	return maxf(0.1, mult)


static func max_poise_bonus(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	return float(equipment_stats.get("poise", 0.0)) + float(talent_stats.get("poise", 0.0))


static func move_speed_multiplier(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	var mult := 1.0 + float(equipment_stats.get("moveSpeedPercent", 0.0)) / 100.0
	mult += float(equipment_stats.get("moveSpeed", 0.0))
	mult += float(talent_stats.get("moveSpeed", 0.0))
	return maxf(0.1, mult)


static func defense_points(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	return (
		float(equipment_stats.get("defense", 0.0))
		+ float(equipment_stats.get("armor", 0.0))
		+ float(talent_stats.get("armor", 0.0))
		+ stack_bonus("defense")
		+ stack_bonus("armor")
	)


static func damage_reduction(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	return (
		float(equipment_stats.get("damageReduction", 0.0))
		+ float(talent_stats.get("damageReduction", 0.0))
	)
