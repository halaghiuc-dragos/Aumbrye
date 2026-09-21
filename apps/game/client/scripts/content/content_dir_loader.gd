extends RefCounted
class_name ContentDirLoader

static var last_manifest: Dictionary = {}


static func load_id_map(
	relative_dirs: Array[String],
	id_key: String = "id",
	catalog_label: String = "ContentDirLoader",
	stamp_content_path: bool = false,
	warn_missing_id: bool = true,
	skip_files: PackedStringArray = PackedStringArray()
) -> Dictionary:
	var out: Dictionary = {}
	var paths: Array[String] = []
	for relative_dir in relative_dirs:
		paths.append_array(_directory_paths(relative_dir, catalog_label, skip_files))
	paths.sort()
	var source_by_id := {}
	var rejected_ids := {}
	var manifest := {}
	for relative in paths:
		var data: Dictionary = ContentLoader.load_json(relative)
		var entry_id := str(data.get(id_key, ""))
		if entry_id.is_empty():
			if warn_missing_id:
				push_error("%s: rejecting %s (missing %s)" % [catalog_label, relative, id_key])
			continue
		if out.has(entry_id) or rejected_ids.has(entry_id):
			push_error(
				"%s: duplicate id '%s' in %s and %s"
				% [catalog_label, entry_id, source_by_id.get(entry_id, "earlier duplicate"), relative]
			)
			rejected_ids[entry_id] = true
			out.erase(entry_id)
			manifest.erase(entry_id)
			continue
		if not _references_exist(data, relative, catalog_label):
			continue
		if stamp_content_path:
			data["content_path"] = relative
		out[entry_id] = data
		source_by_id[entry_id] = relative
		manifest[entry_id] = relative
	last_manifest[catalog_label] = manifest
	return out


static func _directory_paths(
	relative_dir: String, catalog_label: String, skip_files: PackedStringArray
) -> Array[String]:
	var paths: Array[String] = []
	var abs_dir := ContentLoader.content_path(relative_dir)
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		push_warning("%s: missing directory %s" % [catalog_label, abs_dir])
		return paths
	for file_name in dir.get_files():
		if file_name.ends_with(".json") and file_name not in skip_files:
			paths.append("%s/%s" % [relative_dir, file_name])
	return paths


static func _references_exist(value: Variant, source: String, catalog_label: String) -> bool:
	if value is Dictionary:
		for key in value:
			var child: Variant = value[key]
			if (str(key).ends_with("Path") or str(key).ends_with("Script")) and child is String:
				var path := str(child)
				if path.begins_with("res://") and not ResourceLoader.exists(path):
					push_error("%s: %s references missing resource %s" % [catalog_label, source, path])
					return false
			if not _references_exist(child, source, catalog_label):
				return false
	elif value is Array:
		for child in value:
			if not _references_exist(child, source, catalog_label):
				return false
	return true


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
