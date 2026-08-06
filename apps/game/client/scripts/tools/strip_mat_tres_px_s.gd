extends SceneTree

## One-shot PXS cleanup: strip mat_*.tres scene refs, delete legacy materials, emit castle tiles.png.

const SCENES_ROOT := "res://scenes"
const ASSETS_ROOT := "res://assets"


func _initialize() -> void:
	var stripped := _strip_scene_material_refs()
	var deleted := _delete_mat_tres_files()
	var atlas_ok := _generate_castle_tiles_atlas()
	print(
		"strip_mat_tres_px_s: stripped %d scenes, deleted %d mat files, atlas=%s"
		% [stripped, deleted, atlas_ok]
	)
	quit(0 if atlas_ok else 1)


func _strip_scene_material_refs() -> int:
	var count := 0
	var dir := DirAccess.open(SCENES_ROOT)
	if dir == null:
		return 0
	count += _collect_and_strip_tscn(dir, SCENES_ROOT)
	return count


func _collect_and_strip_tscn(dir: DirAccess, prefix: String) -> int:
	var count := 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var path := "%s/%s" % [prefix, entry]
		if dir.current_is_dir():
			var child := DirAccess.open(path)
			if child:
				count += _collect_and_strip_tscn(child, path)
		elif entry.ends_with(".tscn"):
			if _strip_one_tscn(path):
				count += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return count


func _strip_one_tscn(res_path: String) -> bool:
	var text := FileAccess.get_file_as_string(res_path)
	if text.is_empty():
		return false
	var removed_ids: PackedStringArray = []
	var lines: PackedStringArray = text.split("\n")
	var out: PackedStringArray = []
	var changed := false
	for line in lines:
		var trimmed := line.strip_edges()
		if (
			trimmed.begins_with("[ext_resource type=\"Material\"")
			and "/mat_" in trimmed
			and ".tres" in trimmed
		):
			var id_start := trimmed.find("id=\"")
			if id_start >= 0:
				var id_end := trimmed.find("\"", id_start + 4)
				if id_end > id_start:
					removed_ids.append(trimmed.substr(id_start + 4, id_end - id_start - 4))
			changed = true
			continue
		if "ExtResource(" in trimmed:
			var skip_line := false
			for id in removed_ids:
				if trimmed.contains("ExtResource(\"%s\")" % id):
					skip_line = true
					break
			if skip_line:
				changed = true
				continue
		out.append(line)
	if not changed:
		return false
	var joined := "\n".join(out)
	if "load_steps=" in joined:
		var ext_count := 0
		var sub_count := 0
		for line in out:
			if line.begins_with("[ext_resource"):
				ext_count += 1
			elif line.begins_with("[sub_resource"):
				sub_count += 1
		var new_steps := ext_count + sub_count + 1
		var old_steps := _load_steps_token(joined)
		if old_steps != "":
			joined = joined.replace(old_steps, "load_steps=%d" % new_steps)
	FileAccess.open(res_path, FileAccess.WRITE).store_string(joined)
	return true


func _load_steps_token(text: String) -> String:
	var idx := text.find("load_steps=")
	if idx < 0:
		return ""
	var end := idx
	while end < text.length() and text[end] != " " and text[end] != "]":
		end += 1
	return text.substr(idx, end - idx)


func _delete_mat_tres_files() -> int:
	var count := 0
	var dir := DirAccess.open(ASSETS_ROOT)
	if dir == null:
		return 0
	count += _delete_mat_tres_in_dir(dir, ASSETS_ROOT)
	return count


func _delete_mat_tres_in_dir(dir: DirAccess, prefix: String) -> int:
	var count := 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var path := "%s/%s" % [prefix, entry]
		if dir.current_is_dir():
			var child := DirAccess.open(path)
			if child:
				count += _delete_mat_tres_in_dir(child, path)
		elif entry.begins_with("mat_") and entry.ends_with(".tres"):
			var abs := ProjectSettings.globalize_path(path)
			if DirAccess.remove_absolute(abs) == OK:
				count += 1
			var import_path := abs + ".import"
			if FileAccess.file_exists(import_path):
				DirAccess.remove_absolute(import_path)
		entry = dir.get_next()
	dir.list_dir_end()
	return count


func _generate_castle_tiles_atlas() -> bool:
	var palette := _load_palette_json_direct()
	var castle: Dictionary = palette.get("palettes", {}).get("castle", {})
	if castle.is_empty():
		push_error("castle palette missing")
		return false
	var colors: Array[Color] = [
		Color.html(str(castle.get("floor_base", "#595261"))),
		Color.html(str(castle.get("floor_shadow", "#3d3847"))),
		Color.html(str(castle.get("wall_base", "#383347"))),
		Color.html(str(castle.get("wall_shadow", "#241f2e"))),
		Color.html(str(castle.get("accent", "#8c6b47"))),
		Color.html(str(castle.get("prop_wood", "#6b4d2e"))),
		Color.html(str(castle.get("prop_metal", "#7a7580"))),
		Color.html(str(castle.get("emissive", "#ff9e47"))),
	]
	var dir_path := ProjectSettings.globalize_path("res://assets/textures/castle")
	DirAccess.make_dir_recursive_absolute(dir_path)
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(colors[0])
	var tile := 32
	for row in 8:
		for col in 8:
			var variant := (row * 3 + col) % colors.size()
			var base := colors[variant]
			var shadow := base.darkened(0.22)
			for y in tile:
				for x in tile:
					var px := col * tile + x
					var py := row * tile + y
					var checker := int((x / 4 + y / 4 + row + col) % 2)
					var c := shadow if checker == 0 else base
					if x < 2 or y < 2 or x >= tile - 2 or y >= tile - 2:
						c = c.darkened(0.15)
					image.set_pixel(px, py, c)
	var out_path := "%s/tiles.png" % dir_path
	return image.save_png(out_path) == OK


func _load_palette_json_direct() -> Dictionary:
	var root := ProjectSettings.globalize_path("res://").path_join("../../..")
	var path := root.path_join("content/art/palettes.json")
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("missing palettes.json at %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
