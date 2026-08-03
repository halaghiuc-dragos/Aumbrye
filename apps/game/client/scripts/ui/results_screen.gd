extends Control

## Post-run outcome screen — escape/death economy (FLOW-2.1 / FLOW-4.1).

@onready var _title_label: Label = $Panel/Margin/VBox/Title
@onready var _time_label: Label = $Panel/Margin/VBox/TimeLabel
@onready var _kills_label: Label = $Panel/Margin/VBox/KillsLabel
@onready var _loot_label: Label = $Panel/Margin/VBox/LootLabel
@onready var _xp_label: Label = $Panel/Margin/VBox/XpLabel
@onready var _rules_label: Label = $Panel/Margin/VBox/RulesLabel
@onready var _hint_label: Label = $Panel/Margin/VBox/HintLabel


func _ready() -> void:
	_ensure_ui_nodes()
	_display_from_run_flow()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ensure_ui_nodes() -> void:
	if has_node("Panel/Margin/VBox/XpLabel"):
		return
	var vbox: VBoxContainer = $Panel/Margin/VBox
	_xp_label = Label.new()
	_xp_label.name = "XpLabel"
	vbox.add_child(_xp_label)
	vbox.move_child(_xp_label, vbox.get_child_count() - 1)
	_rules_label = Label.new()
	_rules_label.name = "RulesLabel"
	_rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_rules_label)
	vbox.move_child(_rules_label, vbox.get_child_count() - 1)


func _display_from_run_flow() -> void:
	var results: Dictionary = RunFlow.last_run_results
	if results.is_empty():
		results = get_tree().root.get_meta("run_results", {})
	var outcome: String = results.get("outcome", "escaped")
	if outcome == "died":
		_title_label.text = "You Died"
	else:
		_title_label.text = "Run Complete!"
	if results.is_empty():
		_time_label.text = "Time: --"
		_kills_label.text = "Kills: --"
		_loot_label.text = "Loot: --"
		_xp_label.text = "XP: --"
		_rules_label.text = ""
	else:
		var total_secs := int(results.get("time_seconds", 0.0))
		var mins := int(total_secs / 60.0)
		var secs := total_secs % 60
		_time_label.text = "Time: %d:%02d" % [mins, secs]
		_kills_label.text = "Kills: %d" % results.get("kills", 0)
		var loot: Array = results.get("loot", [])
		if results.get("loot_kept", true):
			_loot_label.text = "Loot kept: %s" % (", ".join(loot) if loot.size() > 0 else "(none)")
		else:
			_loot_label.text = "Loot lost: %s" % (", ".join(loot) if loot.size() > 0 else "(none)")
		var xp_gained: int = int(results.get("xp_gained", 0))
		if outcome == "died":
			var full_xp: int = int(results.get("xp_full_would_be", xp_gained * 2))
			_xp_label.text = "XP gained: %d (50%% of %d)" % [xp_gained, full_xp]
		else:
			_xp_label.text = "XP gained: %d" % xp_gained
		if int(results.get("levels_gained", 0)) > 0:
			_xp_label.text += " — Level up!"
		_rules_label.text = results.get("rules_summary", "")
	_hint_label.text = "Press Enter to return to Aumbrye Tower"


func _unhandled_input(event: InputEvent) -> void:
	if not (event.is_action_pressed("ui_accept") or event.is_action_pressed("interact")):
		return
	var vp := get_viewport()
	if vp == null:
		return
	vp.set_input_as_handled()
	var outcome: String = RunFlow.last_run_results.get("outcome", "escaped")
	if outcome == "died":
		RunFlow.return_to_hub("Returned to Aumbrye Tower. Permanent XP saved.")
	else:
		RunFlow.return_to_hub("Run complete! Your progress was saved.")
