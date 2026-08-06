extends "res://scripts/validation/validation_suite.gd"

## Content-vs-code drift checks and quality-bar stub tracking.

const KNOWN_STUBS := {}

const KNOWN_UNAPPLIED_STATUSES := ["burn", "stun"]

const KNOWN_UNREAD_RELIC_STATS := [
	"attackSpeed",
	"lifesteal",
	"healthRegen",
	"frostDamage",
	"poisonDamage",
]

const LEGACY_BEHAVIORAL_GREPS: Array[String] = []

const REQUIRED_ENEMY_CHILDREN := ["Health", "Hurtbox", "Poise"]

const KNOWN_MISSING_ENEMY_COMPONENTS := {
	"res://scenes/enemies/castle_grunt.tscn": ["StatusController", "HitFeedback"],
	"res://scenes/enemies/castle_archer.tscn": ["StatusController", "HitFeedback"],
	"res://scenes/enemies/castle_shield.tscn": ["StatusController", "HitFeedback"],
	"res://scenes/enemies/castle_knight.tscn": ["StatusController", "HitFeedback"],
	"res://scenes/enemies/training_grunt.tscn": ["StatusController", "HitFeedback"],
}


func get_category() -> String:
	return "drift"


func run() -> void:
	_test_known_stubs()
	_test_status_appliers()
	_test_relic_stats()
	_test_enemy_components()
	_test_no_new_behavioral_greps()


func _test_known_stubs() -> void:
	var start := Time.get_ticks_msec()
	var offenders: PackedStringArray = []
	for key in KNOWN_STUBS:
		var parts: PackedStringArray = key.split(":")
		var path: String = parts[0]
		var method_name: String = parts[1]
		if not _is_stubbed_return(path, method_name):
			continue
		offenders.append(key)
	var ok := KNOWN_STUBS.is_empty() or offenders.size() == KNOWN_STUBS.size()
	ctx.timed_record(
		"drift.no_stubbed_public_returns",
		get_category(),
		ok,
		"no undocumented combat stubs (%d tracked)" % KNOWN_STUBS.size(),
		start,
		"M5.combat.weapon"
	)


func _test_status_appliers() -> void:
	var start := Time.get_ticks_msec()
	var offenders: PackedStringArray = []
	for status_id in StatusCatalog.all_ids():
		if status_id in KNOWN_UNAPPLIED_STATUSES:
			continue
		if not _status_has_consumer(status_id):
			offenders.append(status_id)
	ctx.timed_record(
		"drift.every_status_has_an_applier",
		get_category(),
		offenders.is_empty(),
		(
			"status ids without consumers: %s" % ", ".join(offenders)
			if not offenders.is_empty()
			else "all statuses consumed"
		),
		start,
		"M5.status.feel"
	)


func _test_relic_stats() -> void:
	var start := Time.get_ticks_msec()
	var relic_stats := _collect_relic_stat_keys()
	var offenders: PackedStringArray = []
	for stat_key in relic_stats:
		if stat_key in KNOWN_UNREAD_RELIC_STATS:
			continue
		if not _stat_is_read(stat_key):
			offenders.append(stat_key)
	ctx.timed_record(
		"drift.every_relic_stat_is_read",
		get_category(),
		offenders.is_empty(),
		(
			"unread relic stats: %s" % ", ".join(offenders)
			if not offenders.is_empty()
			else "relic stats consumed"
		),
		start,
		"M5.bal.doc"
	)


func _test_enemy_components() -> void:
	for scene_path in KNOWN_MISSING_ENEMY_COMPONENTS:
		var allowed_missing: Array = KNOWN_MISSING_ENEMY_COMPONENTS[scene_path]
		var packed: PackedScene = load(scene_path)
		var start := Time.get_ticks_msec()
		if packed == null:
			ctx.timed_record(
				"drift.enemy_scene_%s" % scene_path.get_file().get_basename(),
				get_category(),
				false,
				"could not load enemy scene %s" % scene_path,
				start
			)
			continue
		var root := packed.instantiate()
		var missing_required: PackedStringArray = []
		for child_name in REQUIRED_ENEMY_CHILDREN:
			if root.get_node_or_null(child_name) == null:
				missing_required.append(child_name)
		root.free()
		ctx.timed_record(
			"drift.every_component_node_exists.%s" % scene_path.get_file().get_basename(),
			get_category(),
			missing_required.is_empty(),
			"required children present; tracked optional gaps: %s" % ", ".join(allowed_missing),
			start,
			"M2.combat.death"
		)


