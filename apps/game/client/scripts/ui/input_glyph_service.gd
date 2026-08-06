extends RefCounted
class_name InputGlyphService

## Resolves input prompts through the shared glyph atlas (SIG-01..SIG-07).

enum DeviceFamily { KEYBOARD, XBOX, PLAYSTATION, GENERIC }

const InputGlyphAtlasScript := preload("res://scripts/ui/input_glyph_atlas.gd")

static var _family := DeviceFamily.KEYBOARD
static var _texture_cache: Dictionary = {}
static var _bus_wired := false


static func connect_device_family_changed(callback: Callable) -> void:
	var watcher := _get_watcher()
	if watcher and watcher.has_signal("device_family_changed"):
		watcher.device_family_changed.connect(callback)


static func disconnect_device_family_changed(callback: Callable) -> void:
	var watcher := _get_watcher()
	if watcher and watcher.device_family_changed.is_connected(callback):
		watcher.device_family_changed.disconnect(callback)


static func emit_device_family_changed_for_test() -> void:
	var watcher := _get_watcher()
	if watcher:
		watcher.device_family_changed.emit()


static func current_family() -> DeviceFamily:
	return _family


static func set_family(family: DeviceFamily) -> void:
	_family = family


static func invalidate_caches() -> void:
	_texture_cache.clear()
	InputGlyphAtlasScript.invalidate()


static func _get_watcher() -> Node:
	if Engine.get_main_loop() == null:
		return null
	return Engine.get_main_loop().root.get_node_or_null("/root/InputGlyphWatcher")


static func _ensure_bus_wired() -> void:
	if _bus_wired:
		return
	var bus := _get_symbol_bus()
	if bus == null:
		return
	if not bus.symbols_invalidated.is_connected(_on_symbols_invalidated):
		bus.symbols_invalidated.connect(_on_symbols_invalidated)
	_bus_wired = true


static func _get_symbol_bus() -> Node:
	if Engine.get_main_loop() == null:
		return null
	return Engine.get_main_loop().root.get_node_or_null("/root/UISymbolBus")


static func _on_symbols_invalidated(_reason: StringName) -> void:
	invalidate_caches()


static func detect_family() -> DeviceFamily:
	return _family


static func get_action_glyph_texture(action: String) -> AtlasTexture:
	_ensure_bus_wired()
	var cache_key := "%s:%d" % [action, int(_family)]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	var cell_key := _cell_key_for_action(action, _family)
	var tex := InputGlyphAtlasScript.get_glyph(cell_key)
	_texture_cache[cache_key] = tex
	return tex


static func get_action_glyph(action: String) -> String:
	return _text_for_action(action, _family)


static func format_interact_label(prefix: String = "Press") -> String:
	return "%s %s" % [prefix, get_action_glyph("interact")]


static func get_action_display_name(action: String) -> String:
	match action:
		"dodge":
			return "Dash"
		"sprint":
			return "Sprint"
		"lock_on":
			return "Lock"
		"inventory":
			return "Inventory"
		"interact":
			return "Interact"
		"jump":
			return "Jump"
		"pause":
			return "Pause"
		"weapon_art":
			return "Weapon art"
		"quick_slot_cycle":
			return "Cycle quick slot"
		"quick_slot_use":
			return "Use quick slot"
		"ui_left", "ui_right", "ui_up", "ui_down":
			return action.replace("ui_", "").capitalize()
		"ui_accept":
			return "Confirm"
		"ui_cancel":
			return "Close"
		"quick_slot_1", "quick_slot_2", "quick_slot_3", "quick_slot_4":
			return action.replace("_", " ").capitalize()
		_:
			return action.replace("_", " ").capitalize()


static func format_action_hint(action: String) -> String:
	return "%s %s" % [get_action_display_name(action), get_action_glyph(action)]


static func _cell_key_for_action(action: String, family: DeviceFamily) -> String:
	var event := _primary_event(action, family)
	if event != null:
		return _event_cell_key(event, family)
	return _fallback_cell_key(action, family)


static func _primary_event(action: String, family: DeviceFamily) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for event in InputMap.action_get_events(action):
		if family == DeviceFamily.KEYBOARD:
			if event is InputEventKey:
				return event
		elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return event
	return null


static func _event_cell_key(event: InputEvent, family: DeviceFamily) -> String:
	if event is InputEventKey:
		var keycode: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		var key_name := OS.get_keycode_string(keycode).to_upper()
		if key_name.is_empty():
			key_name = OS.get_keycode_string(event.keycode).to_upper()
		return "keyboard/%s" % key_name
	if event is InputEventJoypadButton:
		return "%s/%d" % [_family_prefix(family), event.button_index]
	if event is InputEventJoypadMotion:
		return "%s/axis_%d" % [_family_prefix(family), event.axis]
	return "unknown"


static func _fallback_cell_key(action: String, family: DeviceFamily) -> String:
	match family:
		DeviceFamily.XBOX:
			return _xbox_cell_key(action)
		DeviceFamily.PLAYSTATION:
			return _playstation_cell_key(action)
		DeviceFamily.GENERIC:
			return _generic_cell_key(action)
		_:
			return _keyboard_cell_key(action)


