extends RefCounted
class_name InputGlyphService

## POLISH-7.1 — dynamic controller/keyboard glyph labels.

enum DeviceFamily { KEYBOARD, XBOX, PLAYSTATION, GENERIC }

static var _family := DeviceFamily.KEYBOARD


static func detect_family() -> DeviceFamily:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		_family = DeviceFamily.KEYBOARD
		return _family
	var guid := Input.get_joy_guid(pads[0])
	if "xbox" in guid.to_lower() or "xinput" in guid.to_lower():
		_family = DeviceFamily.XBOX
	elif "sony" in guid.to_lower() or "playstation" in guid.to_lower() or "dualshock" in guid.to_lower():
		_family = DeviceFamily.PLAYSTATION
	else:
		_family = DeviceFamily.GENERIC
	return _family


static func get_action_glyph(action: String) -> String:
	detect_family()
	match _family:
		DeviceFamily.XBOX:
			return _xbox_glyph(action)
		DeviceFamily.PLAYSTATION:
			return _playstation_glyph(action)
		DeviceFamily.GENERIC:
			return _generic_glyph(action)
		_:
			return _keyboard_glyph(action)


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
		_:
			return action.replace("_", " ").capitalize()


static func format_action_hint(action: String) -> String:
	return "%s %s" % [get_action_display_name(action), get_action_glyph(action)]


static func _keyboard_glyph(action: String) -> String:
	match action:
		"interact": return "E"
		"ui_accept": return "Enter"
		"ui_cancel": return "Esc"
		"inventory": return "I"
		"pause": return "Esc"
		"lock_on": return "Tab"
		"sprint": return "Shift"
		"dodge": return "Space"
		"jump": return "F"
		_: return action.substr(0, 1).to_upper()


static func _xbox_glyph(action: String) -> String:
	match action:
		"interact": return "A"
		"ui_accept": return "A"
		"ui_cancel": return "B"
		"inventory": return "Y"
		"pause": return "Menu"
		"lock_on": return "RB"
		"sprint": return "LS"
		"dodge": return "B"
		"jump": return "A"
		_: return "A"


static func _playstation_glyph(action: String) -> String:
	match action:
		"interact": return "Cross"
		"ui_accept": return "Cross"
		"ui_cancel": return "Circle"
		"inventory": return "Triangle"
		"pause": return "Options"
		"lock_on": return "R1"
		"sprint": return "L3"
		"dodge": return "Circle"
		"jump": return "Cross"
		_: return "Cross"


static func _generic_glyph(action: String) -> String:
	match action:
		"interact": return "Btn 0"
		"ui_accept": return "Btn 0"
		"ui_cancel": return "Btn 1"
		_: return "Btn"
