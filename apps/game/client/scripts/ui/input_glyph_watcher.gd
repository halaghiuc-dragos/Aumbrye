extends Node


signal device_family_changed

const JOYPAD_SWITCH_DEADZONE := 0.35

var _last_family: int = -1


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_last_family = int(InputGlyphService.current_family())


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion and absf(event.axis_value) < JOYPAD_SWITCH_DEADZONE:
		return
	if event is InputEventJoypadButton and not event.pressed:
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_set_family(_family_from_joy_event(event))
	elif event is InputEventKey or event is InputEventMouseButton:
		_set_family(InputGlyphService.DeviceFamily.KEYBOARD)


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if not connected and Input.get_connected_joypads().is_empty():
		_set_family(InputGlyphService.DeviceFamily.KEYBOARD)


func _family_from_joy_event(event: InputEvent) -> int:
	var device := 0
	if event is InputEventJoypadButton:
		device = event.device
	elif event is InputEventJoypadMotion:
		device = event.device
	var identity := "%s %s" % [Input.get_joy_guid(device), Input.get_joy_name(device)]
	identity = identity.to_lower()
	if "xbox" in identity or "xinput" in identity:
		return InputGlyphService.DeviceFamily.XBOX
	if "sony" in identity or "playstation" in identity or "dualshock" in identity or "dualsense" in identity:
		return InputGlyphService.DeviceFamily.PLAYSTATION
	return InputGlyphService.DeviceFamily.GENERIC


func _set_family(family: int) -> void:
	if family == _last_family:
		return
	_last_family = family
	InputGlyphService.set_family(family)
	device_family_changed.emit()
	var bus := get_node_or_null("/root/UISymbolBus")
	if bus:
		bus.invalidate(&"device")
