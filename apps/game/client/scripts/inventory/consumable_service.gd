extends RefCounted
class_name ConsumableService

## Shared consumable dispatch for inventory UI, quick slots, and combat HUD (INV-04).

const BUFF_META_PREFIX := "consumable_buff_"


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
		"refillFlask":
			var heal_node := player.get_node_or_null("PlayerHeal") as PlayerHeal
			if heal_node == null:
				return false
			heal_node.grant_charge(maxi(1, int(effect.get("amount", 1))))
			return true
		"throw":
			return _apply_throwable(player, effect)
		"escape":
			if RunFlow == null or not RunFlow.is_run_active():
				return false
			RunFlow.return_to_hub(TranslationServer.translate("INV_ESCAPE_RETURNED"))
			return true
		"cure":
			var status_ctrl := player.get_node_or_null("StatusController") as StatusController
			if status_ctrl == null:
				return false
			status_ctrl.clear_all()
			return true
	return false


static func active_buff_stats(player: Node) -> Dictionary:
	var totals: Dictionary = {}
	if player == null or not is_instance_valid(player):
		return totals
	var now := Time.get_ticks_msec()
	for meta_name in player.get_meta_list():
		var key := str(meta_name)
		if not key.begins_with(BUFF_META_PREFIX):
			continue
		var entry: Variant = player.get_meta(key, {})
		if not entry is Dictionary:
			continue
		if int((entry as Dictionary).get("until", 0)) <= now:
			player.remove_meta(key)
			continue
		var stat := str((entry as Dictionary).get("stat", ""))
		if stat == "":
			continue
		totals[stat] = float(totals.get(stat, 0.0)) + float((entry as Dictionary).get("amount", 0.0))
	return totals


static func _apply_throwable(player: Node, effect: Dictionary) -> bool:
	var origin_node := player as Node3D
	if origin_node == null or player.get_tree() == null:
		return false
	var status_id := str(effect.get("statusId", ""))
	if status_id == "":
		return false
	var radius := float(effect.get("radius", 4.0))
	var radius_sq := radius * radius
	var duration := float(effect.get("duration", effect.get("amount", 6.0)))
	var origin := origin_node.global_position
	var affected := 0
	for node in player.get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_squared_to(origin) > radius_sq:
			continue
		var controller := enemy.get_node_or_null("StatusController") as StatusController
		if controller == null:
			continue
		controller.apply_status(status_id, 1, duration)
		affected += 1
	if VfxService:
		VfxService.play_rune_flare(origin)
	return affected > 0


static func _apply_consumable_status(player: Node, effect: Dictionary) -> bool:
	var status_id := str(effect.get("statusId", ""))
	var duration := float(effect.get("duration", 60.0))
	var amount := float(effect.get("amount", 0.0))
	if status_id.begins_with("elixir_"):
		var until := Time.get_ticks_msec() + int(duration * 1000.0)
		(
			player
			. set_meta(
				"%s%s" % [BUFF_META_PREFIX, status_id],
				{
					"until": until,
					"amount": amount,
					"stat": str(effect.get("stat", "")),
				}
			)
		)
		if InventoryService:
			InventoryService.apply_equipment_to_player_node(player)
		return true
	var status_ctrl := player.get_node_or_null("StatusController") as StatusController
	if status_ctrl == null:
		return false
	status_ctrl.apply_status(status_id, 1, duration)
	return true
