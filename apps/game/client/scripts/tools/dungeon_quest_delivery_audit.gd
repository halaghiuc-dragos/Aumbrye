extends Node

const DialogueRunnerScript := preload("res://scripts/dialogue/dialogue_runner.gd")
const ValidatorScript := preload("res://scripts/dungeon/procgen/room_content_validator.gd")

var _failures := 0
var _saved_inventory: Dictionary
var _saved_receipt: Variant


func _ready() -> void:
	_saved_inventory = InventoryService.inventory.to_save_dict()
	_saved_receipt = CharacterService.get_flag("receipt_dungeon_stranded_scout", null)
	CharacterService.set_flag("receipt_dungeon_stranded_scout", false)
	InventoryService.inventory.from_save_dict({})
	_check_catalog_contract()
	_check_payment_receipt()
	_check_pickup_reachability()
	_restore()
	print("DUNGEON QUEST DELIVERY RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_catalog_contract() -> void:
	var scout := DungeonQuestCatalog.quest_for_id("dungeon_stranded_scout")
	var delivery := DungeonQuestCatalog.delivery_for_quest(scout)
	_check(str(delivery.get("kind", "")) == "npc_payment", "scout uses explicit NPC payment")
	_check(str(delivery.get("receiptFlag", "")) != "", "scout payment has a receipt")
	var no_chest := ValidatorScript.validate_quest_delivery(delivery, {}, {}, [])
	_check(bool(no_chest.get("ok", false)), "NPC payment does not require a reward chest")


func _check_payment_receipt() -> void:
	InventoryService.add_item("iron_scrap", 2)
	var before := InventoryService.count_item("iron_scrap")
	var runner := DialogueRunnerScript.new()
	_check(
		bool(runner.call("_apply_actions", [{"type": "grant_dungeon_payment", "questId": "dungeon_stranded_scout"}])),
		"scout payment succeeds even when ordinary scrap was collected first"
	)
	_check(
		InventoryService.count_item("iron_scrap") == before + 1
		and CharacterService.is_flag_truthy("receipt_dungeon_stranded_scout"),
		"payment adds exactly one earned receipt-backed item"
	)
	_check(
		not bool(runner.call("_apply_actions", [{"type": "grant_dungeon_payment", "questId": "dungeon_stranded_scout"}])),
		"receipt prevents a second scout payment"
	)


func _check_pickup_reachability() -> void:
	var delivery := {"kind": "required_pickup", "itemId": "iron_scrap"}
	var npc := {"rewardPlacementId": "pickup"}
	var locked := {
		"placementId": "pickup", "roomId": "vault", "contentType": "locked_vault",
		"items": [{"itemId": "iron_scrap"}],
	}
	var locked_result := ValidatorScript.validate_quest_delivery(delivery, npc, {"pickup": locked}, ["vault"])
	_check(not bool(locked_result.get("ok", false)), "required pickup behind an unrelated lock is rejected")
	var unreachable := {
		"placementId": "pickup", "roomId": "side_room", "contentType": "reward",
		"items": [{"itemId": "iron_scrap"}],
	}
	var unreachable_result := ValidatorScript.validate_quest_delivery(delivery, npc, {"pickup": unreachable}, ["start"])
	_check(not bool(unreachable_result.get("ok", false)), "required pickup outside the traversable route is rejected")
	var reachable_result := ValidatorScript.validate_quest_delivery(delivery, npc, {"pickup": unreachable}, ["start", "side_room"])
	_check(bool(reachable_result.get("ok", false)), "designated reachable pickup is accepted")


func _restore() -> void:
	InventoryService.inventory.from_save_dict(_saved_inventory)
	CharacterService.set_flag("receipt_dungeon_stranded_scout", _saved_receipt)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(label)
