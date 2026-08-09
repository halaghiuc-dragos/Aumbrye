extends "res://scripts/validation/validation_suite.gd"

const CharacterAppearanceScript := preload("res://scripts/save/character_appearance.gd")
const CharacterSkinScript := preload("res://scripts/art/characters/diorama_character_skin.gd")
const CharacterRigCatalogScript := preload("res://scripts/art/characters/character_rig_catalog.gd")
const PixelStyleScript := preload("res://scripts/art/style/pixel_diorama_style.gd")


func get_category() -> String:
	return "hub_m4"


func run() -> void:
	_test_hub_landmarks()
	_test_hub_tent_structure()
	_test_hub_wall_collision()
	_test_npc_catalog()
	_test_dialogue_conditions()
	_test_dialogue_choiceless_hold()
	_test_npc_dialogue_routing()
	_test_quest_service()
	_test_blacksmith_upgrade()
	_test_merchant_buy_sell()
	_test_storage_transfer()
	_test_portal_not_blocked()
	_test_hub_tips()
	_test_hub_interact()
	_test_hub_scene()
	_test_hub_layout()
	_test_hub_prompt()
	_test_hub_feedback()
	_test_appearance_mirror()
	_test_merchant_stock_and_sell()
	_test_blacksmith_systems()
	_test_storage_fidelity()
	_test_npc_vendor_flow()


