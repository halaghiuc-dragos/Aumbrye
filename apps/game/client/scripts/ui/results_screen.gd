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
var _run_report_label: Label
var _run_report_frame: PanelContainer
var _seed_button: Button
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
		_cloud_retry_button = GameUISkinScript.make_button(tr("RESULTS_RETRY_SYNC"))
		_cloud_retry_button.name = "CloudRetryButton"
		_cloud_retry_button.visible = false
		_cloud_retry_button.pressed.connect(_on_cloud_retry_pressed)
		vbox.add_child(_cloud_retry_button)
	if _leaderboard_label == null:
		_leaderboard_label = Label.new()
		_leaderboard_label.name = "LeaderboardLabel"
		_leaderboard_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(_leaderboard_label)
	if _seed_button == null:
		_seed_button = GameUISkinScript.make_button(tr("RESULTS_COPY_SEED"))
		_seed_button.name = "CopySeedButton"
		_seed_button.visible = false
		_seed_button.pressed.connect(_on_copy_seed_pressed)
		vbox.add_child(_seed_button)
	if _continue_button == null:
		_continue_button = GameUISkinScript.make_button(tr("RESULTS_CONTINUE"))
		_continue_button.name = "ContinueButton"
		_continue_button.pressed.connect(_on_continue_pressed)
		vbox.add_child(_continue_button)


func _display_from_run_flow() -> void:
	var results: Dictionary = RunFlow.last_run_results
	if results.is_empty():
		results = get_tree().root.get_meta("run_results", {})
	var outcome: String = results.get("outcome", RunLifecycleScript.OUTCOME_ESCAPED)
	var hero_name := LocalSave.get_character_display_name()
	_title_label.text = _title_for_outcome(outcome, hero_name)
	if results.is_empty():
		_time_label.text = tr("RESULTS_TIME_EMPTY")
		_kills_label.text = tr("RESULTS_KILLS_EMPTY")
		_loot_label.text = tr("RESULTS_LOOT_EMPTY")
		_xp_label.text = tr("RESULTS_XP_PENDING")
		_rules_label.text = ""
	else:
		var total_secs := int(results.get("time_seconds", 0.0))
		var mins := int(total_secs / 60.0)
		var secs := total_secs % 60
		_time_label.text = tr("RESULTS_TIME").format({"time": "%d:%02d" % [mins, secs]})
		_kills_label.text = tr("RESULTS_KILLS").format({"kills": int(results.get("kills", 0))})
		var loot: Array = results.get("loot", [])
		if results.get("loot_kept", true):
			_loot_label.text = tr("RESULTS_LOOT_KEPT").format({"items": ", ".join(loot) if loot.size() > 0 else tr("RESULTS_LOOT_NONE")})
		else:
			_loot_label.text = tr("RESULTS_LOOT_LOST").format({"items": ", ".join(loot) if loot.size() > 0 else tr("RESULTS_LOOT_NONE")})
		var xp_gained: int = int(results.get("xp_gained", 0))
		if outcome == RunLifecycleScript.OUTCOME_DIED:
			var full_xp: int = int(results.get("xp_full_would_be", xp_gained * 2))
			_xp_label.text = tr("RESULTS_XP_HALVED").format({"xp": xp_gained, "full": full_xp})
		else:
			_xp_label.text = tr("RESULTS_XP_GAINED_RUN").format({"xp": xp_gained})
		if int(results.get("levels_gained", 0)) > 0:
			_xp_label.text += tr("RESULTS_LEVEL_UP")
		_rules_label.text = results.get("rules_summary", "")
		_ensure_run_report_label()
		_run_report_label.text = _build_run_report(results)
		if _run_report_frame:
			_run_report_frame.visible = _run_report_label.text != ""
		_refresh_seed_button(results)
	_hint_label.text = tr("RESULTS_RETURN_HINT")


func _ensure_run_report_label() -> void:
	if _run_report_label != null and is_instance_valid(_run_report_label):
		return
	var vbox: VBoxContainer = $Panel/Margin/VBox
	_run_report_label = Label.new()
	_run_report_label.name = "RunReportLabel"
	_run_report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(_run_report_label)
	var report_frame := GameUISkinScript.make_pixel_frame(tr("RESULTS_REPORT_TITLE"))
	report_frame.name = "RunReportFrame"
	GameUISkinScript.pixel_frame_content(report_frame).add_child(_run_report_label)
	report_frame.visible = false
	vbox.add_child(report_frame)
	if _rules_label and _rules_label.get_parent() == vbox:
		vbox.move_child(report_frame, _rules_label.get_index() + 1)
	_run_report_frame = report_frame


