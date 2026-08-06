extends RefCounted
class_name ConsumableService

## Shared consumable dispatch for inventory UI, quick slots, and combat HUD (INV-04).


static func can_use(def: Dictionary, in_run: bool, in_hub: bool) -> Dictionary:
	var effect: Dictionary = def.get("consumableEffect", {})
	if effect.is_empty():
		return {"ok": false, "reason": TranslationServer.translate("INV_CONSUMABLE_NO_EFFECT")}
	var usable_run := bool(effect.get("usableInRun", true))
	var usable_hub := bool(effect.get("usableInHub", true))
	if in_run and not usable_run:
		return {"ok": false, "reason": TranslationServer.translate("INV_CONSUMABLE_RUN_BLOCKED")}
	if in_hub and not usable_hub:
		return {"ok": false, "reason": TranslationServer.translate("INV_CONSUMABLE_HUB_BLOCKED")}
	if str(effect.get("kind", "")) == "skipFloors":
		return {"ok": false, "reason": TranslationServer.translate("INV_SKIP_PORTAL_ONLY")}
	return {"ok": true, "reason": ""}


static func apply(def: Dictionary, player: Node) -> bool:
	if player == null:
		return false
	var health := player.get_node_or_null("Health") as Health
	if health and health.is_dead():
		return false
	var effect: Dictionary = def.get("consumableEffect", {})
	if effect.is_empty():
		return false
	var kind: String = str(effect.get("kind", ""))
	match kind:
		"heal":
			if health == null:
				return false
			health.heal(float(effect.get("amount", 30.0)))
			return true
		"restoreMana":
			var mana := player.get_node_or_null("Mana") as Mana
			if mana == null:
				return false
			mana.current = minf(mana.max_mana, mana.current + float(effect.get("amount", 30.0)))
			mana.mana_changed.emit(mana.current, mana.max_mana)
			return true
		"restoreStamina":
			var stamina := player.get_node_or_null("Stamina") as Stamina
			if stamina == null:
				return false
			stamina.current = minf(
				stamina.max_stamina, stamina.current + float(effect.get("amount", 30.0))
			)
			stamina.stamina_changed.emit(stamina.current, stamina.max_stamina)
			return true
		"applyStatus":
			return _apply_consumable_status(player, effect)
		"skipFloors":
			return false
		"cure":
			var status_ctrl := player.get_node_or_null("StatusController") as StatusController
			if status_ctrl == null:
				return false
			status_ctrl.clear_all()
			return true
	return false


static func _apply_consumable_status(player: Node, effect: Dictionary) -> bool:
	var status_id := str(effect.get("statusId", ""))
	var duration := float(effect.get("duration", 60.0))
	var amount := float(effect.get("amount", 0.0))
	if status_id.begins_with("elixir_"):
		var until := Time.get_ticks_msec() + int(duration * 1000.0)
		player.set_meta("consumable_buff_%s" % status_id, {"until": until, "amount": amount})
		if InventoryService:
			InventoryService.apply_equipment_to_player_node(player)
		return true
	var status_ctrl := player.get_node_or_null("StatusController") as StatusController
	if status_ctrl == null:
		return false
	status_ctrl.apply_status(status_id, 1, duration)
	return true
