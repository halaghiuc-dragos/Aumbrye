class_name FloorKeyring
extends RefCounted

## The keys the player is carrying on the current floor.
##
## Doom's keycards, not loot. A key takes no bag space, cannot be dropped, sold or stashed, and is
## never spent -- picking up the red key opens every red door on that floor for as long as you are
## on it, and taking the stairs leaves the whole ring behind. That is what makes a locked door a
## navigation problem rather than a shopping list: the question is "have I found it yet", not
## "can I afford it".
##
## Held keys are `WorldState` flags rather than a store of their own, which means they persist into
## the run snapshot, come back correctly when a run is continued, and already have a change signal
## the HUD can listen to.

const COLOR_ORDER: Array[String] = ["red", "blue", "yellow"]

## Doom's three keycards. The order is fixed so the first lock on a floor is always the red one --
## a player learns to read the colour as "how deep is this door" without being told.
const COLORS := {
	"red": {"label": "Red Key", "tint": Color(0.85, 0.18, 0.18)},
	"blue": {"label": "Blue Key", "tint": Color(0.25, 0.45, 0.95)},
	"yellow": {"label": "Yellow Key", "tint": Color(0.95, 0.80, 0.20)},
}


## The colour for the nth lock on a floor. Floors past three locks reuse colours from the start.
static func color_for_index(index: int) -> String:
	if index < 0:
		return COLOR_ORDER[0]
	return COLOR_ORDER[index % COLOR_ORDER.size()]


static func color_of(key_id: String) -> String:
	for color in COLOR_ORDER:
		if key_id.ends_with("_" + color) or key_id == color:
			return color
	return ""


static func label_for(key_id: String) -> String:
	var color := color_of(key_id)
	if color == "":
		return "Key"
	return str(COLORS[color]["label"])


static func tint_for(key_id: String) -> Color:
	var color := color_of(key_id)
	if color == "":
		return Color.WHITE
	return COLORS[color]["tint"]


static func is_held(key_id: String) -> bool:
	if key_id == "" or WorldState == null:
		return false
	return WorldState.is_flag_true(WorldFlags.key_held(key_id))


## Picks a key up. Returns false when it was already held, so a pickup cannot fire twice.
static func take(key_id: String) -> bool:
	if key_id == "" or WorldState == null:
		return false
	if is_held(key_id):
		return false
	WorldState.set_flag(WorldFlags.key_held(key_id), true)
	return true


static func held_colors() -> Array[String]:
	var out: Array[String] = []
	if WorldState == null:
		return out
	for color in COLOR_ORDER:
		for key_id in _held_key_ids():
			if color_of(key_id) == color:
				out.append(color)
				break
	return out


static func _held_key_ids() -> Array[String]:
	var out: Array[String] = []
	if WorldState == null:
		return out
	for flag_id in WorldState.all_flags():
		var id := str(flag_id)
		if not id.begins_with(WorldFlags.NS_KEY + "."):
			continue
		if not WorldState.is_flag_true(id):
			continue
		out.append(id.substr(WorldFlags.NS_KEY.length() + 1).trim_suffix(".held"))
	return out


## Empties the ring. Called when the player leaves a floor, in either direction.
static func clear() -> void:
	if WorldState == null:
		return
	for key_id in _held_key_ids():
		WorldState.set_flag(WorldFlags.key_held(key_id), false)
