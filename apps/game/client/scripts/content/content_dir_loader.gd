extends RefCounted
class_name ContentDirLoader


static func load_id_map(
	relative_dirs: Array[String],
	id_key: String = "id",
	catalog_label: String = "ContentDirLoader",
	stamp_content_path: bool = false,
	warn_missing_id: bool = true,
	skip_files: PackedStringArray = PackedStringArray()
) -> Dictionary:
	var out: Dictionary = {}
	for relative_dir in relative_dirs:
		_load_directory(
			relative_dir,
			id_key,
			catalog_label,
			stamp_content_path,
			warn_missing_id,
			out,
			skip_files
		)
	return out


static func _load_directory(
	relative_dir: String,
	id_key: String,
	catalog_label: String,
	stamp_content_path: bool,
	warn_missing_id: bool,
	out: Dictionary,
	skip_files: PackedStringArray = PackedStringArray()
) -> void:
	var abs_dir := ContentLoader.content_path(relative_dir)
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		push_warning("%s: missing directory %s" % [catalog_label, abs_dir])
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json") and file_name not in skip_files:
			var relative := "%s/%s" % [relative_dir, file_name]
			var data: Dictionary = ContentLoader.load_json(relative)
			var entry_id: String = str(data.get(id_key, ""))
			if entry_id.is_empty():
				if warn_missing_id:
					push_warning("%s: skipping %s (missing %s)" % [catalog_label, relative, id_key])
			else:
				if stamp_content_path:
					data["content_path"] = relative
				out[entry_id] = data
		file_name = dir.get_next()
	dir.list_dir_end()
