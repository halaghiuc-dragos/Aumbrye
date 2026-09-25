extends Node

var _failures := 0
var _saved_flags: Dictionary = {}
var _dialogue_lines: Dictionary = {}
const RESCUE_NPCS := ["corrin", "halbrek", "ivo", "nettle", "odile", "veil"]
const NPC_RULES := {
	"corrin": "lampwright_corrin", "halbrek": "serjeant_halbrek", "ivo": "clerk_ivo",
	"nettle": "fenwife_nettle", "odile": "lector_odile", "veil": "widow_of_the_stair",
}
const ARRIVAL_FLAGS := ["lamps_relit", "gate_reopened", "heard_the_keeping", "prayer_restored", "heard_the_hierarch"]
const ARRIVAL_FLAG_BY_NPC := {
	"corrin": "lamps_relit", "halbrek": "gate_reopened", "ivo": "heard_the_keeping",
	"odile": "prayer_restored", "veil": "heard_the_hierarch",
}
var _captured_dialogue_id := ""
var _captured_shop_type := ""
var _captured_choices: Array = []
var _rule_overlap_count := 0
var _rule_case_count := 0
const AUDIT_BIOMES := ["crystal_caverns", "dark_cathedral", "forgotten_castle", "frozen_fortress", "glacial_hollow", "iron_vault", "poison_swamp", "prism_depths", "umbral_chapel", "venom_mire"]
const RESCUE_BIOME_BY_NPC := {
	"corrin": "prism_depths", "halbrek": "forgotten_castle", "ivo": "iron_vault",
	"nettle": "poison_swamp", "odile": "dark_cathedral", "veil": "umbral_chapel",
}


