extends Node

## Autoload facade for input rebinding — delegates to InputBindings (CFG-02).

signal bindings_changed(action: StringName)


func _ready() -> void:
	pass


func get_context_groups() -> Dictionary:
	return {
		"menu": [&"pause", &"inventory", &"talents"],
		"gameplay": InputBindings.REBINDABLE,
	}


func get_rebindable_actions() -> Array[StringName]:
	return InputBindings.get_rebindable_actions()


func get_action_events(action: StringName) -> Array:
	return InputBindings.get_action_events(action)


func get_action_label(action: StringName) -> String:
	return InputBindings.get_action_label(action)


func get_action_binding_text(action: StringName) -> String:
	return InputBindings.get_action_binding_text(action)


func rebind(action: StringName, event: InputEvent) -> Dictionary:
	var result := InputBindings.rebind(action, event)
	if bool(result.get("ok", false)):
		bindings_changed.emit(action)
		var bus := get_node_or_null("/root/UISymbolBus")
		if bus:
			bus.emit_invalidated(&"rebind")
	return result


## C-83: the settings UI committed rebinds through `InputMapService`, a thin facade that emits no
## `bindings_changed` and never invalidates the glyph cache — so rebinding dodge from Space to Shift
## left every prompt in the game showing Space until something unrelated invalidated the cache. The
## conflict-resolution half of that facade lives here now, so every write path signals.
func swap_binding(action: StringName, conflict: StringName, event: InputEvent) -> Dictionary:
	var result := InputBindings.swap_binding(action, conflict, event)
	if bool(result.get("ok", false)):
		bindings_changed.emit(action)
		bindings_changed.emit(conflict)
		_invalidate_glyphs()
	return result


func find_conflict(action: StringName, event: InputEvent) -> StringName:
	return InputBindings.find_conflict(action, event)


func conflicts() -> Dictionary:
	return InputBindings.conflicts()


func _invalidate_glyphs() -> void:
	var bus := get_node_or_null("/root/UISymbolBus")
	if bus:
		bus.emit_invalidated(&"rebind")


func reset_action(action: StringName) -> void:
	InputBindings.reset_action(action)
	bindings_changed.emit(action)
	var bus := get_node_or_null("/root/UISymbolBus")
	if bus:
		bus.emit_invalidated(&"rebind")


func reset_all() -> void:
	InputBindings.reset_all()
	bindings_changed.emit(StringName())
	var bus := get_node_or_null("/root/UISymbolBus")
	if bus:
		bus.emit_invalidated(&"rebind")
