extends "res://scripts/validation/validation_suite.gd"

const AccessibilitySettingsScript := preload("res://scripts/accessibility/accessibility_settings.gd")


func get_category() -> String:
	return "ui"


func run() -> void:
	_test_manifest_schema()
	_test_cells_in_bounds()
	_test_no_orphan_cells()
	_test_covers_all_statuses()
	_test_polarity_present()
	_test_atlas_texture_shared()
	_test_freeze_distinct()
	_test_no_plotter()
	_test_unknown_warns()
	_test_icon_size_shared()
	_test_colorblind_variant()
	_test_polarity_frames()


func _test_manifest_schema() -> void:
	var start := Time.get_ticks_msec()
	var manifest := ContentLoader.load_json("content/ui/status_icon_atlas.json")
	var ok := (
		int(manifest.get("schemaVersion", 0)) == 1
		and not str(manifest.get("texture", "")).is_empty()
		and manifest.has("cellSize")
		and manifest.has("columns")
		and manifest.has("rows")
		and manifest.get("cells", {}) is Dictionary
	)
	ctx.timed_record(
		"content.status_atlas_schema",
		"content",
		ok,
		"status icon atlas manifest matches status-icon-atlas.v1.json shape",
		start,
		"SIA-01"
	)


func _test_cells_in_bounds() -> void:
	var start := Time.get_ticks_msec()
	var manifest := ContentLoader.load_json("content/ui/status_icon_atlas.json")
	var cell_size := int(manifest.get("cellSize", 16))
	var columns := int(manifest.get("columns", 0))
	var rows := int(manifest.get("rows", 0))
	var texture_path := str(manifest.get("texture", ""))
	var ok := columns > 0 and rows > 0
	if ok and ResourceLoader.exists(texture_path):
		var tex := load(texture_path) as Texture2D
		if tex:
			ok = columns * cell_size == tex.get_width() and rows * cell_size == tex.get_height()
	var cells: Dictionary = manifest.get("cells", {})
	for cell_id in cells.keys():
		var entry: Dictionary = cells[cell_id]
		if int(entry.get("col", -1)) >= columns or int(entry.get("row", -1)) >= rows:
			ok = false
	ctx.timed_record(
		"content.status_atlas_cells_in_bounds",
		"content",
		ok,
		"status atlas cells fit manifest grid and texture dimensions",
		start,
		"SIA-08"
	)


func _test_no_orphan_cells() -> void:
	var start := Time.get_ticks_msec()
	var manifest := ContentLoader.load_json("content/ui/status_icon_atlas.json")
	var cells: Dictionary = manifest.get("cells", {})
	var ok := true
	for cell_id in cells.keys():
		if cell_id == "unknown" or str(cell_id).begins_with("frame_"):
			continue
		if not FileAccess.file_exists(
			ContentLoader.content_path("content/statuses/%s.json" % cell_id)
		):
			ok = false
	ctx.timed_record(
		"content.status_atlas_no_orphan_cells",
		"content",
		ok,
		"every manifest status cell has a content/statuses file",
		start,
		"SIA-06"
	)


func _test_covers_all_statuses() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for file_name in DirAccess.get_files_at(ContentLoader.content_path("content/statuses")):
		if not file_name.ends_with(".json"):
			continue
		if not StatusIconAtlas.has_icon(file_name.get_basename()):
			ok = false
	ctx.timed_record(
		"content.status_atlas_covers_all",
		"content",
		ok,
		"every authored status has an atlas cell",
		start,
		"SIA-02"
	)


func _test_polarity_present() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for file_name in DirAccess.get_files_at(ContentLoader.content_path("content/statuses")):
		if not file_name.ends_with(".json"):
			continue
		var def: Dictionary = ContentLoader.load_json("content/statuses/%s" % file_name)
		var polarity := str(def.get("polarity", ""))
		if polarity != "buff" and polarity != "debuff":
			ok = false
	ctx.timed_record(
		"content.status_polarity_present",
		"content",
		ok,
		"every status file declares polarity buff or debuff",
		start,
		"SIA-04"
	)


