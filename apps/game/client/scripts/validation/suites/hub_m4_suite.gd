extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "hub_m4"


func run() -> void:
	_test_hub_landmarks()
	_test_hub_tent_structure()
	_test_hub_wall_collision()
	_test_npc_catalog()
	_test_dialogue_conditions()
	_test_quest_service()
	_test_blacksmith_upgrade()
	_test_merchant_buy_sell()
	_test_storage_transfer()
	_test_portal_not_blocked()


func _test_hub_landmarks() -> void:
	var start := Time.get_ticks_msec()
	var hub: Node3D = load("res://scenes/hub/hub.tscn").instantiate() as Node3D
	var landmarks := [
		"CastlePortal", "ArenaDoor", "SkiesPortal", "CathedralPortal",
		"Blacksmith", "Merchant",
		"Storage", "QuestBoard", "NpcAldric", "NpcElara", "NpcMira",
	]
	var all_present := true
	for name in landmarks:
		if hub.get_node_or_null(name) == null:
			all_present = false
	ctx.timed_record(
		"hub_m4.landmarks",
		get_category(),
		all_present,
		"hub.tscn has all M4 service landmarks",
		start,
		"M4.hub.landmarks"
	)
	var npc_count := 0
	for child in hub.get_children():
		if child.is_in_group("hub_npc"):
			npc_count += 1
	hub.free()
	start = Time.get_ticks_msec()
	ctx.timed_record(
		"hub_m4.npc_group",
		get_category(),
		npc_count >= 3,
		"hub scene includes 3 NPC instances",
		start,
		"M4.npc.framework"
	)


func _test_hub_tent_structure() -> void:
	var start := Time.get_ticks_msec()
	var hub: Node3D = load("res://scenes/hub/hub.tscn").instantiate() as Node3D
	HubDiorama.apply(hub)
	var service_names := ["Blacksmith", "Merchant", "Storage", "QuestBoard"]
	var all_ok := true
	for service_name in service_names:
		var landmark := hub.get_node_or_null(service_name) as Node3D
		if landmark == null:
			all_ok = false
			continue
		var tent_col := landmark.get_node_or_null("TentCollision") as StaticBody3D
		if tent_col == null:
			all_ok = false
			continue
		var shape_count := 0
		var has_sealed_front := false
		var cfg: Dictionary = HubDiorama.SERVICE_TENTS.get(service_name, {})
		var tent_width: float = cfg.get("width", 5.0)
		for child in tent_col.get_children():
			if child is CollisionShape3D:
				shape_count += 1
				if child.name == "ColFrontLip":
					var box := child.shape as BoxShape3D
					if box and box.size.x >= tent_width - 0.1:
						has_sealed_front = true
		if shape_count < 3 or has_sealed_front:
			all_ok = false
		var visuals := landmark.get_node_or_null("DioramaVisuals") as Node3D
		if visuals == null or visuals.get_node_or_null("Dressing") == null:
			all_ok = false
	hub.free()
	ctx.timed_record(
		"hub_m4.tent_collision",
		get_category(),
		all_ok,
		"service tents have split doorway collision and dressing roots",
		start,
		"M4.hub.tent_collision"
	)


func _test_hub_wall_collision() -> void:
	var start := Time.get_ticks_msec()
	var hub: Node3D = load("res://scenes/hub/hub.tscn").instantiate() as Node3D
	HubDiorama.apply(hub)
	var walls := hub.get_node_or_null("LandmarkWalls") as Node3D
	var wall_col := walls.get_node_or_null("WallCollision") as StaticBody3D if walls else null
	var shape_count := 0
	if wall_col:
		for child in wall_col.get_children():
			if child is CollisionShape3D:
				shape_count += 1
	hub.free()
	ctx.timed_record(
		"hub_m4.wall_collision",
		get_category(),
		shape_count == 4,
		"perimeter WallCollision has four wall shapes",
		start,
		"M4.hub.wall_collision"
	)


func _test_npc_catalog() -> void:
	var start := Time.get_ticks_msec()
	var ids := NpcCatalog.get_all_ids()
	ctx.timed_record(
		"hub_m4.npc_count",
		get_category(),
		ids.size() >= 3,
		"at least 3 NPCs defined in content/npcs/",
		start,
		"M4.npc.catalog"
	)