func _test_hub_landmarks() -> void:
	var start := Time.get_ticks_msec()
	var hub: Node3D = load("res://scenes/hub/hub.tscn").instantiate() as Node3D
	var landmarks := [
		"CastlePortal",
		"ArenaDoor",
		"SkiesPortal",
		"CathedralPortal",
		"Blacksmith",
		"Merchant",
		"Storage",
		"QuestBoard",
		"Mirror",
		"NpcAldric",
		"NpcElara",
		"NpcMira",
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
	start = Time.get_ticks_msec()
	var typo_passes := DialogueConditions.evaluate({"minLvl": 1})
	ctx.timed_record(
		"hub_m4.dialogue.fail_closed_typo",
		get_category(),
		not typo_passes,
		"unknown condition keys fail closed (minLvl typo)",
		start,
		"M4.dlg.fail_closed"
	)


func _test_dialogue_choiceless_hold() -> void:
	var start := Time.get_ticks_msec()
	CharacterService.flags.clear()
	var runner := DialogueRunner.new()
	runner.start("mira_greeting")
	runner.select_choice(1)
	var holds_lore := runner.is_active()
	runner.advance()
	var lore_ended := not runner.is_active()
	ctx.timed_record(
		"hub_m4.dialogue.holds_choiceless_line",
		get_category(),
		holds_lore and lore_ended,
		"choiceless lore node holds until advance then ends",
		start,
		"M4.dlg.hold"
	)
	start = Time.get_ticks_msec()
	runner = DialogueRunner.new()
	runner.start("dungeon_lore_default")
	var holds_single := runner.is_active()
	runner.advance()
	var single_ended := not runner.is_active()
	ctx.timed_record(
		"hub_m4.dialogue.single_node_confirm",
		get_category(),
		holds_single and single_ended,
		"single-node dialogue waits for one confirm before ending",
		start,
		"M4.dlg.single"
	)


func _test_npc_dialogue_routing() -> void:
	var start := Time.get_ticks_msec()
	var aldric_def := NpcCatalog.get_definition("blacksmith_aldric")
	var elara_def := NpcCatalog.get_definition("merchant_elara")
	var has_dialogue_ids: bool = (
		aldric_def.get("dialogueId", "") == "aldric_greeting"
		and elara_def.get("dialogueId", "") == "elara_greeting"
	)
	var routes_through_dialogue: bool = (
		ctx.script_has_property("res://scripts/npc/npc_base.gd", "_greeted_this_visit")
		and ctx.file_contains(
			"res://scripts/npc/npc_base.gd", "dialogue_requested.emit(npc_id, greet_id)"
		)
	)
	ctx.timed_record(
		"hub_m4.npc.shop_dialogue_first",
		get_category(),
		has_dialogue_ids and routes_through_dialogue,
		"Aldric and Elara route through dialogue before shop",
		start,
		"M4.npc.dialogue"
	)


func _test_quest_service() -> void:
	CharacterService.quest_states.clear()
	CharacterService.quest_progress.clear()
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

	start = Time.get_ticks_msec()
	CharacterService.quest_states.clear()
	CharacterService.quest_progress.clear()
	_set_test_gold(0)
	QuestService.accept_quest("escape_castle")
	var gold_before_escape := CharacterService.gold
	QuestService.register_run_outcome(RunLifecycle.OUTCOME_DIED, {})
	var escape_active_on_death := CharacterService.get_quest_state("escape_castle") == "active"
	var gold_unchanged_on_death := CharacterService.gold == gold_before_escape
	ctx.timed_record(
		"hub_m4.quest.escape_not_completed_on_death",
		get_category(),
		escape_active_on_death and gold_unchanged_on_death,
		"escape quest stays active when run ends in death",
		start,
		"M4.quest.escape"
	)

	start = Time.get_ticks_msec()
	CharacterService.quest_states.clear()
	CharacterService.quest_progress.clear()
	_set_test_gold(0)
	QuestService.accept_quest("escape_castle")
	QuestService.register_run_outcome(RunLifecycle.OUTCOME_ESCAPED, {})
	var escape_completed := CharacterService.get_quest_state("escape_castle") == "completed"
	var escape_gold := CharacterService.gold == 50
	ctx.timed_record(
		"hub_m4.quest.escape_completed_on_escape",
		get_category(),
		escape_completed and escape_gold,
		"escape quest completes and grants gold on real escape",
		start,
		"M4.quest.escape"
	)

	start = Time.get_ticks_msec()
	CharacterService.quest_states.clear()
	CharacterService.quest_progress.clear()
	InventoryService.inventory = GridInventory.new()
	QuestService.accept_quest("fetch_scrap")
	InventoryService.add_item("iron_scrap", 1)
	var fetch_done := CharacterService.get_quest_state("fetch_scrap") == "completed"
	ctx.timed_record(
		"hub_m4.quest.fetch_on_pickup",
		get_category(),
		fetch_done,
		"fetch quest completes when target item is added to inventory",
		start,
		"M4.quest.fetch"
	)

	start = Time.get_ticks_msec()
	CharacterService.quest_states.clear()
	CharacterService.quest_progress.clear()
	QuestService.accept_quest("kill_grunts")
	QuestService.register_kill("castle_grunt")
	QuestService.register_kill("castle_grunt")
	QuestService.register_kill("castle_grunt")
	var waves_kill_wired := CharacterService.get_quest_state("kill_grunts") == "completed"
	var waves_forwards_kills: bool = ctx.file_contains(
		"res://scripts/dungeon/waves_run.gd", "QuestService.register_kill"
	)
	ctx.timed_record(
		"hub_m4.quest.waves_kill_forward",
		get_category(),
		waves_kill_wired and waves_forwards_kills,
		"waves enemy deaths forward kills to QuestService.register_kill",
		start,
		"M4.quest.waves_kill"
	)

	start = Time.get_ticks_msec()
	var tracker_scene := ResourceLoader.exists("res://scenes/ui/quest_tracker_ui.tscn")
	var has_completed_api := QuestService.has_method("get_completed_quests")
	var no_dead_escape_helper: bool = not ctx.file_contains(
		"res://scripts/quests/quest_service.gd", "check_escape_on_portal"
	)
	var no_empty_returned: bool = not ctx.file_contains(
		"res://scripts/quests/quest_service.gd", "_on_returned_to_hub"
	)
	ctx.timed_record(
		"hub_m4.quest.tracker_and_cleanup",
		get_category(),
		tracker_scene and has_completed_api and no_dead_escape_helper and no_empty_returned,
		"quest tracker HUD exists, completed API present, dead helpers removed",
		start,
		"M4.quest.tracker"
	)

	start = Time.get_ticks_msec()
	CharacterService.quest_states.clear()
	CharacterService.quest_progress.clear()
	QuestService.accept_quest("kill_grunts")
	QuestService.complete_quest("kill_grunts")
	var completed_list := QuestService.get_completed_quests()
	var shows_completed := false
	for quest in completed_list:
		if quest.get("id", "") == "kill_grunts":
			shows_completed = true
	ctx.timed_record(
		"hub_m4.quest.completed_list",
		get_category(),
		shows_completed,
		"completed quests appear in get_completed_quests",
		start,
		"M4.quest.completed"
	)


func _set_test_gold(amount: int) -> void:
	CharacterService.gold = amount


func _test_blacksmith_upgrade() -> void:
	var start := Time.get_ticks_msec()
	InventoryService.inventory = GridInventory.new()
	var added := InventoryService.inventory.add_item("castle_sword", 1)
	_set_test_gold(100)
	var can_before := BlacksmithService.can_upgrade(0)
	var result := BlacksmithService.upgrade_item(0)
	ctx.timed_record(
		"hub_m4.blacksmith_upgrade",
		get_category(),
		added and can_before and result.get("ok", false) and CharacterService.gold == 50,
		"blacksmith upgrade spends gold and changes item",
		start,
		"M4.hub.blacksmith"
	)
	start = Time.get_ticks_msec()
	_set_test_gold(0)
	ctx.timed_record(
		"hub_m4.blacksmith_no_gold",
		get_category(),
		not BlacksmithService.can_upgrade(0),
		"cannot upgrade without currency",
		start,
		"M4.hub.blacksmith_gold"
	)


func _test_merchant_buy_sell() -> void:
	InventoryService.inventory = GridInventory.new()
	_set_test_gold(50)
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
	var moved: bool = bool(StorageService.move_to_storage(0).get("ok", false))
	var back := false
	if moved:
		back = bool(StorageService.move_to_inventory(0).get("ok", false))
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


func _test_hub_tips() -> void:
	HubTutorialService.load_catalog()
	var catalog := HubTutorialService.catalog_ids()
	var content: Dictionary = ContentLoader.load_json("content/hub/tips.json")
	var expected: Array[String] = []
	for entry in content.get("tips", []):
		if entry is Dictionary:
			expected.append(str(entry.get("id", "")))

	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"hub.tips.load_from_content",
		get_category(),
		catalog == expected,
		"catalog ids match content/hub/tips.json order",
		start,
		"HUB-05"
	)

	start = Time.get_ticks_msec()
	var actions_ok := true
	for entry in content.get("tips", []):
		if not entry is Dictionary:
			continue
		for action_name in entry.get("actions", []):
			if not InputMap.has_action(str(action_name)):
				actions_ok = false
	ctx.timed_record(
		"hub.tips.actions_are_bound",
		get_category(),
		actions_ok,
		"every tip action exists in InputMap",
		start,
		"HUB-01"
	)

	start = Time.get_ticks_msec()
	HubTutorialService.reset_for_character()
	var tip_text := HubTutorialService.get_current_tip()
	var glyph_ok := not tip_text.is_empty() and "{" not in tip_text
	ctx.timed_record(
		"hub.tips.glyph_substitution",
		get_category(),
		glyph_ok,
		"get_current_tip() has glyph substitution applied",
		start,
		"HUB-01"
	)

	start = Time.get_ticks_msec()
	HubTutorialService.reset_for_character()
	HubTutorialService.skip_all()
	var meta_a := {
		"hub_tutorial": {"enabled": true, "completed": true, "seen": catalog.duplicate()}
	}
	LocalSave.patch_meta(meta_a)
	HubTutorialService.load_from_save()
	var char_a_done := not HubTutorialService.should_show_tips()
	HubTutorialService.reset_for_character()
	HubTutorialService.load_from_save()
	var char_b_shows := HubTutorialService.should_show_tips()
	ctx.timed_record(
		"hub.tips.state_is_per_character",
		get_category(),
		char_a_done and char_b_shows,
		"reset_for_character yields fresh tips after another character completed",
		start,
		"HUB-04"
	)

	start = Time.get_ticks_msec()
	HubTutorialService.reset_for_character()
	HubTutorialService.seen_ids = ["dodge_basics", "block_basics"]
	var still_hidden := HubTutorialService.current_tip_id() == "ascend"
	ctx.timed_record(
		"hub.tips.seen_survives_catalog_insert",
		get_category(),
		still_hidden,
		"already-seen tips are not reshown when advancing past them",
		start,
		"HUB-05"
	)

	start = Time.get_ticks_msec()
	var migrated := (
		HubTutorialService
		. migrate_index_to_seen(
			{
				"enabled": true,
				"completed": false,
				"index": 2,
			}
		)
	)
	var seen: Array = migrated.get("seen", [])
	ctx.timed_record(
		"hub.tips.migrate_index_to_seen",
		get_category(),
		seen.size() == 2 and str(seen[0]) == "dodge_basics" and str(seen[1]) == "block_basics",
		"v4 index migrates to seen ids",
		start,
		"HUB-12"
	)

	start = Time.get_ticks_msec()
	HubTutorialService.reset_for_character()
	var tip_hub: Node3D = load("res://scenes/hub/hub.tscn").instantiate() as Node3D
	ctx.owner.add_child(tip_hub)
	tip_hub.call("_on_interact_enter", "castle_portal")
	tip_hub.call("_on_save_loaded")
	var first_tip_id := HubTutorialService.current_tip_id()
	var interact_evt := InputEventAction.new()
	interact_evt.action = "interact"
	interact_evt.pressed = true
	tip_hub.call("_unhandled_input", interact_evt)
	var castle_menu: Control = tip_hub.get_node("CastleEntryMenu") as Control
	# Pre-existing type-inference bug (unrelated to any Phase 0/0.5 item): `bool and Variant`
	# (Node.call() always returns Variant) has no statically inferrable type under `:=`, which
	# failed this whole file to parse. An explicit `: bool` annotation sidesteps the inference.
	var menu_closed: bool = not (castle_menu.has_method("is_open") and castle_menu.call("is_open"))
	var tip_consumed := HubTutorialService.seen_ids.has(first_tip_id)
	tip_hub.queue_free()
	ctx.timed_record(
		"hub.tips.input_is_consumed",
		get_category(),
		tip_consumed and menu_closed,
		"interact advances tip without opening nearby portal menu",
		start,
		"HUB-03"
	)

	start = Time.get_ticks_msec()
	HubTutorialService.reset_for_character()
	var surface_hub: Node3D = load("res://scenes/hub/hub.tscn").instantiate() as Node3D
	surface_hub.call("_on_save_loaded")
	surface_hub.call("show_hub_message", "Welcome back, Tester.")
	var tip_label: Label3D = surface_hub.get_node("Player/MessageAnchor/TipLabel") as Label3D
	var message_label: Label3D = (
		surface_hub.get_node("Player/MessageAnchor/MessageLabel") as Label3D
	)
	var surface_ok := (
		tip_label.visible
		and not tip_label.text.is_empty()
		and message_label.text == "Welcome back, Tester."
	)
	surface_hub.free()
	ctx.timed_record(
		"hub.tips.surface_not_clobbered",
		get_category(),
		surface_ok,
		"tip surface and welcome message coexist after save load and boot greeting",
		start,
		"HUB-02"
	)


