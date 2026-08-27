extends Node3D


const HubDioramaScript := preload("res://scripts/hub/hub_diorama.gd")
const CharacterCreateUIScript := preload("res://scripts/ui/character_create_ui.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const HubNpcScene := preload("res://scenes/hub/hub_npc.tscn")
const RainFieldScript := preload("res://scripts/art/world/rain_field.gd")

const INTERACT_HANDLERS := {
	"castle_portal": "_open_castle_menu",
	"endless_portal": "_open_endless_menu",
	"waves_portal": "_open_waves_menu",
	"skies_portal": "_show_coming_soon_skies",
	"cathedral_portal": "_show_coming_soon_cathedral",
	"arena_door": "_enter_arena",
	"blacksmith": "open_blacksmith",
	"merchant": "open_merchant",
	"storage": "open_storage",
	"quest_board": "open_quest_board",
	"appearance_mirror": "open_appearance_mirror",
}

@onready var _castle_portal_area: HubInteractable = $CastlePortal/InteractArea
@onready var _message_label: Label3D = $Player/MessageAnchor/MessageLabel
@onready var _tip_label: Label3D = $Player/MessageAnchor/TipLabel
@onready var _castle_menu: Control = $CastleEntryMenu
@onready var _endless_menu: Control = $UmbralEndlessMenu
@onready var _waves_menu: Control = $UmbralWavesMenu
@onready var _dialogue_ui: Control = $DialogueUI
@onready var _blacksmith_ui: Control = $BlacksmithUI
@onready var _merchant_ui: Control = $MerchantUI
@onready var _storage_ui: Control = $StorageUI
@onready var _quest_board_ui: Control = $QuestBoardUI

var _appearance_mirror_ui: Control

var _nearby: Array[String] = []
var _interactable_by_id: Dictionary = {}
var _current_prompt := ""
var _prompt_writes := 0
var _message_dismiss_armed := false


func _ready() -> void:
	PixelDioramaBootstrap.prime()
	_spawn_catalog_npcs()
	HubDioramaScript.apply(self)
	_appearance_mirror_ui = CharacterCreateUIScript.new()
	_appearance_mirror_ui.name = "AppearanceMirrorUI"
	add_child(_appearance_mirror_ui)
	_appearance_mirror_ui.appearance_saved.connect(_on_appearance_mirror_saved)
	call_deferred("_apply_pixel_diorama_to_scene")
	_register_interactables()
	_apply_npc_availability()
	_assert_interact_handlers()

	_connect_tip_refresh_sources()

	_dialogue_ui.closed.connect(_update_prompt)

	_castle_menu.dungeon_run_requested.connect(_on_dungeon_run)
	_castle_menu.continue_requested.connect(_on_castle_continue)
	_castle_menu.seed_run_requested.connect(_on_castle_seed_run)
	_endless_menu.endless_run_requested.connect(_on_endless_run)
	DungeonTierService.tier_unlocked.connect(_refresh_castle_portal_label)
	_endless_menu.continue_requested.connect(_on_endless_continue)
	_waves_menu.waves_run_requested.connect(_on_waves_run)
	_waves_menu.continue_requested.connect(_on_waves_continue)

	for npc in get_tree().get_nodes_in_group("hub_npc"):
		if npc.has_signal("dialogue_requested"):
			npc.dialogue_requested.connect(_on_npc_dialogue)
		if npc.has_signal("shop_requested"):
			npc.shop_requested.connect(_on_npc_shop)

	call_deferred("_face_spawn_view")
	_show_return_message()
	_refresh_castle_portal_label()
	RunFlow.returned_to_hub.connect(_on_returned_to_hub)
	if not RunFlow.run_warning.is_connected(_on_run_warning):
		RunFlow.run_warning.connect(_on_run_warning)
	if InventoryService and not InventoryService.inventory_rejected.is_connected(_on_inventory_rejected):
		InventoryService.inventory_rejected.connect(_on_inventory_rejected)
	AudioDirector.play_hub_ambience()
	_attach_weather()
	call_deferred("_apply_player_viewmodel_theme")
	LocalSave.save_loaded.connect(_on_save_loaded)
	call_deferred("_boot_save_and_services")


func _face_spawn_view() -> void:
	var player := get_node_or_null("Player") as Node3D
	if player == null:
		return
	var arm := player.get_node_or_null("CameraPivot/SpringArm3D")
	if arm != null and arm.has_method("snap_look_direction"):
		arm.call("snap_look_direction", Vector3(0.0, 0.0, -1.0))


func _attach_weather() -> void:
	WeatherService.set_outdoors(true)
	var player := get_node_or_null("Player") as Node3D
	if player == null or get_node_or_null("RainField") != null:
		return
	var rain := Node3D.new()
	rain.set_script(RainFieldScript)
	add_child(rain)
	rain.call(
		"set_floor_extent", HubDioramaScript.FLOOR_WIDTH * 0.5, HubDioramaScript.FLOOR_DEPTH * 0.5
	)
	rain.call("setup", player)


func _exit_tree() -> void:
	WeatherService.set_outdoors(false)
	if DungeonTierService and DungeonTierService.tier_unlocked.is_connected(_refresh_castle_portal_label):
		DungeonTierService.tier_unlocked.disconnect(_refresh_castle_portal_label)
	if RunFlow.returned_to_hub.is_connected(_on_returned_to_hub):
		RunFlow.returned_to_hub.disconnect(_on_returned_to_hub)
	if RunFlow.run_warning.is_connected(_on_run_warning):
		RunFlow.run_warning.disconnect(_on_run_warning)
	if InventoryService and InventoryService.inventory_rejected.is_connected(_on_inventory_rejected):
		InventoryService.inventory_rejected.disconnect(_on_inventory_rejected)
	if LocalSave.save_loaded.is_connected(_on_save_loaded):
		LocalSave.save_loaded.disconnect(_on_save_loaded)


func _boot_save_and_services() -> void:
	var result: Dictionary = await LocalSave.sync_from_cloud()
	var synced: bool = bool(result.get("ok", false))
	var reloaded := false
	if not synced and LocalSave.has_save():
		reloaded = LocalSave.reload_active_into_services()
	if CharacterService.class_id == "":
		push_error(
			(
				"Hub: no class on the active character (id '%s') — returning to the main menu. "
				+ "The save was loaded but carries no classId."
			)
			% LocalSave.get_active_character_id()
		)
		SceneTransition.goto(get_tree(), "res://scenes/ui/main_menu.tscn")
		return
	if not reloaded:
		_on_save_loaded()
	_auto_equip_starting_weapon()
	LocalSave.autosave()
	show_hub_message("Welcome back, %s." % LocalSave.get_character_name())


func _spawn_catalog_npcs() -> void:
	var existing: Dictionary = {}
	for child in get_children():
		if not child.is_in_group("hub_npc"):
			continue
		var npc_node := child as NpcBase
		if npc_node != null:
			existing[npc_node.get_npc_id()] = true
		elif "npc_id" in child:
			existing[str(child.get("npc_id"))] = true
	for npc_id in NpcCatalog.get_all_ids():
		if existing.has(npc_id):
			continue
		var npc := HubNpcScene.instantiate()
		npc.name = "Npc_%s" % npc_id
		npc.set("npc_id", npc_id)
		add_child(npc)


func _apply_npc_availability() -> void:
	for node in get_tree().get_nodes_in_group("hub_npc"):
		var npc := node as NpcBase
		if npc != null:
			npc.set_available(npc.is_available())


func _on_save_loaded() -> void:
	HubTutorialService.load_from_save()
	_apply_npc_availability()
	if DungeonTierService and not DungeonTierService.tier_unlocked.is_connected(_on_tier_unlocked):
		DungeonTierService.tier_unlocked.connect(_on_tier_unlocked)
	_refresh_tip_surface()


func _on_tier_unlocked(_tier: int) -> void:
	_apply_npc_availability()


func _auto_equip_starting_weapon() -> void:
	if InventoryService.inventory.get_equipped_weapon_id() != "":
		return
	var class_id := CharacterService.class_id
	var weapon_id := (
		ClassCatalog.get_starting_weapon_item_id(class_id) if class_id != "" else "castle_sword"
	)
	InventoryService.equip_weapon_item(weapon_id)

func _apply_pixel_diorama_to_scene() -> void:
	PixelDioramaBootstrap.attach(self)


func _unhandled_input(event: InputEvent) -> void:
	if HubTutorialService.should_show_tips() and _handle_tip_input(event):
		get_viewport().set_input_as_handled()
		return
	if _any_ui_open():
		return
	if not PlayerInput.interact_just_pressed(event):
		return
	var interact_id := _nearest_interact_id()
	if interact_id.is_empty():
		return
	get_viewport().set_input_as_handled()
	_dispatch_interact(interact_id)


func _handle_tip_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		HubTutorialService.skip_all()
		_refresh_tip_surface()
		return true
	if event.is_action_pressed("ui_accept") or PlayerInput.interact_just_pressed(event):
		HubTutorialService.advance_tip()
		_refresh_tip_surface()
		return true
	return false


func open_loadout() -> void:
	PlayerControls.open_loadout()


func open_blacksmith() -> void:
	_blacksmith_ui.open()
	_update_prompt()


func open_merchant() -> void:
	_merchant_ui.open()
	_update_prompt()


func open_storage() -> void:
	_storage_ui.open()
	_update_prompt()


func open_quest_board() -> void:
	_quest_board_ui.open()
	_update_prompt()


func open_appearance_mirror() -> void:
	if _appearance_mirror_ui and _appearance_mirror_ui.has_method("open_edit_mode"):
		_appearance_mirror_ui.call("open_edit_mode")
	_update_prompt()


func _apply_player_viewmodel_theme() -> void:
	var player := get_node_or_null("Player") as CharacterBody3D
	if player == null:
		return
	var theme := PixelStyle.PaletteTheme.HUB
	if CharacterService:
		theme = CharacterService.appearance_theme as PixelStyle.PaletteTheme
	var director := player.get_node_or_null("AnimDirector")
	if director and director.has_method("set_viewmodel_theme"):
		director.call("set_viewmodel_theme", theme)


func _on_appearance_mirror_saved(_profile: Dictionary) -> void:
	show_hub_message("Appearance updated.")
	_apply_player_viewmodel_theme()
	_update_prompt()


const MESSAGE_DISMISS_ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"sprint",
	&"jump",
	&"dodge",
	&"interact",
]