func _ready() -> void:
	for npc_id in RESCUE_NPCS:
		_snapshot(npc_id)
	_clear("halbrek")
	_check(QuestService.set_rescue_state("halbrek", "deferred"), "defer transition accepts a known rescue")
	_check(
		bool(CharacterService.get_flag("rescue_deferred_halbrek", false))
		and not bool(CharacterService.get_flag("rescued_halbrek", false)),
		"deferring preserves the unresolved rescue for a revisit"
	)
	_check(QuestService.set_rescue_state("halbrek", "committed"), "commit transition succeeds")
	QuestService.resolve_committed_rescues(RunLifecycle.OUTCOME_DIED)
	_check(
		bool(CharacterService.get_flag("lost_halbrek", false))
		and not bool(CharacterService.get_flag("rescue_committed_halbrek", false)),
		"a committed rescue is lost when its run ends in failure"
	)
	_clear("halbrek")
	QuestService.set_rescue_state("halbrek", "committed")
	QuestService.resolve_committed_rescues(RunLifecycle.OUTCOME_ESCAPED)
	_check(
		bool(CharacterService.get_flag("rescued_halbrek", false))
		and not bool(CharacterService.get_flag("rescue_committed_halbrek", false)),
		"a committed rescue arrives safely only after escape"
	)
	for npc_id in RESCUE_NPCS:
		_clear(npc_id)
		CharacterService.set_flag("rescue_committed_%s" % npc_id, true)
		_check_rescue_dialogue(npc_id, "committed")
		CharacterService.set_flag("rescue_committed_%s" % npc_id, false)
		CharacterService.set_flag("rescued_%s" % npc_id, true)
		_check_rescue_dialogue(npc_id, "already")
	_audit_npc_reaction_precedence()
	_audit_roster_rule_matrix()
	_audit_npc_availability_and_service()
	_audit_rescue_world_spawn_consumer()
	_restore()
	print("RESCUE STATE RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _snapshot(npc_id: String) -> void:
	for prefix in ["rescued_", "lost_", "rescue_committed_", "rescue_deferred_"]:
		var flag: String = prefix + npc_id
		_saved_flags[flag] = CharacterService.get_flag(flag, false)
	for flag in ARRIVAL_FLAGS + ["last_run", "story_beat", "deaths"]:
		var default_value: Variant = {}
		if flag != "last_run":
			default_value = 0
		_saved_flags[flag] = CharacterService.get_flag(flag, default_value)
	for npc_key in RESCUE_NPCS:
		var relationship_flag := "rel_%s" % npc_key
		_saved_flags[relationship_flag] = CharacterService.get_flag(relationship_flag, 0)


func _clear(npc_id: String) -> void:
	for prefix in ["rescued_", "lost_", "rescue_committed_", "rescue_deferred_"]:
		CharacterService.set_flag(prefix + npc_id, false)


func _restore() -> void:
	for flag in _saved_flags:
		CharacterService.set_flag(str(flag), _saved_flags[flag])


func _audit_npc_reaction_precedence() -> void:
	CharacterService.set_flag("last_run", {"outcome": "died", "boss": true, "biome": "iron_vault", "floor": 4})
	for npc_key in RESCUE_NPCS:
		var relationship_flag := "rel_%s" % npc_key
		CharacterService.set_flag(relationship_flag, 0)
		var npc := NpcBase.new()
		npc._data = NpcCatalog.get_definition(str(NPC_RULES[npc_key]))
		_check(npc.resolve_dialogue_id() == "%s_arrival" % npc_key, "%s selects its one-time arrival dialogue first" % npc_key)
		var arrival := DialogueRunner.new()
		_check(arrival.start("%s_arrival" % npc_key) != DialogueRunner.StartResult.FAILED, "%s arrival tree executes" % npc_key)
		arrival.end_dialogue()
		_check(DialogueConditions.flag_number(relationship_flag) >= 2, "%s arrival commits its relationship threshold once" % npc_key)
		if ARRIVAL_FLAG_BY_NPC.has(npc_key):
			var arrival_flag := str(ARRIVAL_FLAG_BY_NPC[npc_key])
			_check(CharacterService.is_flag_truthy(arrival_flag), "%s arrival records its one-time story reaction" % npc_key)
			if arrival_flag in ["lamps_relit", "gate_reopened", "heard_the_keeping"]:
				_check_title_unlock(arrival_flag, npc_key)
		_check(npc.resolve_dialogue_id() == "%s_reactions" % npc_key, "%s re-evaluates to contextual reaction after arrival relationship commits" % npc_key)
		npc.free()


func _audit_roster_rule_matrix() -> void:
	var scenarios: Array[Dictionary] = [{},
		{"outcome": "died", "boss": true, "floor": 1},
		{"outcome": "died", "boss": false, "floor": 4},
		{"outcome": "escaped", "boss": true, "floor": 1}]
	for biome in AUDIT_BIOMES:
		scenarios.append({"outcome": "escaped", "boss": false, "floor": 1, "biome": biome})
	CharacterService.set_flag("deaths", 10)
	scenarios.append({"outcome": "died", "boss": false, "floor": 1})
	for npc_id in NpcCatalog.get_all_ids():
		var definition := NpcCatalog.get_definition(npc_id)
		var relationship := ""
		for rule in definition.get("dialogueRules", []):
			relationship = _find_relationship_key(rule.get("condition"))
			if relationship != "":
				break
		if relationship != "":
			CharacterService.set_flag("rel_%s" % relationship, 2)
		var npc := NpcBase.new()
		npc._data = definition
		for scenario in scenarios:
			CharacterService.set_flag("last_run", scenario)
			var expected := str(definition.get("dialogueId", ""))
			var matching := 0
			for rule in definition.get("dialogueRules", []):
				if DialogueConditions.evaluate(rule.get("condition")):
					matching += 1
					if matching == 1:
						expected = str(rule.get("dialogueId", expected))
			_rule_overlap_count += maxi(0, matching - 1)
			_rule_case_count += 1
			var resolved := npc.resolve_dialogue_id()
			_check(resolved == expected, "%s uses its first matching dialogue rule for %s" % [npc_id, str(scenario)])
			if resolved != "":
				var runner := DialogueRunner.new()
				_check(runner.start(resolved) != DialogueRunner.StartResult.FAILED, "%s selected graph opens for %s" % [npc_id, str(scenario)])
				runner.end_dialogue()
		npc.free()
	print("NPC RULE MATRIX %d cases, %d later matching rules shadowed by first-match precedence" % [_rule_case_count, _rule_overlap_count])
	_audit_rescue_story_reactions()


func _check_title_unlock(flag: String, npc_key: String) -> void:
	var found := false
	for entry in AppearanceCatalog.get_titles():
		if str(entry.get("unlockFlag", "")) != flag:
			continue
		found = true
		_check(AppearanceCatalog.is_unlocked(entry), "%s arrival unlocks its visible title reward" % npc_key)
		break
	_check(found, "%s story reaction is consumed by a visible appearance title" % npc_key)


func _audit_rescue_story_reactions() -> void:
	_check_rescue_choice("aldric_greeting", "rescued_halbrek", "You were at the muster, then.")
	_check_rescue_choice("vessit_greeting", "rescued_ivo", "Kell says the columns are the same column.")
	_check_rescue_choice("veil_greeting", "rescued_odile", "Odile is here too.")


func _check_rescue_choice(dialogue_id: String, rescue_flag: String, expected_text: String) -> void:
	CharacterService.set_flag(rescue_flag, true)
	_captured_choices.clear()
	var runner := DialogueRunner.new()
	runner.line_changed.connect(_capture_choices)
	_check(runner.start(dialogue_id) != DialogueRunner.StartResult.FAILED, "%s opens for rescue-consequence audit" % dialogue_id)
	var found := false
	for choice in _captured_choices:
		if str(choice.get("text", "")) == expected_text:
			found = true
	_check(found, "%s exposes rescue-specific hub dialogue" % rescue_flag)
	runner.end_dialogue()
	CharacterService.set_flag(rescue_flag, false)


func _capture_choices(_speaker: String, _text: String, choices: Array) -> void:
	_captured_choices = choices.duplicate(true)


func _find_relationship_key(condition: Variant) -> String:
	if not condition is Dictionary:
		return ""
	if condition.has("relationship"):
		return str(condition.get("relationship", ""))
	for key in ["all", "any"]:
		for child in condition.get(key, []):
			var found := _find_relationship_key(child)
			if found != "":
				return found
	if condition.has("not"):
		return _find_relationship_key(condition.get("not"))
	return ""


func _audit_rescue_world_spawn_consumer() -> void:
	for npc_id in RESCUE_NPCS:
		var biome := str(RESCUE_BIOME_BY_NPC[npc_id])
		var dialogue_id := "rescue_%s" % npc_id
		var authored := false
		for quest in DungeonQuestCatalog.quests_for_biome(biome):
			if str(quest.get("dialogueId", "")) == dialogue_id:
				authored = true
				break
		_check(authored, "%s rescue has a procgen world entry in %s" % [npc_id, biome])
		for resolved_prefix in ["rescued_", "lost_", "rescue_committed_"]:
			for key in RESCUE_NPCS:
				_clear(key)
			CharacterService.set_flag(resolved_prefix + npc_id, true)
			var selected_resolved := false
			for sample_index in 32:
				var sample_rng := RandomNumberGenerator.new()
				sample_rng.seed = sample_index
				var selected := RoomContentAssigner._pick_dungeon_quest(biome, sample_rng)
				if str(selected.get("dialogueId", "")) == dialogue_id:
					selected_resolved = true
					break
			_check(
				not selected_resolved,
				"%s is not regenerated after %s" % [npc_id, resolved_prefix]
			)
		for key in RESCUE_NPCS:
			_clear(key)
		CharacterService.set_flag("rescue_deferred_%s" % npc_id, true)
		var deferred_still_eligible := false
		for sample_index in 32:
			var sample_rng := RandomNumberGenerator.new()
			sample_rng.seed = sample_index
			var selected := RoomContentAssigner._pick_dungeon_quest(biome, sample_rng)
			if str(selected.get("dialogueId", "")) == dialogue_id:
				deferred_still_eligible = true
				break
		_check(deferred_still_eligible, "%s remains revisitable after deferral" % npc_id)
	for npc_id in RESCUE_NPCS:
		_clear(npc_id)
	CharacterService.set_flag("rescued_halbrek", true)
	CharacterService.set_flag("lost_ivo", true)
	CharacterService.set_flag("rescue_committed_nettle", true)
	var fallback_rng := RandomNumberGenerator.new()
	fallback_rng.seed = 1
	var fallback := RoomContentAssigner._pick_dungeon_quest("venom_mire", fallback_rng)
	_check(
		str(fallback.get("dialogueId", "")) == "dungeon_npc_stranded",
		"resolved-only biome pool falls back to the generic stranded-NPC encounter"
	)


func _audit_npc_availability_and_service() -> void:
	CharacterService.set_flag("last_run", {})
	for npc_key in RESCUE_NPCS:
		var definition: Dictionary = NpcCatalog.get_definition(str(NPC_RULES[npc_key]))
		var npc := NpcBase.new()
		npc._data = definition
		CharacterService.set_flag("rescued_%s" % npc_key, false)
		_check(not npc.is_available(), "%s remains absent from hub before rescue" % npc_key)
		CharacterService.set_flag("rescued_%s" % npc_key, true)
		_check(npc.is_available(), "%s becomes available in hub after rescue" % npc_key)
		npc.free()
	var clerk := NpcBase.new()
	clerk._data = NpcCatalog.get_definition("clerk_ivo")
	CharacterService.set_flag("rescued_ivo", true)
	CharacterService.set_flag("rel_ivo", 0)
	_captured_dialogue_id = ""
	_captured_shop_type = ""
	clerk.dialogue_requested.connect(_capture_npc_dialogue)
	clerk.shop_requested.connect(_capture_npc_shop)
	clerk._on_interacted()
	_check(_captured_dialogue_id == "ivo_arrival", "storage NPC offers its contextual greeting before service")
	clerk.notify_dialogue_start_result(true)
	clerk._on_interacted()
	_check(_captured_shop_type == "storage", "storage service becomes available after the greeting completes")
	clerk.free()
	var serjeant := NpcBase.new()
	serjeant._data = NpcCatalog.get_definition("serjeant_halbrek")
	CharacterService.set_flag("rescued_halbrek", true)
	CharacterService.set_flag("rel_halbrek", 2)
	_captured_dialogue_id = ""
	_captured_shop_type = ""
	serjeant.dialogue_requested.connect(_capture_npc_dialogue)
	serjeant.shop_requested.connect(_capture_npc_shop)
	serjeant._on_interacted()
	_check(_captured_dialogue_id == "halbrek_greeting", "rescued serjeant offers his greeting before the bounty board")
	serjeant.notify_dialogue_start_result(true)
	serjeant._on_interacted()
	_check(_captured_shop_type == "bounty_board", "bounty-board service becomes available after the greeting completes")
	serjeant.free()


func _capture_npc_dialogue(_npc_id: String, dialogue_id: String) -> void:
	_captured_dialogue_id = dialogue_id


func _capture_npc_shop(_npc_id: String, shop_type: String) -> void:
	_captured_shop_type = shop_type


func _check_rescue_dialogue(npc_id: String, expected_node: String) -> void:
	_dialogue_lines[npc_id] = ""
	var dialogue := DialogueCatalog.get_dialogue("rescue_%s" % npc_id)
	var nodes: Dictionary = dialogue.get("nodes", {})
	var expected_text := str(nodes.get(expected_node, {}).get("text", ""))
	var runner := DialogueRunner.new()
	runner.line_changed.connect(_capture_dialogue_line.bind(npc_id))
	var result := runner.start("rescue_%s" % npc_id)
	_check(result == DialogueRunner.StartResult.OPENED, "%s rescue dialogue opens for %s state" % [npc_id, expected_node])
	_check(
		str(_dialogue_lines.get(npc_id, "")) == expected_text,
		"%s rescue dialogue selects its %s response" % [npc_id, expected_node]
	)
	runner.end_dialogue()


func _capture_dialogue_line(_speaker: String, text: String, _choices: Array, npc_id: String) -> void:
	_dialogue_lines[npc_id] = text


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(label)
