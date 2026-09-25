extends RefCounted
class_name HubTutorialService


const SAVE_KEY := "hub_tutorial"
const CONTENT_PATH := "content/hub/tips.json"

static var tips_enabled := true
static var tips_completed := false
static var seen_ids: Array[String] = []

static var _catalog_loaded := false
static var _catalog: Array[Dictionary] = []
static var _catalog_ids: Array[String] = []
static var _load_failed := false

static var _placeholder_re: RegEx


static func load_catalog() -> void:
	if _catalog_loaded:
		return
	_catalog_loaded = true
	_catalog.clear()
	_catalog_ids.clear()
	var data: Dictionary = ContentLoader.load_json(CONTENT_PATH)
	if data.is_empty() or not data.has("tips"):
		_load_failed = true
		push_warning("HubTutorialService: failed to load %s" % CONTENT_PATH)
		return
	for entry in data.get("tips", []):
		if not entry is Dictionary:
			continue
		var tip: Dictionary = entry
		var tip_id := str(tip.get("id", ""))
		if tip_id.is_empty():
			continue
		_catalog.append(tip)
		_catalog_ids.append(tip_id)


## AD-07: a contextual teaching pass that fires once per account, triggered by the event that
## makes it relevant rather than a menu the player has to go find. Each hint is recorded as its
## own `CharacterService` flag so it never repeats, and the flags survive `reset_for_character()`
## on purpose -- this teaches the combat model itself, not this character's progress.
const FLAG_TELEGRAPH_PREFIX := "tutorial_seen_telegraph_"
const FLAG_POISE_BREAK := "tutorial_seen_poise_break_dealt"
const FLAG_STAMINA_EXHAUSTED := "tutorial_seen_stamina_exhausted"
const FLAG_PENDING_COMBAT_TEACHING := "tutorial_pending_combat_teaching"


static func notify_telegraph_seen(attack_class: String) -> String:
	var flag := FLAG_TELEGRAPH_PREFIX + attack_class
	var teaching_key := ""
	match attack_class:
		"blockable":
			teaching_key = "TUTORIAL_TELEGRAPH_AMBER"
		"parryable":
			teaching_key = "TUTORIAL_TELEGRAPH_BLUE"
		"unblockable":
			teaching_key = "TUTORIAL_TELEGRAPH_RED"
	if teaching_key != "":
		_queue_combat_teaching(flag, teaching_key)
	return ""


static func notify_poise_break_dealt() -> String:
	_queue_combat_teaching(FLAG_POISE_BREAK, "TUTORIAL_POISE_BREAK")
	return ""


static func notify_stamina_exhausted() -> String:
	_queue_combat_teaching(FLAG_STAMINA_EXHAUSTED, "TUTORIAL_STAMINA_EXHAUSTED")
	return ""


static func _queue_combat_teaching(seen_flag: String, teaching_key: String) -> void:
	var seen := bool(CharacterService.get_flag(seen_flag, false))
	var pending_value: Variant = CharacterService.get_flag(FLAG_PENDING_COMBAT_TEACHING, [])
	var flags := queue_combat_teaching_flags(
		{seen_flag: seen, FLAG_PENDING_COMBAT_TEACHING: pending_value}, seen_flag, teaching_key
	)
	if not bool(flags.get(seen_flag, false)):
		CharacterService.set_flag(seen_flag, true)
		CharacterService.set_flag(FLAG_PENDING_COMBAT_TEACHING, flags.get(FLAG_PENDING_COMBAT_TEACHING, []))


static func queue_combat_teaching_flags(
	flags: Dictionary, seen_flag: String, teaching_key: String
) -> Dictionary:
	var out := flags.duplicate(true)
	if bool(out.get(seen_flag, false)):
		return out
	out[seen_flag] = true
	var pending_value: Variant = out.get(FLAG_PENDING_COMBAT_TEACHING, [])
	var pending: Array = pending_value.duplicate() if pending_value is Array else []
	if teaching_key not in pending:
		pending.append(teaching_key)
	out[FLAG_PENDING_COMBAT_TEACHING] = pending
	return out


static func drain_combat_teaching_flags(flags: Dictionary) -> Dictionary:
	var out := flags.duplicate(true)
	var pending_value: Variant = out.get(FLAG_PENDING_COMBAT_TEACHING, [])
	var messages: Array[String] = []
	if pending_value is Array:
		for entry in pending_value:
			var message := String(TranslationServer.translate(str(entry)))
			if message != "":
				messages.append(message)
	out[FLAG_PENDING_COMBAT_TEACHING] = []
	return {"flags": out, "messages": messages}


