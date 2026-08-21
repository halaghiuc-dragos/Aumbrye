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
	if _is_blocked(trimmed):
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


## C-249: `character_create_ui` validates on every text change, so this compiled the pattern and
## rebuilt the lower-cased blocklist once per keystroke — eighteen times for an eighteen-character
## name. Both are constant for the session.
## The blocklist cache C-249 added is `_lists_cache` / `_lists_loaded` below; the pair that used
## to live here was left behind by C-248's rewrite from one list to three and cached nothing.
static var _charset_regex: RegEx = null


static func _matches_charset(trimmed: String) -> bool:
	if trimmed.length() == 1:
		return trimmed[0].is_valid_identifier() or trimmed.is_valid_int()
	if _charset_regex == null:
		_charset_regex = RegEx.new()
		_charset_regex.compile(_ALLOWED_PATTERN)
	return _charset_regex.search(trimmed) != null


## C-248: matching was `lowered == blocked` — equality, not containment — so `admin` was rejected
## while `admin1`, `xadmin` and `The admin` all passed. Impersonation is the whole point of the
## list, and `Admin_Steve` is the attack; the bare reserved word is what nobody would pick.
##
## Three rules, because one rule is wrong for both ends of the list:
##   - `reserved` (5+ characters): matched anywhere in the normalised name.
##   - `shortReserved` (`god`, `dev`, `test`, `null`): matched as a whole token only, because a
##     substring rule on three letters rejects Godwin, Devlin and Testa.
##   - `blocked`: substring, and currently empty — populating it is a product decision.
##
## Normalisation folds the cheap evasions: case, separators, and leetspeak digit substitutions.
## This remains a client-side courtesy. Names reach other players through the leaderboard
## (`results_screen`, `ApiClient`), so the authoritative check belongs on the server.
const _LEET_FOLD := {
	"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "!": "i"
}

static var _lists_cache: Dictionary = {}
static var _lists_loaded := false


static func _name_lists() -> Dictionary:
	if _lists_loaded:
		return _lists_cache
	_lists_loaded = true
	var data: Dictionary = ContentLoader.load_json(BLOCKED_PATH)
	var reserved := _string_list(data.get("reserved", []))
	# schemaVersion 1 documents carried everything under `blocked`, all of them reserved words.
	if reserved.is_empty() and not data.has("reserved"):
		reserved = _string_list(data.get("blocked", []))
		_lists_cache = {
			"reserved": reserved, "shortReserved": PackedStringArray(), "blocked": PackedStringArray()
		}
		return _lists_cache
	_lists_cache = {
		"reserved": reserved,
		"shortReserved": _string_list(data.get("shortReserved", [])),
		"blocked": _string_list(data.get("blocked", [])),
	}
	return _lists_cache


static func _string_list(value: Variant) -> PackedStringArray:
	var out: PackedStringArray = []
	if value is Array:
		for word in value:
			var lowered := str(word).to_lower().strip_edges()
			if lowered != "":
				out.append(lowered)
	return out


static func normalise(name: String) -> String:
	var out := ""
	for character in name.to_lower():
		var folded: String = _LEET_FOLD.get(character, character)
		if (folded >= "a" and folded <= "z") or (folded >= "0" and folded <= "9"):
			out += folded
	return out


static func _tokens(name: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for raw in name.to_lower().replace("'", " ").replace("-", " ").split(" ", false):
		var token := ""
		for character in raw:
			var folded: String = _LEET_FOLD.get(character, character)
			if (folded >= "a" and folded <= "z") or (folded >= "0" and folded <= "9"):
				token += folded
		if token != "":
			out.append(token)
	return out


static func _is_blocked(trimmed: String) -> bool:
	var lists := _name_lists()
	var normalised := normalise(trimmed)
	if normalised == "":
		return false
	for word in lists.get("reserved", PackedStringArray()):
		if normalised.contains(word):
			return true
	for word in lists.get("blocked", PackedStringArray()):
		if normalised.contains(word):
			return true
	var tokens := _tokens(trimmed)
	for word in lists.get("shortReserved", PackedStringArray()):
		if tokens.has(word) or normalised == word:
			return true
	return false
