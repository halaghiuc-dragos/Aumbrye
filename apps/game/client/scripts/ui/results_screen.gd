extends Control

## Post-run outcome screen — escape/death/waves economy (FLOW-2.1 / FLOW-4.1).

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const RunLifecycleScript := preload("res://scripts/app/run_lifecycle.gd")

@onready var _title_label: Label = $Panel/Margin/VBox/Title
@onready var _time_label: Label = $Panel/Margin/VBox/TimeLabel
@onready var _kills_label: Label = $Panel/Margin/VBox/KillsLabel
@onready var _loot_label: Label = $Panel/Margin/VBox/LootLabel
@onready var _xp_label: Label = $Panel/Margin/VBox/XpLabel
@onready var _rules_label: Label = $Panel/Margin/VBox/RulesLabel
@onready var _hint_label: Label = $Panel/Margin/VBox/HintLabel
var _continue_button: Button
var _cloud_indicator: Label
var _cloud_retry_button: Button
var _leaderboard_label: Label


func _ready() -> void:
	_ensure_ui_nodes()
	GameUISkinScript.apply_modal_menu(self, "Panel")
	_display_from_run_flow()
	_load_leaderboard_panel()
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not ApiConfig.cloud_state_changed.is_connected(_on_cloud_state_changed):
		ApiConfig.cloud_state_changed.connect(_on_cloud_state_changed)
	_refresh_cloud_indicator()
	if _continue_button:
		_continue_button.grab_focus()


func _ensure_ui_nodes() -> void:
	var vbox: VBoxContainer = $Panel/Margin/VBox
	if not has_node("Panel/Margin/VBox/XpLabel"):
		_xp_label = Label.new()
		_xp_label.name = "XpLabel"
		vbox.add_child(_xp_label)
		vbox.move_child(_xp_label, vbox.get_child_count() - 1)
	if not has_node("Panel/Margin/VBox/RulesLabel"):
		_rules_label = Label.new()
		_rules_label.name = "RulesLabel"
		_rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(_rules_label)
		vbox.move_child(_rules_label, vbox.get_child_count() - 1)
	if _cloud_indicator == null:
		_cloud_indicator = Label.new()
		_cloud_indicator.name = "CloudIndicator"
		_cloud_indicator.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_cloud_indicator.visible = false
		vbox.add_child(_cloud_indicator)
	if _cloud_retry_button == null:
		_cloud_retry_button = Button.new()
		_cloud_retry_button.name = "CloudRetryButton"
		_cloud_retry_button.text = "Retry cloud sync"
		_cloud_retry_button.visible = false
		_cloud_retry_button.pressed.connect(_on_cloud_retry_pressed)
		vbox.add_child(_cloud_retry_button)
	if _leaderboard_label == null:
		_leaderboard_label = Label.new()
		_leaderboard_label.name = "LeaderboardLabel"
		_leaderboard_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(_leaderboard_label)
	if _continue_button == null:
		_continue_button = Button.new()
		_continue_button.name = "ContinueButton"
		_continue_button.text = "Continue"
		_continue_button.pressed.connect(_on_continue_pressed)
		vbox.add_child(_continue_button)


func _display_from_run_flow() -> void:
	var results: Dictionary = RunFlow.last_run_results
	if results.is_empty():
		results = get_tree().root.get_meta("run_results", {})
	var outcome: String = results.get("outcome", RunLifecycleScript.OUTCOME_ESCAPED)
	var hero_name := LocalSave.get_character_name()
	_title_label.text = _title_for_outcome(outcome, hero_name)
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
		if outcome == RunLifecycleScript.OUTCOME_DIED:
			var full_xp: int = int(results.get("xp_full_would_be", xp_gained * 2))
			_xp_label.text = "XP gained: %d (50%% of %d)" % [xp_gained, full_xp]
		else:
			_xp_label.text = "XP gained: %d" % xp_gained
		if int(results.get("levels_gained", 0)) > 0:
			_xp_label.text += " — Level up!"
		_rules_label.text = results.get("rules_summary", "")
	_hint_label.text = "Press Enter to return to Aumbrye Tower"