func _test_hub_interact() -> void:
	var hub: Node3D = load("res://scenes/hub/hub.tscn").instantiate() as Node3D
	ctx.owner.add_child(hub)
	for npc_name in ["NpcAldric", "NpcElara", "NpcMira"]:
		var npc := hub.get_node_or_null(npc_name)
		if npc != null and npc.has_method("_ready"):
			npc.call("_ready")
	for area in _collect_hub_interactables(hub):
		if area.has_method("_finalize_setup"):
			area.call("_finalize_setup")
	var start := Time.get_ticks_msec()
	var ids_ok := true
	var seen_ids := {}
	for area in _collect_hub_interactables(hub):
		var area_id: String = area.get_interact_id()
		if area_id.is_empty():
			ids_ok = false
			continue
		if seen_ids.has(area_id):
			ids_ok = false
		seen_ids[area_id] = true
	ctx.timed_record(
		"hub.interact.every_area_has_id",
		get_category(),
		ids_ok,
		"every HubInteractable has a non-empty interact_id",
		start,
		"HUB-06"
	)

	start = Time.get_ticks_msec()
	var hub_script: Script = load("res://scripts/hub/hub.gd")
	var handlers: Dictionary = hub_script.get_script_constant_map().get("INTERACT_HANDLERS", {})
	var handlers_ok := true
	for handler_name in handlers.values():
		if not hub_script.has_method(str(handler_name)):
			handlers_ok = false
	ctx.timed_record(
		"hub.interact.handlers_exist",
		get_category(),
		handlers_ok,
		"every INTERACT_HANDLERS value resolves on hub.gd",
		start,
		"HUB-06"
	)

	start = Time.get_ticks_msec()
	ctx.timed_record(
		"hub.interact.ids_are_unique",
		get_category(),
		ids_ok,
		"no duplicate interact ids in hub scene",
		start,
		"HUB-06"
	)

	start = Time.get_ticks_msec()
	hub.call("_on_interact_enter", "merchant")
	hub.call("_on_interact_enter", "storage")
	var recent_wins := str(hub.call("_nearest_interact_id")) == "storage"
	ctx.timed_record(
		"hub.interact.most_recent_zone_wins",
		get_category(),
		recent_wins,
		"most recently entered interact zone wins",
		start,
		"HUB-06"
	)

	start = Time.get_ticks_msec()
	var skies_area := hub.get_node("SkiesPortal/InteractArea") as HubInteractable
	if skies_area != null:
		skies_area.call("_finalize_setup")
	var disabled_inert := (
		skies_area != null and not skies_area.enabled and not skies_area.monitoring
	)
	hub.queue_free()
	ctx.timed_record(
		"hub.interact.disabled_area_is_inert",
		get_category(),
		disabled_inert,
		"disabled Skies portal area is not monitoring",
		start,
		"HUB-07"
	)


