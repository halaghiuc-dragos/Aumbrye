extends Node

const HubScript := preload("res://scripts/hub/hub.gd")

var _failures := 0


func _ready() -> void:
	var key := "audit_telegraph_seen"
	var flags := HubTutorialService.queue_combat_teaching_flags({}, key, "TUTORIAL_TELEGRAPH_RED")
	_check(bool(flags.get(key, false)), "queueing marks the concept seen")
	_check(
		(flags.get(HubTutorialService.FLAG_PENDING_COMBAT_TEACHING, []) as Array).size() == 1,
		"first concept event queues one deferred teaching note"
	)
	flags = HubTutorialService.queue_combat_teaching_flags(flags, key, "TUTORIAL_TELEGRAPH_RED")
	_check(
		(flags.get(HubTutorialService.FLAG_PENDING_COMBAT_TEACHING, []) as Array).size() == 1,
		"repeated concept events do not duplicate a pending note"
	)
	flags = HubTutorialService.queue_combat_teaching_flags(flags, "audit_stamina_seen", "TUTORIAL_STAMINA_EXHAUSTED")
	var drained := HubTutorialService.drain_combat_teaching_flags(flags)
	var messages: Array[String] = drained.get("messages", [])
	var cleared_flags: Dictionary = drained.get("flags", {})
	_check(messages.size() == 2, "multiple lessons drain together at the safe hub point")
	var explains_pattern := false
	for message in messages:
		explains_pattern = explains_pattern or "double ring" in message.to_lower()
	_check(explains_pattern, "telegraph lesson explains its non-color pattern")
	_check((cleared_flags.get(HubTutorialService.FLAG_PENDING_COMBAT_TEACHING, []) as Array).is_empty(), "draining clears only pending lessons")
	_check(bool(cleared_flags.get(key, false)), "draining preserves seen state")
	var long_message := "Read the red double ring and its cone direction before deciding whether to guard or dodge through an unblockable attack."
	var wrapped := str(HubScript._wrap_world_message(long_message, 32))
	var wrapped_lines := wrapped.split("\n")
	var line_lengths_ok := true
	for line in wrapped_lines:
		line_lengths_ok = line_lengths_ok and line.length() <= 32
	_check(line_lengths_ok, "world coaching wraps each line to its configured character width")
	_check(" ".join(wrapped_lines) == long_message, "world coaching wrapping preserves the original words and order")
	print("TUTORIAL QUEUE RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
