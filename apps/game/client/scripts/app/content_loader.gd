class_name ContentLoader
extends Node

## Resolves repo `content/` JSON. Override root via ProjectSettings `aumbrye/content_root`
## (absolute path) for exports or non-standard layouts.

const ContentSchemaValidator := preload("res://scripts/app/content_schema_validator.gd")


static func content_root() -> String:
	var configured := str(ProjectSettings.get_setting("aumbrye/content_root", ""))
	if not configured.is_empty():
		return configured
	return ProjectSettings.globalize_path("res://").path_join("../../..")


static func content_path(relative: String) -> String:
	return content_root().path_join(relative)


static func load_json(relative: String) -> Dictionary:
	var path := content_path(relative)
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		var msg := "ContentLoader: missing %s" % path
		if CrashLogger:
			CrashLogger.log_error("content_loader.missing", {"path": path})
		elif OS.is_debug_build():
			push_error(msg)
		else:
			push_warning(msg)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	var result: Dictionary = parsed if parsed is Dictionary else {}
	if OS.is_debug_build() and not result.is_empty():
		ContentSchemaValidator.validate_loaded(relative, result)
	return result


static func clear_all_caches() -> void:
	ItemCatalog.clear_cache()
	EnemyCatalog.clear_cache()
	ClassCatalog.clear_cache()
	RelicCatalog.clear_cache()
	QuestCatalog.clear_cache()
	DialogueCatalog.clear_cache()
	var portal_script: Script = load("res://scripts/content/portal_catalog.gd")
	if portal_script:
		portal_script.call("clear_cache")
