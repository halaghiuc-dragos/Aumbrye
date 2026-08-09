extends SceneTree


func _initialize() -> void:
	var Schema := load("res://scripts/ui/settings_schema.gd")
	var keys := {}
	for page in Schema.PAGES:
		keys["SETTINGS_PAGE_%s" % page.to_upper()] = true
		for entry in Schema.entries_for_page(page):
			for field in ["name_key", "desc_key"]:
				var k := str(entry.get(field, ""))
				if k != "":
					keys[k] = true
			for opt in entry.get("options", []):
				if opt is Dictionary:
					var lk := str(opt.get("label_key", opt.get("label", "")))
					if lk != "" and lk == lk.to_upper():
						keys[lk] = true
	var out: Array = keys.keys()
	out.sort()
	print("SCHEMA_KEYS_BEGIN")
	for k in out:
		print(k)
	print("SCHEMA_KEYS_END")
	quit()
