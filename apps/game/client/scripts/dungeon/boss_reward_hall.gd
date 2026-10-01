extends Node3D
class_name BossRewardHall

## The two things that appear in a boss room once its boss is down.
##
## A floor boss is the end of a long push, and until now the only thing waiting on the other side of
## it was a menu. Both of these exist to turn that moment into somewhere the player stands: a
## merchant, so the loot that just dropped immediately becomes a decision, and a way home that is a
## thing in the room rather than an option in a list.
##
## The merchant deliberately does not share the hub's stock. Ten bosses a tier with a full shop
## behind each one would make the hub's own merchant and blacksmith pointless, so `boss_merchant`
## carries a handful of consumables that get restocked once per floor.

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const MERCHANT_SCENE := preload("res://scenes/ui/merchant_ui.tscn")

const MERCHANT_ID := "boss_merchant"
const MERCHANT_UI_GROUP := &"dungeon_merchant_ui"
const HALL_NAME := "BossRewardHall"

const MERCHANT_OFFSET := Vector3(-4.5, 0.0, 4.0)
const PORTAL_OFFSET := Vector3(4.5, 0.0, 4.0)
const INTERACT_RANGE := 3.2
const PROMPT_OFFSET := Vector3(0.0, 2.8, 0.0)

var _biome_id := "forgotten_castle"
var _merchant_prompt: InteractPrompt
var _portal_prompt: InteractPrompt


## Whether `room` already has a hall in it.
##
## The caller constructs the node -- a script cannot name its own `class_name` from inside itself
## while it is being compiled -- so the "already there?" half of the check lives here.
static func is_open_in(room: Node3D) -> bool:
	return room != null and room.get_node_or_null(HALL_NAME) != null


## Builds the stall and the portal. Safe to call once, on a node already inside the boss room.
func setup(biome_id: String) -> void:
	_biome_id = biome_id
	_build()


func _build() -> void:
	var merchant := Node3D.new()
	merchant.name = "RewardMerchant"
	merchant.position = MERCHANT_OFFSET
	add_child(merchant)
	DioramaSkin.build_merchant_stall(merchant, _biome_id)
	_merchant_prompt = InteractPrompt.build(merchant, PROMPT_OFFSET)
	DungeonInteractionService.register_candidate(
		merchant,
		merchant,
		INTERACT_RANGE,
		3,
		Callable(self, "_open_merchant"),
		Callable(),
		Callable(self, "_set_merchant_prompt")
	)

	var portal := Node3D.new()
	portal.name = "ReturnPortal"
	portal.position = PORTAL_OFFSET
	add_child(portal)
	DioramaSkin.build_exit_portal(portal, _biome_id)
	_portal_prompt = InteractPrompt.build(portal, PROMPT_OFFSET)
	DungeonInteractionService.register_candidate(
		portal,
		portal,
		INTERACT_RANGE,
		4,
		Callable(self, "_ask_return_to_hub"),
		Callable(),
		Callable(self, "_set_portal_prompt")
	)


func _set_merchant_prompt(active: bool) -> void:
	if active:
		_merchant_prompt.show_action(tr("BOSS_HALL_TRADE"))
	else:
		_merchant_prompt.hide_prompt()


func _set_portal_prompt(active: bool) -> void:
	if active:
		_portal_prompt.show_action(tr("BOSS_HALL_RETURN"))
	else:
		_portal_prompt.hide_prompt()


func _open_merchant() -> void:
	var existing := get_tree().get_first_node_in_group(MERCHANT_UI_GROUP) as Control
	if existing == null or not is_instance_valid(existing):
		existing = MERCHANT_SCENE.instantiate() as Control
		existing.add_to_group(MERCHANT_UI_GROUP)
		var host: Node = get_tree().current_scene
		if host == null:
			host = get_tree().root
		host.add_child(existing)
	if existing.has_method("open_for_merchant"):
		existing.call("open_for_merchant", MERCHANT_ID)


## Leaving the run is a decision, so it asks the same question the exit portal does.
func _ask_return_to_hub() -> void:
	if not (RunFlow and RunFlow.can_retreat_to_hub()):
		return
	var spec := ConfirmSpec.new()
	spec.title_key = &"EXIT_PORTAL_TITLE"
	spec.message_key = &"EXIT_PORTAL_MESSAGE"
	spec.confirm_key = &"EXIT_PORTAL_LEAVE"
	spec.cancel_key = &"EXIT_PORTAL_STAY"
	spec.pause_game = true
	spec.on_confirm = func() -> void:
		RunFlow.retreat_to_hub()
	MenuStack.confirm(spec)


## Gives the boss merchant its stock back for a new floor.
##
## Purchases are stored per merchant id and never expire on their own, so without this the shop
## would be picked clean after the first boss of a tier and empty behind the other nine.
static func restock_for_floor() -> void:
	if LocalSave:
		LocalSave.clear_merchant_purchased(MERCHANT_ID)
