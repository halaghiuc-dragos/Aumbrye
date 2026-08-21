class_name CharacterFlags
extends RefCounted

## Registered character flag ids — type, default, and JSON-safe coercion.

enum Kind { BOOL, INT, STRING, DICT }

const REGISTRY: Dictionary = {
	"deaths": {"kind": Kind.INT, "default": 0},
	"runs_started": {"kind": Kind.INT, "default": 0},
	"dungeon_max_tier": {"kind": Kind.INT, "default": 1},
	"dungeon_unlocked_count": {"kind": Kind.INT, "default": 1},
	"story_completed": {"kind": Kind.BOOL, "default": false},
	"recoverable_xp_shard": {"kind": Kind.DICT, "default": {}},
	"theme_forgotten_castle_cleared": {"kind": Kind.BOOL, "default": false},
	"theme_crystal_caverns_cleared": {"kind": Kind.BOOL, "default": false},
	"theme_poison_swamp_cleared": {"kind": Kind.BOOL, "default": false},
	"theme_frozen_fortress_cleared": {"kind": Kind.BOOL, "default": false},
	"theme_dark_cathedral_cleared": {"kind": Kind.BOOL, "default": false},
	"theme_iron_vault_cleared": {"kind": Kind.BOOL, "default": false},
	"theme_prism_depths_cleared": {"kind": Kind.BOOL, "default": false},
	"theme_venom_mire_cleared": {"kind": Kind.BOOL, "default": false},
	"theme_glacial_hollow_cleared": {"kind": Kind.BOOL, "default": false},
	"theme_umbral_chapel_cleared": {"kind": Kind.BOOL, "default": false},
	"heard_castle_lore": {"kind": Kind.BOOL, "default": false},
	"met_dungeon_npc": {"kind": Kind.BOOL, "default": false},
	"story_beat": {"kind": Kind.INT, "default": 0},
	"discoveries_found": {"kind": Kind.INT, "default": 0},
	"heard_the_keeping": {"kind": Kind.BOOL, "default": false},
	"heard_the_aumbrage": {"kind": Kind.BOOL, "default": false},
	"heard_the_hierarch": {"kind": Kind.BOOL, "default": false},
	"gate_reopened": {"kind": Kind.BOOL, "default": false},
	"lamps_relit": {"kind": Kind.BOOL, "default": false},
	"prayer_restored": {"kind": Kind.BOOL, "default": false},
	"rescued_halbrek": {"kind": Kind.BOOL, "default": false},
	"rescued_ivo": {"kind": Kind.BOOL, "default": false},
	"rescued_nettle": {"kind": Kind.BOOL, "default": false},
	"rescued_corrin": {"kind": Kind.BOOL, "default": false},
	"rescued_odile": {"kind": Kind.BOOL, "default": false},
	"rescued_veil": {"kind": Kind.BOOL, "default": false},
	"lost_halbrek": {"kind": Kind.BOOL, "default": false},
	"lost_ivo": {"kind": Kind.BOOL, "default": false},
	"lost_nettle": {"kind": Kind.BOOL, "default": false},
	"lost_corrin": {"kind": Kind.BOOL, "default": false},
	"lost_odile": {"kind": Kind.BOOL, "default": false},
	"lost_veil": {"kind": Kind.BOOL, "default": false},
	"rel_aldric": {"kind": Kind.INT, "default": 0},
	"rel_elara": {"kind": Kind.INT, "default": 0},
	"rel_mira": {"kind": Kind.INT, "default": 0},
	"rel_vessit": {"kind": Kind.INT, "default": 0},
	"rel_halbrek": {"kind": Kind.INT, "default": 0},
	"rel_ivo": {"kind": Kind.INT, "default": 0},
	"rel_nettle": {"kind": Kind.INT, "default": 0},
	"rel_corrin": {"kind": Kind.INT, "default": 0},
	"rel_odile": {"kind": Kind.INT, "default": 0},
	"rel_veil": {"kind": Kind.INT, "default": 0},
	"lore_forgotten_castle_read": {"kind": Kind.INT, "default": 0},
	"lore_iron_vault_read": {"kind": Kind.INT, "default": 0},
	"lore_crystal_caverns_read": {"kind": Kind.INT, "default": 0},
	"lore_prism_depths_read": {"kind": Kind.INT, "default": 0},
	"lore_poison_swamp_read": {"kind": Kind.INT, "default": 0},
	"lore_venom_mire_read": {"kind": Kind.INT, "default": 0},
	"lore_frozen_fortress_read": {"kind": Kind.INT, "default": 0},
	"lore_glacial_hollow_read": {"kind": Kind.INT, "default": 0},
	"lore_dark_cathedral_read": {"kind": Kind.INT, "default": 0},
	"lore_umbral_chapel_read": {"kind": Kind.INT, "default": 0},
	"last_run": {"kind": Kind.DICT, "default": {}},
	"bestiary_kills": {"kind": Kind.DICT, "default": {}},
	"bestiary_studied_count": {"kind": Kind.INT, "default": 0},
	"bestiary_mastered_count": {"kind": Kind.INT, "default": 0},
	"bestiary_complete": {"kind": Kind.BOOL, "default": false},
	"bounty_tokens": {"kind": Kind.INT, "default": 0},
	"bounty_state": {"kind": Kind.DICT, "default": {}},
	"bounty_claimed_total": {"kind": Kind.INT, "default": 0},
	"account_seed": {"kind": Kind.INT, "default": 0},
	"nettle_remedy_taught": {"kind": Kind.BOOL, "default": false},
	"corrin_lamp_lit": {"kind": Kind.INT, "default": 0},
	"odile_reading_given": {"kind": Kind.INT, "default": 0},
	"veil_names_given": {"kind": Kind.INT, "default": 0},
	"halbrek_muster_open": {"kind": Kind.BOOL, "default": false},
	"ivo_vault_open": {"kind": Kind.BOOL, "default": false},
	"mira_reading_given": {"kind": Kind.INT, "default": 0},
	"aldric_apprenticed": {"kind": Kind.BOOL, "default": false},
	"elara_ledger_settled": {"kind": Kind.BOOL, "default": false},
	"vessit_bounties_open": {"kind": Kind.BOOL, "default": false},
}


