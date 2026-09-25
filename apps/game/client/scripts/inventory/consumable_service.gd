extends RefCounted
class_name ConsumableService


const BUFF_META_PREFIX := "consumable_buff_"
const ThrowableProjectileScene := preload("res://scenes/combat/throwable_projectile.tscn")
const ProjectileContainerScript := preload("res://scripts/combat/projectile_container.gd")
const THROWABLE_SPEED := 16.0
const THROWABLE_ORIGIN_HEIGHT := 1.3


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


static func can_commit(player: Node) -> bool:
	if player == null:
		return false
	var reactions := player.get_node_or_null("CombatReactions")
	if reactions and reactions.has_method("can_act") and not bool(reactions.call("can_act")):
		return false
	var weapon := player.get_node_or_null("WeaponController") as WeaponController
	if weapon and weapon.is_attacking:
		return false
	var dodge := player.get_node_or_null("Dodge") as Dodge
	if dodge and dodge.is_dodging:
		return false
	var guard := player.get_node_or_null("Guard") as Guard
	if guard and guard.is_guard_active:
		return false
	var heal := player.get_node_or_null("PlayerHeal") as PlayerHeal
	return heal == null or not heal.is_drinking


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
			if health == null or health.current >= health.max_health:
				return false
			health.heal(float(effect.get("amount", 30.0)))
			return true
		"restoreMana":
			var mana := player.get_node_or_null("Mana") as Mana
			if mana == null or mana.current >= mana.max_mana:
				return false
			mana.restore(float(effect.get("amount", 30.0)))
			return true
		"restoreStamina":
			var stamina := player.get_node_or_null("Stamina") as Stamina
			if stamina == null or stamina.current >= stamina.max_stamina:
				return false
			stamina.restore(float(effect.get("amount", 30.0)))
			return true
		"applyStatus":
			return _apply_consumable_status(player, effect)
		"skipFloors":
			return false
		"refillFlask":
			var heal_node := player.get_node_or_null("PlayerHeal") as PlayerHeal
			if heal_node == null or heal_node.current_charges >= heal_node.max_charges:
				return false
			heal_node.grant_charge(maxi(1, int(effect.get("amount", 1))))
			return true
		"throw":
			return _apply_throwable(player, effect)
		"throwable":
			return _apply_throwable_projectile(player, effect)
		"escape":
			if RunFlow == null or not RunFlow.is_run_active():
				return false
			return bool(RunFlow.escape_with_loot())
		"cure":
			var status_ctrl := player.get_node_or_null("StatusController") as StatusController
			if status_ctrl == null:
				return false
			return status_ctrl.cleanse_debuffs()
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


## `RG-04`: unlike `_apply_throwable()` (an instant AoE centred on the player), this actually spawns
## a `Projectile` aimed downrange -- the melee build's answer to an archer on a ledge, not a status
## the player has to already be standing in melee range to apply.
static func _apply_throwable_projectile(player: Node, effect: Dictionary) -> bool:
	var origin_node := player as Node3D
	if origin_node == null or player.get_tree() == null or player.get_tree().current_scene == null:
		return false
	var weapon := player.get_node_or_null("WeaponController") as WeaponController
	var origin := origin_node.global_position + Vector3(0.0, THROWABLE_ORIGIN_HEIGHT, 0.0)
	var direction := Vector3.FORWARD
	var target_pos := Vector3.INF
	if weapon and weapon.has_method("get_soft_lock_aim_direction"):
		direction = weapon.call("get_soft_lock_aim_direction")
		if weapon.has_method("get_aim_point"):
			target_pos = weapon.call("get_aim_point", origin)
			direction = (target_pos - origin).normalized()
	elif player.has_method("get_facing_direction"):
		direction = player.call("get_facing_direction")
	var projectile: Node3D = ProjectileContainerScript.acquire(player, ThrowableProjectileScene)
	if projectile == null:
		return false
	projectile.global_position = origin
	projectile.call(
		"configure",
		str(effect.get("statusId", "")),
		int(effect.get("statusStacks", 1)),
		float(effect.get("duration", 6.0)),
		float(effect.get("radius", 4.0)),
		float(effect.get("damage", 0.0)),
		str(effect.get("damageType", DamageInfo.TYPE_PHYSICAL)),
		bool(effect.get("lure", false)),
		str(effect.get("projectileArchetype", "lobbed_item"))
	)
	projectile.call(
		"launch", direction, THROWABLE_SPEED, 0.0, 0.0, player, DamageInfo.TYPE_PHYSICAL, "", 1, 0.0, 1.5, "blockable", 0.0, target_pos
	)
	return true


static func _apply_consumable_status(player: Node, effect: Dictionary) -> bool:
	var status_id := str(effect.get("statusId", ""))
	var duration := float(effect.get("duration", 60.0))
	var amount := float(effect.get("amount", 0.0))
	if status_id.begins_with("elixir_"):
		if RunBuffs == null or not RunBuffs.add_temporary_effect(status_id, str(effect.get("stat", "")), amount, duration):
			return false
		if InventoryService:
			InventoryService.apply_equipment_to_player_node(player)
		return true
	var status_ctrl := player.get_node_or_null("StatusController") as StatusController
	if status_ctrl == null:
		return false
	status_ctrl.apply_status(status_id, 1, duration)
	return true
