extends Control

## Post-run results screen (FLOW-2.1).

@onready var _time_label: Label = $Panel/Margin/VBox/TimeLabel
@onready var _kills_label: Label = $Panel/Margin/VBox/KillsLabel
@onready var _loot_label: Label = $Panel/Margin/VBox/LootLabel
@onready var _hint_label: Label = $Panel/Margin/VBox/HintLabel


func _ready() -> void:
	_display_from_run_flow()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _display_from_run_flow() -> void:
	var results: Dictionary = RunFlow.last_run_results
	if results.is_empty():
		results = get_tree().root.get_meta("run_results", {})
	if results.is_empty():
		_time_label.text = "Time: --"
		_kills_label.text = "Kills: --"
		_loot_label.text = "Loot: --"
	else:
		var total_secs := int(results.get("time_seconds", 0.0))
		var mins := int(total_secs / 60.0)
		var secs := total_secs % 60
		_time_label.text = "Time: %d:%02d" % [mins, secs]
		_kills_label.text = "Kills: %d" % results.get("kills", 0)
		var loot: Array = results.get("loot", [])
		_loot_label.text = "Loot: %s" % ", ".join(loot) if loot.size() > 0 else "Loot: (none)"
	_hint_label.text = "Press Enter to return to Hub"


func _unhandled_input(event: InputEvent) -> void:
	if not (event.is_action_pressed("ui_accept") or event.is_action_pressed("interact")):
		return
	var vp := get_viewport()
	if vp == null:
		return
	vp.set_input_as_handled()
	RunFlow.return_to_hub("Run complete! Your progress was saved.")
