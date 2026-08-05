class_name ContentLoader
extends Node

## Resolves repo `content/` JSON. Override root via ProjectSettings `aumbrye/content_root`
## (absolute path) for exports or non-standard layouts.


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
		if OS.is_debug_build():
			push_error(msg)
		else:
			push_warning(msg)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
