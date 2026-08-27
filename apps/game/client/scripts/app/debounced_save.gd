class_name DebouncedSave
extends RefCounted


## Coalesces a burst of settings changes into one write.
##
## The audio, accessibility and diorama settings modules each carried their own copy of this timer
## dance. Keyed per module, so they debounce independently; a second request inside the window
## pushes the deadline out rather than starting a second timer.
static var _timers: Dictionary = {}


static func request(key: StringName, seconds: float, on_due: Callable) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		on_due.call()
		return
	var pending: SceneTreeTimer = _timers.get(key)
	if pending != null and is_instance_valid(pending):
		pending.time_left = seconds
		return
	var timer := tree.create_timer(seconds)
	_timers[key] = timer
	timer.timeout.connect(
		func() -> void:
			_timers.erase(key)
			on_due.call(),
		CONNECT_ONE_SHOT
	)