static func _family_prefix(family: DeviceFamily) -> String:
	match family:
		DeviceFamily.XBOX:
			return "xbox"
		DeviceFamily.PLAYSTATION:
			return "playstation"
		DeviceFamily.GENERIC:
			return "generic"
		_:
			return "keyboard"


static func _keyboard_cell_key(action: String) -> String:
	match action:
		"interact":
			return "keyboard/E"
		"ui_accept":
			return "keyboard/ENTER"
		"ui_cancel":
			return "keyboard/ESC"
		"inventory":
			return "keyboard/TAB"
		"pause":
			return "keyboard/ESC"
		"lock_on":
			return "keyboard/TAB"
		"sprint":
			return "keyboard/SHIFT"
		"dodge":
			return "keyboard/SPACE"
		"jump":
			return "keyboard/F"
		"ui_left":
			return "keyboard/LEFT"
		"ui_right":
			return "keyboard/RIGHT"
		"ui_up":
			return "keyboard/UP"
		"ui_down":
			return "keyboard/DOWN"
		_:
			var letter := action.substr(0, 1).to_upper()
			if letter.length() == 1:
				return "keyboard/%s" % letter
			return "unknown"


static func _xbox_cell_key(action: String) -> String:
	match action:
		"interact", "ui_accept", "jump":
			return "xbox/0"
		"ui_cancel", "dodge":
			return "xbox/1"
		"inventory":
			return "xbox/3"
		"pause":
			return "xbox/6"
		"lock_on":
			return "xbox/5"
		"sprint":
			return "xbox/8"
		_:
			return "xbox/0"


static func _playstation_cell_key(action: String) -> String:
	match action:
		"interact", "ui_accept", "jump":
			return "playstation/0"
		"ui_cancel", "dodge":
			return "playstation/1"
		"inventory":
			return "playstation/3"
		"pause":
			return "playstation/6"
		"lock_on":
			return "playstation/5"
		"sprint":
			return "playstation/10"
		_:
			return "playstation/0"


static func _generic_cell_key(action: String) -> String:
	match action:
		"interact", "ui_accept":
			return "generic/0"
		"ui_cancel":
			return "generic/1"
		_:
			return "generic/0"


static func _text_for_action(action: String, family: DeviceFamily) -> String:
	var event := _primary_event(action, family)
	if event is InputEventKey:
		var keycode: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		var label := OS.get_keycode_string(keycode)
		if label.is_empty():
			label = OS.get_keycode_string(event.keycode)
		return label
	if event is InputEventJoypadButton:
		return _joy_button_label(event.button_index, family)
	match family:
		DeviceFamily.XBOX:
			return _xbox_text(action)
		DeviceFamily.PLAYSTATION:
			return _playstation_text(action)
		DeviceFamily.GENERIC:
			return _generic_text(action)
		_:
			return _keyboard_text(action)


static func _joy_button_label(button_index: int, family: DeviceFamily) -> String:
	match family:
		DeviceFamily.XBOX:
			match button_index:
				0:
					return "A"
				1:
					return "B"
				3:
					return "Y"
				5:
					return "RB"
				6:
					return "Menu"
				8:
					return "LS"
				_:
					return "Btn %d" % button_index
		DeviceFamily.PLAYSTATION:
			match button_index:
				0:
					return "Cross"
				1:
					return "Circle"
				3:
					return "Triangle"
				5:
					return "R1"
				6:
					return "Options"
				10:
					return "L3"
				_:
					return "Btn %d" % button_index
		_:
			return "Btn %d" % button_index


static func _keyboard_text(action: String) -> String:
	match action:
		"interact":
			return "E"
		"ui_accept":
			return "Enter"
		"ui_cancel":
			return "Esc"
		"inventory":
			return "Tab"
		"pause":
			return "Esc"
		"lock_on":
			return "Tab"
		"sprint":
			return "Shift"
		"dodge":
			return "Space"
		"jump":
			return "F"
		"ui_left":
			return "Left"
		"ui_right":
			return "Right"
		"ui_up":
			return "Up"
		"ui_down":
			return "Down"
		_:
			return action.substr(0, 1).to_upper()


static func _xbox_text(action: String) -> String:
	match action:
		"interact", "ui_accept", "jump":
			return "A"
		"ui_cancel", "dodge":
			return "B"
		"inventory":
			return "Y"
		"pause":
			return "Menu"
		"lock_on":
			return "RB"
		"sprint":
			return "LS"
		_:
			return "A"


static func _playstation_text(action: String) -> String:
	match action:
		"interact", "ui_accept", "jump":
			return "Cross"
		"ui_cancel", "dodge":
			return "Circle"
		"inventory":
			return "Triangle"
		"pause":
			return "Options"
		"lock_on":
			return "R1"
		"sprint":
			return "L3"
		_:
			return "Cross"


static func _generic_text(action: String) -> String:
	match action:
		"interact", "ui_accept":
			return "Btn 0"
		"ui_cancel":
			return "Btn 1"
		_:
			return "Btn"