func _refresh_seed_button(results: Dictionary) -> void:
	if _seed_button == null:
		return
	var run_seed := int(results.get("seed", 0))
	_seed_button.visible = run_seed > 0
	if run_seed > 0:
		_seed_button.text = tr("RESULTS_COPY_SEED_N").format({"seed": run_seed})


func _on_copy_seed_pressed() -> void:
	var run_seed := int(RunFlow.last_run_results.get("seed", 0))
	if run_seed <= 0:
		return
	DisplayServer.clipboard_set(str(run_seed))
	if _seed_button:
		_seed_button.text = tr("RESULTS_SEED_COPIED_N").format({"seed": run_seed})


func _format_duration(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [int(total / 60.0), total % 60]


func _run_context_lines(results: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var challenge_name := str(results.get("challenge_name", ""))
	var mode_name := str(results.get("mode_name", ""))
	if challenge_name != "":
		lines.append(tr("RESULTS_WEEKLY_CHALLENGE").format({"name": challenge_name}))
	elif mode_name != "":
		lines.append(tr("RESULTS_RULE_SET").format({"name": mode_name}))
	var dungeon_name := str(results.get("dungeon_name", ""))
	if dungeon_name != "" and str(results.get("run_mode", "")) == "castle":
		lines.append(
			"%s, depth %d." % [dungeon_name, int(results.get("difficulty_tier", 1))]
		)
	return lines


func _personal_best_lines(results: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var raw: Variant = results.get("history", {})
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return lines
	var history: Dictionary = raw
	var depth := int(results.get("floor_reached", 0))
	var previous_depth := int(history.get("previousBestDepth", 0))
	if bool(history.get("depthIsBest", false)) and previous_depth > 0:
		lines.append(tr("RESULTS_DEPTH_BEST").format({"floor": depth, "previous": previous_depth}))
	elif previous_depth > 0 and depth > 0:
		lines.append(tr("RESULTS_DEPTH_SHORT").format({"floor": depth, "previous": previous_depth}))
	var previous_time := float(history.get("previousBestTime", 0.0))
	if bool(history.get("timeIsBest", false)):
		if previous_time > 0.0:
			lines.append(
				tr("RESULTS_TIME_BEST").format(
					{
						"time": _format_duration(float(results.get("time_seconds", 0.0))),
						"previous": _format_duration(previous_time),
					}
				)
			)
		else:
			lines.append(tr("RESULTS_TIME_FIRST_CLEAR"))
	elif previous_time > 0.0:
		lines.append(tr("RESULTS_TIME_NOT_BEST").format({"previous": _format_duration(previous_time)}))
	if bool(history.get("killsIsBest", false)) and int(history.get("previousBestKills", 0)) > 0:
		lines.append(tr("RESULTS_KILLS_BEST"))
	var rate := float(history.get("successRate", -1.0))
	if rate >= 0.0:
		lines.append(tr("RESULTS_SURVIVAL_RATE").format({"count": int(round(rate * 10.0))}))
	return lines


func _challenge_lines(results: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var raw: Variant = results.get("challenge", {})
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return lines
	var record: Dictionary = raw
	var best: Variant = record.get("best", {})
	var best_dict: Dictionary = best if best is Dictionary else {}
	if bool(record.get("improved", false)):
		lines.append(tr("RESULTS_WEEKLY_BEST"))
	elif not best_dict.is_empty():
		lines.append(tr("RESULTS_WEEKLY_NOT_BEST"))
	return lines


func _highlight_lines(results: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var raw: Variant = results.get("highlights", {})
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return lines
	var highlights: Dictionary = raw
	var relics: Variant = highlights.get("relics", [])
	if relics is Array and not (relics as Array).is_empty():
		var names: Array[String] = []
		for relic in relics as Array:
			if relic is Dictionary:
				names.append(str((relic as Dictionary).get("name", "")))
		if not names.is_empty():
			lines.append(tr("RESULTS_RELICS_CARRIED").format({"relics": ", ".join(names)}))
	var top_relic := str(highlights.get("topRelic", ""))
	var top_procs := int(highlights.get("topRelicProcs", 0))
	if top_relic != "" and top_procs > 0:
		var top_name := top_relic
		if relics is Array:
			for relic in relics as Array:
				if relic is Dictionary and str((relic as Dictionary).get("id", "")) == top_relic:
					top_name = str((relic as Dictionary).get("name", top_relic))
		lines.append(tr("RESULTS_TOP_RELIC").format({"relic": top_name, "count": top_procs}))
	# C-124: the biggest hit of the run, and what made it big.
	var best_hit: Dictionary = highlights.get("bestHit", {})
	if best_hit is Dictionary and float(best_hit.get("amount", 0.0)) > 0.0:
		var flags: PackedStringArray = []
		if bool(best_hit.get("backstab", false)):
			flags.append(tr("RESULTS_HIT_BACKSTAB"))
		if bool(best_hit.get("crit", false)):
			flags.append(tr("RESULTS_HIT_CRIT"))
		var suffix := " (%s)" % ", ".join(flags) if flags.size() > 0 else ""
		(
			lines
			. append(
				tr("RESULTS_BEST_HIT").format(
					{"amount": int(round(float(best_hit.get("amount", 0.0))))}
				)
				+ suffix
			)
		)
	var offers := int(highlights.get("offersTaken", 0))
	if offers > 0:
		lines.append(tr("RESULTS_OFFERS_TAKEN").format({"count": offers}))
	var traps := int(highlights.get("trapCatches", 0))
	if traps > 0:
		lines.append(tr("RESULTS_TRAPS_HIT").format({"count": traps}))
	return lines


func _build_run_report(results: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append_array(_run_context_lines(results))
	lines.append_array(_personal_best_lines(results))
	lines.append_array(_challenge_lines(results))
	lines.append_array(_highlight_lines(results))
	var staked := int(results.get("gold_staked", 0))
	if staked > 0:
		lines.append(tr("RESULTS_GOLD_STAKED").format({"gold": staked}))
	if str(results.get("run_mode", "")) == "endless":
		var best := int(results.get("endless_best_floor", 0))
		var previous := int(results.get("endless_previous_best", 0))
		var floor_reached := int(results.get("floor_reached", 0))
		if best > previous:
			lines.append(tr("RESULTS_DESCENT_BEST").format({"floor": best, "previous": previous}))
		elif previous > 0:
			lines.append(tr("RESULTS_DESCENT_NOT_BEST").format({"floor": floor_reached, "previous": previous}))
		var tokens := int(results.get("descent_tokens_awarded", 0))
		if tokens > 0:
			lines.append(tr("RESULTS_DESCENT_TOKENS").format({"count": tokens}))
	var failure: Variant = results.get("failure_point", {})
	if failure is Dictionary and not (failure as Dictionary).is_empty():
		lines.append("You fell at %s." % str((failure as Dictionary).get("label", "")))
		var parts: Array[String] = []
		for row in ProgressionService.get_failure_hotspots(3):
			if int(row.get("count", 0)) < 2:
				continue
			parts.append("%s (x%d)" % [str(row.get("label", "")), int(row.get("count", 0))])
		if not parts.is_empty():
			lines.append(tr("RESULTS_RECURRING_FAILURE").format({"causes": ", ".join(parts)}))
	if bool(results.get("assists_active", false)):
		var assists := AccessibilitySettings.active_assist_summary()
		if not assists.is_empty():
			lines.append(tr("RESULTS_ASSISTS").format({"assists": ", ".join(assists)}))
	return "\n".join(lines)


func _load_leaderboard_panel() -> void:
	if _leaderboard_label == null:
		return
	if ApiConfig.access_token == "" and ApiConfig.refresh_token == "":
		_leaderboard_label.text = tr("RESULTS_LEADERBOARD_SIGN_IN")
		return
	var biome_id := str(RunFlow.current_biome_id)
	var tier := RunFlow.current_dungeon_tier
	var result := await ApiClient.fetch_leaderboard(biome_id, tier, 10)
	if not result.get("ok", false):
		_leaderboard_label.text = tr("RESULTS_LEADERBOARD_UNAVAILABLE")
		return
	var body: Dictionary = result.get("body", {})
	var entries: Array = body.get("entries", [])
	if entries.is_empty():
		_leaderboard_label.text = tr("RESULTS_LEADERBOARD_EMPTY").format({"biome": biome_id, "tier": tier})
		return
	var lines: PackedStringArray = [tr("RESULTS_LEADERBOARD_TITLE").format({"biome": biome_id, "tier": tier})]
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
			_cloud_indicator.text = tr("RESULTS_CLOUD_FAILED")
			if _cloud_retry_button:
				_cloud_retry_button.visible = true
		ApiConfig.CloudState.VERSION_MISMATCH:
			_cloud_indicator.visible = true
			_cloud_indicator.text = tr("RESULTS_CLOUD_UPDATE_REQUIRED")
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
			return tr("RESULTS_WAVES_CLEARED") % hero_name
		RunLifecycleScript.OUTCOME_WAVES_FAILED:
			return tr("RESULTS_WAVES_FAILED") % hero_name
		RunLifecycleScript.OUTCOME_ESCAPED:
			if CharacterService.has_flag("story_completed"):
				return tr("RESULTS_OATH_FULFILLED") % hero_name
			return tr("RESULTS_RUN_COMPLETE") % hero_name
		_:
			return tr("RESULTS_RUN_COMPLETE") % hero_name


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
