extends Node


signal device_family_changed

var _last_family: int = -1


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_last_family = int(InputGlyphService.current_family())


func _input(event: InputEvent) -> void:
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
	var guid := Input.get_joy_guid(device).to_lower()
	if "xbox" in guid or "xinput" in guid:
		return InputGlyphService.DeviceFamily.XBOX
	if "sony" in guid or "playstation" in guid or "dualshock" in guid or "dualsense" in guid:
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
