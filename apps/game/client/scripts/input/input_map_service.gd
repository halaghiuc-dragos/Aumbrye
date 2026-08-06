extends RefCounted
class_name InputMapService

## Persistence facade for input rebinding — delegates to InputBindings (SET-04).

static func set_binding(action: StringName, device_family: String, event: InputEvent) -> Dictionary:
	var _unused := device_family
	return InputBindings.rebind(action, event)


static func swap_binding(action: StringName, conflict: StringName, event: InputEvent) -> Dictionary:
	return InputBindings.swap_binding(action, conflict, event)


static func find_conflict(action: StringName, event: InputEvent) -> StringName:
	return InputBindings.find_conflict(action, event)


static func load_and_apply() -> void:
	InputBindings.load_from_save()
	InputBindings.apply()


static func conflicts() -> Dictionary:
	return InputBindings.conflicts()
