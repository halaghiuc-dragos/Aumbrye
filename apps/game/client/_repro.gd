extends SceneTree

func _init() -> void:
	var r := DungeonProcgen.generate("forgotten_castle", 42001, 1, 1, 1, false, false)
	print("ok=", r.get("ok"), " err=", r.get("error", ""))
	if r.get("ok", false):
		var d: Dictionary = r["definition"]
		var ids := []
		for room in d["rooms"]:
			ids.append(room["id"])
		print("rooms(", ids.size(), ")=", ids)
		for e in d["edges"]:
			print("edge ", e)
		print("secrets placement=", d["placements"]["secrets"])
		var v := DungeonDefinitionValidator.validate(d)
		print("validate=", v)
	quit()
