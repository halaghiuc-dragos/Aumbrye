class_name GuardIndicator
extends RefCounted


## The parry/block *timing* used to be readable straight off the HUD -- a countdown bar for the
## perfect-parry window, another for how long the block itself was still up. Removed on request:
## parrying and blocking are meant to be learned by feel (the swing, the animation, the sound),
## not read off a gauge. The one thing this still surfaces is the riposte prompt after a successful
## parry -- that is a "you can act now" interaction cue, not a timing readout, the same kind of
## prompt any other interactable gives.
static func update(
	guard: Guard,
	parry_bar: ProgressBar,
	block_bar: ProgressBar,
	parry_label: Label,
	riposte_timer: float
) -> float:
	parry_bar.visible = false
	block_bar.visible = false
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