func _load_leaderboard_panel() -> void:
	if _leaderboard_label == null:
		return
	if ApiConfig.access_token == "" and ApiConfig.refresh_token == "":
		_leaderboard_label.text = "Sign in to see leaderboards."
		return
	var biome_id := str(RunFlow.current_biome_id)
	var tier := RunFlow.current_dungeon_tier
	var result := await ApiClient.fetch_leaderboard(biome_id, tier, 10)
	if not result.get("ok", false):
		_leaderboard_label.text = "Leaderboards unavailable."
		return
	var body: Dictionary = result.get("body", {})
	var entries: Array = body.get("entries", [])
	if entries.is_empty():
		_leaderboard_label.text = "Top 10 for %s (tier %d): no entries yet." % [biome_id, tier]
		return
	var lines: PackedStringArray = ["Top 10 for %s (tier %d):" % [biome_id, tier]]
	var rank := 1
	for entry in entries:
		if entry is Dictionary:
			var name := str(entry.get("displayName", "Unknown"))
			var elapsed := float(entry.get("elapsedSeconds", 0.0))
			var mins := int(elapsed / 60.0)
			var secs := int(elapsed) % 60
			lines.append("%d. %s — %d:%02d" % [rank, name, mins, secs])
			rank += 1
	_leaderboard_label.text = "\n".join(lines)


func _on_cloud_state_changed(_state: int, _detail: String) -> void:
	_refresh_cloud_indicator()


func _refresh_cloud_indicator() -> void:
	if _cloud_indicator == null:
		return
	match ApiConfig.cloud_state:
		ApiConfig.CloudState.ERROR:
			_cloud_indicator.visible = true
			_cloud_indicator.text = "Cloud sync failed."
			if _cloud_retry_button:
				_cloud_retry_button.visible = true
		ApiConfig.CloudState.VERSION_MISMATCH:
			_cloud_indicator.visible = true
			_cloud_indicator.text = "Update required to use cloud features."
			if _cloud_retry_button:
				_cloud_retry_button.visible = false
		_:
			_cloud_indicator.visible = false
			if _cloud_retry_button:
				_cloud_retry_button.visible = false


func _on_cloud_retry_pressed() -> void:
	LocalSave.push_to_cloud()


func _title_for_outcome(outcome: String, hero_name: String) -> String:
	match outcome:
		RunLifecycleScript.OUTCOME_DIED:
			return "%s — Echo Returned" % hero_name
		RunLifecycleScript.OUTCOME_WAVES_COMPLETE:
			return "%s — Waves Cleared" % hero_name
		RunLifecycleScript.OUTCOME_WAVES_FAILED:
			return "%s — Waves Failed" % hero_name
		RunLifecycleScript.OUTCOME_ESCAPED:
			if CharacterService.has_flag("story_completed"):
				return "%s — Oath Fulfilled" % hero_name
			return "%s — Run Complete" % hero_name
		_:
			return "%s — Run Complete" % hero_name


func _hub_message_for_outcome(outcome: String) -> String:
	match outcome:
		RunLifecycleScript.OUTCOME_DIED:
			return "Returned to Aumbrye Tower. Permanent XP saved."
		RunLifecycleScript.OUTCOME_WAVES_FAILED:
			return "Waves failed. Run loot was lost."
		RunLifecycleScript.OUTCOME_WAVES_COMPLETE:
			return "Waves cleared! Rewards saved to your stash."
		RunLifecycleScript.OUTCOME_ESCAPED:
			return "Run complete! Your progress was saved."
		_:
			return "Returned to Aumbrye Tower."


func _on_continue_pressed() -> void:
	_accept_and_return()


func _unhandled_input(event: InputEvent) -> void:
	if not (event.is_action_pressed("ui_accept") or event.is_action_pressed("interact")):
		return
	var vp := get_viewport()
	if vp == null:
		return
	vp.set_input_as_handled()
	_accept_and_return()


func _accept_and_return() -> void:
	var outcome: String = RunFlow.last_run_results.get(
		"outcome", RunLifecycleScript.OUTCOME_ESCAPED
	)
	RunFlow.return_to_hub(_hub_message_for_outcome(outcome))
