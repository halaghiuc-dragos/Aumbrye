extends RefCounted
class_name InputBindings

## Runtime input rebinding overlay. Defaults come from project.godot; overrides live in LocalSave meta.

const SAVE_KEY := "input_bindings"

const REBINDABLE: Array[StringName] = [
	&"sprint",
	&"jump",
	&"dodge",
	&"light_attack",
	&"heavy_attack",
	&"block",
	&"lock_on",
	&"pause",
	&"inventory",
	&"talents",
	&"heal",
	&"interact",
	&"two_hand",
	&"weapon_art",
	&"quick_slot_1",
	&"quick_slot_2",
	&"quick_slot_3",
	&"quick_slot_4",
	&"quick_slot_cycle",
	&"quick_slot_use",
]

const KEYBOARD_ONLY: Array[StringName] = [
	&"toggle_camera",
	&"zoom_in",
	&"zoom_out",
	&"quick_slot_1",
	&"quick_slot_2",
	&"quick_slot_3",
	&"quick_slot_4",
]

static var _defaults: Dictionary = {}
static var _saved_bindings: Dictionary = {}


static func snapshot_defaults() -> void:
	_defaults.clear()
	for action in InputMap.get_actions():
		if str(action).begins_with("ui_"):
			continue
		var events: Array = []
		for event in InputMap.action_get_events(action):
			events.append(event.duplicate())
		_defaults[action] = events


static func load_from_save() -> void:
	_saved_bindings = LocalSave.get_meta_data().get(SAVE_KEY, {}).duplicate(true)
	if not _saved_bindings is Dictionary:
		_saved_bindings = {}


static func apply() -> void:
	for action_name in _saved_bindings.keys():
		var action := StringName(str(action_name))
		if not InputMap.has_action(action):
			continue
		var serialized_events: Variant = _saved_bindings[action_name]
		if not serialized_events is Array:
			continue
		InputMap.action_erase_events(action)
		for entry in serialized_events:
			if entry is Dictionary:
				var event := _deserialize_event(entry)
				if event != null:
					InputMap.action_add_event(action, event)


static func save() -> void:
	var meta := LocalSave.get_meta_data()
	meta[SAVE_KEY] = _serialize_all_overrides()
	LocalSave.set_meta_data(meta)
	LocalSave.autosave()


static func conflicts() -> Dictionary:
	var seen: Dictionary = {}
	var out: Dictionary = {}
	for action in REBINDABLE:
		if not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			var signature := _event_signature(event)
			if signature.is_empty():
				continue
			if signature in seen:
				var first: StringName = seen[signature]
				if signature not in out:
					out[signature] = [first]
				if action not in out[signature]:
					out[signature].append(action)
			else:
				seen[signature] = action
	return out


static func get_rebindable_actions() -> Array[StringName]:
	var actions := REBINDABLE.duplicate()
	actions.sort()
	return actions


static func get_action_label(action: StringName) -> String:
	return InputGlyphService.get_action_display_name(str(action))


static func get_action_events(action: StringName) -> Array:
	return _get_action_events(action)


static func get_action_binding_text(action: StringName) -> String:
	var parts: PackedStringArray = []
	for event in _get_action_events(action):
		parts.append(event.as_text())
	return ", ".join(parts) if not parts.is_empty() else "(unbound)"


static func find_conflict(action: StringName, event: InputEvent) -> StringName:
	return _find_conflict(action, event)


static func swap_binding(action: StringName, conflict: StringName, event: InputEvent) -> Dictionary:
	if action not in REBINDABLE or conflict not in REBINDABLE:
		return {"ok": false, "conflict": StringName()}
	var give_to_conflict: InputEvent = null
	for existing in _get_action_events(action):
		if _same_device_family(existing, event):
			give_to_conflict = existing
			break
	if give_to_conflict != null:
		_replace_matching_device_events(conflict, give_to_conflict.duplicate())
	else:
		for existing in _get_action_events(conflict):
			if _same_device_family(existing, event):
				InputMap.action_erase_event(conflict, existing)
				break
	_replace_matching_device_events(action, event)
	_persist_action_override(action)
	_persist_action_override(conflict)
	save()
	return {"ok": true, "conflict": conflict}