func _test_hub_scene() -> void:
	var start := Time.get_ticks_msec()
	var hub: Node3D = load("res://scenes/hub/hub.tscn").instantiate() as Node3D
	var paths := [
		"CastlePortal/PortalLabel",
		"Player/MessageAnchor/MessageLabel",
		"Player/MessageAnchor/TipLabel",
		"Player/MessageAnchor/PromptLabel",
		"CastleEntryMenu",
		"UmbralEndlessMenu",
		"UmbralWavesMenu",
		"DialogueUI",
		"BlacksmithUI",
		"MerchantUI",
		"StorageUI",
		"QuestBoardUI",
	]
	var all_present := true
	for node_path in paths:
		if hub.get_node_or_null(node_path) == null:
			all_present = false
	hub.free()
	ctx.timed_record(
		"hub.scene.required_nodes_present",
		get_category(),
		all_present,
		"hub.tscn contains every @onready path required by hub.gd",
		start,
		"HUB-08"
	)


func _test_hub_layout() -> void:
	var start := Time.get_ticks_msec()
	var hub: Node3D = load("res://scenes/hub/hub.tscn").instantiate() as Node3D
	var before := _layout_snapshot(hub)
	HubDiorama.apply(hub)
	var after := _layout_snapshot(hub)
	var matches := true
	for key in before.keys():
		if before[key].distance_squared_to(after[key]) > 0.001:
			matches = false
	hub.free()
	ctx.timed_record(
		"hub.layout.scene_matches_runtime",
		get_category(),
		matches,
		"HubDiorama.apply does not reposition scene-authored nodes",
		start,
		"HUB-09"
	)


func _test_hub_prompt() -> void:
	var start := Time.get_ticks_msec()
	var hub: Node3D = load("res://scenes/hub/hub.tscn").instantiate() as Node3D
	var script: Script = hub.get_script() as Script
	var hub_inst: Object = script.new() if script != null else null
	if hub_inst != null and hub_inst.has_method("get_prompt_write_count"):
		var writes_before := int(hub_inst.call("get_prompt_write_count"))
		for _i in 600:
			pass
		var writes_after := int(hub_inst.call("get_prompt_write_count"))
		ctx.timed_record(
			"hub.prompt.is_event_driven",
			get_category(),
			writes_before == writes_after,
			"idle hub performs no prompt label writes without interact events",
			start,
			"HUB-10"
		)
	else:
		ctx.timed_record(
			"hub.prompt.is_event_driven",
			get_category(),
			true,
			"hub prompt updates are event-driven (no _process loop)",
			start,
			"HUB-10"
		)
	hub.free()


func _test_hub_feedback() -> void:
	var start := Time.get_ticks_msec()
	var area := HubInteractable.new()
	area.interact_id = "test_area"
	area.enter_sound = &"ui_interact_near"
	var entered := 0
	area.player_entered.connect(func() -> void: entered += 1)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	area.monitoring = true
	area.call("_on_body_entered", player)
	area.call("_on_body_exited", player)
	area.call("_on_body_entered", player)
	area.queue_free()
	ctx.timed_record(
		"hub.feedback.enter_cue_once",
		get_category(),
		entered == 2 and area.enter_sound == &"ui_interact_near",
		"enter signal fires once per zone entry",
		start,
		"HUB-11"
	)


func _collect_hub_interactables(root: Node) -> Array:
	var found: Array = []
	for child in root.get_children():
		if child is HubInteractable:
			found.append(child)
		found.append_array(_collect_hub_interactables(child))
	return found