static func is_registered(flag_id: String) -> bool:
	return REGISTRY.has(flag_id)


static func default_for(flag_id: String) -> Variant:
	if is_registered(flag_id):
		var entry: Dictionary = REGISTRY[flag_id]
		var default_value: Variant = entry.get("default")
		if default_value is Dictionary:
			return default_value.duplicate(true)
		return default_value
	return false


static func content_writable_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for flag_id in REGISTRY:
		ids.append(flag_id)
	return ids


static func coerce(flag_id: String, value: Variant) -> Variant:
	if not _is_json_serializable(value):
		push_warning(
			"CharacterFlags: rejected unserialisable value for '%s' (%s)"
			% [flag_id, typeof(value)]
		)
		return default_for(flag_id)
	if not is_registered(flag_id):
		return _coerce_unregistered(value)
	var kind: int = int(REGISTRY[flag_id].get("kind", Kind.BOOL))
	match kind:
		Kind.BOOL:
			if value is bool:
				return value
			if value is int or value is float:
				return bool(value)
			if value is String:
				return value.to_lower() in ["true", "1", "yes"]
			push_warning("CharacterFlags: coerced '%s' to bool" % flag_id)
			return bool(value)
		Kind.INT:
			if value is int:
				return value
			if value is float:
				return int(value)
			if value is String and value.is_valid_int():
				return int(value)
			if value is bool:
				return 1 if value else 0
			push_warning("CharacterFlags: coerced '%s' to int" % flag_id)
			return int(value) if str(value).is_valid_int() else int(default_for(flag_id))
		Kind.STRING:
			return str(value)
		Kind.DICT:
			if value is Dictionary:
				return value.duplicate(true)
			push_warning("CharacterFlags: reset '%s' to default dict" % flag_id)
			return default_for(flag_id)
	return default_for(flag_id)


static func coerce_all(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var result: Dictionary = {}
	for key in raw:
		var flag_id := str(key)
		result[flag_id] = coerce(flag_id, raw[key])
	return result


static func is_truthy(_flag_id: String, value: Variant) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return value != 0
	if value is String:
		return not value.is_empty()
	if value is Dictionary:
		return not value.is_empty()
	if value is Array:
		return not value.is_empty()
	return bool(value)


static func _coerce_unregistered(value: Variant) -> Variant:
	if not _is_json_serializable(value):
		push_warning("CharacterFlags: dropped unserialisable unregistered flag value (%s)" % typeof(value))
		return null
	if value is Dictionary:
		return value.duplicate(true)
	if value is Array:
		return value.duplicate()
	return value


static func _is_json_serializable(value: Variant) -> bool:
	if value == null:
		return true
	var t := typeof(value)
	return (
		t
		in [
			TYPE_BOOL,
			TYPE_INT,
			TYPE_FLOAT,
			TYPE_STRING,
			TYPE_DICTIONARY,
			TYPE_ARRAY,
			TYPE_NIL,
		]
	)
