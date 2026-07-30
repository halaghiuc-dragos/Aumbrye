extends Node3D

## Hub stub — portal to castle run + arena door (HUB-2.1).

@onready var _portal_area: Area3D = $CastlePortal/InteractArea
@onready var _arena_area: Area3D = $ArenaDoor/InteractArea
@onready var _message_label: Label3D = $MessageLabel
@onready var _castle_menu: Control = $CastleEntryMenu

var _near_portal := false
var _near_arena := false


func _ready() -> void:
	_portal_area.body_entered.connect(_on_portal_enter)
	_portal_area.body_exited.connect(_on_portal_exit)
	_arena_area.body_entered.connect(_on_arena_enter)
	_arena_area.body_exited.connect(_on_arena_exit)
	_castle_menu.new_run_requested.connect(_on_castle_new_run)
	_castle_menu.continue_requested.connect(_on_castle_continue)
	_castle_menu.seed_run_requested.connect(_on_castle_seed_run)
	if LocalSave.has_save():
		LocalSave.load_into_services()
	else:
		InventoryService.inventory.add_item("castle_sword", 1)
	LocalSave.autosave()
	AudioDirector.stop_all(0.5)
	if RunFlow.last_hub_message != "":
		_message_label.text = RunFlow.last_hub_message
		RunFlow.last_hub_message = ""
	else:
		_message_label.text = "Welcome to the Hub"


func _unhandled_input(event: InputEvent) -> void:
	if _castle_menu.is_open():
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


func show_hub_message(message: String) -> void:
	_message_label.text = message


func _on_castle_new_run() -> void:
	RunFlow.start_new_castle_run()
	_refresh_hub_message()


func _on_castle_continue() -> void:
	RunFlow.continue_castle_run()
	_refresh_hub_message()


func _on_castle_seed_run(run_seed_value: int) -> void:
	RunFlow.start_castle_run_with_seed(run_seed_value)
	_refresh_hub_message()


func _refresh_hub_message() -> void:
	if RunFlow.last_hub_message != "":
		_message_label.text = RunFlow.last_hub_message
		RunFlow.last_hub_message = ""


func _on_portal_enter(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_portal = true


func _on_portal_exit(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_portal = false


func _on_arena_enter(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_arena = true


func _on_arena_exit(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_arena = false
