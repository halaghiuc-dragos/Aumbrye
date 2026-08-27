class_name LootTableLoader
extends RefCounted


const TABLES_DIR := "content/loot/tables"


static func load_for_biome(biome_id: String) -> Dictionary:
	if biome_id == "":
		return {}
	var path := "%s/%s.json" % [TABLES_DIR, biome_id]
	var data: Dictionary = ContentLoader.load_json(path)
	if data.is_empty():
		return {}
	var tables: Variant = data.get("lootTables", {})
	if tables is Dictionary:
		return (tables as Dictionary).duplicate(true)
	return {}


static func resolve_loot_tables(biome: Dictionary) -> Dictionary:
	var biome_id: String = str(biome.get("id", ""))
	var external := load_for_biome(biome_id)
	if not external.is_empty():
		return external
	var table_path: String = str(biome.get("lootTablePath", ""))
	if table_path != "":
		var data: Dictionary = ContentLoader.load_json(table_path)
		var tables: Variant = data.get("lootTables", {})
		if tables is Dictionary and not (tables as Dictionary).is_empty():
			return (tables as Dictionary).duplicate(true)
	var inline: Variant = biome.get("lootTables", {})
	if inline is Dictionary:
		return (inline as Dictionary).duplicate(true)
	return {}
