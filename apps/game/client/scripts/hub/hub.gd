extends Node3D

## M4 hub — blacksmith, merchant, storage, arena, quest board, portals (HUB-4.1).

const HubDioramaScript := preload("res://scripts/hub/hub_diorama.gd")

@onready var _castle_portal_label: Label3D = $CastlePortal/PortalLabel
@onready var _portal_area: HubInteractable = $CastlePortal/InteractArea
@onready var _endless_portal_area: HubInteractable = $UmbralEndlessPortal/InteractArea
@onready var _waves_portal_area: HubInteractable = $UmbralWavesPortal/InteractArea
@onready var _skies_portal_area: HubInteractable = $SkiesPortal/InteractArea
@onready var _cathedral_portal_area: HubInteractable = $CathedralPortal/InteractArea
@onready var _arena_area: HubInteractable = $ArenaDoor/InteractArea
@onready var _blacksmith_area: HubInteractable = $Blacksmith/InteractArea
@onready var _merchant_area: HubInteractable = $Merchant/InteractArea
@onready var _storage_area: HubInteractable = $Storage/InteractArea
@onready var _quest_board_area: HubInteractable = $QuestBoard/InteractArea
@onready var _message_label: Label3D = $MessageLabel
@onready var _prompt_label: Label3D = $PromptLabel
@onready var _castle_menu: Control = $CastleEntryMenu
@onready var _endless_menu: Control = $UmbralEndlessMenu
@onready var _waves_menu: Control = $UmbralWavesMenu
@onready var _dialogue_ui: Control = $DialogueUI
@onready var _blacksmith_ui: Control = $BlacksmithUI
@onready var _merchant_ui: Control = $MerchantUI
@onready var _storage_ui: Control = $StorageUI
@onready var _quest_board_ui: Control = $QuestBoardUI

var _near_portal := false
var _near_endless_portal := false
var _near_waves_portal := false
var _near_skies_portal := false
var _near_cathedral_portal := false
var _near_arena := false
var _near_blacksmith := false
var _near_merchant := false
var _near_storage := false
var _near_quest_board := false


func _ready() -> void:
	PixelDioramaBootstrap.prime()
	HubDioramaScript.apply(self)
	call_deferred("_apply_pixel_diorama_to_scene")
	_wire_interactable(_portal_area, _on_portal_enter, _on_portal_exit)
	_wire_interactable(_endless_portal_area, _on_endless_portal_enter, _on_endless_portal_exit)
	_wire_interactable(_waves_portal_area, _on_waves_portal_enter, _on_waves_portal_exit)
	_wire_interactable(_skies_portal_area, _on_skies_portal_enter, _on_skies_portal_exit)
	_wire_interactable(_cathedral_portal_area, _on_cathedral_portal_enter, _on_cathedral_portal_exit)
	_wire_interactable(_arena_area, _on_arena_enter, _on_arena_exit)
	_wire_interactable(_blacksmith_area, _on_blacksmith_enter, _on_blacksmith_exit)
	_wire_interactable(_merchant_area, _on_merchant_enter, _on_merchant_exit)
	_wire_interactable(_storage_area, _on_storage_enter, _on_storage_exit)
	_wire_interactable(_quest_board_area, _on_quest_board_enter, _on_quest_board_exit)

	if has_node("SkiesPortal"):
		$SkiesPortal.visible = false
	if has_node("CathedralPortal"):
		$CathedralPortal.visible = false

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
	AudioDirector.stop_all(0.5)
	HubTutorialService.load_from_save()
	call_deferred("_boot_save_and_services")
	call_deferred("_maybe_show_hub_tips")


func _boot_save_and_services() -> void:
	var synced := await LocalSave.sync_from_cloud()
	if not synced and LocalSave.has_save():
		LocalSave.load_into_services()
	if CharacterService.class_id == "":
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
		return
	_auto_equip_starting_weapon()
	LocalSave.autosave()
	show_hub_message("Welcome back, %s." % LocalSave.get_character_name())


func _auto_equip_starting_weapon() -> void:
	if InventoryService.inventory.get_equipped_weapon_id() != "":
		return
	var class_id := CharacterService.class_id
	var weapon_id := ClassCatalog.get_starting_weapon_item_id(class_id) if class_id != "" else "castle_sword"
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
	if _any_ui_open():
		return
	if not event.is_action_pressed("interact"):
		return
	var vp := get_viewport()
	if vp == null:
		return
	if _near_portal:
		vp.set_input_as_handled()
		_castle_menu.open_menu()
	elif _near_endless_portal:
		vp.set_input_as_handled()
		_endless_menu.open_menu()
	elif _near_waves_portal:
		vp.set_input_as_handled()
		_waves_menu.open_menu()
	elif _near_skies_portal:
		vp.set_input_as_handled()
		show_hub_message("Aumbrye Skies is coming soon.")
	elif _near_cathedral_portal:
		vp.set_input_as_handled()
		show_hub_message("Aumbrye Cathedral is coming soon.")
	elif _near_arena:
		vp.set_input_as_handled()
		if Input.is_key_pressed(KEY_SHIFT):
			open_loadout()
		else:
			_near_arena = false
			RunFlow.go_to_arena()
	elif _near_blacksmith:
		vp.set_input_as_handled()
		open_blacksmith()
	elif _near_merchant:
		vp.set_input_as_handled()
		open_merchant()
	elif _near_storage:
		vp.set_input_as_handled()
		open_storage()
	elif _near_quest_board:
		vp.set_input_as_handled()
		open_quest_board()
	else:
		for npc in get_tree().get_nodes_in_group("hub_npc"):
			if npc.has_method("is_player_near") and npc.is_player_near():
				vp.set_input_as_handled()
				npc.trigger_interact()
				break
	_update_prompt()


