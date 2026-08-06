class_name NameValidator
extends RefCounted

## Warden name rules for character creation.

const MIN_LENGTH := 2
const MAX_LENGTH := 18
const BLOCKED_PATH := "content/text/blocked_names.json"
const WARDEN_NAMES_PATH := "content/text/warden_names.json"

const _ALLOWED_PATTERN := "^[A-Za-z0-9][A-Za-z0-9 '\\-]*[A-Za-z0-9]$|^[A-Za-z0-9]$"


static func validate(name: String, existing_names: PackedStringArray = []) -> Dictionary:
	var trimmed := name.strip_edges()
	if trimmed.length() < MIN_LENGTH:
		return {"ok": false, "reason_key": "CREATE_NAME_ERR_SHORT"}
	if trimmed.length() > MAX_LENGTH:
		return {"ok": false, "reason_key": "CREATE_NAME_ERR_LONG"}
	if not _matches_charset(trimmed):
		return {"ok": false, "reason_key": "CREATE_NAME_ERR_CHARS"}
	var lowered := trimmed.to_lower()
	for blocked in _blocked_words():
		if lowered == blocked:
			return {"ok": false, "reason_key": "CREATE_NAME_ERR_BLOCKED"}
	for existing in existing_names:
		if lowered == str(existing).strip_edges().to_lower():
			return {"ok": false, "reason_key": "CREATE_NAME_ERR_TAKEN"}
	return {"ok": true, "reason_key": ""}


static func random_valid_name(existing_names: PackedStringArray = []) -> String:
	var data: Dictionary = ContentLoader.load_json(WARDEN_NAMES_PATH)
	var first_list: Variant = data.get("first", [])
	var epithet_list: Variant = data.get("epithet", [])
	if not first_list is Array or first_list.is_empty():
		return "Warden"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _attempt in 128:
		var first := str(first_list[rng.randi_range(0, first_list.size() - 1)])
		var candidate := first
		if epithet_list is Array and not epithet_list.is_empty():
			var epithet := str(epithet_list[rng.randi_range(0, epithet_list.size() - 1)])
			candidate = "%s %s" % [first, epithet]
			if candidate.length() > MAX_LENGTH:
				candidate = first
		var result := validate(candidate, existing_names)
		if bool(result.get("ok", false)):
			return candidate
	return str(first_list[0])


static func _matches_charset(trimmed: String) -> bool:
	if trimmed.length() == 1:
		return trimmed[0].is_valid_identifier() or trimmed.is_valid_int()
	var regex := RegEx.new()
	regex.compile(_ALLOWED_PATTERN)
	return regex.search(trimmed) != null


static func _blocked_words() -> PackedStringArray:
	var data: Dictionary = ContentLoader.load_json(BLOCKED_PATH)
	var blocked: Variant = data.get("blocked", [])
	if blocked is Array:
		var out: PackedStringArray = []
		for word in blocked:
			out.append(str(word).to_lower())
		return out
	return PackedStringArray()
