extends Node
class_name ContentLoader

static func content_path(relative: String) -> String:
	var project_dir := ProjectSettings.globalize_path("res://")
	return project_dir.path_join("../../..").path_join(relative)


static func load_json(relative: String) -> Dictionary:
	var path := content_path(relative)
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("ContentLoader: missing %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
