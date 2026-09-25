extends Node

## Checks that every icon the UI asks for actually resolves to artwork.
##
## The icon sheets are generated (tools/icon-gen/atlas_build.py) and the code reads them through
## manifests, so the two can drift apart without anything failing loudly: a missing cell just
## quietly renders the "?" marker, and a cell whose coordinates fall off the end of the texture
## renders nothing at all. Both of those look like an art problem in play and are a data problem
## in fact, which is what this scene is for.
##
## Run: godot --path apps/game/client --headless res://scenes/debug/icon_atlas_audit.tscn

const ItemIconAtlasScript := preload("res://scripts/ui/item_icon_atlas.gd")
const StatusIconAtlasScript := preload("res://scripts/ui/status_icon_atlas.gd")

const MINIMAP_ATLAS_PATH := "res://assets/ui/minimap_icons.png"
const MinimapScript := preload("res://scripts/ui/minimap.gd")

var _failures: int = 0


func _ready() -> void:
	await get_tree().process_frame
	_audit_items()
	_audit_statuses()
	_audit_minimap()
	_audit_minimap_state()
	print("ICON AUDIT RESULT %d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL %s" % message)


func _audit_items() -> void:
	var atlas := UISymbolAtlas.shared("content/ui/item_icon_atlas.json")
	var keys := atlas.keys()
	var checked := 0
	for key in keys:
		if not _region_is_drawn(atlas, key, "item"):
			continue
		checked += 1
	# Every equipment slot needs its empty-socket hint, or the paperdoll shows a hole.
	for slot in ["weapon", "secondary", "helmet", "chest", "gloves", "boots", "ring", "amulet"]:
		if not atlas.has_cell("slot/%s" % slot):
			_fail("item atlas has no slot hint for '%s'" % slot)
	# There is deliberately no fallback cell: coverage is guaranteed when the sheet is built, so
	# the presence of one would only hide a data bug.
	if atlas.has_cell("unknown"):
		_fail("item atlas still carries a placeholder 'unknown' cell")
	print("ITEM ATLAS %d cells, %d drawn" % [keys.size(), checked])


func _audit_statuses() -> void:
	for texture_override in ["", StatusIconAtlasScript.CB_TEXTURE_PATH]:
		var label := "colourblind" if texture_override != "" else "default"
		var atlas := UISymbolAtlas.shared("content/ui/status_icon_atlas.json", texture_override)
		var drawn := 0
		# The catalog is the list the game can actually apply, so it is the list that must be
		# drawable -- on both sheets. Half the colourblind sheet used to be empty cells.
		for status_id in _status_ids():
			if not atlas.has_cell(status_id):
				_fail("%s status sheet has no cell for '%s'" % [label, status_id])
				continue
			if _region_is_drawn(atlas, status_id, "%s status" % label):
				drawn += 1
		if atlas.has_cell("unknown"):
			_fail("%s status sheet still carries a placeholder 'unknown' cell" % label)
		for frame_key in ["frame_buff", "frame_debuff"]:
			if not atlas.has_cell(frame_key):
				_fail("%s status sheet has no '%s' cell" % [label, frame_key])
			else:
				_region_is_drawn(atlas, frame_key, "%s status" % label)
		print("STATUS ATLAS (%s) %d statuses drawn" % [label, drawn])


## The statuses the game can actually apply, read off the content tree rather than off a list kept
## in this file, so a status added later is audited without anyone remembering to come back here.
func _status_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	var dir := DirAccess.open(ContentLoader.content_path("content/statuses"))
	if dir == null:
		_fail("cannot read content/statuses")
		return ids
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			ids.append(file_name.get_basename())
	ids.sort()
	return ids


func _audit_minimap() -> void:
	var texture := load(MINIMAP_ATLAS_PATH) as Texture2D
	if texture == null:
		_fail("minimap atlas missing at %s" % MINIMAP_ATLAS_PATH)
		return
	var image := texture.get_image()
	var cell: int = MinimapScript.ICON_CELL
	var drawn := 0
	for kind: String in MinimapScript.KIND_CELLS.keys():
		var at: Vector2i = MinimapScript.KIND_CELLS[kind]
		var rect := Rect2i(at.x * cell, at.y * cell, cell, cell)
		if not Rect2i(0, 0, image.get_width(), image.get_height()).encloses(rect):
			_fail("minimap cell for '%s' is off the texture" % kind)
			continue
		if _opaque_pixels(image, rect) == 0:
			_fail("minimap cell for '%s' is blank" % kind)
			continue
		drawn += 1
	print("MINIMAP ATLAS %d of %d kinds drawn" % [drawn, MinimapScript.KIND_CELLS.size()])