func _process(_delta: float) -> void:
	_update_prompt()


func open_loadout() -> void:
	PlayerControls.open_loadout()


func open_blacksmith() -> void:
	_blacksmith_ui.open()


func open_merchant() -> void:
	_merchant_ui.open()


func open_storage() -> void:
	_storage_ui.open()


func open_quest_board() -> void:
	_quest_board_ui.open()


func show_hub_message(message: String) -> void:
	_message_label.text = message


func _wire_interactable(
	area: HubInteractable,
	enter_cb: Callable,
	exit_cb: Callable
) -> void:
	area.player_entered.connect(enter_cb)
	area.player_exited.connect(exit_cb)


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
		or PlayerControls.is_player_meta_ui_open()
	)


func _update_prompt() -> void:
	if _any_ui_open():
		_prompt_label.text = ""
		return
	if _near_portal:
		_prompt_label.text = _portal_area.get_prompt()
	elif _near_endless_portal:
		_prompt_label.text = _endless_portal_area.get_prompt()
	elif _near_waves_portal:
		_prompt_label.text = _waves_portal_area.get_prompt()
	elif _near_skies_portal:
		_prompt_label.text = _skies_portal_area.get_prompt()
	elif _near_cathedral_portal:
		_prompt_label.text = _cathedral_portal_area.get_prompt()
	elif _near_arena:
		_prompt_label.text = _arena_area.get_prompt()
	elif _near_blacksmith:
		_prompt_label.text = _blacksmith_area.get_prompt()
	elif _near_merchant:
		_prompt_label.text = _merchant_area.get_prompt()
	elif _near_storage:
		_prompt_label.text = _storage_area.get_prompt()
	elif _near_quest_board:
		_prompt_label.text = _quest_board_area.get_prompt()
	else:
		for npc in get_tree().get_nodes_in_group("hub_npc"):
			if npc.has_method("is_player_near") and npc.is_player_near():
				_prompt_label.text = npc.get_node("InteractArea").get_prompt()
				return
		_prompt_label.text = ""


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


func _on_dungeon_run(dungeon_id: String) -> void:
	RunFlow.start_new_run(dungeon_id)
	_refresh_hub_message()


func _on_castle_continue() -> void:
	RunFlow.continue_castle_run()
	_refresh_hub_message()


func _on_castle_seed_run(run_seed_value: int) -> void:
	var dungeon_id := DungeonCatalog.DEFAULT_DUNGEON_ID
	if _castle_menu.has_method("get_selected_dungeon"):
		dungeon_id = str(_castle_menu.get_selected_dungeon())
	RunFlow.start_run_with_seed(dungeon_id, run_seed_value)
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


func _on_endless_portal_enter() -> void:
	_near_endless_portal = true


func _on_endless_portal_exit() -> void:
	_near_endless_portal = false


func _on_waves_portal_enter() -> void:
	_near_waves_portal = true


func _on_waves_portal_exit() -> void:
	_near_waves_portal = false


func _on_skies_portal_enter() -> void:
	_near_skies_portal = true


func _on_skies_portal_exit() -> void:
	_near_skies_portal = false


func _on_cathedral_portal_enter() -> void:
	_near_cathedral_portal = true


func _on_cathedral_portal_exit() -> void:
	_near_cathedral_portal = false


func _refresh_hub_message() -> void:
	if RunFlow.last_hub_message != "":
		_message_label.text = RunFlow.last_hub_message
		RunFlow.last_hub_message = ""


func _on_npc_dialogue(_npc_id: String, dialogue_id: String) -> void:
	_dialogue_ui.start_dialogue(dialogue_id)


func _on_npc_shop(_npc_id: String, shop_type: String) -> void:
	match shop_type:
		"blacksmith":
			open_blacksmith()
		"merchant":
			open_merchant()
		"quest_board":
			open_quest_board()


func _on_portal_enter() -> void:
	_near_portal = true


func _on_portal_exit() -> void:
	_near_portal = false


func _on_arena_enter() -> void:
	_near_arena = true


func _on_arena_exit() -> void:
	_near_arena = false


func _on_blacksmith_enter() -> void:
	_near_blacksmith = true


func _on_blacksmith_exit() -> void:
	_near_blacksmith = false


func _on_merchant_enter() -> void:
	_near_merchant = true


func _on_merchant_exit() -> void:
	_near_merchant = false


func _on_storage_enter() -> void:
	_near_storage = true


func _on_storage_exit() -> void:
	_near_storage = false


func _on_quest_board_enter() -> void:
	_near_quest_board = true


func _on_quest_board_exit() -> void:
	_near_quest_board = false


func _maybe_show_hub_tips() -> void:
	if not HubTutorialService.should_show_tips():
		return
	var tip := HubTutorialService.get_current_tip()
	if tip.is_empty():
		return
	if _message_label:
		_message_label.text = "%s (Esc to skip tips)" % tip


func _input(event: InputEvent) -> void:
	if HubTutorialService.should_show_tips() and event.is_action_pressed("ui_cancel"):
		HubTutorialService.skip_all()
		if _message_label:
			_message_label.text = ""
		return
	if HubTutorialService.should_show_tips() and (event.is_action_pressed("ui_accept") or event.is_action_pressed("interact")):
		var next := HubTutorialService.advance_tip()
		if _message_label:
			_message_label.text = next if not next.is_empty() else ""
