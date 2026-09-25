extends Node

var _failures := 0


func _ready() -> void:
	var voice := AudioStreamPlayer.new()
	add_child(voice)
	AudioDirector._prepare_voice(voice, "audit_cue", 1)
	AudioDirector._prepare_voice(voice, "audit_cue", 1)
	_check(voice.finished.get_connections().size() == 1, "pooled voice keeps exactly one finished listener")
	voice.finished.emit()
	_check(not voice.has_meta(&"sfx_kind"), "finished voice releases ownership metadata")
	print("AUDIO VOICE LIFECYCLE RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(label)
