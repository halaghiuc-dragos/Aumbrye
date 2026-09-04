extends RefCounted
class_name EnemyIntentGlyphAtlas

## Modelled on `HudIconAtlas`: a manifest of pixel regions cut from one shared texture, loaded once
## and cached as `AtlasTexture`s. See `content/ui/intent_atlas.json`.

const MANIFEST_PATH := "content/ui/intent_atlas.json"

## `EN-01`'s four attack classes, each with its own glyph. `grab` shares no colour with the other
## three under `AccessibilitySettings.get_telegraph_class_color()` (it falls to the same default as
## `blockable`), so the hand shape is what actually distinguishes it -- shape carries the message
## colour alone cannot.
const CELL_FOR_CLASS := {
	"blockable": "sword",
	"unblockable": "shield_break",
	"parryable": "parry_star",
	"grab": "hand",
}

static var _manifest: Dictionary = {}
static var _source: Texture2D
static var _cache: Dictionary = {}
static var _loaded := false


static func get_glyph_for_class(attack_class: String) -> AtlasTexture:
	var cell := str(CELL_FOR_CLASS.get(attack_class, "sword"))
	return _region(cell)


static func _region(cell: String) -> AtlasTexture:
	_ensure_loaded()
	if _cache.has(cell):
		return _cache[cell]
	var entry: Dictionary = _manifest.get(cell, {})
	var tex := AtlasTexture.new()
	tex.atlas = _source
	tex.region = Rect2(
		float(entry.get("x", 0)),
		float(entry.get("y", 0)),
		float(entry.get("w", 16)),
		float(entry.get("h", 16))
	)
	_cache[cell] = tex
	return tex


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_manifest = ContentLoader.load_json(MANIFEST_PATH)
	var texture_path: String = str(_manifest.get("texture", ""))
	if ResourceLoader.exists(texture_path):
		_source = load(texture_path) as Texture2D
	_loaded = true
