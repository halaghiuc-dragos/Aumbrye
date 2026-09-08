extends RefCounted

## Resources belong to the run, including while its world scene is being rebuilt.
static func capture(player: Node) -> Dictionary:
	if not is_instance_valid(player):
		return {}
	var state := {}
	for spec in [["Health", "health"], ["Stamina", "stamina"], ["Mana", "mana"]]:
		var component := player.get_node_or_null(spec[0])
		if component:
			state[spec[1]] = float(component.get("current"))
	var heal := player.get_node_or_null("PlayerHeal") as PlayerHeal
	if heal:
		# A interrupted/reloaded drink still spends its charge, even before the gulp.
		state["flaskCharges"] = maxi(0, heal.current_charges - (1 if heal.is_drinking else 0))
	var arrows := player.get_node_or_null("PlayerArrows") as PlayerArrows
	if arrows:
		state["arrows"] = arrows.current_arrows
	return state


static func restore(player: Node, state: Dictionary) -> void:
	if not is_instance_valid(player):
		return
	var health := player.get_node_or_null("Health") as Health
	if health and state.has("health"):
		health.restore_current(_finite_value(state["health"], health.current))
	var stamina := player.get_node_or_null("Stamina") as Stamina
	if stamina and state.has("stamina"):
		stamina.reset_stamina()
		stamina.current = clampf(_finite_value(state["stamina"], stamina.current), 0.0, stamina.max_stamina)
		stamina._exhausted = stamina.current <= 0.0
		stamina._regen_timer = Stamina.REGEN_DELAY
		stamina.stamina_changed.emit(stamina.current, stamina.max_stamina)
	var mana := player.get_node_or_null("Mana") as Mana
	if mana and state.has("mana"):
		mana.reset_mana()
		mana.current = clampf(_finite_value(state["mana"], mana.current), 0.0, mana.max_mana)
		mana._regen_timer = Mana.REGEN_DELAY
		mana.mana_changed.emit(mana.current, mana.max_mana)
	var heal := player.get_node_or_null("PlayerHeal") as PlayerHeal
	if heal and state.has("flaskCharges"):
		heal.current_charges = clampi(int(_finite_value(state["flaskCharges"], heal.current_charges)), 0, heal.max_charges)
		heal.charges_changed.emit(heal.current_charges, heal.max_charges)
	var arrows := player.get_node_or_null("PlayerArrows") as PlayerArrows
	if arrows and state.has("arrows"):
		arrows.current_arrows = clampi(int(_finite_value(state["arrows"], arrows.current_arrows)), 0, arrows.max_arrows)
		arrows.arrows_changed.emit(arrows.current_arrows, arrows.max_arrows)


static func _finite_value(value: Variant, fallback: float) -> float:
	if not (value is int or value is float):
		return fallback
	var number := float(value)
	return number if is_finite(number) else fallback
