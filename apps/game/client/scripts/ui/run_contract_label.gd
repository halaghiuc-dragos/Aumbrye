class_name RunContractLabel
extends RefCounted

## AD-01: the one formatter every entry menu's contract label calls, so the card reads the same
## way in the castle, endless and waves menus -- one source, three consumers, per the plan.


static func format_lines(lines: Array[Dictionary]) -> String:
	var out: PackedStringArray = []
	for line in lines:
		var text := str(line.get("text", ""))
		if text != "":
			out.append("• %s" % text)
	return "\n".join(out)


static func refresh(label: Label, mode: String, dungeon_id: String, tier: int) -> void:
	if label == null:
		return
	var lines := RunFlow.build_run_contract(mode, dungeon_id, tier)
	var text := format_lines(lines)
	label.text = text
	label.visible = text != ""
