class_name GuardIndicator
extends RefCounted

## Draws the parry window, the block reserve, and the riposte prompt.
##
## The riposte prompt is the part that did not previously exist anywhere: `Guard.riposte_ready`
## was emitted and never listened to, so the 1.4 s window in which a heavy press becomes a
## critical riposte was invisible — the player had to already know the mechanic existed and
## guess at its length.
##
## Lives outside `combat_hud.gd` so the HUD stays under the project's file-length limit.


## Updates all three indicators for one frame.
##
## Returns the riposte timer to keep, which is zero once the prompt has run out or the guard no
## longer holds a riposte — the caller owns the countdown, this owns the presentation.
static func update(
	guard: Guard,
	parry_bar: ProgressBar,
	block_bar: ProgressBar,
	parry_label: Label,
	riposte_timer: float
) -> float:
	if guard == null:
		parry_bar.visible = false
		block_bar.visible = false
		parry_label.visible = false
		return 0.0
	var parry_left := guard.get_parry_time_remaining()
	var block_left := guard.get_block_time_remaining()
	parry_bar.max_value = guard.get_parry_window_duration()
	block_bar.max_value = guard.get_block_window_duration()
	var kept := riposte_timer
	# Riposte outranks the parry tell: the parry has already succeeded, and the actionable
	# information is now the closing window to punish with.
	if riposte_timer > 0.0 and guard.riposte_active:
		parry_bar.visible = false
		parry_label.visible = true
		parry_label.text = TranslationServer.translate("HUD_RIPOSTE_READY")
	elif parry_left > 0.0:
		parry_bar.visible = true
		parry_bar.value = parry_left
		parry_label.visible = true
		parry_label.text = TranslationServer.translate("HUD_PARRY")
	else:
		kept = 0.0
		parry_bar.visible = false
		parry_label.visible = false
	if block_left > 0.0:
		block_bar.visible = true
		block_bar.value = block_left
	else:
		block_bar.visible = false
	return kept
