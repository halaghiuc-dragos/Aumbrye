class_name AlternateModeRow
extends RefCounted

## MD-05: `content/modes/catalog.json`'s three rule sets were well-written and reachable only
## through the tower board -- a menu inside a menu inside the hub. Surfaces the ones scoped to a
## given base mode directly on that mode's own entry menu instead, each mode's own unlock hint
## shown when locked rather than the whole row disappearing.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")


## Builds one button per catalog mode whose `baseMode` matches, appends them to `vbox`, and wires
## each unlocked one to `on_pressed(mode_id)`. Returns the buttons added, for focus-ring wiring.
static func build_into(vbox: VBoxContainer, base_mode: String, on_pressed: Callable) -> Array[Button]:
	var buttons: Array[Button] = []
	var counters := ProgressCounters.snapshot()
	for mode in RunModeCatalog.get_all():
		if str(mode.get("baseMode", "")) != base_mode:
			continue
		var mode_id := str(mode.get("id", ""))
		if mode_id == "":
			continue
		var unlocked := RunModeCatalog.is_unlocked(mode_id, counters)
		var label := str(mode.get("name", mode_id))
		var btn := GameUISkinScript.make_button(label)
		btn.disabled = not unlocked
		if unlocked:
			btn.tooltip_text = str(mode.get("flavour", mode.get("description", "")))
			btn.pressed.connect(on_pressed.bind(mode_id))
		else:
			btn.tooltip_text = RunModeCatalog.unlock_hint(mode_id, counters)
		vbox.add_child(btn)
		buttons.append(btn)
	return buttons
