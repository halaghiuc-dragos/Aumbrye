extends Node


const LocalProcgenScript := preload("res://scripts/dungeon/local_procgen.gd")

const CASES := [
	["forgotten_castle", 17041],
	["crystal_caverns", 17042],
	["poison_swamp", 17043],
	["frozen_fortress", 17044],
	["dark_cathedral", 17045],
	["iron_vault", 17046],
	["prism_depths", 17047],
	["venom_mire", 17048],
	["glacial_hollow", 17049],
	["umbral_chapel", 17050],
]

var _failures := 0


func _ready() -> void:
	for case in CASES:
		var biome_id := str(case[0])
		var case_seed := int(case[1])
		var result: Dictionary = LocalProcgenScript.generate(
			biome_id, case_seed, 1, "castle", 1, 1, false, false, true
		)
		var diagnostics: Dictionary = result.get("generation_diagnostics", {})
		var candidates: Array = diagnostics.get("candidates", [])
		_check(not diagnostics.is_empty(), "%s emits generation diagnostics" % biome_id)
		_check(
			int(diagnostics.get("inputSeed", -1)) == case_seed,
			"%s diagnostics retain the input seed" % biome_id
		)
		_check(
			int(diagnostics.get("candidateCount", -1)) == candidates.size(),
			"%s candidate count matches detailed outcomes" % biome_id
		)
		var failures := 0
		for index in candidates.size():
			var candidate: Dictionary = candidates[index]
			_check(
				int(candidate.get("attempt", -1)) == index + 1,
				"%s candidate attempt order is retained" % biome_id
			)
			if str(candidate.get("status", "")) != "valid":
				failures += 1
		_check(
			int(diagnostics.get("failedCandidateCount", -1)) == failures,
			"%s failure count distinguishes rejected candidates" % biome_id
		)
		_check(
			is_equal_approx(
				float(diagnostics.get("candidateFailureRate", -1.0)),
				float(failures) / float(candidates.size()) if not candidates.is_empty() else 0.0
			),
			"%s reports the candidate failure rate" % biome_id
		)
		if result.get("ok", false):
			var definition: Dictionary = result.get("definition", {})
			var boss_room_id := ""
			for room in definition.get("rooms", []):
				if room is Dictionary and str(room.get("type", "")) == "boss":
					boss_room_id = str(room.get("id", ""))
			var boss_direction_reveal_found := false
			for landmark in definition.get("landmarks", []):
				if landmark is Dictionary and str(landmark.get("kind", "")) == "orientation_spire":
					boss_direction_reveal_found = str(landmark.get("revealRoomId", "")) == boss_room_id
			_check(
				boss_room_id != "" and boss_direction_reveal_found,
				"%s boss-direction landmark points to the boss room outline" % biome_id
			)
			for preview in definition.get("branchPreviews", []):
				if preview is Dictionary:
					_check(
						str(preview.get("hint", "")) == "unknown"
							and int(preview.get("clueQuality", 0)) == 0,
						"%s doesn't reveal optional room purpose without an authored clue" % biome_id
					)
			var selected_attempt := int(diagnostics.get("selectedAttempt", 0))
			_check(selected_attempt > 0, "%s records selected attempt" % biome_id)
			_check(selected_attempt <= candidates.size(), "%s selected attempt exists" % biome_id)
			_check(
				str(diagnostics.get("selectionReason", ""))
					in ["quality_threshold", "highest_quality_after_attempt_budget"],
				"%s records why the candidate won" % biome_id
			)
			if selected_attempt > 0 and selected_attempt <= candidates.size():
				var selected: Dictionary = candidates[selected_attempt - 1]
				_check(
					str(selected.get("status", "")) == "valid",
					"%s selected candidate passed validation" % biome_id
				)
				_check(
					int(selected.get("seed", 0)) == int(diagnostics.get("selectedSeed", -1)),
					"%s selected seed matches candidate record" % biome_id
				)
			_check(
					(diagnostics.get("selectedQuality", {}) as Dictionary)
					== (result.get("selection", {}) as Dictionary),
					"%s selected quality is retained independently" % biome_id
			)
		else:
			_check(
				int(diagnostics.get("selectedAttempt", -1)) == 0,
				"%s failed generation has no selected attempt" % biome_id
			)
	print("PROCGEN DIAGNOSTICS RESULT %d failures across %d biomes" % [_failures, CASES.size()])
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