func _audit_minimap_state() -> void:
	var minimap := MinimapScript.new()
	minimap.configure({
		"rooms": [
			{"id": "known", "kind": "combat", "transform": {"x": 0.0, "z": 0.0}, "size": {"x": 4.0, "z": 4.0}},
			{"id": "neighbor", "kind": "stairs", "transform": {"x": 8.0, "z": 0.0}, "size": {"x": 4.0, "z": 4.0}},
		],
		"edges": [{"from": "known", "to": "neighbor", "oneWay": "down"}],
	})
	if minimap.toggle_manual_pin("neighbor"):
		_fail("map allowed pinning an undiscovered room")
	minimap.mark_visited("known")
	if minimap.get_reveal_tier("neighbor") != MinimapScript.RevealTier.SEEN:
		_fail("visiting a room did not reveal its connected exit")
	if not minimap.toggle_manual_pin("known") or not minimap.is_manually_pinned("known"):
		_fail("visited room could not be manually pinned")
	minimap.mark_cleared("known")
	var state: Dictionary = minimap.export_state()
	var serialized_discovery := JSON.stringify(minimap.export_discovery_state())
	var restored := MinimapScript.new()
	restored.configure({
		"rooms": [
			{"id": "known", "kind": "combat", "transform": {"x": 0.0, "z": 0.0}, "size": {"x": 4.0, "z": 4.0}},
			{"id": "neighbor", "kind": "stairs", "transform": {"x": 8.0, "z": 0.0}, "size": {"x": 4.0, "z": 4.0}},
		],
		"edges": [{"from": "known", "to": "neighbor", "oneWay": "down"}],
	})
	var decoded_discovery: Variant = JSON.parse_string(serialized_discovery)
	if decoded_discovery is Dictionary:
		restored.import_discovery_state(decoded_discovery)
	else:
		_fail("map discovery snapshot did not survive JSON serialization")
	if not restored.is_manually_pinned("known"):
		_fail("manual pin did not survive map export/import")
	if restored.get_reveal_tier("known") != MinimapScript.RevealTier.VISITED:
		_fail("discovery state did not survive map export/import")
	if restored.reveal_landmark_room("neighbor") != true:
		_fail("authored landmark could not reveal its known destination")
	if restored.get_reveal_tier("neighbor") != MinimapScript.RevealTier.SEEN:
		_fail("landmark revealed a destination without keeping it at outline-only SEEN")
	if restored.reveal_landmark_room("unknown_save_id"):
		_fail("landmark revealed an unknown destination ID")
	if restored.get_reveal_tier("known") != MinimapScript.RevealTier.VISITED:
		_fail("landmark reveal downgraded a visited room")
	if not restored.toggle_manual_pin("known") or restored.is_manually_pinned("known"):
		_fail("manual pin could not be toggled off")
	var overlay := MinimapScript.new()
	overlay.import_state(state)
	if not overlay.toggle_manual_pin("known"):
		_fail("overlay map could not toggle a visited-room pin")
	minimap.import_discovery_state(overlay.export_discovery_state())
	if minimap.is_manually_pinned("known"):
		_fail("overlay pin removal could not be merged back into the HUD map")
	if not overlay.toggle_manual_pin("known"):
		_fail("overlay map could not restore a visited-room pin")
	minimap.import_discovery_state(overlay.export_discovery_state())
	if not minimap.is_manually_pinned("known"):
		_fail("overlay pin addition could not be merged back into the HUD map")
	minimap.import_discovery_state({
		"reveal": {"unknown_save_id": MinimapScript.RevealTier.VISITED},
		"manual_pins": {"unknown_save_id": true},
	})
	if minimap.get_reveal_tier("unknown_save_id") != MinimapScript.RevealTier.UNKNOWN:
		_fail("map discovery import trusted an unknown saved room ID")
	minimap.free()
	restored.free()
	overlay.free()
	print("MINIMAP STATE manual pin, discovery, landmark outline, neighbor reveal, persistence checked")


## A cell that resolves but contains nothing renders as a hole, which is the failure the sheets
## kept shipping. Checking the pixels is the only way to catch it.
func _region_is_drawn(atlas: UISymbolAtlas, key: String, label: String) -> bool:
	var tex := atlas.cell(key)
	if tex == null or tex.atlas == null:
		_fail("%s cell '%s' has no texture" % [label, key])
		return false
	var image := tex.atlas.get_image()
	var rect := Rect2i(tex.region)
	if not Rect2i(0, 0, image.get_width(), image.get_height()).encloses(rect):
		_fail("%s cell '%s' region %s falls outside the texture" % [label, key, rect])
		return false
	if _opaque_pixels(image, rect) == 0:
		_fail("%s cell '%s' is blank" % [label, key])
		return false
	return true


func _opaque_pixels(image: Image, rect: Rect2i) -> int:
	var count := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count