func _test_atlas_texture_shared() -> void:
	var start := Time.get_ticks_msec()
	var burn_icon := StatusIconAtlas.get_icon("burn")
	var poison_icon := StatusIconAtlas.get_icon("poison")
	var ok := burn_icon is AtlasTexture and poison_icon is AtlasTexture
	if ok:
		ok = burn_icon.atlas == poison_icon.atlas
	ctx.timed_record(
		"ui.status_atlas_is_atlas",
		get_category(),
		ok,
		"status icons share one AtlasTexture source",
		start,
		"SIA-01"
	)


func _test_freeze_distinct() -> void:
	var start := Time.get_ticks_msec()
	var burn_icon := StatusIconAtlas.get_icon("burn")
	var freeze_icon := StatusIconAtlas.get_icon("freeze")
	var unknown_icon := StatusIconAtlas.get_icon("unknown")
	var ok := (
		burn_icon is AtlasTexture
		and freeze_icon is AtlasTexture
		and unknown_icon is AtlasTexture
		and freeze_icon.region != burn_icon.region
		and freeze_icon.region != unknown_icon.region
	)
	ctx.timed_record(
		"ui.status_atlas_freeze_distinct",
		get_category(),
		ok,
		"freeze icon region differs from burn and unknown",
		start,
		"SIA-02"
	)


func _test_no_plotter() -> void:
	var start := Time.get_ticks_msec()
	var ok := not ctx.file_contains("res://scripts/ui/status_icon_atlas.gd", "set_pixel")
	ctx.timed_record(
		"ui.status_atlas_no_plotter",
		get_category(),
		ok,
		"status icon atlas has no procedural set_pixel renderer",
		start,
		"SIA-01"
	)


func _test_unknown_warns() -> void:
	var start := Time.get_ticks_msec()
	var ok := not StatusIconAtlas.has_icon("zzz")
	var unknown_icon := StatusIconAtlas.get_icon("zzz")
	var known_unknown := StatusIconAtlas.get_icon("unknown")
	if ok and unknown_icon is AtlasTexture and known_unknown is AtlasTexture:
		ok = unknown_icon.region == known_unknown.region
	ctx.timed_record(
		"ui.status_atlas_unknown_warns",
		get_category(),
		ok,
		"missing status id resolves to unknown atlas region",
		start,
		"SIA-09"
	)


func _test_icon_size_shared() -> void:
	var start := Time.get_ticks_msec()
	var ok := ctx.file_contains("res://scripts/ui/combat_hud.gd", "StatusIconAtlas.icon_size()")
	ok = ok and not ctx.file_contains("res://scripts/ui/combat_hud.gd", "Vector2(22, 22)")
	ctx.timed_record(
		"ui.status_atlas_size_shared",
		get_category(),
		ok,
		"combat HUD sizes status icons from StatusIconAtlas.icon_size()",
		start,
		"SIA-08"
	)


func _test_colorblind_variant() -> void:
	var start := Time.get_ticks_msec()
	AccessibilitySettingsScript.colorblind_mode = "protanopia"
	StatusIconAtlas.reload()
	var cb_icon := StatusIconAtlas.get_icon("burn")
	var ok := cb_icon is AtlasTexture and cb_icon.atlas != null
	if ok:
		ok = str(cb_icon.atlas.resource_path).ends_with("status_icons_cb.png")
	AccessibilitySettingsScript.colorblind_mode = "default"
	StatusIconAtlas.reload()
	ctx.timed_record(
		"ui.status_atlas_cb_variant",
		get_category(),
		ok,
		"colorblind mode loads status_icons_cb.png atlas texture",
		start,
		"SIA-05"
	)


func _test_polarity_frames() -> void:
	var start := Time.get_ticks_msec()
	var buff_frame := StatusIconAtlas.get_polarity_frame("buff")
	var debuff_frame := StatusIconAtlas.get_polarity_frame("debuff")
	var ok := (
		buff_frame is AtlasTexture
		and debuff_frame is AtlasTexture
		and buff_frame.region != debuff_frame.region
	)
	ctx.timed_record(
		"ui.status_atlas_polarity_frames",
		get_category(),
		ok,
		"buff and debuff polarity frames use distinct atlas regions",
		start,
		"SIA-04"
	)