func show_hub_message(message: String) -> void:
	_message_label.text = message
	_message_label.visible = message != ""
	_message_dismiss_armed = message != ""


func _dismiss_message_on_movement() -> void:
	if not _message_dismiss_armed:
		return
	for action in MESSAGE_DISMISS_ACTIONS:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			_clear_hub_message()
			return
	if Input.get_vector("move_left", "move_right", "move_forward", "move_back").length_squared() > 0.04:
		_clear_hub_message()


func _clear_hub_message() -> void:
	_message_dismiss_armed = false
	_message_label.text = ""
	_message_label.visible = false


func _process(_delta: float) -> void:
	_dismiss_message_on_movement()


func _ui_is_open(ui: Control) -> bool:
	return ui != null and ui.has_method("is_open") and ui.call("is_open")


func has_open_ui() -> bool:
	return _any_ui_open()


func _any_ui_open() -> bool:
	return (
		_ui_is_open(_castle_menu)
		or _ui_is_open(_endless_menu)
		or _ui_is_open(_waves_menu)
		or _ui_is_open(_dialogue_ui)
		or _ui_is_open(_blacksmith_ui)
		or _ui_is_open(_merchant_ui)
		or _ui_is_open(_storage_ui)
		or _ui_is_open(_quest_board_ui)
		or (
			_appearance_mirror_ui != null
			and _appearance_mirror_ui.has_method("is_open")
			and _appearance_mirror_ui.call("is_open")
		)
		or PlayerControls.is_player_meta_ui_open()
	)


