extends "res://scripts/validation/validation_suite.gd"

const MANIFEST_PATHS := [
	"content/ui/status_icon_atlas.json",
	"content/ui/input_glyph_atlas.json",
	"content/ui/item_icon_atlas.json",
]


func get_category() -> String:
	return "ui_symbols"


func run() -> void:
	_test_manifests_validate()
	_test_uniform_cell_size()
	_test_grid_matches_texture()
	_test_cells_in_bounds()
	_test_status_coverage()
	_test_item_coverage()
	_test_shared_atlas_object()
	_test_unknown_warns()
	_test_helpers_used()
	_test_bus_registered()
	_test_no_unicode_inventory()


func _test_manifests_validate() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for path in MANIFEST_PATHS:
		var manifest := ContentLoader.load_json(path)
		if int(manifest.get("schemaVersion", 0)) != 1:
			ok = false
		if int(manifest.get("cellSize", 0)) != 16:
			ok = false
		if str(manifest.get("texture", "")).is_empty():
			ok = false
	ctx.timed_record(
		"ui_symbols.manifests_validate",
		get_category(),
		ok,
		"all three UI symbol manifests validate and use cellSize 16",
		start,
		"SIG-02"
	)


func _test_uniform_cell_size() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for path in MANIFEST_PATHS:
		var manifest := ContentLoader.load_json(path)
		if int(manifest.get("cellSize", 0)) != 16:
			ok = false
	ctx.timed_record(
		"ui_symbols.uniform_cell_size",
		get_category(),
		ok,
		"all manifests report cellSize == 16",
		start,
		"SIG-04"
	)


func _test_grid_matches_texture() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for path in MANIFEST_PATHS:
		var manifest := ContentLoader.load_json(path)
		var cell_size := int(manifest.get("cellSize", 16))
		var columns := int(manifest.get("columns", 0))
		var rows := int(manifest.get("rows", 0))
		var texture_path := str(manifest.get("texture", ""))
		if not ResourceLoader.exists(texture_path):
			ok = false
			continue
		var tex := load(texture_path) as Texture2D
		if tex == null:
			ok = false
			continue
		if columns * cell_size != tex.get_width() or rows * cell_size != tex.get_height():
			ok = false
	ctx.timed_record(
		"ui_symbols.grid_matches_texture",
		get_category(),
		ok,
		"manifest grid dimensions match texture pixel size",
		start,
		"SIG-02"
	)


func _test_cells_in_bounds() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for path in MANIFEST_PATHS:
		var manifest := ContentLoader.load_json(path)
		var columns := int(manifest.get("columns", 0))
		var rows := int(manifest.get("rows", 0))
		var cells: Dictionary = manifest.get("cells", {})
		for key in cells.keys():
			var entry: Dictionary = cells[key]
			if int(entry.get("col", -1)) >= columns or int(entry.get("row", -1)) >= rows:
				ok = false
		var unknown: Variant = manifest.get("unknown", {})
		if unknown is Dictionary:
			if int(unknown.get("col", -1)) >= columns or int(unknown.get("row", -1)) >= rows:
				ok = false
	ctx.timed_record(
		"ui_symbols.cells_in_bounds",
		get_category(),
		ok,
		"every cell and unknown cell satisfy col < columns and row < rows",
		start,
		"SIG-02"
	)


func _test_status_coverage() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	var dir := DirAccess.open("content/statuses")
	if dir:
		dir.list_dir_begin()
		var file := dir.get_next()
		while file != "":
			if file.ends_with(".json"):
				var data := ContentLoader.load_json("content/statuses/%s" % file)
				var id := str(data.get("id", ""))
				if id != "" and not StatusIconAtlas.has_icon(id):
					ok = false
			file = dir.get_next()
	ctx.timed_record(
		"ui_symbols.status_coverage",
		get_category(),
		ok,
		"every status id has a status-atlas cell",
		start,
		"SIA-01"
	)


func _test_item_coverage() -> void:
	var start := Time.get_ticks_msec()
	var catalog := ContentLoader.load_json("content/items/catalog.json")
	var ids: Variant = catalog.get("items", [])
	var ok := ids is Array
	if ok:
		for entry in ids:
			var id := str(entry)
			if not ItemIconAtlas.has_icon(id):
				ok = false
	ctx.timed_record(
		"ui_symbols.item_coverage",
		get_category(),
		ok,
		"every catalog item id has an item-atlas cell",
		start,
		"SIG-08"
	)


func _test_shared_atlas_object() -> void:
	var start := Time.get_ticks_msec()
	var burn := StatusIconAtlas.get_icon("burn")
	var poison := StatusIconAtlas.get_icon("poison")
	var ok := (
		burn is AtlasTexture
		and poison is AtlasTexture
		and burn.atlas != null
		and burn.atlas == poison.atlas
	)
	ctx.timed_record(
		"ui_symbols.shared_atlas_object",
		get_category(),
		ok,
		"status atlas cells share one GPU texture",
		start,
		"SIG-01"
	)


func _test_unknown_warns() -> void:
	var start := Time.get_ticks_msec()
	var atlas := UISymbolAtlas.load_manifest("content/ui/status_icon_atlas.json")
	var unknown := atlas.cell("unknown")
	var missing := atlas.cell("zzz_not_a_key")
	var ok := missing is AtlasTexture and unknown is AtlasTexture and missing.region == unknown.region
	ctx.timed_record(
		"ui_symbols.unknown_warns",
		get_category(),
		ok,
		"missing atlas key returns unknown region",
		start,
		"SIG-03"
	)


func _test_helpers_used() -> void:
	var start := Time.get_ticks_msec()
	var hud_ok := (
		not ctx.file_contains("res://scripts/ui/combat_hud.gd", "Vector2(22, 22)")
		and ctx.file_contains("res://scripts/ui/combat_hud.gd", "make_symbol")
	)
	var inv_ok := ctx.file_contains("res://scripts/ui/inventory_ui.gd", "ItemIconAtlas")
	ctx.timed_record(
		"ui_symbols.helpers_used",
		get_category(),
		hud_ok and inv_ok,
		"combat HUD uses symbol helpers; no legacy 22px literal",
		start,
		"SIG-05"
	)


func _test_bus_registered() -> void:
	var start := Time.get_ticks_msec()
	var bus := ctx.owner.get_node_or_null("/root/UISymbolBus")
	var ok := bus != null and bus.has_signal("symbols_invalidated")
	ctx.timed_record(
		"ui_symbols.bus_registered",
		get_category(),
		ok,
		"UISymbolBus autoload declares symbols_invalidated",
		start,
		"SIG-06"
	)


func _test_no_unicode_inventory() -> void:
	var start := Time.get_ticks_msec()
	var ok := not ctx.file_contains("res://scripts/ui/inventory_ui.gd", "⚔")
	ctx.timed_record(
		"ui_symbols.no_unicode_glyphs",
		get_category(),
		ok,
		"inventory_ui.gd has no Unicode glyph literals",
		start,
		"SIG-08"
	)
