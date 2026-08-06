extends "res://scripts/validation/validation_suite.gd"

## Documentation path and link integrity for validation suites.

const DOC_ROOTS := [
	"docs",
]


func get_category() -> String:
	return "docs"


func run() -> void:
	_test_referenced_paths_exist()
	_test_relative_links_resolve()
	_test_manual_checklist_exists()


func _test_referenced_paths_exist() -> void:
	var start := Time.get_ticks_msec()
	var missing: PackedStringArray = []
	for path in _collect_suite_doc_paths():
		if not FileAccess.file_exists(path):
			missing.append(path)
	ctx.timed_record(
		"docs.referenced_paths_exist",
		get_category(),
		missing.is_empty(),
		(
			"missing referenced docs: %s" % ", ".join(missing)
			if not missing.is_empty()
			else "all suite doc paths exist"
		),
		start,
		"M4.flow.economy"
	)


func _test_relative_links_resolve() -> void:
	var start := Time.get_ticks_msec()
	var broken: PackedStringArray = []
	for rel_root in DOC_ROOTS:
		var abs_root: String = ctx.repo_root().path_join(rel_root)
		_collect_broken_links(abs_root, broken)
	ctx.timed_record(
		"docs.relative_links_resolve",
		get_category(),
		broken.is_empty(),
		(
			"broken doc links: %s" % ", ".join(broken)
			if not broken.is_empty()
			else "doc links resolve"
		),
		start,
		"M7.ship.manual_checklist"
	)


func _test_manual_checklist_exists() -> void:
	var start := Time.get_ticks_msec()
	var path: String = ctx.repo_root().path_join("docs/validation/manual-checklist.md")
	var ok := FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).length() > 0
	ctx.timed_record(
		"docs.checklist_refs_resolve",
		get_category(),
		ok,
		"manual checklist present for checklist_ref headings",
		start,
		"M7.ship.manual_checklist"
	)
	if not ok:
		return
	var missing: PackedStringArray = []
	for ref in _collect_checklist_refs_from_suites():
		if not ValidationHelpers.checklist_heading_exists(ref):
			missing.append(ref)
	start = Time.get_ticks_msec()
	ctx.timed_record(
		"docs.checklist_headings_resolve",
		get_category(),
		missing.is_empty(),
		(
			"unresolved checklist_ref headings: %s" % ", ".join(missing)
			if not missing.is_empty()
			else "all checklist_ref headings resolve"
		),
		start,
		"M7.ship.manual_checklist"
	)


func _collect_checklist_refs_from_suites() -> PackedStringArray:
	var refs: PackedStringArray = []
	var dir := DirAccess.open("res://scripts/validation/suites")
	if dir == null:
		return refs
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".gd"):
			var text := FileAccess.get_file_as_string(
				"res://scripts/validation/suites/%s" % file_name
			)
			var idx := 0
			while true:
				var pos := text.find("checklist_ref", idx)
				if pos < 0:
					break
				var quote := text.find('"', pos)
				if quote < 0:
					break
				var end := text.find('"', quote + 1)
				if end < 0:
					break
				var ref := text.substr(quote + 1, end - quote - 1)
				if ref != "" and ref not in refs:
					refs.append(ref)
				idx = end + 1
		file_name = dir.get_next()
	dir.list_dir_end()
	return refs


func _collect_suite_doc_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open("res://scripts/validation/suites")
	if dir == null:
		return paths
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".gd"):
			var text := FileAccess.get_file_as_string(
				"res://scripts/validation/suites/%s" % file_name
			)
			for token in ["docs/validation/"]:
				var idx := 0
				while true:
					var pos := text.find(token, idx)
					if pos < 0:
						break
					var end: int = pos + token.length()
					while end < text.length() and text[end] not in ['"', "'", ")", " ", "\n", "\t"]:
						end += 1
					var rel := text.substr(pos, end - pos)
					var abs: String = ctx.repo_root().path_join(rel)
					if abs not in paths:
						paths.append(abs)
					idx = pos + 1
		file_name = dir.get_next()
	dir.list_dir_end()
	return paths


func _collect_broken_links(abs_root: String, broken: PackedStringArray) -> void:
	var dir := DirAccess.open(abs_root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := abs_root.path_join(entry)
		if dir.current_is_dir():
			_collect_broken_links(path, broken)
		elif entry.ends_with(".md"):
			var text := FileAccess.get_file_as_string(path)
			var idx := 0
			while true:
				var pos := text.find("](", idx)
				if pos < 0:
					break
				var close := text.find(")", pos + 2)
				if close < 0:
					break
				var target := text.substr(pos + 2, close - pos - 2).split("#")[0]
				if target.begins_with("http"):
					idx = close + 1
					continue
				var resolved := path.get_base_dir().path_join(target).simplify_path()
				if not FileAccess.file_exists(resolved):
					broken.append("%s -> %s" % [path, target])
				idx = close + 1
		entry = dir.get_next()
	dir.list_dir_end()
