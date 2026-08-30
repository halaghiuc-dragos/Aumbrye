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


## Flat damage from gear: scaled to the weight of the swing, and bounded by the weapon.
##
## Two things were wrong with adding it whole to every hit.
##
## It ignored the swing. A light jab and a committed heavy took the same bonus, so once gear
## carried real flat damage the fastest attack in the game was strictly the best one and every slow
## weapon was a mistake.
##
## And it dwarfed the weapon. A legendary loadout reaches roughly 190 flat damage between the
## weapon's own stat line, an amulet, a ring, gloves and two rolled affixes -- against light
## attacks that deal 7 to 22. The weapon tables were about six per cent of the player's damage,
## which is why every weapon in the game felt the same in the hand: the player was not really
## swinging a dagger or a greatsword, they were swinging their gear.
##
## The cap fixes the second. Gear may add at most `FLAT_DAMAGE_CAP_RATIO` times the attack's own
## damage, so it amplifies the weapon instead of replacing it -- a fully geared player hits about
## three times as hard as a bare one, and it still matters which weapon they picked.
const FLAT_DAMAGE_CAP_RATIO := 2.0


static func flat_damage_bonus(
	equipment_stats: Dictionary, weight: float = 1.0, attack_damage: float = 0.0
) -> float:
	var bonus := float(equipment_stats.get("bonusDamage", 0.0)) * maxf(0.0, weight)
	if attack_damage > 0.0:
		bonus = minf(bonus, attack_damage * FLAT_DAMAGE_CAP_RATIO)
	return bonus


## An attack's weight: how hard it hits relative to the weapon's opening light swing. The opener is
## the reference because it is the one attack every weapon has and the one its numbers are written
## around.
static func attack_weight(attack: Dictionary, weapon_data: Dictionary) -> float:
	var opener := 0.0
	var lights: Variant = weapon_data.get("light_attacks", [])
	if lights is Array and not (lights as Array).is_empty():
		var first: Variant = (lights as Array)[0]
		if first is Dictionary:
			opener = float((first as Dictionary).get("damage", 0.0))
	if opener <= 0.0:
		return 1.0
	return float(attack.get("damage", opener)) / opener


static func poise_damage_multiplier(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	var mult := 1.0 + float(equipment_stats.get("poiseDamage", 0.0))
	mult += float(talent_stats.get("poiseDamage", 0.0))
	return maxf(0.1, mult)


static func stamina_cost_multiplier(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	var reduction := float(equipment_stats.get("staminaCostReduction", 0.0))
	reduction += float(talent_stats.get("staminaCostReduction", 0.0))
	return maxf(0.1, 1.0 - reduction)


## Read from gear as well as talents. The gear side was missing, so an item that promised faster
## arts delivered none.
static func cooldown_reduction(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	return clampf(
		float(equipment_stats.get("cooldownReduction", 0.0))
		+ float(talent_stats.get("cooldownReduction", 0.0)),
		0.0,
		0.6
	)


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

## How much faster the player swings. Items have carried `attackSpeed` since the first loot pass and
## nothing ever read it: six pieces of gear advertised it, the merchant priced it in, and it did
## nothing. It scales the startup, active and recovery of every attack, so it is the stat that
## decides how the weapon feels in the hand rather than how hard it lands.
##
## The cap is what keeps it a feel stat rather than a damage stat. Past a point, shortening the
## recovery stops making the weapon responsive and starts deleting the commitment that makes a
## swing a decision, so the whole combat model would go with it.
const ATTACK_SPEED_CAP := 0.45


static func attack_speed_bonus(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	var bonus := float(equipment_stats.get("attackSpeed", 0.0))
	bonus += float(talent_stats.get("attackSpeed", 0.0))
	bonus += stack_bonus("attackSpeed")
	return clampf(bonus, -ATTACK_SPEED_CAP, ATTACK_SPEED_CAP)


## The multiplier applied to each phase of an attack. Higher attack speed means a shorter phase, so
## this is the reciprocal of the bonus rather than the bonus itself.
static func attack_phase_scale(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	return 1.0 / (1.0 + attack_speed_bonus(equipment_stats, talent_stats))


## Health returned per second out of combat pressure. Authored on thirteen items and never applied.
static func health_regen(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	return maxf(
		0.0,
		float(equipment_stats.get("healthRegen", 0.0))
		+ float(talent_stats.get("healthRegen", 0.0))
		+ stack_bonus("healthRegen")
	)


## Chance to slip a hit entirely.
##
## Fourteen items and a talent branch have advertised evasion since launch with nothing behind it.
## The cap is deliberately low: this is a game about reading a telegraph and rolling, and a build
## that could stack its way to never being hit would be playing a different one. Kept small, it
## reads as the occasional lucky escape, which is what the word promises.
const EVASION_PER_POINT := 0.004
const EVASION_CAP := 0.25


static func evasion_chance(equipment_stats: Dictionary, talent_stats: Dictionary) -> float:
	var points := float(equipment_stats.get("evasion", 0.0))
	points += float(talent_stats.get("evasion", 0.0))
	points += stack_bonus("evasion")
	return clampf(maxf(0.0, points) * EVASION_PER_POINT, 0.0, EVASION_CAP)
