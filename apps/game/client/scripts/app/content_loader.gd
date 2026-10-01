class_name ContentLoader
extends Node


const ContentSchemaValidatorScript := preload("res://scripts/app/content_schema_validator.gd")

static var _json_cache: Dictionary = {}

static var _missing_paths: Dictionary = {}

const CONTENT_ROOT_ENV := "AUMBRYE_CONTENT_ROOT"


static func content_root() -> String:
	var configured := str(ProjectSettings.get_setting("aumbrye/content_root", ""))
	if not configured.is_empty():
		return _normalise_root(configured)
	# This is deliberately an explicit deployment/testing override, not a search path. A release
	# still fails closed beside its executable when staging is missing; CI can exercise that exact
	# layout without leaking repository content into the package.
	var environment_root := OS.get_environment(CONTENT_ROOT_ENV).strip_edges()
	if not environment_root.is_empty():
		var normalised_environment_root := _normalise_root(environment_root)
		if DirAccess.dir_exists_absolute(normalised_environment_root.path_join("content")):
			return normalised_environment_root
		push_error("ContentLoader: %s has no content/ directory: %s" % [CONTENT_ROOT_ENV, normalised_environment_root])
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").path_join("../../..")
	return OS.get_executable_path().get_base_dir()


static func _normalise_root(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path.simplify_path()


static func content_path(relative: String) -> String:
	return content_root().path_join(relative)


static func load_json(relative: String) -> Dictionary:
	var outcome := load_json_result(relative)
	var data: Variant = outcome.get("data", {})
	return data as Dictionary if data is Dictionary else {}


## The cached document itself, read-only, for callers that only read it and sit on a hot path
## (every tooltip, every spawn). `load_json` deep-copies so that a caller may edit its copy; this
## one does not copy, and writing to it fails.
static func load_json_shared(relative: String) -> Dictionary:
	if not _json_cache.has(relative):
		load_json_result(relative)
	var cached: Variant = _json_cache.get(relative)
	if not cached is Dictionary:
		return {}
	var document: Dictionary = cached
	if not document.is_read_only():
		document.make_read_only()
	return document


static func load_json_result(relative: String, retry: bool = false) -> Dictionary:
	if retry:
		_json_cache.erase(relative)
		_missing_paths.erase(relative)
	if _json_cache.has(relative):
		return {"ok": true, "data": (_json_cache[relative] as Dictionary).duplicate(true)}
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
		return {"ok": false, "error": "missing", "path": path, "data": {}}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		if CrashLogger:
			CrashLogger.log_error("content_loader.malformed", {"path": path})
		return {"ok": false, "error": "malformed", "path": path, "data": {}}
	var result: Dictionary = parsed
	if OS.is_debug_build() and not result.is_empty():
		ContentSchemaValidatorScript.validate_loaded(relative, result)
	_json_cache[relative] = result
	return {"ok": true, "data": result.duplicate(true)}


static func prime(paths: Array) -> int:
	var loaded := 0
	for path in paths:
		var relative := str(path)
		if relative.is_empty() or _json_cache.has(relative):
			continue
		load_json(relative)
		loaded += 1
	return loaded


