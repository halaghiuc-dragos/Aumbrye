class_name ContentLoader
extends Node

## Resolves repo `content/` JSON. Override root via ProjectSettings `aumbrye/content_root`
## (absolute path) for exports or non-standard layouts.
##
## Root resolution order:
##  1. `aumbrye/content_root` project setting, if set — explicit override for CI or custom
##     layouts.
##  2. In the editor / `--script` headless runs (`OS.has_feature("editor")` is true), the repo
##     root three levels above `res://` — this is where the source tree keeps `content/` and is
##     never true for an exported build.
##  3. In an exported build, the directory containing the executable — which requires the release
##     pipeline to copy `content/` next to the binary at export time.
##
##     C-265: this named `.github/workflows/release.yml` for a long time while no such workflow
##     existed — the same class of dangling reference as C-261. It was not cosmetic: `content/`
##     lives at the repo root, *outside* `res://`, so `export_filter="all_resources"` does not pack
##     it and an export without the copy ships with no catalogues at all.
##
##     **This copy is a manual export step.** The project has no CI and will not have one (see
##     CLAUDE.md), so nothing performs it automatically and nothing verifies it: a source run
##     resolves content against the repo root and never exercises this branch. Whoever cuts a
##     release copies `content/` next to the binary and then runs the *exported* executable with
##     `--smoke-test`, which is the only check that this path works.
## `res://` globalises to the *install* directory in an exported build, not the source tree, so
## resolving relative to it (as this used to do unconditionally) silently found nothing outside
## the editor. See BUG-01.

const ContentSchemaValidatorScript := preload("res://scripts/app/content_schema_validator.gd")

## Parsed-and-validated JSON keyed by relative path. `load_json` is called from many catalogue
## `_ensure_loaded()` paths and from ad-hoc one-off readers alike; caching here means the schema
## validator and the directory walk in `ContentDirLoader` only ever pay for a given file once per
## session, including the failure case (a missing/malformed file is cached as `{}` rather than
## re-opened and re-parsed on every subsequent call). Callers always get their own duplicate so
## in-place mutation (e.g. `ContentDirLoader` stamping `content_path` onto the result) can never
## corrupt the cached copy.
static var _json_cache: Dictionary = {}

## Relative paths that resolved to nothing this session.
##
## A missing `content/` directory in an exported build previously produced one `push_warning`
## per file — invisible to a player — and the game booted with no weapons, no enemies and no
## loot, looking broken rather than misconfigured. Callers that can surface a real error (boot,
## the validation harness, a diagnostics screen) ask this instead of guessing from empty
## dictionaries, which are also a legitimate result for an intentionally absent optional file.
static var _missing_paths: Dictionary = {}


## Whether any content file failed to resolve, i.e. the content root is wrong or unpackaged.
static func has_missing_content() -> bool:
	return not _missing_paths.is_empty()


## Relative paths that failed to resolve, for an error surface to report.
static func missing_content_paths() -> Array:
	var paths: Array = _missing_paths.keys()
	paths.sort()
	return paths


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


## Loads a batch of content files into the cache up front, so the first in-gameplay touch is a
## dictionary lookup rather than a disk read and JSON parse.
##
## Call this while a loading screen is up. Returns how many paths were newly parsed (already-cached
## paths cost nothing), which makes it easy to assert in tests that a prewarm actually did work.
static func prime(paths: Array) -> int:
	var loaded := 0
	for path in paths:
		var relative := str(path)
		if relative.is_empty() or _json_cache.has(relative):
			continue
		load_json(relative)
		loaded += 1
	return loaded


## Whether a path has already been parsed this session. Used by prewarm diagnostics to spot content
## that is still being loaded during gameplay instead of during the loading screen.
static func is_cached(relative: String) -> bool:
	return _json_cache.has(relative)


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
