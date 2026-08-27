class_name ClassPerks
extends RefCounted


const BLOODRAGE := "bloodrage"
const STEADFAST := "steadfast"
const SHADOWSTEP := "shadowstep"
const BULWARK := "bulwark"
const ARCANE_FOCUS := "arcane_focus"

const BLOODRAGE_MAX_BONUS := 0.5
const STEADFAST_GUARD_REGEN_MULT := 2.5
const SHADOWSTEP_IFRAME_BONUS := 0.12
const BULWARK_STABILITY_BONUS := 0.25
const ARCANE_FOCUS_MANA_ON_HIT := 4.0


static func is_player_perk(body: Node, perk_id: String) -> bool:
	if body == null or not body.is_in_group("player"):
		return false
	if not CharacterService:
		return false
	return ClassCatalog.get_perk(CharacterService.class_id) == perk_id


static func bloodrage_damage_multiplier(body: Node, health: Health) -> float:
	if health == null or health.max_health <= 0.0 or not is_player_perk(body, BLOODRAGE):
		return 1.0
	var missing_fraction := 1.0 - clampf(health.current / health.max_health, 0.0, 1.0)
	return 1.0 + missing_fraction * BLOODRAGE_MAX_BONUS


static func steadfast_poise_regen_multiplier(body: Node) -> float:
	if not is_player_perk(body, STEADFAST):
		return 1.0
	var guard := body.get_node_or_null("Guard")
	if guard and bool(guard.get("is_guard_active")):
		return STEADFAST_GUARD_REGEN_MULT
	return 1.0


static func shadowstep_iframe_bonus(body: Node, is_backstep: bool) -> float:
	if not is_backstep or not is_player_perk(body, SHADOWSTEP):
		return 0.0
	return SHADOWSTEP_IFRAME_BONUS


static func bulwark_stability_bonus(body: Node) -> float:
	return BULWARK_STABILITY_BONUS if is_player_perk(body, BULWARK) else 0.0


static func arcane_focus_mana_on_hit(body: Node) -> float:
	return ARCANE_FOCUS_MANA_ON_HIT if is_player_perk(body, ARCANE_FOCUS) else 0.0
