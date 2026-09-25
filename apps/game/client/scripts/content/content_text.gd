class_name ContentText
extends RefCounted

## Presentation boundary for authored content. Content remains readable when a locale entry has not
## yet shipped, while every definition has one deterministic key that translators and audits can
## target without UI code inventing prose.

static func description(definition: Dictionary, fallback: String = "") -> String:
	return field(definition, "description", fallback)


static func name(definition: Dictionary, fallback: String = "") -> String:
	return field(definition, "name", fallback)


static func field(definition: Dictionary, field_name: String, fallback: String = "") -> String:
	var authored := str(definition.get(field_name, fallback))
	var id := str(definition.get("id", ""))
	if id.is_empty():
		return authored
	return text("CONTENT_%s_%s" % [id.to_upper(), field_name.to_upper()], authored)


static func text(key: String, fallback: String, parameters: Dictionary = {}) -> String:
	var translated := String(TranslationServer.translate(key))
	var value := fallback if translated == key else translated
	for parameter in parameters:
		value = value.replace("{%s}" % str(parameter), str(parameters[parameter]))
	return value


static func plural(key: String, count: int, fallback_one: String, fallback_other: String) -> String:
	var suffix := "ONE" if count == 1 else "OTHER"
	var fallback := fallback_one if count == 1 else fallback_other
	return text("%s_%s" % [key, suffix], fallback, {"count": count})
