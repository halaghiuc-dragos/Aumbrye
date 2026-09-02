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
const INTERACT_EXTENTS := Vector3(3.0, 2.5, 3.0)

var _biome_id := "forgotten_castle"
var _near_merchant := false
var _near_portal := false


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
	_add_interact_area(merchant, _on_merchant_entered, _on_merchant_exited)

	var portal := Node3D.new()
	portal.name = "ReturnPortal"
	portal.position = PORTAL_OFFSET
	add_child(portal)
	DioramaSkin.build_exit_portal(portal, _biome_id)
	_add_interact_area(portal, _on_portal_entered, _on_portal_exited)


func _add_interact_area(host: Node3D, entered: Callable, exited: Callable) -> void:
	var area := Area3D.new()
	area.name = "InteractArea"
	# Layer 0, mask 2: the area detects the player without being something the world collides with.
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = INTERACT_EXTENTS
	shape.shape = box
	area.add_child(shape)
	host.add_child(area)
	area.body_entered.connect(entered)
	area.body_exited.connect(exited)


func _on_merchant_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_merchant = true


func _on_merchant_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_merchant = false


func _on_portal_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_portal = true


func _on_portal_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_portal = false


func _unhandled_input(event: InputEvent) -> void:
	if not PlayerInput.interact_just_pressed(event):
		return
	if _near_merchant:
		_open_merchant()
		get_viewport().set_input_as_handled()
		return
	if _near_portal:
		_return_to_hub()
		get_viewport().set_input_as_handled()


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


func _return_to_hub() -> void:
	if RunFlow and RunFlow.can_retreat_to_hub():
		RunFlow.retreat_to_hub()


## Gives the boss merchant its stock back for a new floor.
##
## Purchases are stored per merchant id and never expire on their own, so without this the shop
## would be picked clean after the first boss of a tier and empty behind the other nine.
static func restock_for_floor() -> void:
	if LocalSave:
		LocalSave.clear_merchant_purchased(MERCHANT_ID)