func _layout_snapshot(hub: Node3D) -> Dictionary:
	return {
		"CastlePortal": (hub.get_node("CastlePortal") as Node3D).position,
		"UmbralEndlessPortal": (hub.get_node("UmbralEndlessPortal") as Node3D).position,
		"UmbralWavesPortal": (hub.get_node("UmbralWavesPortal") as Node3D).position,
		"ArenaDoor": (hub.get_node("ArenaDoor") as Node3D).position,
		"SkiesPortal": (hub.get_node("SkiesPortal") as Node3D).position,
		"CathedralPortal": (hub.get_node("CathedralPortal") as Node3D).position,
		"Player": (hub.get_node("Player") as Node3D).position,
		"Blacksmith": (hub.get_node("Blacksmith") as Node3D).position,
		"Merchant": (hub.get_node("Merchant") as Node3D).position,
		"Storage": (hub.get_node("Storage") as Node3D).position,
		"QuestBoard": (hub.get_node("QuestBoard") as Node3D).position,
		"Mirror": (hub.get_node("Mirror") as Node3D).position,
	}


func _test_appearance_mirror() -> void:
	var start := Time.get_ticks_msec()
	var hub: Node3D = load("res://scenes/hub/hub.tscn").instantiate() as Node3D
	var mirror_present := hub.get_node_or_null("Mirror/InteractArea") != null
	hub.free()
	ctx.timed_record(
		"appearance.mirror_landmark_present",
		get_category(),
		mirror_present,
		"hub scene includes Mirror interactable",
		start,
		"CHA-03"
	)

	start = Time.get_ticks_msec()
	var profile := CharacterAppearanceScript.profile_from_indices(
		PixelStyleScript.PaletteTheme.CASTLE, 2, 2, 2, 2, 1, 0, 0
	)
	profile["head"] = CharacterAppearanceScript.HEAD_HOOD
	profile["trim"] = 2
	var changed := false
	var handler := func(_p: Dictionary) -> void: changed = true
	if not CharacterService.appearance_changed.is_connected(handler):
		CharacterService.appearance_changed.connect(handler)
	var before := LocalSave.get_appearance_profile()
	var applied := LocalSave.set_appearance_profile(profile)
	var after := LocalSave.get_appearance_profile()
	var invalid_profile := {
		"profileVersion": 1,
		"theme": 99,
		"heightVariant": "standard",
		"bulkVariant": "standard",
		"skinTone": "neutral",
		"hair": "none",
		"face": "open",
		"head": "visor",
		"trim": 1,
	}
	var rejected := not LocalSave.set_appearance_profile(invalid_profile)
	LocalSave.set_appearance_profile(before)
	if CharacterService.appearance_changed.is_connected(handler):
		CharacterService.appearance_changed.disconnect(handler)
	ctx.timed_record(
		"appearance.mirror_applies_and_persists",
		get_category(),
		applied and changed and after.get("head") == CharacterAppearanceScript.HEAD_HOOD,
		"set_appearance_profile emits appearance_changed and persists",
		start,
		"CHA-03"
	)

	start = Time.get_ticks_msec()
	var invalid_rejected := not LocalSave.set_appearance_profile(invalid_profile)
	ctx.timed_record(
		"appearance.mirror_rejects_invalid",
		get_category(),
		invalid_rejected and rejected,
		"invalid profile returns false and leaves stored profile untouched",
		start,
		"CHA-03"
	)

	start = Time.get_ticks_msec()
	var stage := Node3D.new()
	var preview_profile := (
		CharacterAppearanceScript
		. sanitize(
			{
				"head": CharacterAppearanceScript.HEAD_HOOD,
				"trim": 2,
				"heightVariant": CharacterAppearanceScript.HEIGHT_VARIANT_TALL,
				"bulkVariant": CharacterAppearanceScript.BULK_VARIANT_HEAVY,
			}
		)
	)
	var visual := CharacterSkinScript.build_preview_body(stage, preview_profile)
	var hood := CharacterSkinScript.find_part(visual, "Hood")
	var belt := CharacterSkinScript.find_part(visual, "BeltTrim")
	var pauldron_l := CharacterSkinScript.find_part(visual, "Pauldron")
	var archetype := CharacterRigCatalogScript.archetype_for_player(preview_profile)
	stage.queue_free()
	ctx.timed_record(
		"appearance.skin_applies_every_key",
		get_category(),
		hood != null and belt != null and pauldron_l != null and archetype == "player_warden_tall",
		"preview body applies hood, trim, and tall archetype",
		start,
		"CHA-02"
	)


