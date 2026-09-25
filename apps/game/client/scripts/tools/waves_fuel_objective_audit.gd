extends Node

const WavesRunScript := preload("res://scripts/dungeon/waves_run.gd")

var _failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Waves fuel objective audit: %s" % message)


func _ready() -> void:
	var positions: Array[Vector3] = []
	for wave in range(1, 5):
		var point: Vector3 = WavesRunScript.fuel_objective_position_for_wave(wave)
		positions.append(point)
		_check(is_equal_approx(Vector2(point.x, point.z).length(), 16.0), "waystone remains on the readable inner arena ring")
		_check(WavesRunScript.fuel_objective_position_for_wave(wave + 4).is_equal_approx(point), "quadrant rotation repeats deterministically every four waves")
	_check(not positions[0].is_equal_approx(positions[1]), "consecutive waves use different recovery quadrants")
	_check(not positions[1].is_equal_approx(positions[2]), "the objective continues alternating around the arena")
	_check(WavesRunScript.fuel_objective_position_for_wave(0).is_zero_approx(), "non-combat phase has no active objective location")

	var objective_rate := WavesRunScript.fuel_rate_for_positions(positions[0], positions[0], true)
	var central_rate := WavesRunScript.fuel_rate_for_positions(Vector3.ZERO, positions[0], true)
	var drain_rate := WavesRunScript.fuel_rate_for_positions(Vector3(40.0, 0.0, 0.0), positions[0], false)
	_check(objective_rate > central_rate, "moving to the active objective restores fuel faster than central camping")
	_check(central_rate > 0.0, "central cresset remains a slow emergency recovery fallback for slower builds")
	_check(drain_rate < 0.0, "fuel still drains when the player is away from both recovery routes")
	_check(
		is_equal_approx(objective_rate, 0.25) and is_equal_approx(central_rate, 1.0 / 30.0),
		"objective and fallback rates preserve their authored recovery pacing"
	)
	print("WAVES FUEL OBJECTIVE RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