func _register_interactables() -> void:
	_interactable_by_id.clear()
	for node in _find_interactables(self):
		var area := node as HubInteractable
		var area_id := area.get_interact_id()
		if area_id.is_empty():
			continue
		_interactable_by_id[area_id] = area
		area.player_entered.connect(_on_interact_enter.bind(area_id))
		area.player_exited.connect(_on_interact_exit.bind(area_id))


func _find_interactables(root: Node) -> Array:
	var found: Array = []
	for child in root.get_children():
		if child is HubInteractable:
			found.append(child)
		found.append_array(_find_interactables(child))
	return found


func _on_interact_enter(interact_id: String) -> void:
	_nearby.erase(interact_id)
	_nearby.append(interact_id)
	_update_prompt()


func _on_interact_exit(interact_id: String) -> void:
	_nearby.erase(interact_id)
	_update_prompt()


func _nearest_interact_id() -> String:
	if _nearby.is_empty():
		return ""
	var player := get_node_or_null("Player") as Node3D
	if player == null:
		return _nearby[_nearby.size() - 1]
	var origin := player.global_position
	var best_id := ""
	var best_dist := INF
	for interact_id in _nearby:
		var area: HubInteractable = _interactable_by_id.get(interact_id)
		if area == null or not area.is_player_near():
			continue
		var to_zone := area.get_focus_position() - origin
		to_zone.y = 0.0
		var dist := to_zone.length_squared()
		if dist < best_dist:
			best_dist = dist
			best_id = interact_id
	if best_id.is_empty():
		return _nearby[_nearby.size() - 1]
	return best_id