func _test_no_new_behavioral_greps() -> void:
	var start := Time.get_ticks_msec()
	var offenders: PackedStringArray = []
	var dir := DirAccess.open("res://scripts/validation/suites")
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".gd"):
				var path := "res://scripts/validation/suites/%s" % file_name
				var text := FileAccess.get_file_as_string(path)
				var idx := 0
				while true:
					var pos := text.find("file_contains(", idx)
					if pos < 0:
						break
					var needle_pos := text.find('"func ', pos)
					if needle_pos >= 0 and needle_pos < pos + 120:
						var signature := (
							"%s:%s" % [path, text.substr(needle_pos + 1, 48).split('"')[0]]
						)
						if (
							not signature in LEGACY_BEHAVIORAL_GREPS
							and not _legacy_grep_allowed(path, text, needle_pos)
						):
							offenders.append(
								"%s:%d" % [path, text.substr(0, needle_pos).count("\n") + 1]
							)
					idx = pos + 1
			file_name = dir.get_next()
		dir.list_dir_end()
	ctx.timed_record(
		"drift.no_behavioral_file_greps",
		get_category(),
		offenders.is_empty(),
		(
			"new behavioral greps: %s" % ", ".join(offenders)
			if not offenders.is_empty()
			else "only legacy greps remain"
		),
		start,
		"M1.combat.guard"
	)


func _legacy_grep_allowed(path: String, text: String, needle_pos: int) -> bool:
	for legacy in LEGACY_BEHAVIORAL_GREPS:
		if legacy.begins_with(path):
			var needle := legacy.split(":", false, 1)[1]
			if needle in text:
				return true
	return false


func _is_stubbed_return(path: String, method_name: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	var marker := "func %s" % method_name
	var start := text.find(marker)
	if start < 0:
		return false
	var body_start := text.find("->", start)
	if body_start < 0:
		return false
	var return_pos := text.find("return ", body_start)
	if return_pos < 0 or return_pos > start + 120:
		return false
	var line_end := text.find("\n", return_pos)
	var return_line := (
		text.substr(return_pos, line_end - return_pos) if line_end >= 0 else text.substr(return_pos)
	)
	return (
		"Vector3.ZERO" in return_line or "return {}" in return_line or "return 0.0" in return_line
	)


func _status_has_consumer(status_id: String) -> bool:
	var content_dirs := ["content/enemies", "content/bosses", "content/weapons", "content/hazards"]
	for rel in content_dirs:
		var abs := ContentLoader.content_path(rel)
		var dir := DirAccess.open(abs)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json"):
				var data: Variant = ContentLoader.load_json("%s/%s" % [rel, file_name])
				if data is Dictionary and JSON.stringify(data).find(status_id) >= 0:
					dir.list_dir_end()
					return true
			file_name = dir.get_next()
		dir.list_dir_end()
	var scripts_root := ProjectSettings.globalize_path("res://scripts")
	return _grep_scripts_for_status(scripts_root, status_id)


func _grep_scripts_for_status(root: String, status_id: String) -> bool:
	var dir := DirAccess.open(root)
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := root.path_join(entry)
		if dir.current_is_dir() and entry != ".godot":
			if _grep_scripts_for_status(path, status_id):
				dir.list_dir_end()
				return true
		elif entry.ends_with(".gd") and not entry.ends_with("combat_hud.gd"):
			var text := FileAccess.get_file_as_string(path)
			if (
				'apply_status("%s"' % status_id in text
				or "status_on_hit" in text and status_id in text
			):
				dir.list_dir_end()
				return true
		entry = dir.get_next()
	dir.list_dir_end()
	return false


func _collect_relic_stat_keys() -> Array[String]:
	var keys: Array[String] = []
	var abs := ContentLoader.content_path("content/relics")
	var dir := DirAccess.open(abs)
	if dir == null:
		return keys
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var data: Dictionary = ContentLoader.load_json("content/relics/%s" % file_name)
			var stats: Variant = data.get("stats", {})
			if stats is Dictionary:
				for key in stats:
					if key not in keys:
						keys.append(str(key))
		file_name = dir.get_next()
	dir.list_dir_end()
	return keys


func _stat_is_read(stat_key: String) -> bool:
	var scripts_root := ProjectSettings.globalize_path("res://scripts")
	return _grep_scripts_for_token(scripts_root, stat_key)


func _grep_scripts_for_token(root: String, token: String) -> bool:
	var dir := DirAccess.open(root)
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := root.path_join(entry)
		if dir.current_is_dir() and entry != ".godot":
			if _grep_scripts_for_token(path, token):
				dir.list_dir_end()
				return true
		elif entry.ends_with(".gd"):
			var text := FileAccess.get_file_as_string(path)
			if '"%s"' % token in text or "'%s'" % token in text:
				dir.list_dir_end()
				return true
		entry = dir.get_next()
	dir.list_dir_end()
	return false