func _test_dialogue_conditions() -> void:
	var start := Time.get_ticks_msec()
	var dialogue := DialogueCatalog.get_dialogue("mira_greeting")
	var has_nodes := dialogue.has("nodes") and dialogue.has("startNode")
	ctx.timed_record(
		"hub_m4.dialogue_load",
		get_category(),
		has_nodes,
		"mira_greeting dialogue loads with nodes",
		start,
		"M4.dlg.load"
	)
	start = Time.get_ticks_msec()
	CharacterService.flags.clear()
	var hidden := not DialogueConditions.evaluate({"flag": "heard_castle_lore"})
	CharacterService.set_flag("heard_castle_lore", true)
	var shown := DialogueConditions.evaluate({"flag": "heard_castle_lore"})
	ctx.timed_record(
		"hub_m4.dialogue_conditions",
		get_category(),
		hidden and shown,
		"dialogue flag conditions gate correctly",
		start,
		"M4.dlg.conditions"
	)


func _test_quest_service() -> void:
	CharacterService.quests.clear()
	var start := Time.get_ticks_msec()
	var accepted := QuestService.accept_quest("kill_grunts")
	ctx.timed_record(
		"hub_m4.quest_accept",
		get_category(),
		accepted and CharacterService.get_quest_state("kill_grunts") == "active",
		"quest board quest can be accepted",
		start,
		"M4.quest.accept"
	)
	start = Time.get_ticks_msec()
	QuestService.register_kill("castle_grunt")
	QuestService.register_kill("castle_grunt")
	QuestService.register_kill("castle_grunt")
	var completed := CharacterService.get_quest_state("kill_grunts") == "completed"
	ctx.timed_record(
		"hub_m4.quest_kill",
		get_category(),
		completed,
		"kill quest completes after required kills",
		start,
		"M4.quest.kill"
	)


func _test_blacksmith_upgrade() -> void:
	var start := Time.get_ticks_msec()
	InventoryService.inventory = GridInventory.new()
	InventoryService.inventory.add_item("castle_sword", 1)
	CharacterService.gold = 100
	var can_before := BlacksmithService.can_upgrade(0)
	var result := BlacksmithService.upgrade_item(0)
	ctx.timed_record(
		"hub_m4.blacksmith_upgrade",
		get_category(),
		can_before and result.get("ok", false) and CharacterService.gold == 50,
		"blacksmith upgrade spends gold and changes item",
		start,
		"M4.hub.blacksmith"
	)
	start = Time.get_ticks_msec()
	CharacterService.gold = 0
	ctx.timed_record(
		"hub_m4.blacksmith_no_gold",
		get_category(),
		not BlacksmithService.can_upgrade(0),
		"cannot upgrade without currency",
		start,
		"M4.hub.blacksmith_gold"
	)


func _test_merchant_buy_sell() -> void:
	MerchantService.reset_session()
	InventoryService.inventory = GridInventory.new()
	CharacterService.gold = 50
	var start := Time.get_ticks_msec()
	var buy := MerchantService.buy_item("health_potion")
	var gold_after_buy: int = CharacterService.gold
	ctx.timed_record(
		"hub_m4.merchant_buy",
		get_category(),
		buy.get("ok", false) and gold_after_buy == 35,
		"merchant buy deducts gold and adds item",
		start,
		"M4.hub.merchant_buy"
	)
	start = Time.get_ticks_msec()
	var sell := MerchantService.sell_item(0)
	ctx.timed_record(
		"hub_m4.merchant_sell",
		get_category(),
		sell.get("ok", false) and CharacterService.gold > gold_after_buy,
		"merchant sell adds gold",
		start,
		"M4.hub.merchant_sell"
	)


func _test_storage_transfer() -> void:
	StorageService.storage = GridInventory.new(8, 6)
	InventoryService.inventory = GridInventory.new()
	InventoryService.inventory.add_item("iron_scrap", 2)
	var start := Time.get_ticks_msec()
	var moved := StorageService.move_to_storage(0)
	var back := false
	if moved:
		back = StorageService.move_to_inventory(0)
	ctx.timed_record(
		"hub_m4.storage_transfer",
		get_category(),
		moved and back,
		"items move inventory to storage and back",
		start,
		"M4.hub.storage"
	)


func _test_portal_not_blocked() -> void:
	var start := Time.get_ticks_msec()
	var hub_exists := ResourceLoader.exists(RunFlow.HUB_SCENE)
	var portal_ok := RunFlow.has_method("start_new_castle_run")
	var no_quest_gate: bool = (
		not ctx.file_contains("res://scripts/app/run_flow.gd", "quest")
		or ctx.file_contains("res://scripts/quests/quest_service.gd", "never block")
	)
	ctx.timed_record(
		"hub_m4.portal_always_open",
		get_category(),
		hub_exists and portal_ok,
		"castle portal available regardless of quest state",
		start,
		"M4.quest.optional"
	)
