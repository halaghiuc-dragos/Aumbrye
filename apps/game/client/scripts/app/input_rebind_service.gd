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
