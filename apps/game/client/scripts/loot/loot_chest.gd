extends Node3D


signal opened
signal contents_changed

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const ToastScene: PackedScene = preload("res://scenes/ui/achievement_toast.tscn")

const INTERACT_RANGE := 2.4

var _mesh: Node3D
@onready var _label: Label3D = $Label3D

var _items: Array = []
var _opened := false
var _sealed := false
## A key vault's chest also holds the floor key fragment: opening it takes the key and the items
## together, so there is one thing to interact with.
var _key_fragment_id := ""
var _key_label := ""
var _key_taken := false


func _ready() -> void:
	_mesh = DioramaSkin.build_chest(self, DioramaSkin.resolve_biome(self))
	if _opened:
		apply_opened_state(true)
	_label.visible = false
	DungeonInteractionService.register_candidate(
		self,
		self,
		INTERACT_RANGE,
		2,
		Callable(self, "_open"),
		Callable(self, "_can_open"),
		Callable(self, "_set_selected_prompt")
	)


func configure(placement: Dictionary) -> void:
	_items = placement.get("items", []).duplicate(true)
	_key_fragment_id = str(placement.get("keyFragmentId", ""))
	_key_label = str(placement.get("keyLabel", ""))


func is_opened() -> bool:
	return _opened


func capture_state() -> Dictionary:
	return {"opened": _opened, "remaining": _items.duplicate(true), "keyTaken": _key_taken}


func apply_opened_state(was_opened: bool) -> void:
	_opened = was_opened
	if _opened:
		var lid := DioramaSkin.find_chest_lid(_mesh)
		if lid:
			lid.rotation.x = DioramaSkin.LID_OPEN_ANGLE
	_label.visible = false


func apply_state(state: Dictionary) -> void:
	_items = state.get("remaining", _items).duplicate(true)
	_key_taken = bool(state.get("keyTaken", _key_taken))
	apply_opened_state(bool(state.get("opened", false)))


## A sealed chest can no longer be opened: its timed window ran out.
func seal() -> void:
	_sealed = true
	_label.visible = false


func _can_open() -> bool:
	return not _opened and not _sealed


func _set_selected_prompt(active: bool) -> void:
	_label.visible = active and not _opened
	if _label.visible:
		_label.text = (
			InputGlyphServiceScript.format_interact_name(_key_label)
			if _key_label != ""
			else InputGlyphServiceScript.get_action_prompt(&"interact")
		)


func _present_rarity_juice(item_id: String, instance: Dictionary = {}) -> void:
	var def := ItemCatalog.get_definition(item_id)
	var rarity := RarityRegistryScript.normalize(str(instance.get("rarity", def.get("rarity", "common"))))
	if AudioDirector:
		var sfx := RarityRegistryScript.drop_sfx_id(rarity)
		if AudioDirector.has_sfx(sfx):
			AudioDirector.play_sfx(sfx, global_position)
		else:
			AudioDirector.play_sfx("ui_interact_near", global_position)
	if RarityRegistryScript.wants_drop_toast(rarity):
		var toast := ToastScene.instantiate()
		if toast.has_method("show_loot"):
			get_tree().root.add_child(toast)
			toast.show_loot(str(def.get("name", item_id)), RarityRegistryScript.display_color(rarity))
	if RarityRegistryScript.wants_camera_nudge(rarity) and VfxService:
		VfxService.request_shake(0.12, 320)
		# The same top-tier gate that earns a camera nudge earns the "you should look at
		# this" stinger -- a legendary should be impossible to miss even with your eyes elsewhere.
		AudioDirector.play_stinger("rare_drop")


func _open() -> void:
	if _opened:
		return
	# The key goes into the floor keyring, not the bag: a full bag must never be the reason a floor
	# cannot be finished.
	if _key_fragment_id != "" and not _key_taken:
		_key_taken = true
		FloorKeyring.take(_key_fragment_id)
		# A keycard punctuates the same way a secret or a lock does -- it is the beat that
		# tells the player their next dead end just opened.
		AudioDirector.play_stinger("key_taken")
	var remaining: Array = []
	for entry in _items:
		var item_id: String = entry.get("itemId", "")
		var qty: int = entry.get("quantity", 1)
		if item_id == "":
			continue
		var opts := {"quantity": qty, "roll": bool(entry.get("roll", false))}
		if entry.has("rollSeed"):
			opts["rollSeed"] = int(entry.get("rollSeed", -1))
		if InventoryService.add_loot(item_id, opts):
			RunFlow.register_loot(item_id, str(entry.get("instanceId", "")))
			_present_rarity_juice(item_id, InventoryService.get_last_granted_instance())
		else:
			remaining.append(entry)
	_items = remaining
	contents_changed.emit()
	if not remaining.is_empty():
		if InventoryService and InventoryService.has_signal("inventory_rejected"):
			InventoryService.inventory_rejected.emit("full")
		return
	_opened = true
	_label.visible = false
	opened.emit()
	var lid := DioramaSkin.find_chest_lid(_mesh)
	if lid:
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_BACK)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(lid, "rotation:x", DioramaSkin.LID_OPEN_ANGLE, 0.42)
