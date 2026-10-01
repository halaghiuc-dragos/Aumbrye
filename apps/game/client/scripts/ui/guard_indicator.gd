class_name GuardIndicator
extends RefCounted


## Parrying and blocking are learned by feel (the swing, the animation, the sound), not read off a
## gauge. The one thing the HUD surfaces is the riposte prompt after a successful parry: a "you can
## act now" cue, the same kind of prompt any other interactable gives.
static func update(guard: Guard, parry_label: Label, riposte_timer: float) -> float:
	if guard == null:
		parry_label.visible = false
		return 0.0
	var kept := riposte_timer
	if riposte_timer > 0.0 and guard.riposte_active:
		parry_label.visible = true
		parry_label.text = TranslationServer.translate("HUD_RIPOSTE_READY")
	else:
		kept = 0.0
		parry_label.visible = false
	return kept
