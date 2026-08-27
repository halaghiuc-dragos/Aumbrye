class_name ContentLoader
extends Node


const ContentSchemaValidatorScript := preload("res://scripts/app/content_schema_validator.gd")

static var _json_cache: Dictionary = {}

static var _missing_paths: Dictionary = {}


static func content_root() -> String:
	var configured := str(ProjectSettings.get_setting("aumbrye/content_root", ""))
	if not configured.is_empty():
		return configured
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").path_join("../../..")
	return OS.get_executable_path().get_base_dir()


static func content_path(relative: String) -> String:
	return content_root().path_join(relative)


static func load_json(relative: String) -> Dictionary:
	if _json_cache.has(relative):
		return (_json_cache[relative] as Dictionary).duplicate(true)
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
		_missing_paths[relative] = true
		_json_cache[relative] = {}
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	var result: Dictionary = parsed if parsed is Dictionary else {}
	if OS.is_debug_build() and not result.is_empty():
		ContentSchemaValidatorScript.validate_loaded(relative, result)
	_json_cache[relative] = result
	return result.duplicate(true)


static func prime(paths: Array) -> int:
	var loaded := 0
	for path in paths:
		var relative := str(path)
		if relative.is_empty() or _json_cache.has(relative):
			continue
		load_json(relative)
		loaded += 1
	return loaded


static func clear_all_caches() -> void:
	_json_cache.clear()
	ItemCatalog.clear_cache()
	EnemyCatalog.clear_cache()
	ClassCatalog.clear_cache()
	RelicCatalog.clear_cache()
	QuestCatalog.clear_cache()
	DialogueCatalog.clear_cache()
	var portal_script: Script = load("res://scripts/content/portal_catalog.gd")
	if portal_script:
		portal_script.call("clear_cache")
