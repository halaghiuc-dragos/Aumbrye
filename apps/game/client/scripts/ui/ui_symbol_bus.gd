extends Node

## Shared invalidation bus for UI symbol atlases (SIG-06).

signal symbols_invalidated(reason: StringName)


func _ready() -> void:
	symbols_invalidated.connect(_on_symbols_invalidated)
	if InputGlyphWatcher.has_signal("device_family_changed"):
		InputGlyphWatcher.device_family_changed.connect(
			func() -> void: symbols_invalidated.emit(&"device")
		)
	if InputRebindService.has_signal("bindings_changed"):
		InputRebindService.bindings_changed.connect(
			func(_action: StringName) -> void: symbols_invalidated.emit(&"rebind")
		)


func invalidate(reason: StringName) -> void:
	symbols_invalidated.emit(reason)


func _on_symbols_invalidated(reason: StringName) -> void:
	match reason:
		&"colorblind", &"preset":
			StatusIconAtlas.reload()
		&"device", &"rebind":
			InputGlyphService.invalidate_caches()
		_:
			StatusIconAtlas.reload()
			ItemIconAtlas.reload()
			InputGlyphService.invalidate_caches()
