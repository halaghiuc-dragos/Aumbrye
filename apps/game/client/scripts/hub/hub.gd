extends Node3D

## M4 hub — blacksmith, merchant, storage, arena, quest board, portals (HUB-4.1).

const HubDioramaScript := preload("res://scripts/hub/hub_diorama.gd")
const CharacterCreateUIScript := preload("res://scripts/ui/character_create_ui.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")

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

@onready var _castle_portal_label: Label3D = $CastlePortal/PortalLabel
@onready var _message_label: Label3D = $Player/MessageAnchor/MessageLabel
@onready var _tip_label: Label3D = $Player/MessageAnchor/TipLabel
@onready var _prompt_label: Label3D = $Player/MessageAnchor/PromptLabel
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


func _ready() -> void:
	PixelDioramaBootstrap.prime()
	HubDioramaScript.apply(self)
	_appearance_mirror_ui = CharacterCreateUIScript.new()
	_appearance_mirror_ui.name = "AppearanceMirrorUI"
	add_child(_appearance_mirror_ui)
	_appearance_mirror_ui.appearance_saved.connect(_on_appearance_mirror_saved)
	call_deferred("_apply_pixel_diorama_to_scene")
	_register_interactables()
	_assert_interact_handlers()

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

	_show_return_message()
	_refresh_castle_portal_label()
	RunFlow.returned_to_hub.connect(_on_returned_to_hub)
	if not RunFlow.run_warning.is_connected(_on_run_warning):
		RunFlow.run_warning.connect(_on_run_warning)
	if InventoryService and not InventoryService.inventory_rejected.is_connected(_on_inventory_rejected):
		InventoryService.inventory_rejected.connect(_on_inventory_rejected)
	AudioDirector.play_hub_ambience()
	call_deferred("_apply_player_viewmodel_theme")
	LocalSave.save_loaded.connect(_on_save_loaded)
	call_deferred("_boot_save_and_services")


func _boot_save_and_services() -> void:
	var result := await LocalSave.sync_from_cloud()
	var synced: bool = bool(result.get("ok", false)) if result is Dictionary else bool(result)
	var reloaded := false
	if not synced and LocalSave.has_save():
		reloaded = LocalSave.load_into_services()
	if CharacterService.class_id == "":
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
		return
	if not reloaded:
		_on_save_loaded()
	_auto_equip_starting_weapon()
	LocalSave.autosave()
	show_hub_message("Welcome back, %s." % LocalSave.get_character_name())


func _on_save_loaded() -> void:
	HubTutorialService.load_from_save()
	_refresh_tip_surface()


func _auto_equip_starting_weapon() -> void:
	if InventoryService.inventory.get_equipped_weapon_id() != "":
		return
	var class_id := CharacterService.class_id
	var weapon_id := (
		ClassCatalog.get_starting_weapon_item_id(class_id) if class_id != "" else "castle_sword"
	)
	_auto_equip_weapon_item(weapon_id)


func _auto_equip_weapon_item(item_id: String) -> void:
	var grid := InventoryService.inventory
	for i in grid.slots.size():
		if grid.slots[i].get("itemId", "") == item_id:
			grid.equip_weapon(i)
			return
	if grid.add_item(item_id, 1):
		grid.equip_weapon(grid.slots.size() - 1)


func _apply_pixel_diorama_to_scene() -> void:
	PixelDioramaBootstrap.attach(self)


func _unhandled_input(event: InputEvent) -> void:
	if HubTutorialService.should_show_tips() and _handle_tip_input(event):
		get_viewport().set_input_as_handled()
		return
	if _any_ui_open():
		return
	if not event.is_action_pressed("interact"):
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
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
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
		theme = CharacterService.appearance_theme
	var director := player.get_node_or_null("AnimDirector")
	if director and director.has_method("set_viewmodel_theme"):
		director.call("set_viewmodel_theme", theme)


func _on_appearance_mirror_saved(_profile: Dictionary) -> void:
	show_hub_message("Appearance updated.")
	_apply_player_viewmodel_theme()
	_update_prompt()


func show_hub_message(message: String) -> void:
	_message_label.text = message


func _ui_is_open(ui: Control) -> bool:
	return ui != null and ui.has_method("is_open") and ui.call("is_open")


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
	return _nearby[_nearby.size() - 1]


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
	_prompt_label.text = next_text
	_prompt_writes += 1


func get_prompt_write_count() -> int:
	return _prompt_writes


func _dispatch_interact(interact_id: String) -> void:
	if interact_id.begins_with("npc:"):
		_trigger_npc_interact(interact_id.substr(4))
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
	for npc in get_tree().get_nodes_in_group("hub_npc"):
		if npc.has_method("get_npc_id") and str(npc.get_npc_id()) == npc_id:
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
	if _castle_portal_label:
		_castle_portal_label.text = DungeonTierService.get_hub_portal_label()


func _on_returned_to_hub(_message: String) -> void:
	_refresh_castle_portal_label()


func _show_return_message() -> void:
	if RunFlow.last_hub_message != "":
		_message_label.text = RunFlow.last_hub_message
		RunFlow.last_hub_message = ""
	else:
		_message_label.text = "Welcome to Aumbrye Tower — explore the landmarks"


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
		_message_label.text = RunFlow.last_hub_message
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
		"quest_board":
			open_quest_board()