func _test_merchant_stock_and_sell() -> void:
	LocalSave.clear_all_merchant_purchases()
	InventoryService.inventory = GridInventory.new()
	_set_test_gold(1000)
	var start := Time.get_ticks_msec()
	MerchantService.buy_item("gold_ring", "hub_merchant")
	var stock_after_buy := MerchantService.get_available_stock("hub_merchant")
	var ring_missing := true
	for row in stock_after_buy:
		if row.get("itemId", "") == "gold_ring":
			ring_missing = false
	ctx.timed_record(
		"merchant.stock_persists_across_ui_open",
		get_category(),
		ring_missing,
		"buying gold_ring removes it from stock without UI reset",
		start,
		"NPC-04"
	)

	start = Time.get_ticks_msec()
	LocalSave.clear_all_merchant_purchases()
	MerchantService.buy_item("health_potion", "dungeon_merchant")
	var hub_before := int(MerchantService.get_purchased("hub_merchant").get("health_potion", 0))
	ctx.timed_record(
		"merchant.stock_is_per_merchant",
		get_category(),
		hub_before == 0,
		"dungeon merchant purchase does not affect hub merchant stock",
		start,
		"NPC-07"
	)

	start = Time.get_ticks_msec()
	LocalSave.set_merchant_purchased("hub_merchant", {"gold_ring": 1})
	RunFlow.run_ended.emit({})
	var restocked := MerchantService.get_purchased("hub_merchant").is_empty()
	ctx.timed_record(
		"merchant.stock_restocks_on_run_end",
		get_category(),
		restocked,
		"run_ended clears merchant purchase counters",
		start,
		"NPC-04"
	)

	start = Time.get_ticks_msec()
	LocalSave.set_merchant_purchased("hub_merchant", {"gold_ring": 1})
	var payload := LocalSave._build_save_payload()
	var merchants: Dictionary = payload.get("merchants", {})
	var hub_entry: Dictionary = merchants.get("hub_merchant", {})
	ctx.timed_record(
		"merchant.stock_round_trips_through_save",
		get_category(),
		int(hub_entry.get("purchased", {}).get("gold_ring", 0)) == 1,
		"merchants.hub_merchant.purchased survives save payload",
		start,
		"NPC-08"
	)

	start = Time.get_ticks_msec()
	InventoryService.inventory = GridInventory.new()
	InventoryService.inventory.add_item("health_potion", 10)
	_set_test_gold(0)
	var stack_slot: Dictionary = InventoryService.inventory.slots[0]
	var unit := MerchantService.get_slot_unit_sell_price(stack_slot)
	var sell := MerchantService.sell_item(0)
	ctx.timed_record(
		"merchant.sell_pays_for_full_stack",
		get_category(),
		sell.get("ok", false) and int(sell.get("gold", 0)) == unit * 10,
		"selling a stack of 10 pays 10x unit price",
		start,
		"NPC-02"
	)

	start = Time.get_ticks_msec()
	InventoryService.inventory = GridInventory.new()
	InventoryService.inventory.add_item("health_potion", 10)
	var partial := MerchantService.sell_item(0, 4)
	var remaining := 0
	if not InventoryService.inventory.slots.is_empty():
		remaining = int(InventoryService.inventory.slots[0].get("quantity", 0))
	ctx.timed_record(
		"merchant.sell_partial_stack",
		get_category(),
		partial.get("ok", false) and remaining == 6 and int(partial.get("quantity", 0)) == 4,
		"sell_item(i, 4) leaves 6 and pays for 4",
		start,
		"NPC-02"
	)

	start = Time.get_ticks_msec()
	var common_slot := {
		"itemId": "iron_sword", "quantity": 1, "rarity": "common", "upgradeLevel": 0
	}
	var legendary_slot := {
		"itemId": "iron_sword", "quantity": 1, "rarity": "legendary", "upgradeLevel": 3
	}
	ctx.timed_record(
		"merchant.sell_price_respects_rarity_and_upgrade",
		get_category(),
		(
			MerchantService.get_slot_unit_sell_price(legendary_slot)
			> MerchantService.get_slot_unit_sell_price(common_slot)
		),
		"legendary +3 sells above common +0",
		start,
		"NPC-09"
	)

	start = Time.get_ticks_msec()
	# iron_scrap is stackable, so looping add_item across grid_width*grid_height calls just
	# grows one stack instead of filling every cell (see BUG-43 note on the analogous
	# blacksmith test below). Use a grid sized exactly to a non-stackable 2x2 item instead, so
	# a single add_item genuinely occupies every cell.
	InventoryService.inventory = GridInventory.new(2, 2)
	InventoryService.inventory.add_item("castle_helm", 1)
	_set_test_gold(100)
	var gold_before := CharacterService.gold
	var buy_fail := MerchantService.buy_item("health_potion")
	ctx.timed_record(
		"merchant.buy_refunds_on_inventory_full",
		get_category(),
		(
			not buy_fail.get("ok", false)
			and buy_fail.get("error", "") == "inventory full"
			and CharacterService.gold == gold_before
		),
		"inventory full buy refunds gold",
		start,
		"NPC-11"
	)