static func rebind(action: StringName, event: InputEvent) -> Dictionary:
	if action not in REBINDABLE:
		return {"ok": false, "conflict": StringName()}
	var conflict := _find_conflict(action, event)
	if conflict != &"":
		return {"ok": false, "conflict": conflict}
	_replace_matching_device_events(action, event)
	_persist_action_override(action)
	save()
	return {"ok": true, "conflict": StringName()}


static func reset_action(action: StringName) -> void:
	if not _defaults.has(action):
		return
	InputMap.action_erase_events(action)
	for default_event in _defaults[action]:
		InputMap.action_add_event(action, default_event.duplicate())
	_saved_bindings.erase(str(action))
	save()


static func reset_all() -> void:
	for action in _defaults.keys():
		InputMap.action_erase_events(action)
		for default_event in _defaults[action]:
			InputMap.action_add_event(action, default_event.duplicate())
	_saved_bindings.clear()
	save()


static func has_gamepad_event(action: StringName) -> bool:
	for event in _get_action_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false


static func _get_action_events(action: StringName) -> Array:
	return InputMap.action_get_events(action)


static func _serialize_all_overrides() -> Dictionary:
	var out: Dictionary = {}
	for action in REBINDABLE:
		var serialized: Array = []
		for event in _get_action_events(action):
			var default_events: Array = _defaults.get(action, [])
			var is_default := false
			for default_event in default_events:
				if _event_signature(default_event) == _event_signature(event):
					is_default = true
					break
			if not is_default:
				serialized.append(_serialize_event(event))
		if not serialized.is_empty():
			out[str(action)] = serialized
	return out


static func _persist_action_override(action: StringName) -> void:
	var serialized: Array = []
	for event in _get_action_events(action):
		serialized.append(_serialize_event(event))
	_saved_bindings[str(action)] = serialized


static func _find_conflict(action: StringName, event: InputEvent) -> StringName:
	var signature := _event_signature(event)
	for other_action in REBINDABLE:
		if other_action == action:
			continue
		for existing in _get_action_events(other_action):
			if _event_signature(existing) == signature:
				return other_action
	return &""


static func _replace_matching_device_events(action: StringName, event: InputEvent) -> void:
	var kept: Array = []
	for existing in _get_action_events(action):
		if not _same_device_family(existing, event):
			kept.append(existing)
	InputMap.action_erase_events(action)
	for kept_event in kept:
		InputMap.action_add_event(action, kept_event)
	InputMap.action_add_event(action, event.duplicate())


static func _same_device_family(a: InputEvent, b: InputEvent) -> bool:
	var a_joy := a is InputEventJoypadButton or a is InputEventJoypadMotion
	var b_joy := b is InputEventJoypadButton or b is InputEventJoypadMotion
	if a_joy or b_joy:
		return a_joy and b_joy
	return (
		(a is InputEventKey or a is InputEventMouseButton)
		and (b is InputEventKey or b is InputEventMouseButton)
	)


static func _event_signature(event: InputEvent) -> String:
	return event.as_text()


static func _serialize_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"type": "key", "code": event.physical_keycode, "value": 0.0}
	if event is InputEventMouseButton:
		return {"type": "mouse", "code": event.button_index, "value": 0.0}
	if event is InputEventJoypadButton:
		return {"type": "joy_button", "code": event.button_index, "value": 0.0}
	if event is InputEventJoypadMotion:
		return {"type": "joy_axis", "code": event.axis, "value": event.axis_value}
	return {}


static func _deserialize_event(data: Dictionary) -> InputEvent:
	match str(data.get("type", "")):
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(data.get("code", 0))
			return key
		"mouse":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(data.get("code", 0))
			return mouse
		"joy_button":
			var button := InputEventJoypadButton.new()
			button.button_index = int(data.get("code", 0))
			return button
		"joy_axis":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(data.get("code", 0))
			motion.axis_value = float(data.get("value", 0.0))
			return motion
		_:
			return null