func _update_prompt() -> void:
	var next_text := ""
	if not _any_ui_open():
		var interact_id := _nearest_interact_id()
		if interact_id != "":
			var area: HubInteractable = _interactable_by_id.get(interact_id)
			if area != null:
				next_text = area.get_prompt()
	if next_text == _current_prompt:
		return
	_current_prompt = next_text
	_prompt_writes += 1


func _dispatch_interact(interact_id: String) -> void:
	if interact_id.begins_with("npc:"):
		_trigger_npc_interact(interact_id.substr(4))
		return
	if interact_id.begins_with("stray:"):
		_on_npc_dialogue("", interact_id.substr(6))
		return
	if not INTERACT_HANDLERS.has(interact_id):
		push_warning("Hub: no handler for interact_id '%s'" % interact_id)
		return
	var handler_name: String = INTERACT_HANDLERS[interact_id]
	if has_method(handler_name):
		call(handler_name)
	elif has_method(handler_name.trim_prefix("_")):
		call(handler_name.trim_prefix("_"))
	else:
		push_warning("Hub: handler '%s' missing for interact_id '%s'" % [handler_name, interact_id])


func _trigger_npc_interact(npc_id: String) -> void:
	for node in get_tree().get_nodes_in_group("hub_npc"):
		var npc := node as NpcBase
		if npc != null and npc.get_npc_id() == npc_id:
			npc.trigger_interact()
			return


func _open_castle_menu() -> void:
	_castle_menu.open_menu()


func _open_endless_menu() -> void:
	_endless_menu.open_menu()


func _open_waves_menu() -> void:
	_waves_menu.open_menu()


func _show_coming_soon_skies() -> void:
	show_hub_message("Aumbrye Skies is coming soon.")


func _show_coming_soon_cathedral() -> void:
	show_hub_message("Aumbrye Cathedral is coming soon.")


func _enter_arena() -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		open_loadout()
	else:
		RunFlow.go_to_arena()


func _assert_interact_handlers() -> void:
	for interact_id in INTERACT_HANDLERS.keys():
		var handler_name: String = INTERACT_HANDLERS[interact_id]
		if not has_method(handler_name) and not has_method(handler_name.trim_prefix("_")):
			push_warning(
				"Hub: INTERACT_HANDLERS['%s'] -> missing method '%s'" % [interact_id, handler_name]
			)