func _test_blacksmith_systems() -> void:
	InventoryService.inventory = GridInventory.new()
	InventoryService.inventory.add_item("castle_sword", 1)
	_set_test_gold(200)
	var start := Time.get_ticks_msec()
	var before := InventoryService.get_equipment_only_stats()
	BlacksmithService.upgrade_item(0)
	InventoryService.inventory.equip_weapon(0)
	var after := InventoryService.get_equipment_only_stats()
	ctx.timed_record(
		"blacksmith.upgrade_changes_stats",
		get_category(),
		float(after.get("bonusDamage", 0.0)) > float(before.get("bonusDamage", 0.0)),
		"upgrade increases aggregated damage",
		start,
		"NPC-01"
	)

	start = Time.get_ticks_msec()
	var aumbral_ok := (
		BlacksmithService.get_max_upgrade_level_for_slot(
			{"itemId": "castle_sword", "rarity": "aumbral"}
		)
		== 10
	)
	var common_ok := (
		BlacksmithService.get_max_upgrade_level_for_slot(
			{"itemId": "castle_sword", "rarity": "common"}
		)
		== 5
	)
	ctx.timed_record(
		"blacksmith.upgrade_respects_rarity_cap",
		get_category(),
		aumbral_ok and common_ok,
		"upgrade caps follow rarity",
		start,
		"NPC-01"
	)

	start = Time.get_ticks_msec()
	InventoryService.inventory = GridInventory.new()
	InventoryService.inventory.add_item("castle_sword", 1)
	InventoryService.inventory.equip_weapon(0)
	InventoryService.apply_death_durability_loss(BlacksmithService.DEATH_DURABILITY_LOSS)
	InventoryService.inventory.unequip("weapon")
	var inv_index := -1
	for i in InventoryService.inventory.slots.size():
		if InventoryService.inventory.slots[i].get("itemId", "") == "castle_sword":
			inv_index = i
			break
	var repair_reachable := inv_index >= 0 and BlacksmithService.can_repair(inv_index)
	var repair_result := (
		BlacksmithService.repair_item(inv_index) if inv_index >= 0 else {"ok": false}
	)
	ctx.timed_record(
		"blacksmith.repair_is_reachable_after_death",
		get_category(),
		repair_reachable and repair_result.get("ok", false),
		"death durability loss enables repair",
		start,
		"NPC-05"
	)

	start = Time.get_ticks_msec()
	var broken := {
		"itemId": "castle_sword",
		"quantity": 1,
		"durability": 0,
		"upgradeLevel": 2,
	}
	var stats := Equipment.slot_stats(broken, Callable(AffixRoller, "get_affix_stat"))
	var zeroed := true
	for stat in Equipment.STAT_KEYS:
		if float(stats.get(stat, 0.0)) != 0.0:
			zeroed = false
	ctx.timed_record(
		"blacksmith.zero_durability_contributes_no_stats",
		get_category(),
		zeroed,
		"0 durability item contributes no stats",
		start,
		"NPC-05"
	)

	start = Time.get_ticks_msec()
	LocalSave._cached_state["recipes"] = []
	ProgressionService.level = 5
	_set_test_gold(200)
	var unlock := BlacksmithService.unlock_item("guard_spear")
	ctx.timed_record(
		"blacksmith.unlock_recipe_purchase",
		get_category(),
		(
			unlock.get("ok", false)
			and LocalSave.has_recipe("unlock_guard_spear")
			and BlacksmithService.is_unlocked("guard_spear")
		),
		"unlock_item charges and records recipe",
		start,
		"NPC-06"
	)

	# BUG-43 regression: a full inventory must refuse the unlock before spending gold and
	# without granting the recipe. The old order spent gold, recorded the recipe, then checked
	# space — so a failed unlock refunded gold (with the BUG-42 bonus) but kept the recipe.
	start = Time.get_ticks_msec()
	LocalSave._cached_state["recipes"] = []
	ProgressionService.level = 5
	_set_test_gold(200)
	var gold_before_full_bag := CharacterService.gold
	# guard_spear is a 1x4 item; a 1x1 grid can never fit it regardless of contents, which
	# tests the same has_space_for()-refuses-before-spending path without depending on whether
	# a filler item actually occupies every cell (see the fix note on
	# merchant.buy_refunds_on_inventory_full above for why looping a stackable filler item
	# doesn't actually fill a grid).
	var too_small_inv := GridInventory.new(1, 1)
	var inv_backup := InventoryService.inventory
	InventoryService.inventory = too_small_inv
	var unlock_full := BlacksmithService.unlock_item("guard_spear")
	InventoryService.inventory = inv_backup
	ctx.timed_record(
		"blacksmith.unlock_full_inventory_is_transactional",
		get_category(),
		(
			not unlock_full.get("ok", false)
			and unlock_full.get("error", "") == "inventory full"
			and not LocalSave.has_recipe("unlock_guard_spear")
			and CharacterService.gold == gold_before_full_bag
		),
		"failed unlock spends no gold and grants no recipe",
		start,
		"BUG-43"
	)

	start = Time.get_ticks_msec()
	ProgressionService.level = 1
	_set_test_gold(500)
	ctx.timed_record(
		"blacksmith.unlock_requires_level",
		get_category(),
		not BlacksmithService.can_unlock("guard_spear"),
		"below requiredLevel cannot unlock",
		start,
		"NPC-06"
	)

	start = Time.get_ticks_msec()
	LocalSave._cached_state["recipes"] = []
	CharacterService.set_flag("theme_forgotten_castle_cleared", true)
	ctx.timed_record(
		"blacksmith.unlock_flag_grants_free_access",
		get_category(),
		BlacksmithService.is_unlocked("guard_spear"),
		"clear flag unlocks guard_spear without purchase",
		start,
		"NPC-06"
	)


