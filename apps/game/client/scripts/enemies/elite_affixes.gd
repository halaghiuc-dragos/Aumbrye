class_name EliteAffixes
extends RefCounted

## What makes one elite play differently from another (`content/combat/elite_affixes.json`): each
## affix multiplies the elite's health, speed, swing pace, damage and poise, so a pack with a swift
## elite and a brutal one asks for two different answers.

const PATH := "content/combat/elite_affixes.json"

static var _by_id: Dictionary = {}


static func definition(affix_id: String) -> Dictionary:
	_ensure_loaded()
	return _by_id.get(affix_id, {})


static func pick(rng: RandomNumberGenerator) -> String:
	_ensure_loaded()
	var ids: Array = _by_id.keys()
	ids.sort()
	return str(ids[rng.randi_range(0, ids.size() - 1)]) if not ids.is_empty() else ""


## The behaviour multipliers `CastleEnemyBase.apply_phase_modifiers` reads, from an affix.
static func behaviour_modifiers(affix_id: String) -> Dictionary:
	var def := definition(affix_id)
	if def.is_empty():
		return {}
	return {
		"moveSpeedMult": float(def.get("moveSpeedMult", 1.0)),
		"attackCooldownMult": float(def.get("attackCooldownMult", 1.0)),
		"poiseMult": float(def.get("poiseMult", 1.0)),
	}


static func _ensure_loaded() -> void:
	if not _by_id.is_empty():
		return
	for entry in ContentLoader.load_json(PATH).get("affixes", []):
		_by_id[str((entry as Dictionary).get("id", ""))] = entry