func _refresh_castle_portal_label() -> void:
	if _castle_portal_area:
		_castle_portal_area.set_display_name(DungeonTierService.get_hub_portal_label())


func _on_returned_to_hub(_message: String) -> void:
	_refresh_castle_portal_label()


func _show_return_message() -> void:
	if RunFlow.last_hub_message != "":
		show_hub_message(RunFlow.last_hub_message)
		RunFlow.last_hub_message = ""
	else:
		show_hub_message("Welcome to Aumbrye Tower — explore the landmarks")


func _connect_tip_refresh_sources() -> void:
	if InventoryService:
		InventoryService.inventory_changed.connect(_on_tip_source_changed)
	if StorageService:
		StorageService.storage_changed.connect(_on_tip_source_changed)
	if CharacterService:
		CharacterService.flags_changed.connect(_on_tip_source_changed)
		CharacterService.quests_changed.connect(_on_tip_source_changed)
		CharacterService.gold_changed.connect(_on_tip_source_changed_int)
		CharacterService.level_changed.connect(_on_tip_source_changed_int)
	if DungeonTierService:
		DungeonTierService.tier_unlocked.connect(_on_tip_source_changed_int)


func _on_tip_source_changed() -> void:
	_refresh_tip_surface()


func _on_tip_source_changed_int(_value: int) -> void:
	_refresh_tip_surface()


func _refresh_tip_surface() -> void:
	if not HubTutorialService.should_show_tips():
		_tip_label.text = ""
		_tip_label.visible = false
		return
	var tip := HubTutorialService.get_current_tip()
	if tip.is_empty():
		_tip_label.text = ""
		_tip_label.visible = false
		return
	_tip_label.visible = true
	_tip_label.text = "%s (Esc to skip tips)" % tip


func _on_dungeon_run(dungeon_id: String, difficulty_tier: int = 1) -> void:
	RunFlow.start_new_run(dungeon_id, null, difficulty_tier)
	_refresh_hub_message()


func _on_castle_continue() -> void:
	RunFlow.continue_castle_run()
	_refresh_hub_message()


func _on_castle_seed_run(run_seed_value: int) -> void:
	var dungeon_id := DungeonCatalog.DEFAULT_DUNGEON_ID
	var difficulty_tier := 1
	if _castle_menu.has_method("get_selected_dungeon"):
		dungeon_id = str(_castle_menu.get_selected_dungeon())
	if _castle_menu.has_method("get_selected_difficulty_tier"):
		difficulty_tier = int(_castle_menu.get_selected_difficulty_tier())
	RunFlow.start_new_run(dungeon_id, run_seed_value, difficulty_tier)
	_refresh_hub_message()


func _on_endless_run(start_floor: int, skip_item_id: String) -> void:
	RunFlow.start_endless_run(start_floor, skip_item_id)
	_refresh_hub_message()


func _on_endless_continue() -> void:
	RunFlow.continue_endless_run()
	_refresh_hub_message()


func _on_waves_run() -> void:
	RunFlow.start_waves_run()
	_refresh_hub_message()


func _on_waves_continue() -> void:
	RunFlow.continue_waves_run()
	_refresh_hub_message()


func _refresh_hub_message() -> void:
	if RunFlow.last_hub_message != "":
		show_hub_message(RunFlow.last_hub_message)
		RunFlow.last_hub_message = ""


func _on_run_warning(message: String) -> void:
	show_hub_message(message)


func _on_inventory_rejected(reason: String) -> void:
	if reason == "full":
		show_hub_message("Inventory full.")


func _on_npc_dialogue(_npc_id: String, dialogue_id: String) -> void:
	_dialogue_ui.start_dialogue(dialogue_id)
	_update_prompt()


func _on_npc_shop(_npc_id: String, shop_type: String) -> void:
	match shop_type:
		"blacksmith":
			open_blacksmith()
		"merchant":
			open_merchant()
		"quest_board", "bounty_board":
			open_quest_board()
		"storage":
			open_storage()
