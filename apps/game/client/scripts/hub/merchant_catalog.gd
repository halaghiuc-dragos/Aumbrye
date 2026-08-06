extends RefCounted
class_name MerchantCatalog

## Merchant stock definitions from content/merchant/ (HUB-4.3).

const MERCHANT_DIR := "content/merchant"

static var _stocks: Dictionary = {}
static var _loaded := false


static func get_stock(merchant_id: String) -> Array:
	_ensure_loaded()
	var entry: Variant = _stocks.get(merchant_id, [])
	return entry if entry is Array else []


static func has_merchant(merchant_id: String) -> bool:
	_ensure_loaded()
	return _stocks.has(merchant_id)


static func reload() -> void:
	_stocks.clear()
	_loaded = false
	_ensure_loaded()


static func is_loaded() -> bool:
	return _loaded


static func _ensure_loaded() -> void:
	if _loaded:
		return
	var abs_dir := ContentLoader.content_path(MERCHANT_DIR)
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		push_warning("MerchantCatalog: missing directory %s" % abs_dir)
		_loaded = true
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var data: Dictionary = ContentLoader.load_json("%s/%s" % [MERCHANT_DIR, file_name])
			var merchant_id: String = data.get("id", "")
			if merchant_id != "":
				_stocks[merchant_id] = data.get("items", [])
		file_name = dir.get_next()
	dir.list_dir_end()
	_loaded = true
