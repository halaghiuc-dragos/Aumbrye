extends Node3D

## M4 hub — blacksmith, merchant, storage, arena, quest board, portals (HUB-4.1).

@onready var _portal_area: HubInteractable = $CastlePortal/InteractArea
@onready var _arena_area: HubInteractable = $ArenaDoor/InteractArea
@onready var _blacksmith_area: HubInteractable = $Blacksmith/InteractArea
@onready var _merchant_area: HubInteractable = $Merchant/InteractArea
@onready var _storage_area: HubInteractable = $Storage/InteractArea
@onready var _quest_board_area: HubInteractable = $QuestBoard/InteractArea
@onready var _message_label: Label3D = $MessageLabel
@onready var _prompt_label: Label3D = $PromptLabel
@onready var _castle_menu: Control = $CastleEntryMenu
@onready var _dialogue_ui: Control = $DialogueUI
@onready var _blacksmith_ui: Control = $BlacksmithUI
@onready var _merchant_ui: Control = $MerchantUI
@onready var _storage_ui: Control = $StorageUI
@onready var _quest_board_ui: Control = $QuestBoardUI

var _settings_ui: Control
var _talents_ui: Control
var _loadout_ui: Control

var _near_portal := false
var _near_arena := false
var _near_blacksmith := false
var _near_merchant := false
var _near_storage := false
var _near_quest_board := false


func _ready() -> void:
	_wire_interactable(_portal_area, _on_portal_enter, _on_portal_exit)
	_wire_interactable(_arena_area, _on_arena_enter, _on_arena_exit)
	_wire_interactable(_blacksmith_area, _on_blacksmith_enter, _on_blacksmith_exit)
	_wire_interactable(_merchant_area, _on_merchant_enter, _on_merchant_exit)
	_wire_interactable(_storage_area, _on_storage_enter, _on_storage_exit)
	_wire_interactable(_quest_board_area, _on_quest_board_enter, _on_quest_board_exit)

	_castle_menu.new_run_requested.connect(_on_castle_new_run)
	_castle_menu.biome_run_requested.connect(_on_biome_run)
	_castle_menu.continue_requested.connect(_on_castle_continue)
	_castle_menu.seed_run_requested.connect(_on_castle_seed_run)

	for npc in get_tree().get_nodes_in_group("hub_npc"):
		if npc.has_signal("dialogue_requested"):
			npc.dialogue_requested.connect(_on_npc_dialogue)
		if npc.has_signal("shop_requested"):
			npc.shop_requested.connect(_on_npc_shop)

	_show_return_message()
	_attach_m4_ui()
	AudioDirector.stop_all(0.5)
	call_deferred("_boot_save_and_services")


func _boot_save_and_services() -> void:
	var synced := await LocalSave.sync_from_cloud()
	if not synced:
		if LocalSave.has_save():
			LocalSave.load_into_services()
		else:
			InventoryService.inventory.add_item("castle_sword", 1)
			InventoryService.inventory.add_item("training_greatsword", 1)
			InventoryService.inventory.add_item("rogue_dagger", 1)
	LocalSave.autosave()


func _attach_m4_ui() -> void:
	var settings_script := load("res://scripts/ui/settings_ui.gd")
	if settings_script:
		_settings_ui = Control.new()
		_settings_ui.name = "SettingsUI"
		_settings_ui.set_script(settings_script)
		_settings_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_settings_ui)
	var talents_script := load("res://scripts/ui/talents_ui.gd")
	if talents_script:
		_talents_ui = Control.new()
		_talents_ui.name = "TalentsUI"
		_talents_ui.set_script(talents_script)
		_talents_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_talents_ui)
	var loadout_scene := load("res://scenes/ui/loadout_ui.tscn") as PackedScene
	if loadout_scene:
		_loadout_ui = loadout_scene.instantiate() as Control
		add_child(_loadout_ui)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory") and _loadout_ui and not _any_ui_open():
		open_loadout()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and _settings_ui and not _any_ui_open():
		_settings_ui.open_settings()
		get_viewport().set_input_as_handled()
		return
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
	elif _near_arena:
		vp.set_input_as_handled()
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
	if _loadout_ui:
		_loadout_ui.open()


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


func _any_ui_open() -> bool:
	return (
		_castle_menu.is_open()
		or _dialogue_ui.is_open()
		or _blacksmith_ui.is_open()
		or _merchant_ui.is_open()
		or _storage_ui.is_open()
		or _quest_board_ui.is_open()
		or (_settings_ui and _settings_ui.is_open())
		or (_talents_ui and _talents_ui.is_open())
		or (_loadout_ui and _loadout_ui.is_open())
	)


func _update_prompt() -> void:
	if _any_ui_open():
		_prompt_label.text = ""
		return
	if _near_portal:
		_prompt_label.text = _portal_area.get_prompt()
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


func _show_return_message() -> void:
	if RunFlow.last_hub_message != "":
		_message_label.text = RunFlow.last_hub_message
		RunFlow.last_hub_message = ""
	else:
		_message_label.text = "Welcome to Aumbrye Hub — explore the landmarks"


func _on_biome_run(biome_id: String) -> void:
	RunFlow.start_new_run(biome_id)
	_refresh_hub_message()


func _on_castle_new_run() -> void:
	RunFlow.start_new_castle_run()
	_refresh_hub_message()


func _on_castle_continue() -> void:
	RunFlow.continue_castle_run()
	_refresh_hub_message()


func _on_castle_seed_run(run_seed_value: int) -> void:
	var biome_id: String = RunFlow.DEFAULT_BIOME
	if _castle_menu.has_method("get_selected_biome"):
		biome_id = str(_castle_menu.get_selected_biome())
	RunFlow.start_run_with_seed(biome_id, run_seed_value)
	_refresh_hub_message()


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
