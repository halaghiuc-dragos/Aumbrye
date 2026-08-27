class_name GuardIndicator
extends RefCounted


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
