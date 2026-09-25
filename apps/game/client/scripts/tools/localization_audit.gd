extends Node

## Exercises the shipped translation and font path rather than merely inspecting source text.
## The static CSV gate checks every row's placeholders; this runtime gate verifies that Godot can
## select Romanian, render its diacritics with the actual UI font, and expose layout pressure
## through the engine's own pseudolocalizer.

const UI_FONT_PATH := "res://assets/ui/fonts/aumbrye_pixel.ttf"
const ROMANIAN_GLYPHS := "ĂÂÎȘȚăâîșț"
const ClassCardScript := preload("res://scripts/ui/class_card.gd")

var _failures := 0


func _ready() -> void:
	_check_romanian_translation_and_font()
	_check_pseudolocalization()
	print("LOCALIZATION RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_romanian_translation_and_font() -> void:
	var old_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("ro")
	var localized := TranslationServer.translate("BOSS_DOOR_RETURN_SEALED")
	_check(
		localized != "BOSS_DOOR_RETURN_SEALED" and localized.contains("înapoi"),
		"Romanian translation resources resolve player-facing text"
	)
	var content_description := ContentText.description({
		"id": "boss_sigil",
		"description": "fallback must not be shown",
	})
	var plural := ContentText.plural("CONTENT_AUDIT_STACK", 2, "{count} sigil", "{count} sigils")
	_check(
		content_description.begins_with("Un semn sigilat")
		and plural == "2 sigilii",
		"stable content keys resolve Romanian descriptions and named plural parameters"
	)
	var missing_status_translations: Array[String] = []
	for status_id in ["bleed", "burn", "focus", "freeze", "poison", "resolve", "stoneskin", "stun", "swiftness", "torpor"]:
		var status := StatusCatalog.get_definition(status_id)
		for field_name in ["name", "description"]:
			var key := "CONTENT_%s_%s" % [status_id.to_upper(), field_name.to_upper()]
			var translated := ContentText.field(status, field_name)
			if translated.is_empty() or translated == str(status.get(field_name, "")):
				missing_status_translations.append(key)
	_check(missing_status_translations.is_empty(), "all status names and descriptions resolve through Romanian content keys")
	for key in [
		"RELIC_OFFER_FUTURE_BUILD", "RELIC_OFFER_READY_NOW", "WAVES_STARTER_TITLE",
		"MODE_UNLOCK_SHORTFALL", "MODE_RULE_PERMADEATH", "INPUT_ACTION_INTERACT",
		"PROGRESS_DUNGEONS_CLEARED", "ACHIEVEMENT_STATUS_LOCKED",
	]:
		_check(TranslationServer.translate(key) != key, "Romanian UI key resolves: %s" % key)
	var mode_rules := RunModeCatalog.describe_rules("ironman")
	var locked_mode := RunModeCatalog.unlock_hint("gauntlet", {"dungeonsCleared": 0})
	_check(
		mode_rules.contains("Fără întoarcere") and mode_rules.contains("Scorul depinde")
		and locked_mode.begins_with("Blocat") and locked_mode.contains("săli încheiate"),
		"mode rules and dynamic unlock shortfalls are localized as complete sentences"
	)
	_check(
		InputGlyphService.get_action_display_name("interact") == "Interacțiune"
		and ProgressCounters.describe(ProgressCounters.KEY_RUNS_RECORDED) == "coborâri înregistrate",
		"dynamic input and progression labels resolve in Romanian"
	)
	var saved_active: bool = RunFlow._run_active
	var saved_mode: String = RunFlow.run_mode
	var saved_floor: int = RunFlow.current_floor
	var saved_max_floors: int = RunFlow.max_floors
	var saved_boss_defeated: bool = RunFlow._boss_defeated
	var saved_cleared: Array = RunFlow._cleared_floors.duplicate()
	RunFlow._run_active = true
	RunFlow.run_mode = "castle"
	RunFlow.current_floor = 1
	RunFlow.max_floors = 1
	RunFlow._boss_defeated = true
	RunFlow._cleared_floors.assign([1])
	_check(
		RunFlow.get_current_objective() == "Intră în portal și du prada acasă.",
		"final-floor router objective resolves its Romanian portal instruction"
	)
	RunFlow._run_active = saved_active
	RunFlow.run_mode = saved_mode
	RunFlow.current_floor = saved_floor
	RunFlow.max_floors = saved_max_floors
	RunFlow._boss_defeated = saved_boss_defeated
	RunFlow._cleared_floors.assign(saved_cleared)
	var localized_mode := ContentText.name(RunModeCatalog.get_mode("ember_expedition"), "ember_expedition")
	var localized_mode_flavour := ContentText.field(
		RunModeCatalog.get_mode("ember_expedition"), "flavour"
	)
	_check(
		localized_mode == "Expediția Jarului" and localized_mode_flavour.begins_with("Vatra satului"),
		"mode names and helper-provided flavor resolve through content keys"
	)
	for class_def in ClassCatalog.get_all_classes():
		var class_name_key := "CONTENT_%s_NAME" % str(class_def.get("id", "")).to_upper()
		var localized_class_name := ContentText.name(class_def)
		var class_description := ContentText.description(class_def)
		var class_card := ClassCardScript.new() as ClassCard
		class_card.setup(class_def)
		var card_name := class_card.find_child("NameLabel", true, false) as Label
		var card_description := class_card.find_child("DescriptionLabel", true, false) as Label
		_check(
			TranslationServer.translate(class_name_key) != class_name_key
			and not localized_class_name.is_empty()
			and class_description != str(class_def.get("description", ""))
			and card_name != null
			and card_name.text == localized_class_name
			and card_description != null
			and card_description.text == class_description,
			"Romanian character-creation name and description resolve for %s" % class_def.get("id", "?")
		)
		class_card.free()
	var localized_consumables: Array[Dictionary] = []
	for item_id in ItemCatalog.get_items_by_type("consumable"):
		var item := ItemCatalog.get_definition(item_id)
		var item_name_key := "CONTENT_%s_NAME" % item_id.to_upper()
		var item_description_key := "CONTENT_%s_DESCRIPTION" % item_id.to_upper()
		var item_name := ContentText.name(item)
		var item_description := ContentText.description(item)
		_check(
			TranslationServer.translate(item_name_key) != item_name_key
			and TranslationServer.translate(item_description_key) != item_description_key
			and not item_name.is_empty()
			and not item_description.is_empty(),
			"Romanian consumable name and description resolve for %s" % item_id
		)
		localized_consumables.append(item)
	var localized_materials: Array[Dictionary] = []
	for item_id in ItemCatalog.get_items_by_type("material"):
		var item := ItemCatalog.get_definition(item_id)
		var item_name_key := "CONTENT_%s_NAME" % item_id.to_upper()
		var item_description_key := "CONTENT_%s_DESCRIPTION" % item_id.to_upper()
		_check(
			TranslationServer.translate(item_name_key) != item_name_key
			and TranslationServer.translate(item_description_key) != item_description_key,
			"Romanian material name and description resolve for %s" % item_id
		)
		localized_materials.append(item)
	TranslationServer.set_locale("en")
	for item in localized_consumables + localized_materials:
		_check(
			ContentText.name(item) == str(item.get("name", ""))
			and ContentText.description(item) == str(item.get("description", "")),
			"English consumable name and description resolve for %s" % item.get("id", "?")
		)
	var inventory_fixture := GridInventory.new()
	_check(inventory_fixture.add_item("antidote", 1), "Localized inventory fixture accepts a consumable")
	if not inventory_fixture.slots.is_empty():
		var antidote_slot: Dictionary = inventory_fixture.slots[0]
		_check(
			inventory_fixture.get_slot_display_name(antidote_slot) == ContentText.name(ItemCatalog.get_definition("antidote")),
			"Inventory display names use localized content before quality and rarity prefixes"
		)
	TranslationServer.set_locale("ro")
	var future_build := ContentText.text("RELIC_OFFER_FUTURE_BUILD", "Future build: needs {statuses}", {"statuses": "Burn"})
	_check(future_build.contains("Burn") and not future_build.contains("{statuses}"), "named localization parameters are formatted")
	var font := load(UI_FONT_PATH) as Font
	_check(font != null, "shipped UI font loads")
	var fallback_font := ThemeDB.fallback_font
	_check(fallback_font != null, "engine fallback font is available for locale glyphs")
	var ui_font := GameUISkin.build_theme().default_font
	_check(ui_font != null, "UI theme installs a font stack")
	if ui_font:
		for glyph in ROMANIAN_GLYPHS:
			_check(
				ui_font.has_char(glyph.unicode_at(0)),
				"installed UI font stack contains Romanian glyph '%s'" % glyph
			)
	TranslationServer.set_locale(old_locale)


func _check_pseudolocalization() -> void:
	var old_enabled := TranslationServer.is_pseudolocalization_enabled()
	var setting_keys: Array[String] = [
		"internationalization/pseudolocalization/replace_with_accents",
		"internationalization/pseudolocalization/double_vowels",
		"internationalization/pseudolocalization/skip_placeholders",
		"internationalization/pseudolocalization/expansion_ratio",
		"internationalization/pseudolocalization/prefix",
		"internationalization/pseudolocalization/suffix",
	]
	var old_settings: Dictionary = {}
	for key in setting_keys:
		old_settings[key] = ProjectSettings.get_setting(key)
	TranslationServer.set_pseudolocalization_enabled(true)
	ProjectSettings.set_setting("internationalization/pseudolocalization/replace_with_accents", true)
	ProjectSettings.set_setting("internationalization/pseudolocalization/double_vowels", true)
	ProjectSettings.set_setting("internationalization/pseudolocalization/skip_placeholders", true)
	ProjectSettings.set_setting("internationalization/pseudolocalization/expansion_ratio", 0.3)
	ProjectSettings.set_setting("internationalization/pseudolocalization/prefix", "[")
	ProjectSettings.set_setting("internationalization/pseudolocalization/suffix", "]")
	TranslationServer.reload_pseudolocalization()
	# Godot's built-in pseudolocalizer preserves printf placeholders. Named brace placeholders are
	# intentionally exercised by the CSV parity gate; their expansion needs a presentation wrapper
	# before a project-wide pseudolocale UI pass can be signed off.
	var source := "Load crystals %s/%s"
	var pseudo := TranslationServer.pseudolocalize(source)
	print("PSEUDO SAMPLE: %s" % pseudo)
	_check(pseudo.begins_with("[") and pseudo.ends_with("]"), "pseudolocalization marks test text")
	var formatted := pseudo % [3, 4]
	_check(
		formatted.contains("3/4") and not formatted.contains("{"),
		"pseudolocalization preserves format placeholders through formatting"
	)
	_check(pseudo.length() > source.length(), "pseudolocalization expands text for layout testing")
	TranslationServer.set_pseudolocalization_enabled(old_enabled)
	for key in setting_keys:
		ProjectSettings.set_setting(key, old_settings[key])
	TranslationServer.reload_pseudolocalization()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