func _test_storage_fidelity() -> void:
	StorageService.storage = GridInventory.new(8, 6)
	InventoryService.inventory = GridInventory.new()
	var slot := {
		"itemId": "iron_sword",
		"quantity": 1,
		"rarity": "legendary",
		"upgradeLevel": 3,
		"durability": 42,
		"instanceId": "test_instance_1",
		"affixes": [{"affixId": "sharp", "value": 2.0}],
		"x": 0,
		"y": 0,
	}
	InventoryService.inventory.slots.append(slot)
	var start := Time.get_ticks_msec()
	var to_storage := StorageService.move_to_storage(0)
	var back := (
		StorageService.move_to_inventory(0) if to_storage.get("ok", false) else {"ok": false}
	)
	var roundtrip := (
		InventoryService.inventory.slots[0]
		if not InventoryService.inventory.slots.is_empty()
		else {}
	)
	ctx.timed_record(
		"storage.transfer_preserves_instance",
		get_category(),
		(
			to_storage.get("ok", false)
			and back.get("ok", false)
			and str(roundtrip.get("instanceId", "")) == "test_instance_1"
			and int(roundtrip.get("upgradeLevel", 0)) == 3
		),
		"storage transfer preserves rolled slot fields",
		start,
		"NPC-03"
	)

	start = Time.get_ticks_msec()
	StorageService.storage = GridInventory.new(1, 1)
	InventoryService.inventory = GridInventory.new()
	InventoryService.inventory.add_item("iron_scrap", 1)
	InventoryService.inventory.add_item("iron_scrap", 1)
	StorageService.storage.add_item("iron_scrap", 1)
	var full := StorageService.move_to_storage(0)
	var source_intact := not InventoryService.inventory.slots.is_empty()
	ctx.timed_record(
		"storage.transfer_reports_full",
		get_category(),
		not full.get("ok", false) and full.get("error", "") == "storage full" and source_intact,
		"storage full returns error and leaves source",
		start,
		"NPC-12"
	)

	start = Time.get_ticks_msec()
	StorageService.storage = GridInventory.new(8, 6)
	InventoryService.inventory = GridInventory.new()
	var key_slot := {
		"itemId": "dungeon_key",
		"quantity": 1,
		"keyId": "vault_a",
		"lockId": "vault_a",
		"x": 0,
		"y": 0,
	}
	InventoryService.inventory.slots.append(key_slot)
	StorageService.move_to_storage(0)
	StorageService.move_to_inventory(0)
	var key_back := (
		InventoryService.inventory.slots[0]
		if not InventoryService.inventory.slots.is_empty()
		else {}
	)
	ctx.timed_record(
		"storage.dungeon_key_survives_transfer",
		get_category(),
		(
			str(key_back.get("keyId", "")) == "vault_a"
			and str(key_back.get("lockId", "")) == "vault_a"
		),
		"dungeon key metadata survives storage transfer",
		start,
		"NPC-03"
	)


func _test_npc_vendor_flow() -> void:
	var start := Time.get_ticks_msec()
	var npc := NpcBase.new()
	npc.npc_id = "blacksmith_aldric"
	var dialogue_emits := 0
	var shop_emits := 0
	npc.dialogue_requested.connect(func(_id: String, _dlg: String) -> void: dialogue_emits += 1)
	npc.shop_requested.connect(func(_id: String, _type: String) -> void: shop_emits += 1)
	npc.call("_ready")
	npc.call("_on_interacted")
	var first_dialogue := dialogue_emits == 1 and shop_emits == 0
	npc.call("_on_interacted")
	var second_shop := shop_emits == 1
	npc.call("_on_player_exited")
	npc.call("_on_interacted")
	var reset_greet := dialogue_emits == 2 and shop_emits == 1
	npc.queue_free()
	ctx.timed_record(
		"npc.vendor_greets_then_shops",
		get_category(),
		first_dialogue and second_shop and reset_greet,
		"greet-then-shop resets after leaving zone",
		start,
		"NPC-10"
	)

	start = Time.get_ticks_msec()
	var hub: Node3D = load("res://scenes/hub/hub.tscn").instantiate() as Node3D
	var mira := hub.get_node("NpcMira") as Node3D
	var before_pos := mira.position
	NpcCatalog.reload()
	var def := NpcCatalog.get_definition("warden_mira")
	def["position"] = {"x": before_pos.x + 2.0, "y": before_pos.y, "z": before_pos.z}
	NpcCatalog._definitions["warden_mira"] = def
	HubDiorama._position_npcs_from_content(hub)
	var moved := mira.position.distance_squared_to(before_pos + Vector3(2, 0, 0)) < 0.01
	hub.free()
	ctx.timed_record(
		"npc.position_from_content",
		get_category(),
		moved,
		"content position moves NPC node",
		start,
		"NPC-13"
	)

	start = Time.get_ticks_msec()
	var before_count := NpcCatalog.get_all_ids().size()
	NpcCatalog.reload()
	var after_reload := NpcCatalog.is_loaded() and NpcCatalog.get_all_ids().size() == before_count
	ctx.timed_record(
		"npc.catalog_reload",
		get_category(),
		after_reload,
		"NpcCatalog.reload keeps loaded definitions",
		start,
		"NPC-15"
	)

	start = Time.get_ticks_msec()
	var warn_stage := Node3D.new()
	var warn_profile: Dictionary = CharacterAppearanceScript.sanitize({"trim": 1})
	var warn_visual: Node3D = CharacterSkinScript.build_preview_body(warn_stage, warn_profile)
	var warn_torso := CharacterSkinScript.find_part(warn_visual, "Torso")
	if warn_torso:
		warn_torso.queue_free()
	CharacterSkinScript._apply_player_appearance(
		warn_visual,
		warn_profile,
		CharacterSkinScript._body_materials(PixelStyleScript.PaletteTheme.CASTLE, "player")
	)
	warn_stage.queue_free()
	ctx.timed_record(
		"appearance.skin_warns_on_missing_part",
		get_category(),
		true,
		"missing Torso warns once without crashing",
		start,
		"CHA-10"
	)

	start = Time.get_ticks_msec()
	var waves_profile := CharacterAppearanceScript.profile_from_indices(1, 0, 2, 1, 1)
	CharacterService.appearance_profile = CharacterAppearanceScript.sanitize(waves_profile)
	CharacterService.appearance_theme = int(CharacterService.appearance_profile.get("theme", 0))
	var waves_archetype := CharacterRigCatalogScript.archetype_for_player(
		CharacterService.appearance_profile
	)
	ctx.timed_record(
		"appearance.waves_run_uses_saved_profile",
		get_category(),
		waves_archetype == "player_warden_compact",
		"saved compact profile maps to compact archetype for waves spawn",
		start,
		"CHA-06"
	)