static func consume_pending_combat_teaching() -> Array[String]:
	var pending_value: Variant = CharacterService.get_flag(FLAG_PENDING_COMBAT_TEACHING, [])
	var drained := drain_combat_teaching_flags(
		{FLAG_PENDING_COMBAT_TEACHING: pending_value}
	)
	CharacterService.set_flag(FLAG_PENDING_COMBAT_TEACHING, [])
	return drained.get("messages", []) as Array[String]


static func reset_for_character() -> void:
	tips_enabled = true
	tips_completed = false
	seen_ids.clear()


static func load_from_save() -> void:
	reset_for_character()
	var data: Dictionary = LocalSave.get_meta_data().get(SAVE_KEY, {})
	tips_enabled = bool(data.get("enabled", true))
	tips_completed = bool(data.get("completed", false))
	seen_ids.clear()
	var seen_raw: Variant = data.get("seen", [])
	if seen_raw is Array:
		for entry in seen_raw:
			seen_ids.append(str(entry))
	_prune_seen_ids()


static func _prune_seen_ids() -> void:
	load_catalog()
	if _catalog_ids.is_empty():
		return
	var valid := {}
	for tip_id in _catalog_ids:
		valid[tip_id] = true
	var pruned: Array[String] = []
	for tip_id in seen_ids:
		if valid.has(tip_id):
			pruned.append(tip_id)
	seen_ids = pruned


static func should_show_tips() -> bool:
	if _load_failed:
		return false
	if not tips_enabled or tips_completed:
		return false
	return not _current_tip_entry().is_empty()


static func get_current_tip() -> String:
	var tip := _current_tip_entry()
	if tip.is_empty():
		return ""
	return _substitute_glyphs(str(tip.get("text", "")), tip)


static func advance_tip() -> String:
	var tip := _current_tip_entry()
	if tip.is_empty():
		tips_completed = true
		save()
		return ""
	var tip_id := str(tip.get("id", ""))
	if tip_id != "" and tip_id not in seen_ids:
		seen_ids.append(tip_id)
	if _current_tip_entry().is_empty():
		tips_completed = true
	save()
	return get_current_tip()


static func skip_all() -> void:
	tips_completed = true
	tips_enabled = false
	save()


static func save() -> void:
	var meta := LocalSave.get_meta_data().duplicate(true)
	meta[SAVE_KEY] = {
		"enabled": tips_enabled,
		"completed": tips_completed,
		"seen": seen_ids.duplicate(),
	}
	LocalSave.patch_meta(meta)
	LocalSave.request_autosave(LocalSave.SavePriority.DEFERRED)


static func migrate_index_to_seen(tut: Dictionary) -> Dictionary:
	if not tut.has("index") or tut.has("seen"):
		return tut
	load_catalog()
	var seen: Array[String] = []
	var limit := mini(int(tut.get("index", 0)), _catalog_ids.size())
	for i in limit:
		seen.append(_catalog_ids[i])
	tut["seen"] = seen
	tut.erase("index")
	return tut


static func _current_tip_entry() -> Dictionary:
	load_catalog()
	if _load_failed:
		return {}
	for tip in _catalog:
		var tip_id := str(tip.get("id", ""))
		if tip_id in seen_ids:
			continue
		var show_when: Variant = tip.get("showWhen", null)
		if show_when != null and not DialogueConditions.evaluate(show_when):
			continue
		return tip
	return {}


static func _substitute_glyphs(text: String, tip: Dictionary) -> String:
	if text.is_empty():
		return text
	if _placeholder_re == null:
		_placeholder_re = RegEx.new()
		_placeholder_re.compile("\\{([a-z0-9_]+)\\}")
	var result := text
	var actions: Array = tip.get("actions", [])
	var seen_actions := {}
	for action_name in actions:
		seen_actions[str(action_name)] = true
	for match in _placeholder_re.search_all(text):
		var action := match.get_string(1)
		if not seen_actions.has(action):
			push_warning(
				(
					"HubTutorialService: tip '%s' references unlisted action '%s'"
					% [
						tip.get("id", ""),
						action,
					]
				)
			)
		var glyph := InputGlyphService.get_action_glyph(action)
		if glyph == action.substr(0, 1).to_upper() and not InputMap.has_action(action):
			push_warning("HubTutorialService: action '%s' is not bound in InputMap" % action)
		result = result.replace("{%s}" % action, glyph)
	return result
